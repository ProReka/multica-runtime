# Autoscaling

An agent runtime does not need to run 24/7 if tasks arrive in bursts. The
autoscaler keeps one service per role at `desiredCount` 0 while idle and raises it
to 1 when that role's agents have work.

```
 pending task for multica-php
        │
        ▼
 ┌──────────────┐   describe-services   ┌────────────────┐
 │  autoscaler  │ ────────────────────► │ ECS / Swarm    │
 │  (1 replica) │ ◄──────────────────── │ service 0 ↔ 1  │
 └──────┬───────┘     desiredCount      └────────────────┘
        │ multica agent tasks
        ▼
   Multica API
```

## Why one replica per role

Multica binds an agent to a *runtime id*, and the id is derived from
`MULTICA_DAEMON_ID`. Two containers sharing one daemon id compete for the same
tasks. So a role scales `0 ↔ 1`, and parallelism inside the role comes from
`MULTICA_DAEMON_MAX_CONCURRENT_TASKS`.

If you need more concurrency, raise that value (or split agents across roles with
different daemon ids), not the replica count.

## Why task-driven, not board-driven

Every trigger — a direct message, an @mention, a reply, an issue assignment —
creates an execution task server-side immediately, with a non-terminal status
(`queued`, `dispatched`, `running`, …), even when no runtime is online to pick it
up. That pending task is the true signal.

Counting `issue list --status todo` misses DMs and mentions, and counts work that
is not assigned to any agent. The autoscaler therefore walks each agent's task
stream.

## Configuration

```dotenv
AUTOSCALER_PLATFORM=ecs                 # ecs | swarm (see Beyond ECS and Swarm)
AUTOSCALER_RUNTIMES=[{"daemon_id":"multica-node","service":"multica-node"},{"daemon_id":"multica-php","service":"multica-php"}]

AUTOSCALER_INTERVAL=60                  # seconds between ticks
AUTOSCALER_SCALEDOWN_COOLDOWN=300       # settle time after a scale-down
AUTOSCALER_SCALEDOWN_GRACE=120          # pending must stay 0 this long
AUTOSCALER_TASK_LIMIT=20                # tasks fetched per agent

# ECS only
AUTOSCALER_ECS_CLUSTER=multica

# Credentials
MULTICA_TOKEN=...
MULTICA_SERVER_URL=...                  # optional
MULTICA_WORKSPACE=...                   # optional
```

`AUTOSCALER_RUNTIMES` may also be a path to a JSON file (`/config/roles.json`),
which is easier to template than a one-line JSON string.

### Per-role vs legacy

With `AUTOSCALER_RUNTIMES` set, each entry maps a daemon id to a service. Without
it, the autoscaler falls back to a single pool: count issues in
`AUTOSCALER_PENDING_STATUSES` (default `todo`) and scale one service by
`ceil(pending / AUTOSCALER_TASKS_PER_WORKER)`, clamped by
`AUTOSCALER_MIN_WORKERS` / `AUTOSCALER_MAX_WORKERS`.

Legacy mode exists for older deployments. New deployments should use per-role
mode: it reacts to DMs and mentions, and it does not scale a service whose agents
have no work.

## Scale-down guards

Scale-up is immediate. Scale-down has three independent guards:

1. **Cooldown** — after any scale-down, wait `AUTOSCALER_SCALEDOWN_COOLDOWN`
   seconds before scaling down again. Stops up/down flapping.
2. **Grace** — pending must have been 0 *continuously* for
   `AUTOSCALER_SCALEDOWN_GRACE` seconds. Absorbs the gap between a finished task
   and the next one.
3. **Active task** — even when pending is 0, query the agents once more for a task
   in `running`/`in_progress`/`claimed`. The daemon may mark a task terminal while
   the agent CLI is still streaming results. If one is found, the grace clock
   resets.

Every tick also reads the **live** `desiredCount` (`ecs:DescribeServices` or
`docker service inspect`) instead of trusting memory, so a manual
`update-service`, a Terraform change, or state from a previous autoscaler run
self-heals on the next tick.

## Running it

The autoscaler does not run a Multica daemon. Its entrypoint is the Python loop.

```bash
docker run --rm \
  -e MULTICA_TOKEN \
  -e AUTOSCALER_PLATFORM=ecs \
  -e AUTOSCALER_ECS_CLUSTER=multica \
  -e AUTOSCALER_RUNTIMES='[{"daemon_id":"multica-node","service":"multica-node"}]' \
  -e AWS_REGION=ap-southeast-1 \
  -e AUTOSCALER_DRY_RUN=1 \
  ghcr.io/proreka/multica-autoscaler:latest
```

### Commands

| Command | Purpose |
|---|---|
| `multica-autoscaler` | Run the loop |
| `multica-autoscaler --once` | One tick, then exit |
| `multica-autoscaler --dry-run` | Log decisions, change nothing |
| `multica-autoscaler --check` | Validate configuration, exit 0/2 |
| `multica-autoscaler --health` | Check the heartbeat file (Docker `HEALTHCHECK`) |

`AUTOSCALER_DRY_RUN=1` is equivalent to `--dry-run`, and `AUTOSCALER_ONCE=1` to
`--once` (useful for a one-off ECS test task). Always run one tick in dry-run mode
after changing `AUTOSCALER_RUNTIMES`.

### Logs

```
[autoscaler] per-role mode: multica-node→multica-node, interval=60s cooldown=300s grace=120s dry_run=0
[autoscaler] [multica-node] pending=2 running=1 replicas=1 (unchanged)
[autoscaler] [multica-php] pending=0 want=0 < replicas=1 — holding (grace 42/120s)
[autoscaler] [multica-php] pending=0 → scale 1 → 0
```

## Permissions

### ECS

The autoscaler task role needs exactly two actions on the runtime services:

```json
{
  "Effect": "Allow",
  "Action": ["ecs:DescribeServices", "ecs:UpdateService"],
  "Resource": "arn:aws:ecs:<region>:<account>:service/<cluster>/*"
}
```

The full policy is in
[`deploy/ecs/autoscaler-iam-policy.json`](https://github.com/ProReka/multica-runtime/blob/main/deploy/ecs/autoscaler-iam-policy.json).
No static AWS keys: run it as an ECS task with a task role.

### Swarm

The container needs `/var/run/docker.sock` to call `docker service scale`. That is
root-equivalent access. Run the autoscaler on a manager node you trust, keep the
image pinned, and prefer the ECS adapter where IAM can express the permission.

The image runs as uid 1000, but the socket is `root:docker`. Add its GID so the
process does not need root:

```bash
stat -c '%g' /var/run/docker.sock     # e.g. 999
```

```dotenv
DOCKER_GID=999
```

Compose and the Swarm stack pass that GID via `group_add`. If the GID is wrong,
the autoscaler logs a permission error instead of scaling; fix the GID rather
than running it as root.

## Beyond ECS and Swarm

Today there are two adapters: `ecs` and `swarm`. Both do the same two things:
read the live desired count, and write it as 0 or 1. Everything else — the task
poll, the grace period, the cooldown, the running-task guard — is
platform-independent.

That split is the opening for other platforms. The recommended order is below;
none of it is shipped yet, and the config names are sketches, not final API.

### 1. Metrics exporter + KEDA (recommended for Kubernetes)

The cheapest way to support Kubernetes is not a Kubernetes adapter. It is to
expose the signal the autoscaler already computes:

```text
GET /metrics

multica_pending_tasks{role="multica-php",daemon_id="multica-php"} 2
multica_running_tasks{role="multica-php",daemon_id="multica-php"} 1
multica_desired_workers{role="multica-php",daemon_id="multica-php"} 1
multica_last_tick_timestamp_seconds 1770000000
```

Then KEDA (or any HPA-compatible controller) owns the replica count:

- `minReplicaCount: 0`, `maxReplicaCount: 1` per role;
- a `prometheus` trigger or a small `metrics-api` JSON bridge;
- `cooldownPeriod` and HPA stabilization instead of a second scale-down loop.

The important rule: **one controller per service.** If KEDA owns the scale-down,
do not also let the autoscaler call `Deployment.spec.replicas`. Run the
autoscaler as a metrics exporter (`--metrics`) without its platform adapter, or
keep its adapter in `--dry-run` and let KEDA act.

This also covers Azure Container Apps, which has KEDA built in.

### 2. Webhook adapter (the long tail)

A signed webhook turns the autoscaler into a decision engine and lets users plug
in any platform without waiting for an adapter:

```dotenv
AUTOSCALER_PLATFORM=webhook
AUTOSCALER_WEBHOOK_URL=https://scaler.internal/multica
AUTOSCALER_WEBHOOK_SECRET=...
```

```json
{
  "role": "multica-php",
  "daemon_id": "multica-php",
  "desired": 1,
  "pending": 2,
  "running": 1,
  "reason": "pending",
  "observed_at": "2026-10-21T03:00:00Z"
}
```

The receiver can call Nomad, Cloud Run, Fly Machines, a Coolify/Dokploy API, a
Kubernetes API, or a custom system. Requirements:

- HMAC signature over the raw body (`X-Multica-Signature`);
- retries with backoff, and an idempotency key;
- a receiver that is safe to call repeatedly with the same desired count;
- HTTPS and a secret that is not the Multica token;
- a failed webhook does not update local state as if it succeeded.

This is the highest-leverage option after the metrics endpoint, because it
supports platforms we have never seen.

### 3. Nomad adapter

Nomad is a natural fit for self-hosted clusters: a task group already has a
desired count, an ACL token can be scoped to one job, and no Docker socket is
needed.

```dotenv
AUTOSCALER_PLATFORM=nomad
NOMAD_ADDR=https://nomad.example:4646
NOMAD_TOKEN=...
```

Map a runtime to a job/group (`AUTOSCALER_RUNTIMES` would need one extra field),
read the live count, and scale 0↔1 through the Nomad scaling API. If you already
run Nomad's own autoscaler plugin, expose the metrics endpoint and use that
instead; two controllers on one job is the same mistake as two on one Deployment.

### 4. Native Kubernetes adapter

A native adapter would patch `Deployment.spec.replicas` with a namespace-scoped
Role. It makes sense only when KEDA or another CRD-based controller is not
allowed.

Costs:

- it duplicates reconciliation Kubernetes already provides;
- it needs leader election if more than one autoscaler replica runs;
- it adds a Kubernetes client (or `kubectl`) to a small Python image that
  currently shells out only to `aws` and `docker`;
- it has to reimplement the same guards KEDA/HPA already have.

KEDA first. Native adapter only if there is a concrete deployment that cannot
use it.

### 5. Docker Compose standalone — not a target

Compose has no desired-state API. `docker compose up --scale` is an imperative
local command, not a controller, and running it from inside a container is
brittle. Single-node Swarm already gives you a real desired count and works with
the existing adapter.

If a host only has Compose, use the webhook adapter with a receiver on the host
(systemd, a small agent, or a platform API). Keep the runtime image out of the
host's process management.

### 6. Cloud platforms

| Platform | Fit | Likely path |
|---|---|---|
| AWS ECS | excellent | shipped (`ecs`) |
| Docker Swarm | excellent | shipped (`swarm`) |
| Kubernetes | excellent | metrics + KEDA, then native if needed |
| Azure Container Apps | excellent | metrics + built-in KEDA |
| HashiCorp Nomad | excellent | native adapter |
| Fly Machines | good | webhook → Machines API start/stop |
| Google Cloud Run | workable | webhook → API; check cold start and always-on CPU |
| Dokploy / Coolify | workable | native Swarm adapter if exposed, otherwise webhook |
| Plain Docker Compose | poor | use single-node Swarm or a host-side receiver |

Cloud Run deserves a caveat: request-driven scale-to-zero is a poor fit for a
long-running daemon that receives no HTTP traffic. A worker pool or an explicit
start/stop API is the right shape; the autoscaler should not pretend a web
service is a task worker.

### What does not change

The platform-independent parts stay the same in every adapter:

- one runtime id per role, scaled 0↔1;
- pending tasks, not board columns, as the signal;
- cooldown, grace, and running-task guards;
- live desired count read on every tick;
- `--dry-run` and `--once` for a safe first test.

A future Multica API might let the autoscaler raise
`MULTICA_DAEMON_MAX_CONCURRENT_TASKS` instead of starting another container. That
would be cheaper than any adapter, but it is not a documented API today, and
changing concurrency under a running task needs its own safety review.

### Warm pools and schedules

Scale-to-zero is not always the best cost trade-off. Flutter, PHP, and the design
image are expensive to start; keeping one warm replica during working hours can be
cheaper than repeated cold starts.

A later mode could combine:

- a warm window (`AUTOSCALER_WARM_FROM` / `AUTOSCALER_WARM_TO`);
- a per-role `AUTOSCALER_MIN_WARM` for expensive toolchains;
- the existing task signal for everything outside the window.

That is a cost feature, not a correctness feature. The task-driven path remains
the default.

## Health and shutdown

Each tick writes a heartbeat to `/tmp/multica-autoscaler.heartbeat` (override with
`AUTOSCALER_HEALTH_FILE`). The image's healthcheck fails if the heartbeat is older
than `3 × interval + 30s`, which catches a hung CLI call without restarting on a
single slow tick.

`SIGTERM` finishes the current tick and exits cleanly. The loop sleeps in
one-second slices so shutdown is prompt.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `FATAL: MULTICA_TOKEN is not set` | Missing token | Set it |
| `FATAL: AUTOSCALER_PLATFORM must be ecs or swarm` | Typo | `ecs` or `swarm` |
| `AUTOSCALER_ECS_CLUSTER is required` | ECS platform without cluster | Set it |
| Service never scales up | Runtime never registered, so no agents are bound | Start the role once manually, bind agents, then let it scale |
| Service never scales down | Cooldown/grace/running task | Read the `holding (...)` reason in the log |
| `ecs update-service ... failed` | Task role lacks `UpdateService` | Attach the policy above |
| Scales up and down repeatedly | Grace/cooldown too low, or tasks arrive in bursts | Raise `AUTOSCALER_SCALEDOWN_GRACE` |
| `config OK` but no scaling | Dry run enabled | Unset `AUTOSCALER_DRY_RUN` |
