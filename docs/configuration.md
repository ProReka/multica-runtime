# Configuration

Everything is configured with environment variables. Four are required; the rest
have safe defaults.

```dotenv
MULTICA_TOKEN=...
AI_BASE_URL=...
AI_API_KEY=...
AI_MODEL=...
```

## How values are resolved

The `AI_*` variables are a friendly layer over the native variables the agent
CLIs already understand. **Native variables win** when both are set, so existing
deployments can move over one value at a time.

| Public | Native equivalent | Notes |
|---|---|---|
| `AI_BASE_URL` | `ANTHROPIC_BASE_URL` | Required |
| `AI_API_KEY` | `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` | Required |
| `AI_MODEL` | `ANTHROPIC_MODEL` | Recommended |
| `AI_MODEL_LARGE` | `ANTHROPIC_DEFAULT_OPUS_MODEL` | Optional tier |
| `AI_MODEL_MEDIUM` | `ANTHROPIC_DEFAULT_SONNET_MODEL` | Optional tier |
| `AI_MODEL_SMALL` | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Optional tier |
| `AI_SUBAGENT_MODEL` | `CLAUDE_CODE_SUBAGENT_MODEL` | Optional |

Conflicting values are not silently merged: the container logs a warning and uses
the native variable.

### Credential style

Anthropic's API expects an `x-api-key` header. Routers usually expect
`Authorization: Bearer`. The entrypoint picks based on what you set:

| You set | Header used |
|---|---|
| `ANTHROPIC_AUTH_TOKEN` | Bearer |
| `ANTHROPIC_API_KEY` | `x-api-key` |
| `AI_API_KEY` + `https://api.anthropic.com` | `x-api-key` |
| `AI_API_KEY` + any other URL | Bearer |

If a router only accepts one style, set the native variable explicitly. The
startup banner prints `auth=bearer` or `auth=api-key` — never the key.

## Multica

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `MULTICA_TOKEN` | yes | — | Personal access token |
| `MULTICA_SERVER_URL` | no | Multica Cloud | Self-hosted server URL |
| `MULTICA_WORKSPACE` | no | — | CLI default workspace |
| `MULTICA_DAEMON_WORKSPACE_ALLOWLIST` | no | all reachable | Comma-separated workspace ids/slugs the daemon may register in |
| `MULTICA_DAEMON_ID` | no | container hostname | Stable runtime identity |
| `MULTICA_AGENT_RUNTIME_NAME` | no | `Multica Runtime` | Name shown in the dashboard |
| `MULTICA_DAEMON_MAX_CONCURRENT_TASKS` | no | daemon default | Parallel tasks per runtime |
| `MULTICA_WORKSPACES_ROOT` | no | `/workspaces` | Where task directories and sessions live |

### Set `MULTICA_DAEMON_ID`

If unset, the container hostname is used, and **every restart creates a new
runtime**. Agents bound to the old runtime id do not automatically follow the new
one. Always set a stable id:

```dotenv
MULTICA_DAEMON_ID=multica-php
```

One id per role. Never run two containers with the same id: they will compete for
the same tasks.

### Workspace scope

`MULTICA_WORKSPACE` only sets the CLI default. The daemon may register in every
workspace the token can reach. If the token belongs to several workspaces, scope
it explicitly:

```dotenv
MULTICA_DAEMON_WORKSPACE_ALLOWLIST=acme,acme-sandbox
```

## AI router {#routers}

| Variable | Default | Meaning |
|---|---|---|
| `AI_PROTOCOL` | `auto` | `auto` / `openai` / `anthropic` |
| `AI_PROVIDER_ID` | `multica` | OpenCode provider id; models appear as `<id>/<model>` |
| `AI_MODELS_PROBE` | `1` | Set `0` to skip the `/v1/models` probe |
| `AI_MODELS_URL` | `<origin>/v1/models` | Override the probe URL |

### Protocol detection

OpenCode talks to your endpoint through one of two adapters:

- **`openai`** — `@ai-sdk/openai-compatible`, base URL `<origin>/v1`
- **`anthropic`** — `@ai-sdk/anthropic`, base URL as given

With `AI_PROTOCOL=auto` (the default), the entrypoint requests
`<origin>/v1/models` with your key. If it gets a model list, it uses `openai`;
otherwise it falls back to `anthropic`. The exception is `api.anthropic.com`:
its `/v1/models` answers, but its wire protocol is not OpenAI-compatible, so auto
always selects `anthropic` there. The probe is retried three times with a
10-second timeout.

Set `AI_PROTOCOL` when detection is wrong, and `AI_MODELS_PROBE=0` on a network
where the probe cannot reach the router.

### Model tiers

Claude Code asks for four model slots by name. On a router, the upstream ids
(`claude-sonnet-4-5`, …) may not exist. Anything you do not pin is therefore
derived from `AI_MODEL` — always valid, but it spends the main model on every
slot.

For better cost/latency, pin the tiers:

```dotenv
AI_MODEL=general
AI_MODEL_LARGE=reasoning
AI_MODEL_MEDIUM=general
AI_MODEL_SMALL=fast
AI_SUBAGENT_MODEL=fast
```

The entrypoint warns at startup if a pinned model is not in the router's
catalogue.

## Claude Code

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_CONFIG_DIR` | `/workspaces/.claude` | Transcripts and config |
| `MULTICA_CLAUDE_MODEL` | — | Passed through to the daemon |
| `MULTICA_CLAUDE_ARGS` | — | Extra CLI arguments |

`DISABLE_AUTOUPDATER=1` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` are set
by default: the CLI version is whatever the image pins. An in-place auto-update
would silently change behaviour under you.

## OpenCode

| Variable | Default | Meaning |
|---|---|---|
| `XDG_DATA_HOME` | `/workspaces/.opencode/data` | Session data |
| `OPENCODE_CONFIG` | `$XDG_CONFIG_HOME/opencode/opencode.json` | Config path |
| `MULTICA_OPENCODE_MODEL` | `AI_MODEL` | Main model |
| `MULTICA_OPENCODE_SUBAGENT_MODEL` | `AI_SUBAGENT_MODEL` | Subagent model |

The entrypoint writes the config at container start because OpenCode does not read
`ANTHROPIC_BASE_URL`. The file contains your API key and is created with mode
`0600`.

## Git hosting (optional)

| Variable | Meaning |
|---|---|
| `GH_TOKEN` | GitHub token for `gh` and HTTPS git |
| `GITHUB_TOKEN` | Fallback for `GH_TOKEN` |
| `GIT_AUTHOR_NAME` | Commit identity |
| `GIT_AUTHOR_EMAIL` | Commit email |

With a token, `gh auth setup-git` is run so `git push` over HTTPS works without a
credential prompt.

## PHP image

| Variable | Default | Meaning |
|---|---|---|
| `MULTICA_START_DATABASES` | `1` | Start embedded MariaDB/PostgreSQL/Redis |
| `MULTICA_DB_ROOT` | `/tmp/multica-db` | Ephemeral data directory |
| `MULTICA_DB_NAME` | `DB_DATABASE` or `laravel` | Database created at boot |
| `MULTICA_DB_USER` | `DB_USERNAME` or `laravel` | Database user |
| `MULTICA_DB_PASSWORD` | `DB_PASSWORD` or `secret` | Database password |
| `MULTICA_MYSQL_PORT` | `3306` | MariaDB port |
| `MULTICA_POSTGRES_PORT` | `5432` | PostgreSQL port |
| `MULTICA_REDIS_PORT` | `6379` | Redis port |

The entrypoint deliberately does **not** export `DB_*` variables, so it cannot
override your application's `.env`. Point the app at `127.0.0.1` yourself.

Data lives under `/tmp` and is recreated on every container start. That is
intentional: a runtime is disposable, a database inside it is not a source of
truth.

## Design image

| Variable | Default | Meaning |
|---|---|---|
| `PENPOT_URL` | `https://design.penpot.app` | Penpot instance |
| `PENPOT_MCP_SERVER_PORT` | `4401` | MCP HTTP port |
| `PENPOT_MCP_WEBSOCKET_PORT` | `4402` | Plugin WebSocket port |
| `PENPOT_MCP_PLUGIN_PORT` | `4400` | Plugin server port |
| `PENPOT_MCP_SERVER_HOST` | `127.0.0.1` | MCP bind address |
| `PENPOT_MCP_PLUGIN_SERVER_HOST` | `127.0.0.1` | Plugin bind address |
| `PENPOT_BROWSER_PROFILE` | `/workspaces/.penpot-browser` | Persistent Chromium profile |
| `MULTICA_PENPOT_MCP` | `1` | Register the MCP server with both CLIs |
| `PENPOT_DISPLAY` | `:99` | Xvfb display |
| `PENPOT_SCREEN` | `1440x1024x24` | Xvfb screen |

Penpot credentials are **not** read by the entrypoint. The agent logs in through
the real browser UI, and the session cookie stays in the persistent profile.

## Autoscaler

See [Autoscaling](autoscaling.md) for the full list. The two variables that
matter most:

```dotenv
AUTOSCALER_PLATFORM=ecs            # or swarm
AUTOSCALER_RUNTIMES=[{"daemon_id":"multica-php","service":"multica-php"}]
```

## Diagnostics

| Variable | Meaning |
|---|---|
| `MULTICA_DRY_RUN` | Resolve config, print the banner, exit without logging in |
| `AI_MODELS_PROBE` | Set `0` to skip the router probe |

Dry run is useful in CI and when debugging a bad key without hammering Multica:

```bash
docker compose run --rm -e MULTICA_DRY_RUN=1 runtime
```

## Full template

The annotated template lives at
[`.env.example`](https://github.com/ProReka/multica-runtime/blob/main/.env.example).
