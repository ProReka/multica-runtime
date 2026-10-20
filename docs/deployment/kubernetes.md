# Kubernetes

One Deployment, one PVC, no Service.

```bash
kubectl create secret generic multica-runtime --from-env-file=.env
kubectl apply -f deploy/kubernetes/deployment.yaml
kubectl logs -f deploy/multica-runtime
```

## Why `Recreate`

Two pods sharing a `MULTICA_DAEMON_ID` compete for tasks. The Deployment uses
`strategy: Recreate`, so the old pod terminates before the new one starts.

## Why no Service

The runtime is an outbound worker. It connects to Multica and your AI router and
never accepts inbound traffic. The design image's MCP/plugin ports are reached by
the agent over `127.0.0.1` inside the same pod; expose them only if you have a
specific reason to.

## Security context

The manifest:

- runs as uid/gid `1000`, `runAsNonRoot: true`;
- sets `fsGroup: 1000` so the PVC is writable;
- drops all capabilities;
- disallows privilege escalation;
- uses `RuntimeDefault` seccomp.

No privileged mode, no hostPath, no Docker socket.

## Storage

`ReadWriteOnce` is enough for one replica but pins the pod to a node while the
volume is attached. For rescheduling, use `ReadWriteMany` (EFS, CephFS, NFS).
See [Persistence](../persistence.md).

## Autoscaling

Not supported by the bundled autoscaler (ECS/Swarm only). Run one replica, or
drive a `CronJob`/KEDA from the pending-task signal. See [Autoscaling](../autoscaling.md).

## Updating

```bash
kubectl set image deploy/multica-runtime \
  runtime=ghcr.io/proreka/multica-runtime:v0.2.0-base
kubectl rollout status deploy/multica-runtime
```

Sessions survive because `/workspaces` is a PVC.
