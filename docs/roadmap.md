# Roadmap

What is planned, in rough order. Nothing here is a promise; issues and PRs are
welcome.

## Next

### Codex CLI

OpenAI's Codex CLI is **not installed yet** on purpose. It needs its own
configuration path and a model endpoint that may differ from the Anthropic-compatible
one. When it lands:

- it will be a third runtime registered by the same daemon;
- `AI_*` will keep driving Claude Code and OpenCode, with `CODEX_*` overrides;
- it will be opt-in per image tag first (`:base-codex`) before becoming default.

### Kubernetes autoscaler adapter

The autoscaler supports ECS and Swarm. A Kubernetes adapter would patch
`Deployment.spec.replicas` through the API, with the same scale-down guards.
Until then: one replica, or KEDA on the pending-task signal.

### Signed images

GHCR currently gets provenance and SBOM attestations. Next: cosign signatures and
a verification snippet in the docs.

## Later

- **Flutter on arm64** — blocked on Google's Android build tools. Flutter web and
  Linux desktop already work there.
- **A smaller `:base`** — split optional tools (Chromium, build-essential) into a
  `:slim` tag for agents that only read and write.
- **More stacks** — Rust, .NET, Ruby on Rails. Same pattern: one directory, one
  Dockerfile, versions in `versions.env`.
- **Structured logs** — JSON option for orchestrators that prefer it over the
  human banner.
- **Health endpoint** — an optional HTTP endpoint for liveness checks that are
  deeper than `pgrep` (but still not tied to the AI router).

## Not planned

- **Auto-updating agent CLIs at runtime.** Reproducibility matters more than
  freshness; a new CLI is a new image.
- **Running as root.** The design and PHP variants prove it is unnecessary.
- **A built-in reverse proxy.** The runtime has no inbound traffic.
- **Bundling secrets into images.** Ever.
