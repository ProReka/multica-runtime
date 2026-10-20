# Docker Compose

Best for a single host, a laptop, or a small team.

```bash
cp .env.example .env
$EDITOR .env

docker compose up -d
docker compose logs -f runtime
```

For a production host, add the overlay:

```bash
docker compose -f compose.yaml -f deploy/compose/compose.production.yaml up -d
```

It adds log rotation, a memory ceiling, and `no-new-privileges`.

## Choose the variant

```dotenv
MULTICA_IMAGE=ghcr.io/proreka/multica-runtime:php
```

## Autoscaler

The optional profile scales Swarm services, so it is only useful when the host is
part of a swarm. On a plain compose host, run the runtime continuously.

```bash
docker compose --profile autoscaler up -d
```

It mounts the Docker socket. See [Autoscaling](../autoscaling.md).

## State

The `multica-workspaces` volume holds sessions. Back it up before upgrades if you
care about `claude --resume` history; see [Persistence](../persistence.md).

## Compose is not an orchestrator

`restart: unless-stopped` will start the container again after a crash, but there
is no rollout strategy and no placement constraint. If you need those, use
[Swarm](swarm.md) or [ECS](ecs.md).
