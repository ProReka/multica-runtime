# AGENTS.md

Operating instructions for AI agents contributing to **multica-runtime**.

This file is about *how to work here*. It contains no volatile data — no image
digests, no version numbers, no build status. Those live in `versions.env`, the
CI run, and `CHANGELOG.md`.

## 1. Hard rules

1. **Build in CI, not on a laptop.** A full build of every variant is many
   gigabytes. Do not run `docker build`, `docker compose up`, or any container
   locally unless the human explicitly asks. Lint and test with `make lint`.
2. **Never commit a secret.** No token, key, `.env`, customer data, or credential
   in any tracked file, commit message, log, or screenshot.
3. **One source of versions.** Every tool version lives in `versions.env`. Dockerfile
   version `ARG`s have **no defaults**; `scripts/check-versions.sh` enforces it.
4. **Non-root by default.** New variants run as `runner` (uid 1000). Do not add
   `gosu`, `setpriv` privilege drops, setuid binaries, or a root runtime stage.
   Build-time root is fine; the final stage must switch back.
5. **No privileged containers.** No `--privileged`, no host PID/network, no added
   capabilities. The only Docker socket in the project is the optional Swarm
   autoscaler, already documented.
6. **No inbound ports.** The runtime is an outbound worker. Do not add a web
   server to the base image or publish a port in examples.
7. **Do not weaken a security control to make a build pass.** Fix the build.
8. **Do not let agent CLIs auto-update.** `DISABLE_AUTOUPDATER=1` and
   `autoupdate: false` stay.
9. **`make lint` must pass** before you report done.
10. **Do not commit or push** unless the human asked for it in that turn. Prepare
    the change and report it.
11. **Do not "fix" unrelated things.** Report them instead.

## 2. Repository map

| Path | Purpose |
|---|---|
| `images/base/` | Base Dockerfile, entrypoint, `lib/*.sh` |
| `images/<variant>/` | One Dockerfile per stack; variants inherit `base` |
| `autoscaler/` | Python autoscaler and unit tests |
| `scripts/build.sh` | Build entrypoint (local and CI) |
| `scripts/test-image.sh` | Binary + entrypoint smoke tests |
| `scripts/check-versions.sh` | Version consistency checks |
| `deploy/` | Compose, Swarm, ECS, Kubernetes, Dokploy examples |
| `docs/` | Documentation (MkDocs Material) |
| `versions.env` | Single source of truth for tool versions |
| `compose.yaml` | Single-host quickstart |

## 3. How to validate

```bash
make lint          # versions + bash -n + shellcheck + autoscaler tests
```

Optional, only with a local Docker daemon and explicit human approval:

```bash
VARIANTS=base scripts/build.sh
VARIANTS=base scripts/test-image.sh base
```

CI builds and smoke-tests the base on every pull request, and the full variant
matrix on `main`. A PR is not “verified” because a single local variant built;
say what you ran.

## 4. Changing things

### Add or bump a tool

1. Edit `versions.env`.
2. Reference it as `ARG TOOL_VERSION` (no default) in the Dockerfile.
3. Use it, verify with `tool --version` in the same layer.
4. If upstream publishes a checksum, verify it.
5. `make lint`.

### Add a variant

1. `images/<name>/Dockerfile` with `ARG BASE_IMAGE=multica-runtime:base` and
   `FROM ${BASE_IMAGE}`.
2. Add versions to `versions.env`.
3. Add the context to `scripts/build.sh` and binaries to `scripts/test-image.sh`.
4. Add the matrix entry in `.github/workflows/build.yml`.
5. Document in `docs/variants.md` and the README table.
6. If it needs a side service, use a variant entrypoint that `exec`s
   `/usr/local/bin/multica-entrypoint`. If it only needs to amend CLI config, add
   a hook under `/usr/local/lib/multica/hooks/`.

### Change the entrypoint

- Helpers are sourced; they must not execute anything on their own.
- Keep Bash 3.2 compatibility in host scripts (macOS): no associative arrays, no
  `mapfile`, no `${var,,}`.
- Never print a secret. Use `redact_url` or print only a variable name.
- A failed optional step logs a warning; a failed required step calls `die`.
- Add a line to `scripts/test-image.sh` if the change is observable in dry run.

### Change the autoscaler

- Pure decision logic (`wanted_replicas`, `scale_down_blocked`, `load_runtimes`)
  stays pure and unit-tested.
- Adapters (Multica CLI, AWS, Docker) stay thin.
- A new scale-down guard needs a test proving it holds.
- `--dry-run`, `--once`, `--check`, and `--health` must keep working.

## 5. Definition of done

- [ ] `make lint` passes.
- [ ] No secret in any tracked file.
- [ ] Version ARGs have no defaults and are in `versions.env`.
- [ ] New runtime code runs as uid 1000.
- [ ] No new privileged requirement, inbound port, or Docker socket.
- [ ] `docs/` updated if behaviour changed.
- [ ] `CHANGELOG.md` entry for user-visible changes.
- [ ] CI green on the PR (or the human has explicitly accepted running it after
      merge).
- [ ] Only the intended files changed.

## 6. Division of labour

**Agent may:** read anything, edit files, write docs, run `make lint`, run the
autoscaler unit tests, open a PR.

**Human must:** approve a Docker build/run on their machine, rotate credentials,
publish a release, change registry settings, accept a security trade-off.
