# Upgrading

## Version scheme

Images are tagged three ways:

| Tag | Meaning | Use |
|---|---|---|
| `:base`, `:node`, … | Latest build of `main` | Development, hobby |
| `:v0.2.0-base` | Immutable release | Production |
| `:sha-abc1234-base` | Exact commit | Reproducing a bug |

A digest (`@sha256:…`) is the strongest pin. Tags can be moved; digests cannot.

## What an upgrade changes

- the agent CLI versions (`claude`, `opencode`);
- the toolchains (Node, PHP, Go, Flutter, …);
- the entrypoint logic.

It does **not** change your `/workspaces` volume. Session formats are owned by the
CLIs; a major CLI upgrade can make old sessions unreadable, but it never deletes
them.

## Procedure

```bash
# 1. Read the changelog
# https://github.com/ProReka/multica-runtime/blob/main/CHANGELOG.md

# 2. Pull the release
docker compose pull

# 3. Recreate
docker compose up -d

# 4. Watch the banner
docker compose logs -f runtime
```

For a pin:

```dotenv
MULTICA_IMAGE=ghcr.io/proreka/multica-runtime:v0.2.0-php
```

```bash
docker compose pull && docker compose up -d
```

## Verify, don't assume

After the container starts:

1. The banner shows the expected CLI and protocol.
2. Multica → **Runtimes** shows the same `MULTICA_DAEMON_ID` (no duplicate).
3. Assign a trivial task and confirm it completes.

If anything is wrong, roll back by restoring the previous image tag. The volume is
forward compatible; the old image will still read it.

## Zero-downtime is not a goal

Two containers with the same `MULTICA_DAEMON_ID` compete for tasks. Swarm and
Kubernetes manifests therefore use **stop-first** / **Recreate**. Expect a short
gap while the old runtime deregisters and the new one registers.

## Breaking changes

The changelog marks them. The public contract is:

- the four required environment variables;
- the `AI_*` aliases and their native fallbacks;
- the `/workspaces` layout (`.claude`, `.opencode/data`, task directories);
- the image tag names.

Anything else — internal entrypoint ordering, log wording, helper file names — may
change without notice.

## Upgrading a self-built image

If you build your own variant:

```bash
git pull
VARIANTS=base,myvariant scripts/build.sh
```

`versions.env` is the only file you edit to bump tools. Never add a version
default to a Dockerfile: `scripts/check-versions.sh` fails the build on purpose.
