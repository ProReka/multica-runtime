# Amazon ECS (Fargate)

Recommended when you already run on AWS and want scale-to-zero without managing
hosts.

Two services:

| Service | Replicas | Role |
|---|---|---|
| `multica-<role>` | 0 or 1 | Runtime |
| `multica-autoscaler` | 1 | Scale roles from pending tasks |

## Checklist

1. **EFS** file system and access point mapped to `1000:1000`.
2. **Secrets Manager** secret with `MULTICA_TOKEN`, `AI_BASE_URL`, `AI_API_KEY`,
   `AI_MODEL`.
3. **Execution role** — pull image, logs, read secret.
4. **Task role** — EFS `ClientMount`/`ClientWrite`.
5. **Autoscaler task role** — `ecs:DescribeServices` + `ecs:UpdateService` on the
   runtime services.
6. Register the task definition and create the service with `desiredCount: 0`.

The templates are in [`deploy/ecs`](https://github.com/ProReka/multica-runtime/tree/main/deploy/ecs),
with a render script:

```bash
export AWS_ACCOUNT_ID=... AWS_REGION=ap-southeast-1
export IMAGE=ghcr.io/proreka/multica-runtime:base
export DAEMON_ID=multica-base RUNTIME_NAME="Multica Base"
export EFS_ID=fs-... EFS_ACCESS_POINT_ID=fsap-...

deploy/ecs/render.sh deploy/ecs/runtime-task-definition.json /tmp/runtime.json
aws ecs register-task-definition --cli-input-json file:///tmp/runtime.json
```

Full instructions, IAM policies, and sizing are in
[`deploy/ecs/README.md`](https://github.com/ProReka/multica-runtime/blob/main/deploy/ecs/README.md).

## Things that bite

- **No inbound port.** The runtime is an outbound worker. A load balancer is not
  needed and would only widen the attack surface.
- **EFS is slower than local disk.** Large checkouts and builds feel it. Keep the
  task warm if that matters.
- **Don't use a rolling deployment.** One task per service. Update with
  `force-new-deployment`, which stops the old task first.
- **Ephemeral storage is 20 GB by default.** Flutter builds may need
  `ephemeralStorage.sizeInGiB`.
- **Fargate's seccomp blocks ptrace.** The image is designed around this: no
  `gosu`, no runtime privilege drop. The design image runs Xvfb and the MCP server
  as `runner`.

## Verify the autoscaler before trusting it

```bash
aws ecs run-task --cluster "$ECS_CLUSTER" \
  --task-definition multica-autoscaler --launch-type FARGATE \
  --overrides '{"containerOverrides":[{"name":"autoscaler","environment":[{"name":"AUTOSCALER_DRY_RUN","value":"1"},{"name":"AUTOSCALER_ONCE","value":"1"}]}]}' \
  --network-configuration '...'
```

`AUTOSCALER_ONCE=1` makes the loop run a single tick and exit, which is what you
want for a test task. Read the log: it must name the right service and the right
pending count.

## Cost

A sleeping service costs nothing for Fargate compute. EFS storage and the
autoscaler task are the only fixed costs. Scale the autoscaler's CPU/memory down
(512/1024 is plenty) and keep the runtime task at 2 vCPU / 4 GB unless it is
Flutter.
