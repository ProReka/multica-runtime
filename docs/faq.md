# FAQ

## Is this an official Multica product?

No. It is a set of community-built runtime images maintained by
[ProReka](https://github.com/ProReka). Multica itself is a separate product; these
images package its CLI alongside the agent CLIs.

## Do I need an Anthropic API key?

You need an endpoint that Claude Code can talk to, which means
**Anthropic-compatible**. That can be:

- Anthropic directly (`https://api.anthropic.com`);
- a gateway or router that exposes the Anthropic Messages API;
- a multi-protocol router that translates OpenAI models to the Anthropic wire
  format.

Claude Code does not speak the OpenAI protocol. If your endpoint is OpenAI-only,
OpenCode can use it (`AI_PROTOCOL=openai`) but Claude Code cannot. Use a router
that offers an Anthropic-compatible surface if you want both.

## Claude Code or OpenCode — which one runs?

Both. The daemon detects both CLIs and registers one runtime per CLI. Bind your
agent to the one you want. They share the model endpoint and the workspace volume,
but they are different agents with different behaviour.

## Can several agents share one container?

Yes, within the concurrency limit. Set
`MULTICA_DAEMON_MAX_CONCURRENT_TASKS`. Do not run several *containers* with the
same `MULTICA_DAEMON_ID`; they compete for tasks.

## Does it need a GPU?

No.

## Does it need privileged mode?

No. Everything runs as uid 1000. The only privileged-ish thing in the project is
the optional Swarm autoscaler's Docker socket, which the ECS adapter does not need.

## Which image should I start with?

`:base`. Switch to a stack image only when a task fails for a missing toolchain.
The larger images (Flutter, design) cost more to pull and to run.

## How large are the images?

Roughly: base 2–3 GB, language variants 3–5 GB, Flutter ~10 GB. They share layers,
so pulling `:node` after `:base` downloads only the difference. Exact sizes are on
the package page and in the release notes.

## Does it work on Apple Silicon?

Yes, for amd64 and arm64 variants. Flutter is amd64-only (Android build tools).
Use `--platform linux/amd64` or build in CI.

## Does it work on Windows?

Docker Desktop with the WSL2 backend works. The image is Linux; there is no native
Windows container.

## Where does my code go?

Into `/workspaces/<task-id>`, on the workspaces volume. The agent clones the
repository there. Nothing is sent anywhere except Multica, your AI endpoint, and
whatever Git host the task uses.

## Are sessions kept?

Yes: Claude Code at `/workspaces/.claude`, OpenCode at
`/workspaces/.opencode/data`. Restarts and image upgrades keep them as long as the
volume is mounted. See [Persistence](persistence.md).

## Can I use it offline?

Only the model probe can be disabled (`AI_MODELS_PROBE=0`). The runtime still
needs Multica and the AI endpoint to do anything. There is no offline mode.

## Why is `:latest` not recommended for production?

Tags can move. Pin `:vX.Y.Z-<variant>` or a digest. `:latest` points at the base
image of the latest `main` build and is fine for trying things out.

## How do I upgrade?

`docker compose pull && docker compose up -d`, or change the pinned tag. Sessions
survive. See [Upgrading](operations/upgrading.md).

## Why doesn't the image auto-update Claude Code?

Because a runtime that changes its own behaviour mid-task is not reproducible.
The version is pinned in `versions.env` and baked into the image. Bump it in a PR,
let CI build and test it.

## Can I add my own tools?

Yes. Either run `apt-get`/`npm install` inside a task (ephemeral, gone next
restart), or build a derivative image. See [Development](development.md#adding-a-variant).

## Something is broken. Where do I look?

[Start with the banner](operations/troubleshooting.md). It usually names the
problem: missing token, wrong credential style, model not in the catalogue. If not,
open an issue with the banner lines and the command you ran.
