# Amazon ECS (Fargate)

Two long-running services, no load balancer:

| Service | Desired count | Purpose |
|---|---|---|
| `multica-<role>` | `0` or `1` | The runtime. Autoscaled from pending tasks. |
| `multica-autoscaler` | `1` | Reads pending tasks, calls `ecs:UpdateService`. |

Why `0..1` and not replicas: Multica binds agents to a runtime id, and the id is
derived from `MULTICA_DAEMON_ID`. Two tasks sharing one daemon id compete for the
same tasks. Parallelism comes from `MULTICA_DAEMON_MAX_CONCURRENT_TASKS`.

## 1. Persistent workspaces (EFS)

Fargate has no persistent disk. Session history and task checkouts live on EFS:

```bash
aws efs create-file-system --creation-token multica-workspaces --region "$AWS_REGION"

aws efs create-access-point \
  --file-system-id "$EFS_ID" \
  --posix-user Uid=1000,Gid=1000 \
  --root-directory 'Path=/multica,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=0755}' \
  --region "$AWS_REGION"
```

The access point must map to `1000:1000`, because the image runs as `runner`
(uid/gid 1000). The task definition already enables EFS transit encryption and
IAM authorization.

## 2. Secrets

Create one secret with the four required values:

```bash
aws secretsmanager create-secret \
  --name multica/runtime \
  --secret-string '{
    "MULTICA_TOKEN": "...",
    "AI_BASE_URL": "https://router.example.com",
    "AI_API_KEY": "...",
    "AI_MODEL": "general"
  }'
```

The task definition references individual JSON keys (`...:MULTICA_TOKEN::`), so
the values never appear in Terraform, a compose file, or an image.

## 3. IAM roles

* `multicaTaskExecutionRole` — standard ECS execution role: pull the image,
  write logs, read the secret.
* `multicaTaskRole` — EFS client permissions (`elasticfilesystem:ClientMount`,
  `ClientWrite`) on the file system and access point. No other permissions.
* `multicaAutoscalerTaskRole` — attach
  [`autoscaler-iam-policy.json`](autoscaler-iam-policy.json). It can describe and
  update only services in the cluster.

## 4. Register and run

```bash
export AWS_ACCOUNT_ID=... AWS_REGION=ap-southeast-1
export IMAGE=ghcr.io/proreka/multica-runtime:base
export DAEMON_ID=multica-base RUNTIME_NAME="Multica Base"
export EFS_ID=fs-... EFS_ACCESS_POINT_ID=fsap-...

deploy/ecs/render.sh deploy/ecs/runtime-task-definition.json /tmp/runtime.json
aws ecs register-task-definition --cli-input-json file:///tmp/runtime.json
```

Create the service **with `desiredCount: 0`** so the autoscaler owns its state:

```bash
aws ecs create-service \
  --cluster "$ECS_CLUSTER" \
  --service-name multica-base \
  --task-definition multica-runtime-base \
  --desired-count 0 \
  --launch-type FARGATE \
  --platform-version 1.4.0 \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-...],securityGroups=[sg-...],assignPublicIp=DISABLED}'
```

The task needs outbound HTTPS to Multica and your AI router. There is no inbound
port: the runtime connects out, it does not serve traffic.

## 5. Autoscaler

```bash
export AUTOSCALER_IMAGE=ghcr.io/proreka/multica-autoscaler:latest
export ECS_CLUSTER=multica
export AUTOSCALER_RUNTIMES='[{"daemon_id":"multica-base","service":"multica-base"}]'

deploy/ecs/render.sh deploy/ecs/autoscaler-task-definition.json /tmp/autoscaler.json
aws ecs register-task-definition --cli-input-json file:///tmp/autoscaler.json
aws ecs create-service \
  --cluster "$ECS_CLUSTER" \
  --service-name multica-autoscaler \
  --task-definition multica-autoscaler \
  --desired-count 1 \
  --launch-type FARGATE \
  --platform-version 1.4.0 \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-...],securityGroups=[sg-...],assignPublicIp=DISABLED}'
```

Check it before letting it touch anything:

```bash
aws ecs run-task --cluster "$ECS_CLUSTER" \
  --task-definition multica-autoscaler \
  --launch-type FARGATE \
  --overrides '{"containerOverrides":[{"name":"autoscaler","environment":[{"name":"AUTOSCALER_DRY_RUN","value":"1"}]}]}' \
  --network-configuration '...'
```

Then read the logs: every decision is logged as
`[service] pending=N → scale X → Y` or `— holding (reason)`.

## Sizing

| Role | CPU | Memory | Notes |
|---|---|---|---|
| base/node/python/go | 2 vCPU | 4 GB | Comfortable for tests and builds |
| php | 2 vCPU | 4 GB | Three embedded databases |
| devops | 2 vCPU | 4 GB | Terraform/Kubernetes work |
| qa | 2 vCPU | 4 GB | Playwright Chromium |
| design | 2 vCPU | 4 GB | Chromium + Penpot MCP |
| flutter | 4 vCPU | 8 GB | Android builds need headroom |

The template uses 4 vCPU / 8 GB for every role. Lower it per role if cost
matters; raise only Flutter. Task ephemeral storage defaults to 20 GB; Flutter
builds may need `ephemeralStorage.sizeInGiB` (up to 200).
