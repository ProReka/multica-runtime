#!/usr/bin/env bash
# design variant entrypoint — runs as the unprivileged `runner` user.
#
#   1. Prepare the persistent browser profile / log directory.
#   2. Start Xvfb, the Penpot MCP server and the Penpot plugin server.
#   3. Hand off to the base entrypoint (AI config → Multica login → daemon).
#
# The MCP and plugin servers are background processes: the daemon is the
# foreground process, and tini reaps the rest when the container stops.
set -Eeuo pipefail

log()  { printf '[multica-design] %s\n' "$*" >&2; }
warn() { printf '[multica-design] WARN: %s\n' "$*" >&2; }

export HOME="${HOME:-/home/runner}"
WS_ROOT="${MULTICA_WORKSPACES_ROOT:-/workspaces}"
DISPLAY_NUM="${PENPOT_DISPLAY:-:99}"
STATE_DIR="${WS_ROOT}/.penpot"
PROFILE="${PENPOT_BROWSER_PROFILE:-${WS_ROOT}/.penpot-browser}"

mkdir -p "$STATE_DIR" "$PROFILE" 2>/dev/null || \
    warn "cannot create ${STATE_DIR} — is ${WS_ROOT} writable by uid $(id -u)?"
export PENPOT_BROWSER_PROFILE="$PROFILE"

# --- 1. Virtual display ------------------------------------------------------
DISP_NUM="${DISPLAY_NUM#:}"
X_SOCK="/tmp/.X11-unix/X${DISP_NUM}"
mkdir -p /tmp/.X11-unix 2>/dev/null || true
if [ -S "$X_SOCK" ]; then
    log "Xvfb already running on ${DISPLAY_NUM}"
else
    log "Starting Xvfb on ${DISPLAY_NUM} (${PENPOT_SCREEN:-1440x1024x24})"
    Xvfb "$DISPLAY_NUM" -screen 0 "${PENPOT_SCREEN:-1440x1024x24}" -nolisten tcp \
        >"${STATE_DIR}/xvfb.log" 2>&1 &
    for _ in $(seq 1 40); do
        [ -S "$X_SOCK" ] && break
        sleep 0.25
    done
    [ -S "$X_SOCK" ] || warn "Xvfb socket ${X_SOCK} did not appear — headed Chromium may fail"
fi
export DISPLAY="$DISPLAY_NUM"

# --- 2. Penpot MCP server ----------------------------------------------------
MCP_PORT="${PENPOT_MCP_SERVER_PORT:-4401}"
log "Starting Penpot MCP server on http://127.0.0.1:${MCP_PORT}/mcp"
/usr/local/bin/penpot-mcp-launch >"${STATE_DIR}/mcp.log" 2>&1 &
mcp_pid=$!

ready="0"
for _ in $(seq 1 60); do
    kill -0 "$mcp_pid" 2>/dev/null || break
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${MCP_PORT}/mcp" 2>/dev/null || true)"
    if [ -n "$code" ] && [ "$code" != "000" ]; then ready="1"; break; fi
    sleep 0.5
done
if [ "$ready" = "1" ]; then
    log "Penpot MCP server is up (http=${code})"
else
    warn "Penpot MCP server did not answer on :${MCP_PORT} — see ${STATE_DIR}/mcp.log"
    tail -n 20 "${STATE_DIR}/mcp.log" 2>/dev/null >&2 || true
fi

# --- 3. Penpot plugin server -------------------------------------------------
PLUGIN_PORT="${PENPOT_MCP_PLUGIN_PORT:-4400}"
log "Starting Penpot plugin server on http://127.0.0.1:${PLUGIN_PORT}/manifest.json"
/usr/local/bin/penpot-plugin-launch >"${STATE_DIR}/plugin.log" 2>&1 &
plugin_pid=$!

if [ -f "${PENPOT_MCP_ROOT:-/opt/penpot-mcp/node_modules/@penpot/mcp}/packages/plugin/dist/manifest.json" ]; then
    for _ in $(seq 1 40); do
        kill -0 "$plugin_pid" 2>/dev/null || break
        code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PLUGIN_PORT}/manifest.json" 2>/dev/null || true)"
        if [ "$code" = "200" ]; then break; fi
        sleep 0.5
    done
    log "Plugin manifest http=${code:-000} (load it in Penpot from :${PLUGIN_PORT})"
fi

log "Browser profile → ${PROFILE} (persisted on the workspaces volume)"
log "Reminder: open ${PENPOT_URL:-https://design.penpot.app}, load the plugin and connect it before using MCP tools."

# --- 4. Base entrypoint ------------------------------------------------------
exec /usr/local/bin/multica-entrypoint
