# Multica Runtime

[![Build](https://github.com/ProReka/multica-runtime/actions/workflows/build.yml/badge.svg)](https://github.com/ProReka/multica-runtime/actions/workflows/build.yml)
[![Docs](https://github.com/ProReka/multica-runtime/actions/workflows/docs.yml/badge.svg)](https://proreka.github.io/multica-runtime/)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Images: GHCR](https://img.shields.io/badge/images-ghcr.io%2Fproreka%2Fmultica--runtime-2496ED?logo=docker&logoColor=white)](https://github.com/ProReka/multica-runtime/pkgs/container/multica-runtime)

**Docker images that turn Claude Code and OpenCode into Multica agents.**

One container, four environment variables, and you have an agent runtime that
picks up tasks, works in a real repository, and keeps its session history across
restarts.

```bash
cp .env.example .env      # MULTICA_TOKEN, AI_BASE_URL, AI_API_KEY, AI_MODEL
docker compose up -d
```

No CLI installation, no Node/PHP/Flutter toolchain on your laptop, no per-agent
configuration. Both agent CLIs are wired to the same endpoint from the same three
values.

---

## Why

Running a Multica agent normally means installing an agent CLI, keeping it current,
wiring it to a model endpoint, and repeating that on every machine. It gets worse
when tasks need different toolchains: a Laravel task needs PHP and three
databases, a Flutter task needs the Android SDK, a QA task needs Playwright and k6.

These images put the whole stack in a container that:

- ships **Claude Code + OpenCode**, both pointed at your AI router;
- registers with Multica automatically and runs the daemon in the foreground;
- runs as a **non-root** user (uid 1000) on Debian 13;
- keeps sessions on a volume, so a restart does not lose context;
- is **built and tested in CI** for `linux/amd64` and `linux/arm64`
  (Flutter is `amd64` only);
- pins every tool in one file — no floating versions, no auto-update surprises.

## Images

One package, one tag per stack:

```text
ghcr.io/proreka/multica-runtime:<variant>
```

| Tag | Toolchain | Use for |
|---|---|---|
| `base` | Node 24, Python 3, git/gh, Chromium, build tools | general tasks |
| `node` | pnpm, yarn, TypeScript, Playwright, vitest, eslint | web frontends |
| `python` | uv, Poetry, ruff, mypy, pytest | Python services |
| `php` | PHP 8.4, Composer, Laravel, MariaDB + PostgreSQL + Redis | Laravel/Symfony |
| `go` | Go, golangci-lint | Go services |
| `flutter` | Flutter, Android SDK, JDK 21, Gradle | mobile (amd64) |
| `devops` | Terraform, AWS CLI, kubectl, Helm, Docker CLI, Wrangler | infrastructure |
| `qa` | Playwright + MCP, axe-core, newman, k6, pytest | testing |
| `design` | ImageMagick, Playwright, Penpot MCP + plugin | UI/design |

Every variant includes Claude Code, OpenCode, the Multica CLI, git, gh, jq, and
Chromium. See [Variants](docs/variants.md).

## Configuration

Only four values are required:

```dotenv
MULTICA_TOKEN=...          # https://multica.ai/settings?tab=tokens
AI_BASE_URL=https://...    # Anthropic-compatible endpoint
AI_API_KEY=...
AI_MODEL=...
```

Native variables still work and win when both are set:

| Public | Native |
|---|---|
| `AI_BASE_URL` | `ANTHROPIC_BASE_URL` |
| `AI_API_KEY` | `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` |
| `AI_MODEL` | `ANTHROPIC_MODEL` |

The entrypoint picks `Authorization: Bearer` for routers and `x-api-key` for
Anthropic's own API, then generates the OpenCode config from the same values. See
[Configuration](docs/configuration.md).

## How it works

```text
tini
 └─ variant entrypoint                  php: databases · design: Xvfb + MCP
     └─ multica-entrypoint
         1. resolve AI_* → ANTHROPIC_*
         2. configure Claude Code + OpenCode
         3. log in to Multica
         4. exec multica daemon start --foreground
```

The daemon detects both CLIs and registers one runtime per CLI. Sessions live on
`/workspaces` (`.claude`, `.opencode/data`). See [Architecture](docs/architecture.md).

## Deployment

| Target | Guide |
|---|---|
| Docker Compose | [docs/deployment/compose.md](docs/deployment/compose.md) |
| Docker Swarm | [docs/deployment/swarm.md](docs/deployment/swarm.md) |
| Amazon ECS (Fargate) | [docs/deployment/ecs.md](docs/deployment/ecs.md) |
| Kubernetes | [docs/deployment/kubernetes.md](docs/deployment/kubernetes.md) |
| Dokploy | [docs/deployment/dokploy.md](docs/deployment/dokploy.md) |

The optional [autoscaler](docs/autoscaling.md) scales each role between 0 and 1
based on pending agent tasks, with cooldown, grace, and running-task guards.

## Documentation

- [Quickstart](docs/quickstart.md)
- [Configuration](docs/configuration.md)
- [Variants](docs/variants.md)
- [Architecture](docs/architecture.md)
- [Agent CLIs](docs/agents.md)
- [Persistence](docs/persistence.md)
- [Autoscaling](docs/autoscaling.md)
- [Troubleshooting](docs/operations/troubleshooting.md)
- [Security](docs/operations/security.md)
- [Upgrading](docs/operations/upgrading.md)
- [FAQ](docs/faq.md)

The same content is published at **<https://proreka.github.io/multica-runtime/>**.

## Requirements

- Docker 24+ (Compose v2) or any orchestrator that can run a container
- A Multica token
- An Anthropic-compatible endpoint, or an OpenAI-compatible router
  (detected automatically)

No GPU, no privileged mode, no Docker socket — except for the optional Swarm
autoscaler, which needs it to call `docker service scale`.

## Security

The agent runs arbitrary code by design. Treat the container as a sandbox for
convenience, not as a security boundary against a malicious task. Scope the
Multica and GitHub tokens accordingly.

- no secrets in image layers;
- non-root everywhere;
- no inbound ports;
- pinned, checksum-verified tool downloads;
- provenance and SBOM attestations on published images.

Read [Security](docs/operations/security.md) and report vulnerabilities privately
per [SECURITY.md](SECURITY.md).

## Status

Claude Code and OpenCode are supported now. **Codex CLI is coming soon** — see the
[roadmap](docs/roadmap.md).

## Contributing

Issues and PRs are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and
[Development](docs/development.md). CI builds the base image on every pull
request and the full variant matrix on `main`; a local Docker daemon is optional.
is optional.

## License

[Apache-2.0](LICENSE).
