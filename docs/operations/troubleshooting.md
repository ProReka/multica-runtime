# Troubleshooting

Start with the banner. It prints the resolved protocol, auth style, model, paths
and CLI versions — and never a secret.

```bash
docker compose logs --tail=50 runtime
```

## The container exits immediately

Run the entrypoint with a dry run to see the configuration error:

```bash
docker compose run --rm -e MULTICA_DRY_RUN=1 runtime
```

| Log line | Meaning |
|---|---|
| `MULTICA_TOKEN is required` | Token missing or empty |
| `AI_BASE_URL (or ANTHROPIC_BASE_URL) is required` | Endpoint missing |
| `AI_API_KEY (or ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY) is required` | Key missing |
| `AI_PROTOCOL must be auto, openai or anthropic` | Typo in `AI_PROTOCOL` |
| `AI_PROVIDER_ID must match …` | Provider id has uppercase or punctuation |

## `multica login` fails

- Token expired or revoked → create a new one.
- Self-hosted Multica → set `MULTICA_SERVER_URL` (including scheme).
- Corporate proxy → the container needs `HTTPS_PROXY` and `NO_PROXY`; the
  Multica CLI and both agent CLIs honour them.

```bash
docker compose run --rm -e HTTPS_PROXY=http://proxy:3128 runtime
```

## The runtime does not appear in Multica

1. Check the logs for `Starting Multica daemon (foreground)…`.
2. Check `MULTICA_DAEMON_WORKSPACE_ALLOWLIST` — if the token can reach several
   workspaces, the runtime may have registered in another one.
3. Check the dashboard's **Runtimes** filter (workspace + status).
4. A container with an old `MULTICA_DAEMON_ID` and a new one are two runtimes.
   Agents bound to the old id do not follow automatically.

## Claude Code returns 401

The credential style is wrong. See
[Configuration → Credential style](../configuration.md#credential-style).

```text
auth=bearer      → Authorization: Bearer ...     (routers)
auth=api-key     → x-api-key: ...                (api.anthropic.com)
```

Set `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY` explicitly to force one.

## Claude Code returns 404 / “model not found”

`AI_MODEL` is not what the router calls the model. List the catalogue:

```bash
curl -s "$AI_BASE_URL/v1/models" -H "Authorization: Bearer $AI_API_KEY" | jq
```

Then set `AI_MODEL` to an id from that list. If the router has no `/v1/models`,
set `AI_MODELS_PROBE=0` and `AI_PROTOCOL` explicitly.

## OpenCode starts but every session fails

OpenCode needs `provider/model`. The entrypoint qualifies a bare `AI_MODEL` as
`<AI_PROVIDER_ID>/<model>`. If you set a fully qualified name, keep it consistent
with `AI_PROVIDER_ID`:

```dotenv
AI_PROVIDER_ID=multica
AI_MODEL=multica/general
```

The entrypoint also warns when a pinned model is not in the probed catalogue.

## Sessions disappear after restart

- The volume is not mounted at `/workspaces`.
- A bind mount is not writable by uid 1000.
- `CLAUDE_CONFIG_DIR` or `XDG_DATA_HOME` was overridden to an ephemeral path.

```bash
docker compose exec runtime sh -c 'echo $CLAUDE_CONFIG_DIR; echo $XDG_DATA_HOME; ls -la /workspaces'
```

See [Persistence](../persistence.md).

## PHP image: database connection refused

The embedded databases start before the daemon, but an application that connects
during a custom startup hook may be too early. Check:

```bash
docker compose exec runtime pgrep -a mariadbd
docker compose exec runtime mariadb -h 127.0.0.1 -u laravel -psecret -e 'select 1'
```

Point the app at `127.0.0.1`, not `localhost` (MariaDB is bound to IPv4). The
entrypoint does not export `DB_*`, so your `.env` decides the credentials.

## Design image: Penpot MCP tools fail

The MCP server is useless until a Penpot file is open in Chromium with the plugin
connected. Check the three processes:

```bash
docker compose exec runtime sh -c 'pgrep -a Xvfb; pgrep -af penpot'
docker compose exec runtime curl -sI http://127.0.0.1:4401/mcp
docker compose exec runtime curl -sI http://127.0.0.1:4400/manifest.json
```

Logs are in `/workspaces/.penpot/`. The browser profile persists the login; delete
`/workspaces/.penpot-browser` to force a fresh login.

Chromium 142+ enforces Private Network Access: loading a plugin from
`localhost` into `design.penpot.app` may show a permission prompt. The agent must
approve it, or the browser needs the flag for that origin.

## `no space left on device`

The workspace volume fills up with task checkouts and build caches. Prune inside
the container:

```bash
docker compose exec runtime sh -c '
  rm -rf /workspaces/*/.git/modules 2>/dev/null
  du -sh /workspaces/* 2>/dev/null | sort -h | tail'
```

Then remove finished task directories, or recreate the volume if you do not need
the session history. The image itself is read-only at runtime; only `/workspaces`
and `/tmp` grow.

## ARM64: Flutter build fails

The Flutter image is amd64-only. On Apple Silicon, run it with:

```bash
docker run --platform linux/amd64 ...
```

or build in CI. Flutter web/Linux work on arm64 if you build a custom image that
skips the Android SDK, but `flutter build apk` does not.

## Getting help

Open an issue with:

- the banner lines (they contain no secrets),
- the exact command,
- `docker compose config` (redact credentials),
- the relevant log lines.

See [SUPPORT.md](https://github.com/ProReka/multica-runtime/blob/main/SUPPORT.md).
