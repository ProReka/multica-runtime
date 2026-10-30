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

### Changed

- Update Multica CLI to 0.7.2. Automatically recover `repo checkout` failures
  caused by orphaned target directories: preserve files under
  `/workspaces/.checkout-recovery`, prune stale registrations, and retry once.
  Serialize same-task checkouts; never move Git checkouts or symlinks.
- Build only affected images, map version changes to Dockerfile ARGs, and skip
  Docker for documentation-only changes. Keep PHP/design runtime tests in their
  image jobs; limit variant publication to three concurrent jobs.
- Automatically publish a patch release after successful image-changing main
  builds by promoting existing GHCR manifests. Tag pushes no longer rebuild
  every image. Run the full standalone lint workflow on PRs, not again on merge.

- Refresh pinned tools to upstream stable releases checked on 2026-10-30:
  Multica CLI 0.7.1, Claude Code 2.1.314, OpenCode V1 1.19.5, Node.js 26.13.0 LTS,
  GitHub CLI 2.103.3, pnpm 12.16.1, Wrangler 4.156.0, uv 0.13.6, Ruff 0.17.3,
  mypy 2.4.1, pytest 9.2.0, fontTools 4.68.0, Flutter 3.47.9,
  Android command-line tools 16111833, Terraform 1.17.1, kubectl 1.37.2,
  AWS CLI 2.39.2, Docker CLI 29.9.2, and Docker Compose 5.6.1.
- Keep OpenCode on the V1 `opencode-ai` package for Multica-managed MCP
  compatibility, with automatic updates disabled.
- Add Android platform 37.2 and build-tools 37.0.0; update retained build-tools
  to 36.1.0 and 35.0.1. Keep Android platforms 36 and 35 for compatibility.

### Fixed

- Install `libatomic1` in both base-image stages for Node.js 26's shared-library
  dependency.
- Prune expired stale Git worktree registrations in cached repositories before
  daemon startup, reducing checkout failures after interrupted tasks without
  deleting task files or valid worktrees.

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
