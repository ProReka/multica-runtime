# Docker Compose

The repository root [`compose.yaml`](../../compose.yaml) is the quickstart. For a
single production host, add the overlay:

```bash
cp .env.example .env
$EDITOR .env

docker compose -f compose.yaml -f deploy/compose/compose.production.yaml up -d
docker compose logs -f runtime
```

## Choosing a variant

Set `MULTICA_IMAGE` in `.env`:

```dotenv
MULTICA_IMAGE=ghcr.io/proreka/multica-runtime:php
```

| Variant | Image tag |
|---|---|
| Base | `ghcr.io/proreka/multica-runtime:base` |
| Node/web | `:node` |
| Python | `:python` |
| PHP/Laravel | `:php` |
| Go | `:go` |
| Flutter | `:flutter` |
| DevOps | `:devops` |
| QA | `:qa` |
| UI/Design | `:design` |

## Persistent state

Sessions live in the `multica-workspaces` named volume:

```
/workspaces/.claude             Claude Code transcripts
/workspaces/.opencode/data      OpenCode session data
/workspaces/.penpot-browser     Penpot browser profile (design image)
/workspaces/<task-id>/          task working directories
```

Back it up with a throwaway container:

```bash
docker run --rm -v multica-workspaces:/data -v "$PWD":/backup \
  alpine tar czf /backup/multica-workspaces.tgz -C /data .
```

## Bind mounts

The image runs as uid/gid `1000`. If you replace the named volume with a bind
mount, make it writable first:

```bash
sudo chown -R 1000:1000 /srv/multica-workspaces
```

## Updating

```bash
docker compose pull
docker compose up -d
```

Pin a release tag (`:v0.2.0-base`) instead of `:base` if you want upgrades to be
deliberate. Session data survives an image upgrade; the agent CLIs are pinned
inside the image and do not auto-update.
