# Roadmap

This is a direction, not a contract. Agent CLIs move fast, and an item can move
forward, wait, or disappear when an upstream headless mode, license, or protocol
changes. The order below is roughly the order we would like to ship.

## How a new agent CLI gets in

A CLI is added only when all of these are true:

- it has a **non-interactive mode** with a stable exit code and machine-readable
  output (JSON is ideal, plain text is acceptable);
- it can authenticate from an environment variable or a config file — no
  browser-only login inside the container;
- it accepts a **custom base URL** for Anthropic-compatible, OpenAI-compatible,
  or its own protocol;
- its license allows redistribution in a public image (Apache-2.0, MIT, or
  similar; proprietary binaries only in an opt-in tag);
- it builds or ships for `linux/amd64` and `linux/arm64`;
- it does **not** auto-update at runtime; the version is pinned in
  `versions.env`;
- the Multica daemon can register it as a runtime, or a small adapter can make
  it behave like one.

That last point is the real gate. Installing a CLI is easy; making it a
first-class Multica runtime with correct task lifecycle, cancellation, and
session history is the work.

## Shipped

| CLI | Command | Notes |
|---|---|---|
| Claude Code | `claude` | Anthropic-compatible endpoint, four model slots |
| OpenCode | `opencode` | Anthropic- or OpenAI-compatible, generated config |

## Wave 1 — the next four harnesses

These are the most likely next additions. They have headless modes, active
upstream projects, and a plausible path to the Multica daemon.

### Codex CLI

OpenAI's Codex CLI is still the obvious missing third runtime. It is a mature
headless agent (`codex exec`), but its configuration and auth are its own:
`~/.codex/config.toml`, OpenAI or custom model providers, and a protocol that is
not simply "Anthropic with a different key".

What it needs:

- a Codex adapter that maps `AI_BASE_URL` / `AI_API_KEY` / `AI_MODEL` into
  Codex's provider config;
- `CODEX_*` overrides for people who want a different endpoint than Claude
  Code and OpenCode;
- a decision about the wire protocol: Responses API, OpenAI-compatible chat, or
  a router that supports both;
- a headless smoke test that runs a task, not just `codex --version`.

The image question is size. Codex is not huge, but shipping three CLIs in every
variant is wasteful. The likely shape is `:base` with Claude Code + OpenCode,
and a `:base-codex` or `:agents` tag until the shared adapter layer is proven.

### Qwen Code

Qwen Code (`qwen`) is Alibaba's open-source terminal coding agent, derived from
Gemini CLI and tuned for Qwen-Coder models. It is Apache-2.0, has a headless
mode, and speaks OpenAI-compatible endpoints, so it fits the existing `AI_*`
surface better than Codex does.

What it needs:

- an adapter for `~/.qwen` settings and `OPENAI_*`-style environment variables;
- catalogue handling: Qwen Code is happiest when the model name exists in its
  provider list, so the entrypoint should generate a custom provider entry
  instead of assuming a built-in one;
- a `:base-qwen` tag first, because the CLI pulls a large Node dependency tree;
- tests for both the Qwen endpoint and a generic OpenAI-compatible router.

### Grok Build

Grok Build (`grok`, package `@xai-official/grok`) is xAI's terminal coding agent:
Apache-2.0, headless (`grok -p`), ACP support, MCP, subagents, and a documented
custom-model config at `~/.grok/config.toml` with `base_url` and `env_key`.

That custom-model block makes it a strong fit: a router can be wired in without
pretending to be xAI. The blockers are auth (`XAI_API_KEY` for headless use) and
the fact that Grok Build is still young and its config format can move.

What it needs:

- an adapter that writes `~/.grok/config.toml` and disables auto-update;
- a protocol decision: Grok's native API, OpenAI-compatible, or an
  Anthropic-compatible router if the CLI supports it;
- a pinned binary installed with checksum verification, not a runtime
  `curl | bash`;
- a smoke test for `grok -p` with a non-xAI base URL.

### DeepSeek Harness

DeepSeek Harness (`dsh`) is DeepSeek's MIT-licensed, plugin-based agent harness.
Everything is a plugin — models, tools, sessions, even other harnesses — and it
has a headless profile (`dsh --profile headless "job"`), a web profile, and an
ACP profile.

It is powerful and unusually large (the npm install is in the hundreds of
megabytes before plugins), and it is still a developer preview. That makes it a
good candidate for a dedicated tag rather than the base image.

What it needs:

- a `:harness` or `:base-dsh` tag with its own `DSH_HOME` and plugin profile;
- a stable, pinned profile that does not fetch plugins at container start;
- a headless smoke test that proves the profile boots without the web UI;
- a policy for plugin downloads: image build time only, never task time.

## Wave 2 — the long tail

These are real projects with real headless modes. They are later because they
either duplicate an existing runtime, need a different execution model, or carry
security decisions we do not want to rush.

### Pi

Pi (`pi`) is a deliberately minimal terminal coding harness: a small core, four
default tools, TypeScript extensions, print/JSON/RPC modes, and an SDK. It is
MIT-licensed and has a strong "make it yours" philosophy.

Pi is interesting precisely because it is small. The catch is that it
intentionally ships without a permission system or many of the guardrails other
agents bundle, so the container has to provide the boundary.

What it needs:

- a generated `~/.pi/agent/models.json` custom provider, because Pi does not read
  `ANTHROPIC_BASE_URL`;
- print mode (`pi -p`) and JSON event mode for the daemon adapter;
- an explicit permission story: the container is the sandbox, and the task image
  must not assume Pi will ask before running a command;
- a decision on whether Pi's RPC mode is a better integration than one-shot
  print mode.

### Oh-My-Pi

Oh-My-Pi (`omp`, package `@oh-my-pi/pi-coding-agent`) is a batteries-included
fork of Pi with LSP, DAP debugging, subagents, a browser tool, and 60+ providers.
It is MIT-licensed, runs on Bun, and has one-shot (`omp -p`), RPC, and ACP modes.

It is the opposite trade-off from Pi: much more capability, much more surface
area. It also currently defaults its tool approval mode to `yolo`, which is not
acceptable for a shared runtime without an explicit override.

What it needs:

- Bun in the image, or a verified standalone binary;
- `~/.omp/config.yml` generated with `tools.approvalMode` set to `always-ask` or
  `write` — never `yolo` by default;
- `~/.omp/models.yml` for the custom provider; Oh-My-Pi honours
  `ANTHROPIC_BASE_URL`, but a generated model entry is more predictable;
- a clear warning that it is a fast-moving fork, and a pinned version;
- a test that the approval mode is actually enforced, not just written to disk.

### Hermes Agent

Hermes Agent (`hermes`) from Nous Research is an MIT-licensed, always-on personal
agent runtime: terminal UI, gateway, persistent memory, scheduled jobs, and
channels such as Telegram, Slack, and WhatsApp. It can read files and run
commands, but it is a general-purpose assistant harness, not a dedicated coding
CLI.

That makes it a different integration. It may be more useful as an **orchestrator
runtime** that calls a coding CLI as a tool than as a direct Multica runtime.
Running the gateway can also expose messaging channels, which is a security
surface we would not enable in a worker image without an explicit opt-in.

What it needs:

- a headless, single-turn mode suitable for the daemon (or a small bridge);
- a gateway-off profile, with no messaging channels unless the operator asks;
- a separate `:hermes` tag, not the base image;
- a clear threat model for persistent memory and channel credentials.

### OpenClaw

OpenClaw (`openclaw`) is an open-source agent gateway with a node/exec model. It
has a genuine headless path: `openclaw agent exec` runs one embedded turn, supports
`--cwd`, `--json`, `--model`, and timeouts, and is explicitly documented for CI
and coding automation.

It is not a drop-in replacement for a coding CLI. It expects a gateway, a state
directory, provider configuration, and a permission model. The headless `exec`
path avoids the gateway, which is the part worth exploring.

What it needs:

- an `openclaw agent exec` adapter with a minimal, isolated config;
- `--auth-env-only` (or an equivalent) so no host credentials are reused;
- a sandbox policy for filesystem and shell tools;
- a separate image or an optional layer — the gateway is too large and too
  stateful for every variant.

## Watchlist

Not scheduled, but worth evaluating when the adapter layer exists:

| CLI | Why it is interesting | Main question |
|---|---|---|
| Gemini CLI | Apache-2.0, headless, huge reach | Google auth vs API key; protocol fit |
| Aider | Mature, git-centric, very predictable | No agent runtime lifecycle; one-shot bridge |
| Cline | Strong coding UX, open source | Primarily an IDE extension; CLI story |
| Goose | Block-backed, extensible, local-first | Runtime lifecycle and headless maturity |
| Crush | Charm's terminal agent, polished TUI | Headless mode and provider config |
| Amp | Strong agentic coding product | Licence and headless/API access |
| Continue | IDE + CLI, configurable providers | Headless runtime and task lifecycle |
| Roo Code / Kilo Code | Popular VS Code agent forks | IDE-first; CLI/headless path |
| OpenHands | Full agent platform, sandboxing | Heavy; better as a platform integration |
| SWE-agent | Research-grade issue solving | Batch job, not a long-running runtime |
| Codebuff | Open-source coding agent | Headless mode and runtime integration |
| Zed Agent | Fast editor-native agent | Editor-bound; ACP/headless story |

This list will change. The criteria at the top matter more than the names.

## Image strategy for many CLIs

Putting every CLI in every image would make `:base` enormous and would register a
dozen runtimes in the dashboard. The plan is an adapter layer, not a pile of
`npm install -g` lines:

```text
images/base/agents/
  claude/install.sh   configure.sh
  codex/install.sh    configure.sh
  qwen/install.sh     configure.sh
  ...
```

- `:base` keeps Claude Code + OpenCode as the default pair.
- A `:agents` tag (or per-CLI tags such as `:base-codex`) carries the extra
  harnesses until the shared adapter is proven.
- `MULTICA_AGENT_CLIS=claude,opencode` selects which runtimes the daemon should
  register. Installing a CLI should not force it to appear in every workspace.
- Each adapter owns its native config and its own override prefix (`CODEX_*`,
  `QWEN_*`, `GROK_*`, `DSH_*`, `PI_*`, `OMP_*`, `HERMES_*`, `OPENCLAW_*`).
- `AI_*` remains the shared default. A per-CLI override wins when both are set.
- Versions stay in `versions.env`; no CLI updates itself at runtime.

The hard part is not installation. It is mapping one set of `AI_*` values onto
CLIs that disagree about protocols, model catalogues, auth headers, and what
"headless" means.

## Autoscaler

The current autoscaler supports ECS and Swarm. See
[Autoscaling](autoscaling.md#beyond-ecs-and-swarm) for the design discussion.
The short version:

1. **Metrics exporter first.** Expose pending/running tasks and desired workers
   at `/metrics`. That unlocks KEDA on Kubernetes and Azure Container Apps
   without writing a platform adapter.
2. **Webhook adapter second.** A signed `POST` with the desired count lets users
   drive Nomad, Cloud Run, Fly Machines, Coolify, or anything else with a tiny
   receiver.
3. **Nomad adapter third**, if there is demand. It is a natural fit for
   on-premises and self-hosted clusters.
4. **Native Kubernetes adapter only if KEDA is not acceptable.** Patching
   `Deployment.spec.replicas` duplicates reconciliation that Kubernetes already
   does; KEDA is the better default.
5. **Docker Compose standalone is not a target.** Compose has no desired-state
   API. Use single-node Swarm, or a webhook receiver that manages named
   containers.

Later, a warm-pool mode could keep expensive toolchains (Flutter, PHP, design)
warm during business hours and scale to zero outside them. That is a cost
feature, not a correctness feature, so it comes after the metrics and webhook
work.

## Platform and supply chain

- **Signed images** — cosign signatures and a verification snippet in the docs,
  on top of the existing provenance and SBOM attestations.
- **Digest-pinned examples** — every deployment example should show a digest, not
  only a tag, for production.
- **More stacks** — Rust, .NET, Ruby on Rails, Elixir, and a data/ML image with
  Jupyter and common Python data tools.
- **A smaller base** — a `:slim` tag without Chromium and `build-essential`, for
  agents that only read and write.
- **Structured logs and metrics** — JSON log option, OpenTelemetry traces, and a
  health endpoint deeper than `pgrep` but still independent of the AI router.
- **Secret providers** — Docker secrets, AWS Secrets Manager, and SOPS as
  alternatives to environment variables, without baking values into images.
- **Per-variant PR builds** — build only the variants a pull request changes,
  instead of always building the base.
- **arm64 runtime tests** — build arm64 today; exercise the entrypoints under
  emulation or on native arm64 runners.
- **Localized docs** — Bahasa Indonesia first, then other languages, if there is
  demand.
- **A `multica-runtime doctor` command** — validate config, endpoint, auth style,
  and model names before the daemon starts.

## Not planned

- **Auto-updating agent CLIs at runtime.** Reproducibility matters more than
  freshness; a new CLI is a new image.
- **Running as root.** The design and PHP variants prove it is unnecessary.
- **A built-in reverse proxy.** The runtime has no inbound traffic.
- **Bundling secrets into images.** Ever.
- **One image with every CLI enabled by default.** It would be slow to build, slow
  to pull, and confusing in the dashboard.
