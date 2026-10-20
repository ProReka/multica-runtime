# Persistence

A runtime is disposable. The *sessions* are not. Everything that must survive a
restart, upgrade, or scale-to-zero lives on one volume.

## What is on the volume

| Path | Owner | Contents |
|---|---|---|
| `/workspaces/.claude` | Claude Code | Transcripts and config (`CLAUDE_CONFIG_DIR`) |
| `/workspaces/.opencode/data` | OpenCode | Session data (`XDG_DATA_HOME`) |
| `/workspaces/.penpot-browser` | design image | Chromium profile with the Penpot session |
| `/workspaces/.penpot` | design image | MCP/plugin/Xvfb logs |
| `/workspaces/<task-id>` | Multica daemon | Task checkouts and working files |

The daemon skips dot-directories at the workspace root, so the state directories
are never mistaken for task workspaces.

## What is not

- `/tmp/multica-db` (PHP databases) — recreated on every start;
- the OpenCode config at `~/.config/opencode/opencode.json` — regenerated at start;
- anything the agent installs into the image at runtime (it is thrown away).

That is intentional: a database or a half-installed toolchain inside a runtime is
not a source of truth.

## Docker Compose

A named volume is created on first start:

```yaml
volumes:
  workspaces:
    name: multica-workspaces
```

It inherits the ownership of `/workspaces` from the image (`runner:runner`,
1000:1000), so no `chown` is needed.

### Bind mount instead?

The container runs as uid/gid 1000. A host directory is usually owned by your own
user (often 501 on macOS, 1000 on Linux). Make it writable:

```bash
sudo mkdir -p /srv/multica-workspaces
sudo chown -R 1000:1000 /srv/multica-workspaces
```

Without this, the entrypoint logs a warning and Claude/OpenCode fall back to
ephemeral home directories — sessions look like they vanish on restart.

## Backup

Stop the container (or accept a consistent-enough copy), then archive the volume:

```bash
docker run --rm \
  -v multica-workspaces:/data:ro \
  -v "$PWD":/backup \
  alpine tar czf /backup/multica-workspaces-$(date +%F).tgz -C /data .
```

Restore:

```bash
docker run --rm \
  -v multica-workspaces:/data \
  -v "$PWD":/backup \
  alpine sh -c 'cd /data && tar xzf /backup/multica-workspaces-YYYY-MM-DD.tgz'
```

## Amazon ECS

Fargate has no persistent local disk. Mount EFS at `/workspaces`:

- EFS access point with POSIX user `1000:1000`;
- transit encryption enabled;
- IAM authorization, with a task role that has `ClientMount`/`ClientWrite`.

The task definition in [`deploy/ecs`](https://github.com/ProReka/multica-runtime/tree/main/deploy/ecs)
wires this up. Without EFS, every task restart starts with amnesia.

EFS is slower than local disk. Checkouts and builds on a large repository will
feel it. If that matters, run the runtime on EC2/Swarm with a local volume instead
of Fargate, or keep the task alive (scale-to-zero off) so EFS is read once.

## Kubernetes

The manifest uses a `ReadWriteOnce` PVC. The pod cannot move to another node while
the volume is attached. For rescheduling, use a `ReadWriteMany` class and keep one
replica.

## Evolution

The volume layout is part of the public contract. New state directories are added
as dot-directories; existing ones are not moved without a migration note in the
[changelog](https://github.com/ProReka/multica-runtime/blob/main/CHANGELOG.md).
