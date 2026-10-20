#!/usr/bin/env python3
"""Multica runtime autoscaler — task-driven, one runtime-role per service.

Why task-driven instead of board state
--------------------------------------
An agent needs its runtime awake for many trigger kinds: a direct message, an
@mention in a comment, a reply, or an issue assignment. Every one of those
creates an execution task server-side immediately, with a non-terminal status
(queued/dispatched/running) — even when no runtime is online to pick it up.
That pending task is the real scale-up signal.

Counting `issue list --status todo` misses DMs, mentions and replies, and counts
work that is not assigned to any agent. So this autoscaler looks at each
agent's task stream instead.

Model: one role per service
---------------------------
Multica binds an agent to a runtime via `agent.runtime_id`, and a runtime keeps
its id as long as its daemon keeps the same `MULTICA_DAEMON_ID`. Each role is
therefore a single service whose container pins a fixed daemon id and scales
`desiredCount` 0↔1. Parallelism inside a role comes from
`MULTICA_DAEMON_MAX_CONCURRENT_TASKS`, not from replicas: two containers sharing
one daemon id would collide on task claims.

Loop, per tick
--------------
    agents   = agent list            # agent -> runtime
    runtimes = runtime list          # daemon id -> runtime
    for each role:
        pending = non-terminal tasks of the agents bound to this role
        want    = 1 if pending > 0 else 0
        actual  = live desiredCount (read every tick, never trusted from memory)
        scale when want != actual, subject to the scale-down guards

Scale-down guards
-----------------
1. Cooldown — after a scale-down, wait AUTOSCALER_SCALEDOWN_COOLDOWN seconds
   before scaling down again. Stops up/down flapping.
2. Grace — pending must have been 0 continuously for AUTOSCALER_SCALEDOWN_GRACE
   seconds. Absorbs the gap between a finished task and the next one.
3. Active task — even with pending = 0, query the agents once more for a task
   in running/in_progress/claimed state. The daemon can mark a task terminal
   while the agent CLI is still streaming results; killing the runtime then
   loses work.

Configuration
-------------
    AUTOSCALER_PLATFORM             ecs | swarm               (required)
    AUTOSCALER_RUNTIMES             JSON array, or a path to a JSON file
        [{"daemon_id": "multica-php", "service": "multica-php"}]
    AUTOSCALER_INTERVAL             seconds between ticks     (default 60)
    AUTOSCALER_SCALEDOWN_COOLDOWN   seconds                   (default 300)
    AUTOSCALER_SCALEDOWN_GRACE      seconds                   (default 120)
    AUTOSCALER_TASK_LIMIT           tasks fetched per agent   (default 20)
    AUTOSCALER_ECS_CLUSTER          ECS cluster               (required for ecs)
    MULTICA_TOKEN                   Multica personal token    (required)
    MULTICA_SERVER_URL              self-hosted Multica       (optional)
    MULTICA_WORKSPACE               CLI default workspace     (optional)

Legacy single-pool mode
-----------------------
When AUTOSCALER_RUNTIMES is unset, the autoscaler falls back to counting issues
at AUTOSCALER_PENDING_STATUSES (default "todo") and scaling one service by
ceil(pending / AUTOSCALER_TASKS_PER_WORKER). It is kept for existing
deployments; new deployments should use per-role mode.

Commands
--------
    multica-autoscaler                 # run the loop
    multica-autoscaler --once          # one tick, then exit
    multica-autoscaler --check         # validate config, exit 0/2
    multica-autoscaler --health        # heartbeat check, for HEALTHCHECK

Environment overrides: --dry-run also works via AUTOSCALER_DRY_RUN=1.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from math import ceil
from pathlib import Path
from typing import Any, Iterable

# Task statuses that mean "this agent still needs a runtime awake".
NON_TERMINAL = {"queued", "dispatched", "running", "pending", "in_progress", "claimed"}
# Task statuses that mean the agent CLI is executing right now.
ACTIVE_STATUSES = {"running", "in_progress", "claimed"}

DEFAULT_HEALTH_FILE = "/tmp/multica-autoscaler.heartbeat"
CLI_TIMEOUT = 60


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
def log(msg: str) -> None:
    print(f"[autoscaler] {msg}", file=sys.stderr, flush=True)


def env(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name)
    return value if value not in (None, "") else default


def env_int(name: str, default: int) -> int:
    try:
        return int(env(name, str(default)) or default)
    except (TypeError, ValueError):
        log(f"WARN: {name} is not an integer; using {default}")
        return default


def env_bool(name: str, default: bool = False) -> bool:
    value = (env(name) or "").strip().lower()
    if not value:
        return default
    return value in {"1", "true", "yes", "on"}


def run(cmd: list[str], timeout: int = CLI_TIMEOUT) -> subprocess.CompletedProcess[str]:
    """Run a command with a timeout; never let a hung CLI freeze the loop."""
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        log(f"WARN: `{cmd[0]} {cmd[1] if len(cmd) > 1 else ''}` timed out after {timeout}s")
        return subprocess.CompletedProcess(cmd, 124, "", "timeout")
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, "", f"{cmd[0]}: not found")


def run_json(cmd: list[str], timeout: int = CLI_TIMEOUT) -> Any:
    """Run a Multica CLI command and parse JSON stdout; None on failure."""
    result = run(cmd, timeout)
    if result.returncode != 0:
        log(f"WARN: `{' '.join(cmd)}` failed: {result.stderr.strip()}")
        return None
    try:
        return json.loads(result.stdout or "null")
    except json.JSONDecodeError:
        log(f"WARN: non-JSON output from `{' '.join(cmd)}`")
        return None


def as_list(data: Any, *keys: str) -> list[dict[str, Any]]:
    """Unwrap `{key: [...]}` envelopes, or accept a bare list."""
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict):
        for key in keys:
            value = data.get(key)
            if isinstance(value, list):
                return [item for item in value if isinstance(item, dict)]
    return []


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Role:
    daemon_id: str
    service: str


@dataclass(frozen=True)
class Settings:
    platform: str
    interval: int
    cooldown: int
    grace: int
    task_limit: int
    dry_run: bool
    once: bool
    health_file: str


def load_runtimes(raw: str | None) -> list[Role] | None:
    """Parse AUTOSCALER_RUNTIMES (inline JSON or a path to a JSON file)."""
    if not raw:
        return None
    text = raw
    if raw.lstrip().startswith(("/", "./", "~")):
        path = Path(raw).expanduser()
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise ValueError(f"cannot read {path}: {exc}") from exc
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"AUTOSCALER_RUNTIMES is not valid JSON: {exc}") from exc
    if not isinstance(data, list) or not data:
        raise ValueError("AUTOSCALER_RUNTIMES must be a non-empty JSON array")
    roles: list[Role] = []
    seen_daemons: set[str] = set()
    seen_services: set[str] = set()
    for item in data:
        if not isinstance(item, dict):
            raise ValueError("each AUTOSCALER_RUNTIMES entry must be an object")
        daemon_id = str(item.get("daemon_id") or "").strip()
        service = str(item.get("service") or "").strip()
        if not daemon_id or not service:
            raise ValueError('each entry needs "daemon_id" and "service"')
        if daemon_id in seen_daemons:
            raise ValueError(f"duplicate daemon_id: {daemon_id}")
        if service in seen_services:
            raise ValueError(f"duplicate service: {service}")
        seen_daemons.add(daemon_id)
        seen_services.add(service)
        roles.append(Role(daemon_id=daemon_id, service=service))
    return roles


def load_settings(args: argparse.Namespace) -> Settings:
    platform = env("AUTOSCALER_PLATFORM") or ""
    if platform not in {"ecs", "swarm"}:
        raise ValueError(f"AUTOSCALER_PLATFORM must be ecs or swarm (got {platform!r})")
    if platform == "ecs" and not env("AUTOSCALER_ECS_CLUSTER"):
        raise ValueError("AUTOSCALER_ECS_CLUSTER is required when AUTOSCALER_PLATFORM=ecs")
    return Settings(
        platform=platform,
        interval=max(5, env_int("AUTOSCALER_INTERVAL", 60)),
        cooldown=max(0, env_int("AUTOSCALER_SCALEDOWN_COOLDOWN", 300)),
        grace=max(0, env_int("AUTOSCALER_SCALEDOWN_GRACE", 120)),
        task_limit=max(1, env_int("AUTOSCALER_TASK_LIMIT", 20)),
        dry_run=bool(args.dry_run) or env_bool("AUTOSCALER_DRY_RUN"),
        once=bool(args.once) or env_bool("AUTOSCALER_ONCE"),
        health_file=env("AUTOSCALER_HEALTH_FILE", DEFAULT_HEALTH_FILE) or DEFAULT_HEALTH_FILE,
    )


# ---------------------------------------------------------------------------
# Multica state
# ---------------------------------------------------------------------------
def multica_login() -> bool:
    token = env("MULTICA_TOKEN")
    if not token:
        log("FATAL: MULTICA_TOKEN is not set")
        return False
    server = env("MULTICA_SERVER_URL")
    if server:
        run(["multica", "config", "set", "server_url", server])
    result = run(["multica", "login", "--token", token], timeout=30)
    if result.returncode != 0:
        log(f"FATAL: Multica login failed: {result.stderr.strip()}")
        return False
    workspace = env("MULTICA_WORKSPACE")
    if workspace:
        run(["multica", "workspace", "switch", workspace], timeout=30)
    log("Multica login OK")
    return True


def agents_by_runtime() -> dict[str, list[dict[str, Any]]]:
    """runtime_id -> agents bound to it."""
    agents = as_list(run_json(["multica", "agent", "list", "--output", "json"]), "agents")
    grouped: dict[str, list[dict[str, Any]]] = {}
    for agent in agents:
        runtime_id = agent.get("runtime_id")
        if runtime_id:
            grouped.setdefault(str(runtime_id), []).append(agent)
    return grouped


def runtime_id_for_daemon(
    daemon_id: str, by_runtime: dict[str, list[dict[str, Any]]]
) -> str | None:
    """Runtime id for a daemon, preferring the registration agents are bound to.

    A daemon registers one runtime per bundled AI CLI (claude + opencode share
    MULTICA_DAEMON_ID), and an agent is bound to exactly one of them. Picking
    blindly ("first match") can resolve to the CLI with no agents, report
    pending=0 forever, and scale the role down mid-work.
    """
    runtimes = as_list(run_json(["multica", "runtime", "list", "--output", "json"]), "runtimes")
    candidates = [
        str(rt["id"]) for rt in runtimes
        if rt.get("daemon_id") == daemon_id and rt.get("id")
    ]
    if not candidates:
        return None
    for runtime_id in candidates:
        if by_runtime.get(runtime_id):
            return runtime_id
    return candidates[0]


def agent_task_counts(agent_id: str, limit: int) -> tuple[int, bool]:
    """(non-terminal count, has-actively-running-task) for one agent."""
    data = run_json(["multica", "agent", "tasks", agent_id, "--output", "json"])
    tasks = as_list(data, "tasks")
    if limit > 0:
        tasks = tasks[:limit]  # newest first; non-terminal tasks are recent
    pending = sum(
        1 for task in tasks
        if str(task.get("status", "")).lower() in NON_TERMINAL
    )
    running = any(
        str(task.get("status", "")).lower() in ACTIVE_STATUSES
        for task in tasks
    )
    return pending, running


def role_state(
    role: Role,
    by_runtime: dict[str, list[dict[str, Any]]],
    limit: int,
) -> tuple[int, bool]:
    """(pending, running) across the agents bound to this role's runtime."""
    runtime_id = runtime_id_for_daemon(role.daemon_id, by_runtime)
    if runtime_id is None:
        # The role has never registered, so nothing can be routed to it yet.
        # Zero is the only truthful answer; the first task will appear once the
        # runtime exists.
        return 0, False
    pending = 0
    running = False
    for agent in by_runtime.get(runtime_id, []):
        agent_id = agent.get("id")
        if not agent_id:
            continue
        agent_pending, agent_running = agent_task_counts(str(agent_id), limit)
        pending += agent_pending
        running = running or agent_running
    return pending, running


# ---------------------------------------------------------------------------
# Scaling decisions (pure, unit-tested)
# ---------------------------------------------------------------------------
def wanted_replicas(pending: int) -> int:
    return 1 if pending > 0 else 0


def scale_down_blocked(
    *,
    now: float,
    last_scaledown: float,
    zero_since: float | None,
    running: bool,
    cooldown: int,
    grace: int,
) -> str | None:
    """Return a human-readable reason to hold, or None when scaling down is safe."""
    if now - last_scaledown < cooldown:
        return f"cooldown {int(now - last_scaledown)}/{cooldown}s"
    if zero_since is None:
        return "grace clock not started"
    zero_for = now - zero_since
    if zero_for < grace:
        return f"grace {int(zero_for)}/{grace}s"
    if running:
        return "task still running"
    return None


# ---------------------------------------------------------------------------
# Platform adapters
# ---------------------------------------------------------------------------
def scale_service(settings: Settings, service: str, replicas: int) -> bool:
    if settings.dry_run:
        log(f"[dry-run] would scale {service} → {replicas}")
        return True
    if settings.platform == "ecs":
        cluster = env("AUTOSCALER_ECS_CLUSTER") or ""
        result = run([
            "aws", "ecs", "update-service",
            "--cluster", cluster,
            "--service", service,
            "--desired-count", str(replicas),
        ])
        if result.returncode != 0:
            log(f"WARN: ecs update-service {service}={replicas} failed: {result.stderr.strip()}")
            return False
        return True
    result = run(["docker", "service", "scale", "--detach", f"{service}={replicas}"])
    if result.returncode != 0:
        log(f"WARN: swarm scale {service}={replicas} failed: {result.stderr.strip()}")
        return False
    return True


def live_replicas(settings: Settings, service: str) -> int | None:
    """Read the service's current desired count; None when unreadable."""
    if settings.platform == "ecs":
        cluster = env("AUTOSCALER_ECS_CLUSTER") or ""
        result = run([
            "aws", "ecs", "describe-services",
            "--cluster", cluster, "--services", service,
        ])
        if result.returncode != 0:
            log(f"WARN: ecs describe-services {service} failed: {result.stderr.strip()}")
            return None
        try:
            data = json.loads(result.stdout or "null")
            services = (data or {}).get("services") if isinstance(data, dict) else None
            if not services:
                log(f"WARN: ecs describe-services {service}: service not found")
                return None
            return int(services[0].get("desiredCount"))
        except (json.JSONDecodeError, TypeError, ValueError):
            log(f"WARN: ecs describe-services {service}: unusable output")
            return None

    result = run([
        "docker", "service", "inspect",
        "--format", "{{.Spec.Mode.Replicated.Replicas}}", service,
    ])
    if result.returncode != 0:
        log(f"WARN: swarm inspect {service} failed: {result.stderr.strip()}")
        return None
    try:
        return int((result.stdout or "").strip())
    except (TypeError, ValueError):
        log(f"WARN: swarm inspect {service}: bad replica count")
        return None


# ---------------------------------------------------------------------------
# Per-role loop
# ---------------------------------------------------------------------------
@dataclass
class RoleRuntimeState:
    current: int = -1
    last_scaledown: float = 0.0
    zero_since: float | None = None
    scaled: int = 0


def heartbeat(settings: Settings, info: dict[str, Any] | None = None) -> None:
    payload = {"ts": time.time(), "platform": settings.platform}
    if info:
        payload.update(info)
    try:
        Path(settings.health_file).write_text(json.dumps(payload), encoding="utf-8")
    except OSError:
        pass


def check_health(settings: Settings) -> int:
    try:
        data = json.loads(Path(settings.health_file).read_text(encoding="utf-8"))
        age = time.time() - float(data.get("ts", 0))
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        log(f"unhealthy: no heartbeat at {settings.health_file}")
        return 1
    limit = settings.interval * 3 + 30
    if age > limit:
        log(f"unhealthy: last heartbeat {int(age)}s ago (limit {limit}s)")
        return 1
    log(f"healthy: last heartbeat {int(age)}s ago")
    return 0


class Stopper:
    """Cooperative SIGTERM/SIGINT handling so we finish the tick and exit clean."""

    def __init__(self) -> None:
        self.requested = False

    def install(self) -> None:
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, self._handle)

    def _handle(self, signum: int, _frame: Any) -> None:
        log(f"received signal {signum}; finishing this tick")
        self.requested = True

    def sleep(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while not self.requested and time.monotonic() < deadline:
            time.sleep(min(1.0, deadline - time.monotonic()))


def run_tick(
    settings: Settings,
    roles: list[Role],
    state: dict[str, RoleRuntimeState],
) -> dict[str, int]:
    now = time.time()
    by_runtime = agents_by_runtime()
    summary: dict[str, int] = {}

    for role in roles:
        service = role.service
        role_state_entry = state[service]

        pending, running = role_state(role, by_runtime, settings.task_limit)
        want = wanted_replicas(pending)

        live = live_replicas(settings, service)
        if live is not None:
            role_state_entry.current = live
        current = role_state_entry.current

        if pending > 0:
            role_state_entry.zero_since = None
        elif role_state_entry.zero_since is None:
            role_state_entry.zero_since = now

        summary[service] = want

        if current < 0:
            log(f"[{service}] pending={pending} desired={want} (service state unreadable; skipping)")
            continue

        if want == current:
            log(f"[{service}] pending={pending} running={int(running)} replicas={current} (unchanged)")
            continue

        if want < current:
            reason = scale_down_blocked(
                now=now,
                last_scaledown=role_state_entry.last_scaledown,
                zero_since=role_state_entry.zero_since,
                running=running,
                cooldown=settings.cooldown,
                grace=settings.grace,
            )
            if reason:
                log(f"[{service}] pending={pending} want=0 < replicas={current} — holding ({reason})")
                if reason == "task still running":
                    role_state_entry.zero_since = now
                continue

        log(f"[{service}] pending={pending} → scale {current} → {want}")
        if scale_service(settings, service, want):
            if want < current:
                role_state_entry.last_scaledown = now
            role_state_entry.current = want
            role_state_entry.scaled += 1

    heartbeat(settings, {"roles": {k: v for k, v in summary.items()}})
    return summary


def run_per_role(settings: Settings, roles: list[Role], stopper: Stopper) -> int:
    log(
        "per-role mode: "
        + ", ".join(f"{role.daemon_id}→{role.service}" for role in roles)
        + f" | interval={settings.interval}s cooldown={settings.cooldown}s"
        + f" grace={settings.grace}s dry_run={int(settings.dry_run)}"
    )
    state = {
        role.service: RoleRuntimeState(last_scaledown=time.time())
        for role in roles
    }
    while not stopper.requested:
        run_tick(settings, roles, state)
        if settings.once:
            break
        stopper.sleep(settings.interval)
    log("stopped")
    return 0


# ---------------------------------------------------------------------------
# Legacy single-pool mode
# ---------------------------------------------------------------------------
def legacy_pending_count() -> int:
    statuses = [
        status.strip()
        for status in (env("AUTOSCALER_PENDING_STATUSES", "todo") or "todo").split(",")
        if status.strip()
    ]
    total = 0
    for status in statuses:
        data = run_json([
            "multica", "issue", "list",
            "--status", status, "--output", "json", "--limit", "200",
        ])
        total += len(as_list(data, "issues"))
    return total


def legacy_desired(pending: int) -> int:
    per_worker = max(1, env_int("AUTOSCALER_TASKS_PER_WORKER", 2))
    minimum = max(0, env_int("AUTOSCALER_MIN_WORKERS", 0))
    maximum = max(minimum, env_int("AUTOSCALER_MAX_WORKERS", 10))
    wanted = ceil(pending / per_worker) if pending > 0 else 0
    return max(minimum, min(maximum, wanted))


def run_legacy(settings: Settings, stopper: Stopper) -> int:
    service = (
        env("AUTOSCALER_ECS_SERVICE")
        or env("AUTOSCALER_SWARM_SERVICE", "multica-worker")
        or "multica-worker"
    )
    log(f"legacy single-pool mode: service={service}")
    current = -1
    last_scaledown = time.time()
    while not stopper.requested:
        pending = legacy_pending_count()
        want = legacy_desired(pending)
        live = live_replicas(settings, service)
        if live is not None:
            current = live
        if want == current:
            log(f"pending={pending} want={want} (unchanged)")
        else:
            blocked = want < current and (time.time() - last_scaledown) < settings.cooldown
            if blocked:
                log(f"pending={pending} want={want} < current={current} — holding (cooldown)")
            else:
                log(f"pending={pending} → scale {service} {current} → {want}")
                if scale_service(settings, service, want):
                    if want < current:
                        last_scaledown = time.time()
                    current = want
        heartbeat(settings, {"pending": pending, "mode": "legacy"})
        if settings.once:
            break
        stopper.sleep(settings.interval)
    log("stopped")
    return 0


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="multica-autoscaler",
        description="Scale Multica runtime services from pending agent tasks.",
    )
    parser.add_argument("--once", action="store_true", help="run one tick and exit")
    parser.add_argument("--dry-run", action="store_true", help="log decisions, change nothing")
    parser.add_argument("--check", action="store_true", help="validate configuration and exit")
    parser.add_argument("--health", action="store_true", help="check the heartbeat file and exit")
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        settings = load_settings(args)
        roles = load_runtimes(env("AUTOSCALER_RUNTIMES"))
    except ValueError as exc:
        log(f"FATAL: {exc}")
        return 2

    if args.health:
        return check_health(settings)

    if args.check:
        log(
            f"config OK: platform={settings.platform} interval={settings.interval}s "
            f"cooldown={settings.cooldown}s grace={settings.grace}s "
            f"mode={'per-role' if roles else 'legacy'} roles={len(roles or [])}"
        )
        return 0

    if not multica_login():
        return 2

    stopper = Stopper()
    stopper.install()
    if roles:
        return run_per_role(settings, roles, stopper)
    log("AUTOSCALER_RUNTIMES unset — falling back to legacy single-pool mode")
    return run_legacy(settings, stopper)


if __name__ == "__main__":
    sys.exit(main())
