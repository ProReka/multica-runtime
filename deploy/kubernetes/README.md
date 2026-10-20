# Kubernetes

```bash
kubectl create secret generic multica-runtime --from-env-file=.env
kubectl apply -f deploy/kubernetes/deployment.yaml
kubectl logs -f deploy/multica-runtime
```

## What the manifest does

- Runs one replica with `strategy: Recreate`. Two pods with the same
  `MULTICA_DAEMON_ID` would compete for the same tasks, so a rolling update is
  wrong here.
- Runs as uid/gid `1000`, drops all capabilities, disallows privilege
  escalation, and uses the `RuntimeDefault` seccomp profile.
- Mounts a `ReadWriteOnce` PVC at `/workspaces` for Claude Code and OpenCode
  session history.
- Has no Service. The runtime is an outbound-only worker.

## Choosing a variant

Change the image tag:

```yaml
image: ghcr.io/proreka/multica-runtime:php
```

The design image also needs ports `4400`/`4401` only if you want to reach the
Penpot plugin/MCP from outside the pod; the agent itself uses `127.0.0.1`, so no
Service is required.

## Storage

`ReadWriteOnce` means the pod cannot move to another node while the volume is
attached. That is acceptable for a single runtime. If you need rescheduling
across nodes, use a `ReadWriteMany` class (EFS, CephFS, NFS) and keep one replica.

## Autoscaling

The bundled autoscaler supports ECS and Swarm only. Kubernetes users should
scale with a `CronJob`/KEDA based on the same signal (pending agent tasks) or run
the runtime at one replica permanently. A Kubernetes adapter is on the roadmap;
see [docs/roadmap.md](../../docs/roadmap.md).

## Updating

```bash
kubectl set image deploy/multica-runtime runtime=ghcr.io/proreka/multica-runtime:v0.2.0-base
kubectl rollout status deploy/multica-runtime
```

The image pins both agent CLIs, so an update is the only thing that changes
their version — never an in-place auto-update.
