# Docker Swarm

Swarm is the simplest way to keep one runtime per role. It also gives you a
manager-controlled restart policy and a stop-first update order, which matters:
two containers sharing one `MULTICA_DAEMON_ID` would compete for the same tasks.

## Prepare a node

```bash
docker swarm init                     # once, on the manager
docker node update --label-add multica.runtime=true "$(hostname)"
```

The `multica.runtime` label is what the stack's placement constraint looks for.
Label every node that may run a runtime.

## Deploy one role

```bash
set -a; . ./.env; set +a
docker stack deploy -c deploy/swarm/stack.yml multica-node
```

Use a distinct `MULTICA_DAEMON_ID` and `MULTICA_IMAGE` per role:

```bash
MULTICA_IMAGE=ghcr.io/proreka/multica-runtime:node \
MULTICA_DAEMON_ID=multica-node \
  docker stack deploy -c deploy/swarm/stack.yml multica-node

MULTICA_IMAGE=ghcr.io/proreka/multica-runtime:php \
MULTICA_DAEMON_ID=multica-php \
  docker stack deploy -c deploy/swarm/stack.yml multica-php
```

`docker stack deploy` ignores `env_file` and interpolates from the shell, which
is why the commands export `.env` first.

## Update

```bash
docker pull ghcr.io/proreka/multica-runtime:node
docker service update --image ghcr.io/proreka/multica-runtime:node multica-node_runtime
```

`order: stop-first` in the stack file makes the old container stop (and
deregister) before the new one starts.

## Autoscaler

```bash
set -a; . ./.env; set +a
docker stack deploy -c deploy/swarm/autoscaler.yml multica-autoscaler
```

The autoscaler runs on a manager because it calls `docker service scale`. The
Docker socket is root-equivalent; keep the autoscaler image pinned and limit who
can deploy to the swarm.

## Logs and state

```bash
docker service logs -f multica-node_runtime
docker volume inspect multica-node_workspaces
```

The volume is local to the node that runs the container. If you need a runtime
to move between nodes, use a shared volume driver or pin the role with a
placement constraint.
