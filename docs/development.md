# Development

## CI builds Docker. You do not have to.

Every image is built in GitHub Actions. A pull request builds and smoke-tests the
base; merging to `main` builds and pushes the full variant matrix. A local Docker
daemon is optional and only useful for fast iteration.

Lint, version checks, and the autoscaler tests need nothing but Bash, Python and
(optionally) shellcheck:

```bash
make lint
```

That runs:

- `scripts/check-versions.sh` — `versions.env` matches every Dockerfile, no
  version ARG has a default;
- `bash -n` on every script;
- `shellcheck --severity=warning` when installed;
- the autoscaler unit tests.

## Repository layout

```
images/base/            base Dockerfile, entrypoint, lib/*.sh
images/<variant>/       one Dockerfile per variant
autoscaler/             Python autoscaler + unit tests
scripts/                build.sh, test-image.sh, check-versions.sh
deploy/                 compose, swarm, ecs, kubernetes, dokploy examples
docs/                   this documentation
versions.env            single source of truth for every tool version
compose.yaml            quickstart
```

## Building locally (optional)

```bash
VARIANTS=base scripts/build.sh
VARIANTS=base,node scripts/test-image.sh
```

`scripts/build.sh` loads `versions.env`, exports every key, and passes each as a
build arg. A push build publishes `base` first, then the variants that inherit
from it.

```bash
PUSH=1 VERSION=0.2.0 scripts/build.sh
```

That is for maintainers with registry credentials; CI does it automatically.

## Releasing

Images are published from `main` on every push. A release adds immutable version
tags, runs the runtime checks and creates a GitHub release:

```bash
git tag -a v0.3.0 -m "Multica Runtime v0.3.0"
git push origin v0.3.0
```

This publishes `v0.3.0`, `v0.3.0-base` … `v0.3.0-design` and
`multica-autoscaler:v0.3.0`, then creates the release.

Do not tag a commit whose message contains `[skip ci]`. GitHub Actions treats
that marker as "do not run workflows for this commit" and the tag push is
skipped too. If that happens, dispatch the Build workflow with
`--ref v0.3.0 -f variants=all -f push=true`; the tag is still read from the ref.

## Adding a variant

1. Create `images/<name>/Dockerfile` starting with:

   ```dockerfile
   ARG BASE_IMAGE=multica-runtime:base
   FROM ${BASE_IMAGE}
   ```

2. Declare version ARGs **without defaults**:

   ```dockerfile
   ARG MY_TOOL_VERSION
   ```

   The value must exist in `versions.env`.

3. Install the tool, verify it runs (`mytool --version`), and leave the base
   `ENTRYPOINT` in place unless you need a variant entrypoint.

4. Add the context to `scripts/build.sh` (`context_for`) and the expected
   binaries to `scripts/test-image.sh` (`commands_for`).

5. Add it to the CI matrix in `.github/workflows/build.yml`.

6. Document it in `docs/variants.md` and the README table.

Run `make lint`. CI builds it on the PR.

## Adding a version

```dotenv
# versions.env
MY_TOOL_VERSION=1.2.3
```

One line. Do not add a default to the Dockerfile — `check-versions.sh` rejects
it, because a default is how an image silently stops being pinned.

## Variant entrypoints and hooks

Most variants inherit the base entrypoint unchanged. Two mechanisms exist:

- **A variant entrypoint** (`images/php`, `images/design`) runs before the base
  one, starts side services, then `exec`s `/usr/local/bin/multica-entrypoint`.
- **A hook** (`/usr/local/lib/multica/hooks/*.sh`) is sourced *after* Claude Code
  and OpenCode are configured. The design image uses this to register the Penpot
  MCP server with both CLIs.

Hooks run in lexical order and get the resolved environment (`CLAUDE_CONFIG_DIR`,
`MR_*`, config paths). A failing hook logs a warning and does not abort startup.

## Style

- Shell: Bash 3.2 compatible in scripts that may run on macOS (no associative
  arrays, no `mapfile`, no `${var,,}`). `set -Eeuo pipefail`.
- Prefer `local`; quote expansions; fail loudly.
- Dockerfile: one purpose per layer, `set -eux`, clean apt lists and caches in the
  same layer.
- Python: standard library only for the autoscaler, type hints, docstrings that
  explain *why*.
- Prose: explain decisions, not mechanics. No secrets, ever.

## Commits and PRs

- Small, focused commits with an imperative subject
  (`fix(php): wait for postgres before creating the user`).
- A PR should say what changed, why, and how it was verified. CI attaches the
  build; paste the relevant log lines rather than “works on my machine”.
- Update `CHANGELOG.md` for user-visible changes.
- Do not commit `.env`, generated inventory, or build artifacts.

## Release

1. Bump `versions.env` in a PR (Dependabot does this weekly).
2. Merge to `main`; CI builds and pushes `:base`, `:node`, … and `:sha-*`.
3. Tag `vX.Y.Z`; CI rebuilds and publishes `:vX.Y.Z-base`, … plus `:latest`.
4. Add the changelog entry.

## Testing the entrypoint without a daemon

```bash
docker run --rm \
  --entrypoint /usr/local/bin/multica-entrypoint \
  -e MULTICA_TOKEN=test \
  -e AI_BASE_URL=http://127.0.0.1:9/v1 \
  -e AI_API_KEY=test \
  -e AI_MODEL=test-model \
  -e AI_MODELS_PROBE=0 \
  -e MULTICA_DRY_RUN=1 \
  ghcr.io/proreka/multica-runtime:base
```

It resolves the config, writes the OpenCode file, prints the banner, and exits
without contacting Multica. `scripts/test-image.sh` does exactly this per variant.
