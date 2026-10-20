# ADR 0002: a small `AI_*` surface over native variables

**Status:** accepted

## Context

Claude Code reads `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` /
`ANTHROPIC_API_KEY`, and `ANTHROPIC_MODEL`. OpenCode does not read those; it needs
a config file with a provider, a protocol adapter, and a model list. A user who
just wants “point this at my router” should not have to learn either.

There is also a real correctness trap: Anthropic's API expects `x-api-key`, while
routers expect `Authorization: Bearer`. Setting the wrong one yields a 401 that
looks like a bad key.

## Decision

Expose four variables:

```dotenv
AI_BASE_URL
AI_API_KEY
AI_MODEL
AI_PROTOCOL      # auto | openai | anthropic
```

and derive everything else:

- `AI_BASE_URL` → `ANTHROPIC_BASE_URL`;
- `AI_API_KEY` → `ANTHROPIC_AUTH_TOKEN` (bearer) or `ANTHROPIC_API_KEY`
  (`x-api-key`) based on the endpoint and on which native variable was set;
- `AI_MODEL` → `ANTHROPIC_MODEL` and the four Claude Code slots;
- a generated OpenCode config that points a custom provider at the same endpoint.

**Native variables win.** If both are set, the native value is used and a warning
is logged. This makes migration incremental and keeps existing deployments
working.

Protocol detection is automatic: probe `<origin>/v1/models`; if it answers with a
model list, use the OpenAI-compatible adapter, otherwise the Anthropic adapter.
`api.anthropic.com` is always treated as Anthropic even when its model list
answers. `AI_PROTOCOL` overrides detection, and `AI_MODELS_PROBE=0` disables the
probe.

## Consequences

- Four variables configure both agents. That is the product promise.
- The credential-style choice is explicit and logged (`auth=bearer|api-key`).
- A router without `/v1/models` works, but the probe costs up to ~30 s at startup
  unless `AI_MODELS_PROBE=0` or `AI_PROTOCOL` is set. Acceptable for a long-lived
  runtime; documented.
- Claude Code still requires an Anthropic-compatible endpoint. `AI_PROTOCOL=openai`
  only changes OpenCode. This is documented rather than hidden.
- The generated OpenCode config is rewritten at every start. Persistent MCP
  additions belong in an image hook, not in the config file.
- If a user sets a fully qualified model (`provider/model`), the entrypoint keeps
  it; otherwise it prefixes `AI_PROVIDER_ID`.
