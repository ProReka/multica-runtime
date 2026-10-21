# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Roadmap for new agent CLI adapters: Codex CLI, Qwen Code, Grok Build, DeepSeek
  Harness, Pi, Oh-My-Pi, Hermes Agent and OpenClaw.
- Autoscaler design notes for a metrics endpoint, KEDA, a signed webhook, Nomad,
  and the limits of Docker Compose standalone.

## [0.2.0] - 2026-10-21

### Added

- Initial public release.
- Base image on Debian 13 with Node.js 24, Python 3, git/gh, Chromium, build
  tools, Claude Code, OpenCode, and the Multica CLI.
- Variants: `node`, `python`, `php`, `go`, `flutter`, `devops`, `qa`, `design`.
- Small configuration surface: `MULTICA_TOKEN`, `AI_BASE_URL`, `AI_API_KEY`,
  `AI_MODEL`, with native `ANTHROPIC_*` fallbacks.
- Automatic protocol detection (`/v1/models`) and OpenCode provider generation.
- Session persistence on `/workspaces` for both agent CLIs.
- Non-root runtime (uid/gid 1000) across every variant.
- PHP image with MariaDB, PostgreSQL, and Redis inside the container.
- Design image with Xvfb, Penpot MCP server and plugin, built at image time.
- Task-driven autoscaler for ECS and Swarm, with cooldown, grace, and
  running-task guards, `--once`, `--dry-run`, `--check`, and `--health`.
- CI: lint, version consistency, autoscaler tests, multi-arch builds, image smoke
  tests, runtime tests for the PHP databases and design MCP stack, GHCR
  publishing with provenance and SBOM, and a tagged GitHub release.
- Deployment examples for Compose, Swarm, ECS Fargate, Kubernetes, and Dokploy.
- Documentation site (MkDocs Material) and three ADRs.

### Security

- Checksum verification for every upstream artifact that publishes one.
- No secrets in image layers; OpenCode config written with mode `0600`.
- No privileged mode, no Docker socket except the optional Swarm autoscaler.

[Unreleased]: https://github.com/ProReka/multica-runtime/compare/v0.2.0...main
[0.2.0]: https://github.com/ProReka/multica-runtime/releases/tag/v0.2.0
