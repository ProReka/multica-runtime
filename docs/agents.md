# Agent CLIs

The image contains two agent CLIs, both installed and pinned at build time:

| CLI | Package | Command |
|---|---|---|
| Claude Code | `@anthropic-ai/claude-code` | `claude` |
| OpenCode | `opencode-ai` | `opencode` |

More CLIs are planned, but none are installed yet:

- **Wave 1:** Codex CLI (`codex`), Qwen Code (`qwen`), Grok Build (`grok`),
  DeepSeek Harness (`dsh`).
- **Wave 2:** Pi (`pi`), Oh-My-Pi (`omp`), Hermes Agent (`hermes`), OpenClaw
  (`openclaw`).

Each one needs a headless adapter, a pinned version, and a real runtime test
before it appears in an image. See the [roadmap](roadmap.md) for the criteria and
the honest blockers.

## One runtime per CLI

The Multica daemon detects every supported agent CLI on `PATH` and registers one
runtime per CLI. A single container therefore appears in the dashboard as two
runtimes (for example `Multica Runtime (claude)` and `Multica Runtime (opencode)`),
sharing:

- the same `MULTICA_DAEMON_ID` prefix,
- the same AI router and model,
- the same `/workspaces` volume.

Bind an agent to whichever CLI you want it to use. They are not interchangeable
in behaviour: Claude Code has a different tool set and prompt style than OpenCode.
Running both lets you compare, or pin a particular agent to a particular runtime.

## Same endpoint, two configurations

Claude Code natively reads `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`/`API_KEY`
and `ANTHROPIC_MODEL`. OpenCode does not read those, so the entrypoint writes an
OpenCode config at start.

That config:

- points a custom provider (`AI_PROVIDER_ID`, default `multica`) at your router;
- picks `@ai-sdk/openai-compatible` or `@ai-sdk/anthropic` based on the protocol
  probe;
- lists the router's catalogue when `/v1/models` answers;
- sets the main and subagent model;
- is written with mode `0600` because it contains the key.

You configure the endpoint once. Both CLIs follow.

## Model slots

Claude Code asks for four slots:

| Slot | Used for | Override |
|---|---|---|
| Large | plan mode, “opus” work | `AI_MODEL_LARGE` |
| Medium | normal work, “sonnet” | `AI_MODEL_MEDIUM` |
| Small | fast background work, “haiku” | `AI_MODEL_SMALL` |
| Subagent | every Task-tool subagent | `AI_SUBAGENT_MODEL` |

Unset slots fall back to `AI_MODEL`, which always works. On a router with a real
catalogue, pin them to cheaper models. The entrypoint logs a warning if a pinned
model is not served.

OpenCode uses `AI_MODEL` (or `MULTICA_OPENCODE_MODEL`) as its main model and
`AI_SUBAGENT_MODEL` for subagents. When it probed a catalogue, it only pins a
subagent model that exists there, because OpenCode refuses to start a session
with an unknown model; otherwise subagents inherit the main model. With
`AI_MODELS_PROBE=0`, your explicit subagent model is trusted as-is.

## MCP servers

The design image registers the Penpot MCP server with both CLIs automatically.
For anything else, add MCP servers inside the task or extend the image:

```bash
# Claude Code
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp

# OpenCode: add an "mcp" block to the generated config
```

The OpenCode config is overwritten at every container start, so a persistent MCP
addition belongs in a derivative image (entrypoint hook) rather than in the
config file.

## Version policy

Agent CLIs are pinned in [`versions.env`](https://github.com/ProReka/multica-runtime/blob/main/versions.env)
and installed with `npm install -g <pkg>@<exact>`. They do not auto-update:

- `DISABLE_AUTOUPDATER=1` for Claude Code;
- `autoupdate: false` in the OpenCode config.

A new CLI version is a new image, reviewed and tested in CI. That is deliberate:
a runtime that changes its own behaviour mid-task is not reproducible.

To upgrade, bump the version in `versions.env`, open a PR, and let CI build it.
