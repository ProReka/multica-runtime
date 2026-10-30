# Architecture

## Image graph

```
                 debian:trixie-slim
                         │
                  ┌──────▼──────┐
                  │    base     │  Node 26 · Python 3 · git/gh · Chromium
                  │             │  Claude Code · OpenCode · Multica CLI
                  └──────┬──────┘
      ┌──────────┬───────┼────────┬─────────┬──────────┬────────┐
      ▼          ▼       ▼        ▼         ▼          ▼        ▼
    node      python    php       go     flutter    devops     qa
      │
      └──────────────► design (adds Penpot MCP + Xvfb)

  autoscaler  ← FROM base + AWS CLI + Docker CLI
```

All variant images are built from `base`, so a base-layer change is one rebuild
and every variant picks it up. The base image is published first; variants use
`BASE_IMAGE` to point at either the local tag or the registry tag.

## Build pipeline

`versions.env` is the single source of truth. `scripts/build.sh` reads it, exports
every key, and passes each one as a `--build-arg`. Dockerfile `ARG`s have **no
defaults**, so a build that forgets a version fails immediately instead of
producing an unpinned image. `scripts/check-versions.sh` enforces this in CI.

Downloads are checksum-verified wherever upstream publishes a checksum:

- Node tarball (`SHASUMS256.txt`)
- GitHub CLI, Multica CLI (release `checksums.txt`)
- Terraform (`SHA256SUMS`), kubectl (`.sha256`), Helm (`.sha256sum`)
- Docker Compose, uv, k6, golangci-lint
- Composer installer (signature)

Go's `.sha256` URL does not exist; the checksum comes from the JSON release
manifest at `https://go.dev/dl/?mode=json&include=all`.

## What happens at container start

```
tini
 └─ variant entrypoint                   (php: databases; design: Xvfb + MCP)
     └─ /usr/local/bin/multica-entrypoint
         1. validate MULTICA_TOKEN
         2. resolve AI_* → ANTHROPIC_*  (native wins)
         3. derive model tiers
         4. configure Claude Code       (CLAUDE_CONFIG_DIR on /workspaces)
         5. configure OpenCode          (probe /v1/models, write 0600 config)
         6. run variant hooks           (design: register Penpot MCP)
         7. configure git / gh          (optional)
         8. print banner                (no secrets)
         9. multica login --token
        10. exec multica daemon start --foreground
```

The daemon is the foreground process. `tini` forwards `SIGTERM`; the daemon
deregisters its runtimes and exits. `stop_grace_period: 90s` gives a running task
time to finish.

If you set `MULTICA_DRY_RUN=1`, execution stops after step 8.

### Why the entrypoint is split

| File | Responsibility |
|---|---|
| `lib/common.sh` | logging, boolean parsing, URL helpers, hooks |
| `lib/config.sh` | `AI_*` resolution, credential style, model tiers |
| `lib/claude.sh` | `CLAUDE_CONFIG_DIR`, update/traffic policy |
| `lib/opencode.sh` | catalogue probe, config generation, model refs |
| `lib/git.sh` | git identity, `gh auth setup-git` |
| `lib/banner.sh` | secret-free startup summary |
| `entrypoint.sh` | ordering, login, daemon |

Each concern can be read and tested on its own. Variants extend the sequence by
dropping a file into `/usr/local/lib/multica/hooks/` — the design image uses this
to register the Penpot MCP server without the base image knowing what Penpot is.

## Security posture

- **Non-root.** Everything runs as `runner` (uid/gid 1000). The design image does
  not need root for Xvfb or the MCP server; the PHP databases run as `runner` with
  data under `/tmp`. There is no `gosu`, no `setpriv` privilege drop at runtime,
  and therefore no dependency on ptrace/seccomp behaviour that Fargate blocks.
- **No inbound port.** The runtime connects out to Multica and the AI router.
- **Secrets stay at runtime.** No token or key is in any layer. OpenCode's config
  is written at start with mode `0600`.
- **Agent CLIs do not self-update.** The image is the version.
- **No Docker socket**, except the optional Swarm autoscaler, which needs it to
  call `docker service scale`. The ECS adapter uses IAM instead.

See [Security](operations/security.md) for the threat model.

## Why Debian 13 (`trixie-slim`)

- Current stable at the time of writing; long support window.
- Packages the agent toolchains need (PHP 8.4, Python 3.13, Chromium, MariaDB,
  PostgreSQL) are available without third-party repositories.
- `slim` keeps the base small; anything heavy is installed explicitly.

Node comes from the official tarball rather than Debian's package, so the version
is pinned exactly (24.x LTS) and not tied to the distro release.

## Healthcheck

The image declares:

```dockerfile
HEALTHCHECK CMD pgrep -f "multica daemon" >/dev/null || exit 1
```

It is intentionally shallow: it answers “is the daemon process alive?”, not “is
the AI router healthy?”. A router outage should not restart every runtime and
lose in-flight sessions. Orchestrators that ignore Docker healthchecks (ECS) get
the same command in the task definition.
