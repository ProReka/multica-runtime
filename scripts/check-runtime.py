#!/usr/bin/env python3
"""Read-only pickup diagnosis; never prints task content or CLI error bodies."""
import argparse
from datetime import datetime, timezone
import json
import subprocess
import sys


def query(workspace, *args):
    result = subprocess.run(
        ["multica", "--workspace-id", workspace, *args, "--output", "json"],
        capture_output=True, text=True, timeout=60,
    )
    if result.returncode:
        raise ValueError("Multica query failed; check authentication and workspace")
    return json.loads(result.stdout)


def age_seconds(value, now):
    if not value:
        return float("inf")
    return (now - datetime.fromisoformat(value.replace("Z", "+00:00"))).total_seconds()


def diagnose(agent, runtime, tasks, messages, now, stale_seconds):
    """Return findings, unhealthy flag. Age alone never proves a run is stuck."""
    findings = []
    unhealthy = False
    if not runtime or runtime.get("status") != "online" or age_seconds(
        runtime.get("last_seen_at"), now
    ) > stale_seconds:
        findings.append("OFFLINE: bound runtime missing, offline, or heartbeat stale")
        unhealthy = True
    active = [t for t in tasks if t.get("status") in {"running", "in_progress", "claimed"}]
    queued = [t for t in tasks if t.get("status") in {"queued", "pending", "dispatched"}]
    limit = agent.get("max_concurrent_tasks")
    findings.append(f"TASKS: active={len(active)} queued={len(queued)} agent_limit={limit}")
    for task in active:
        events = messages[task["id"]]
        timestamps = [m["created_at"] for m in events if m.get("created_at")]
        latest = max(timestamps, key=lambda t: datetime.fromisoformat(t.replace("Z", "+00:00"))) if timestamps else task.get("started_at")
        results = [m for m in events if m.get("type") == "tool_result"]
        last_output = str(results[-1].get("output", "")) if results else ""
        errors = [m for m in events if m.get("type") == "error"]
        if errors and events[-1].get("type") == "error":
            findings.append(f"FAILED: run {task['id']} emitted an execution error despite running status")
            unhealthy = True
        elif not events:
            findings.append(f"CHECK: run {task['id']} is running with zero messages; execution unverified")
            unhealthy = True
        elif "shell tool terminated command after exceeding timeout" in last_output:
            findings.append(f"STALLED: run {task['id']} last tool timed out; recent event is not progress")
            unhealthy = True
        elif age_seconds(latest, now) > stale_seconds:
            findings.append(f"CHECK: run {task['id']} has no recent messages; inspect before cancelling")
            unhealthy = True
        else:
            findings.append(f"ACTIVITY: run {task['id']} has recent events; useful progress unverified")
    if queued:
        if isinstance(limit, int) and limit > 0 and len(active) >= limit:
            findings.append("SATURATED: agent concurrency full; queued work waits even if daemon has spare slots")
        else:
            findings.append("CHECK: queued work with free agent slots; inspect dispatch and daemon capacity")
            unhealthy = True
    recent_failures = [t for t in tasks if t.get("failure_reason")
                       and age_seconds(t.get("completed_at"), now) <= 86400]
    for reason in sorted({t["failure_reason"] for t in recent_failures}):
        # Print known categories only, never arbitrary upstream error content.
        if reason in {"api_invalid_request", "idle_watchdog", "runtime_recovery", "runtime_offline"}:
            findings.append(f"HISTORY: {reason} within 24h; inspect execution/dependencies, not just heartbeat")
    return findings, unhealthy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--agent-id", required=True)
    parser.add_argument("--stale-seconds", type=int, default=600)
    args = parser.parse_args()
    if args.stale_seconds <= 0:
        parser.error("--stale-seconds must be positive")
    try:
        agent = query(args.workspace_id, "agent", "get", args.agent_id)
        runtimes = query(args.workspace_id, "runtime", "list")
        runtime = next((r for r in runtimes if r["id"] == agent.get("runtime_id")), None)
        # Do not truncate to the newest 20: older running tasks still occupy slots.
        tasks = []
        before = None
        while True:
            command = ["agent", "tasks", args.agent_id, "--limit", "100"]
            if before:
                command += ["--before", before]
            page = query(args.workspace_id, *command)
            if not isinstance(page, list):
                raise ValueError("Unexpected task response")
            tasks.extend(page)
            if len(page) < 100:
                break
            cursor = page[-1]["created_at"] + "|" + page[-1]["id"]
            if cursor == before:
                raise ValueError("Task pagination did not advance")
            before = cursor
        messages = {t["id"]: query(args.workspace_id, "issue", "run-messages", t["id"])
                    for t in tasks if t.get("status") in {"running", "in_progress", "claimed"}}
        findings, unhealthy = diagnose(agent, runtime, tasks, messages,
                                        datetime.now(timezone.utc), args.stale_seconds)
        print("\n".join(findings))
        return int(unhealthy)
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
        print("UNKNOWN: diagnosis incomplete; check CLI access/schema. No changes made.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
