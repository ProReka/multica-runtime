# Docker Swarm

The smallest orchestrator that gives you restart policies, placement constraints,
and a controlled update order.

```bash
docker swarm init
docker node update --label-add multica.runtime=true "$(hostname)"

set -a; . ./.env; set +a
docker stack deploy -c deploy/swarm/stack.yml multica-node
```

`docker stack deploy` ignores `env_file`, so the stack interpolates from the shell
— export `.env` first.

## One stack per role

```bash
MULTICA_IMAGE=ghcr.io/proreka/multica-runtime:node \
MULTICA_DAEMON_ID=multica-node \
  docker stack deploy -c deploy/swarm/stack.yml multica-node

MULTICA_IMAGE=ghcr.io/proreka/multica-runtime:php \
MULTICA_DAEMON_ID=multica-php \
  docker stack deploy -c deploy/swarm/stack.yml multica-php
```

Each role has its own stack, service, volume and daemon id.

## Why `stop-first`

The stack uses:

```yaml
update_config:
  order: stop-first
```

A rolling update would briefly run two containers with the same
`MULTICA_DAEMON_ID`. They would compete for tasks. Stop-first makes the old
container deregister before the new one starts.

## Autoscaler

```bash
set -a; . ./.env; set +a
docker stack deploy -c deploy/swarm/autoscaler.yml multica-autoscaler
```

It must run on a manager and needs the Docker socket. See
[Autoscaling](../autoscaling.md) for the configuration.

## Logs

```bash
docker service logs -f multica-node_runtime
docker service ps multica-node_runtime
```
