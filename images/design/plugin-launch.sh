#!/usr/bin/env bash
# Serves the built Penpot MCP plugin over HTTP so it can be loaded into Penpot
# (Plugins → Load plugin → http://<host>:4400/manifest.json).
#
# `vite preview` only serves the static build; it needs no compiler at runtime.
set -Eeuo pipefail

ROOT="${PENPOT_MCP_ROOT:-/opt/penpot-mcp/node_modules/@penpot/mcp}"
PLUGIN="${ROOT}/packages/plugin"

if [ ! -f "${PLUGIN}/dist/manifest.json" ]; then
    printf '[multica-design] WARN: plugin build not found at %s/dist — skipping plugin server\n' "$PLUGIN" >&2
    exit 0
fi

cd "$PLUGIN"
exec node "${ROOT}/node_modules/vite/bin/vite.js" preview \
    --host "${PENPOT_MCP_PLUGIN_SERVER_HOST:-127.0.0.1}" \
    --port "${PENPOT_MCP_PLUGIN_PORT:-4400}"
