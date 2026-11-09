# Troubleshooting

Start with the banner. It prints the resolved protocol, auth style, model, paths
and CLI versions — and never a secret.

```bash
docker compose logs --tail=50 runtime
```

## OpenCode reports `Unexpected server error`

A heartbeat is not evidence that an agent can execute. Check the model catalogue
inside the affected worker as its runtime user (`opencode models <provider>`),
not only the router's `/v1/models` endpoint. Never dump provider configuration:
it contains credentials.

One possible cause is a failed startup model-catalogue probe. A router can recover
while an existing worker still has an incomplete local catalogue. Compare the
requested model with the models available inside that worker; this generic error
alone does not establish the cause.

When the probe fails, the fallback includes the configured main, subagent and tier
models. No provider-specific model names are hardcoded. Successful probes remain
authoritative; unconfigured aliases are not added automatically. The fallback
does not provide inference while the upstream service itself is unavailable.

Deploy an image containing the fix using your platform's deployment process.
Preserve credentials, unrelated settings and in-flight work when replacing or
reconfiguring existing workers. Verify an actual agent response and successful
run completion afterward, not merely a heartbeat or container health check.

Regression: `bash scripts/test-opencode-catalogue.sh` (also in `make lint`).

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

## Issues wait / runtime looks stale

Diagnose the **workspace-specific bound runtime**, not another workspace's
runtime with the same daemon id:

```bash
python3 scripts/check-runtime.py --workspace-id <workspace-id> --agent-id <agent-id>
```

This read-only check paginates agent runs, compares heartbeat and recent run
messages, and prints only status metadata. Exit codes: `0` no pickup anomaly,
`1` investigation needed, `2` incomplete diagnosis. Run it from an authenticated
CLI context; never put a token in the command. It does not restart or cancel work.

- `SATURATED`: `agent.max_concurrent_tasks` is full. This is independent of
  `MULTICA_DAEMON_MAX_CONCURRENT_TASKS`; increasing daemon capacity alone cannot
  unblock the agent. Wait for active work, or review an explicit agent-limit
  increase against available CPU/memory and API capacity.
- `ACTIVITY`: recent events exist; useful progress is **not** verified. Read tool
  results and changes, not just timestamps or message counts.
- `STALLED`: last tool result timed out, even if that event is fresh.
- `FAILED`: last event is an execution error despite server `running` status.
- Zero messages on a running task is unverified execution, not healthy progress.
- `CHECK`: no recent messages is a warning, not proof of a dead process. Inspect
  the run before cancelling; a long tool call may be legitimate.
- `OFFLINE`: verify service capacity, outbound connectivity and registration.
  A process-only container healthcheck is not proof of server connectivity.
- `api_invalid_request` with unmatched `tool_use_id` / `tool_result`: malformed
  provider conversation history, not heartbeat failure. Review the run error and
  router protocol. After confirming no live execution for that issue, use
  `multica issue rerun <issue>` for a fresh run; do not resume the broken session,
  delete session files, or restart unrelated active runs. Reruns can repeat side
  effects, so check previous changes first.

### Frontend investigation — 2026-11-01

At approximately 11:55 UTC, GFS frontend's bound OpenCode runtime was online;
ECS service had one healthy task. Agent concurrency was **2**, daemon concurrency
**3**. Two running tasks had recent tool activity; two more tasks were queued.
The initial interpretation (only agent saturation) was incomplete: recent tool
events did not prove sustained progress. GFS-250 subsequently failed
`idle_watchdog` at 12:44:20 UTC after its last message at 12:33:22. Its replacement
produced a 300-second `npm ci` timeout with no output. GFS-249's next run initially
had zero messages. Both replacement runs then emitted `Cannot connect to API`
at approximately 12:55 UTC despite `running` status.

Live ECS inspection found the shared `gfs-ai-9router` service at desired 1,
running 0. Its essential `headroom` container exited 137 with
`OutOfMemoryError: container killed due to memory usage`; its hard memory limit
was 1024 MiB. Essential-container coupling took the router down too. Router logs
also showed compression timeouts and upstream free-provider 429 responses before
the outage. These are separate observations; they do not prove the cause of the
earlier idle-watchdog failure or npm timeout.

Recovery: forced a new deployment of **only** `gfs-ai-9router`, keeping task
definition revision 4 and desired count 1. Frontend runs, credentials, persistent
files and agent limits were not changed. The ECS stable waiter subsequently succeeded and the ALB target returned
`healthy`. End-to-end agent execution recovery remains unverified; deployment
acceptance or target health alone is not proof of successful task completion.
Permanent router work belongs in its infrastructure/source repository: review
headroom request concurrency and memory, then decide whether compression should
fail open rather than killing an essential router dependency. Do not silently
weaken controls or increase billing commitments here.

One earlier run also failed `api_invalid_request` (unmatched tool-result history);
a subsequent run for that issue was already queued. The live image used Multica
0.6.1 / OpenCode 1.18.34, older than this repository's pins; updating the repo does
not update ECS automatically. Deploy through the infrastructure review process,
then verify task pickup and run output. This check is diagnostic, not an automatic
recovery controller or a guarantee against upstream session-history errors.

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

## `git commit` fails: `Author identity unknown`

Git refuses to commit without `user.name` and `user.email`. On each
`multica repo checkout`, the daemon copies the global/system identity into the
worktree's `multica-identity.config` and masks anything missing with empty
values, so an unset global identity becomes `fatal: empty ident name`.

The entrypoint sets the global identity from `GIT_AUTHOR_NAME` /
`GIT_AUTHOR_EMAIL`, or `Multica Agent <agent@multica.invalid>` when both are
unset. Set the variables to attribute commits to a real account:

```dotenv
GIT_AUTHOR_NAME=ProReka Bot
GIT_AUTHOR_EMAIL=<id>+<login>@users.noreply.github.com
```

Check inside a task checkout:

```bash
git config --global --get user.email
git var GIT_AUTHOR_IDENT
```

A checkout created before the fix keeps its empty identity until the next
`multica repo checkout` refreshes it. To commit now, override per command:
`git -c user.name="ProReka Bot" -c user.email=<email> commit ...`.

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
