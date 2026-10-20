# Contributing

Thanks for taking the time to contribute. This project builds container images
that run autonomous coding agents, so correctness and reproducibility matter more
than speed.

## Before you start

- Read [AGENTS.md](AGENTS.md) if you are an AI agent working in this repo.
- For a bug, open an issue with the banner output (it contains no secrets), the
  command, and the relevant logs.
- For a security problem, **do not open a public issue**; see [SECURITY.md](SECURITY.md).

## Development loop

```bash
git clone https://github.com/ProReka/multica-runtime.git
cd multica-runtime

make lint          # versions, shell syntax, shellcheck, autoscaler tests
```

That is the full local check. It needs Bash, Python 3 and (optionally)
shellcheck. Docker is **not** required: CI builds the base on every pull request
and all variants on `main`.

If you do want a local image:

```bash
VARIANTS=base scripts/build.sh
VARIANTS=base scripts/test-image.sh
```

Be aware that a full local build of all variants is many gigabytes. Use CI for
the matrix.

## What makes a good PR

- **One concern.** A version bump, a bug fix, and a refactor are three PRs.
- **A test or a check.** Shell changes should keep `make lint` green. Autoscaler
  logic belongs in a pure function with a unit test.
- **A changelog entry** for user-visible changes.
- **Evidence.** Paste the relevant CI job or log lines. “Works on my machine” is
  not reviewable.
- **No secrets.** Not in code, logs, screenshots, or `.env.example` values.
- **Docs updated** when behaviour changes: configuration, variants, deployment.

## Adding a variant

1. `images/<name>/Dockerfile`:

   ```dockerfile
   ARG BASE_IMAGE=multica-runtime:base
   FROM ${BASE_IMAGE}
   ARG MY_TOOL_VERSION
   # install, verify --version
   ```

2. Add `MY_TOOL_VERSION` to `versions.env`. No default in the Dockerfile.
3. Add the context to `scripts/build.sh` and the expected binaries to
   `scripts/test-image.sh`.
4. Add it to the CI matrix in `.github/workflows/build.yml`.
5. Document it in `docs/variants.md` and the README table.

## Style

- Shell: `set -Eeuo pipefail`, quote expansions, Bash 3.2 compatible in host
  scripts (no associative arrays, no `mapfile`, no `${var,,}`).
- Dockerfile: one purpose per `RUN`, clean caches in the same layer, no version
  defaults.
- Python: standard library only, type hints, docstrings that explain *why*.
- Markdown: one sentence per line is fine; no trailing whitespace.

## Commit messages

Imperative subject, scoped when useful:

```text
fix(php): wait for postgres before creating the app user
feat(design): register the Penpot MCP server with both CLIs
docs: explain the bearer vs x-api-key choice
```

## Review

A maintainer reviews for:

- correctness under Fargate/Kubernetes (non-root, no privileged helpers);
- whether the change widens the secret or network surface;
- reproducibility (versions, checksums);
- whether the docs still tell the truth.

## Maintainer checklist

One-time setup after the first push:

- **Actions** must be allowed to create packages
  (`Settings → Actions → General → Workflow permissions`).
- **GitHub Pages** must use the “GitHub Actions” source; the docs workflow then
  deploys on every push to `main`.
- **GHCR packages** are private by default. Make
  `multica-runtime` and `multica-autoscaler` public if the images are meant to be
  pullable without a login (`Package settings → Change visibility`).

Per release:

1. Bump `versions.env` in a PR and let CI build it.
2. Merge to `main`; images are published as `:<variant>` and `:sha-<sha>-<variant>`.
3. Tag `vX.Y.Z`; the workflow adds `:vX.Y.Z-<variant>` and creates a GitHub
   release with generated notes.
4. Add a human-written summary to `CHANGELOG.md`.

## Code of conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
