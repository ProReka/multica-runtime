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
AUTOSCALER_PLATFORM=ecs                 # ecs | swarm
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

## Kubernetes

Not supported yet. The autoscaler has ECS and Swarm adapters. On Kubernetes, run
one replica permanently or drive a `CronJob`/KEDA from the same signal. See the
[roadmap](roadmap.md).

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
