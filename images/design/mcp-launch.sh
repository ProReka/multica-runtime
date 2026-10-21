#!/usr/bin/env bash
# Starts the Penpot MCP server that was built into the image.
#
# The npm package ships TypeScript sources and normally rebuilds itself through
# `pnpm run bootstrap` on every launch. We build it once at image build time, so
# startup needs neither a network nor a compiler; this script runs the compiled
# entry point directly.
set -Eeuo pipefail

ROOT="${PENPOT_MCP_ROOT:-/opt/penpot-mcp/node_modules/@penpot/mcp}"
ENTRY="${ROOT}/packages/server/dist/index.js"

if [ ! -f "$ENTRY" ]; then
    printf '[multica-design] ERROR: Penpot MCP build not found at %s\n' "$ENTRY" >&2
    exit 1
fi

# Log files, if enabled, must land somewhere the runner can write.
export PENPOT_MCP_LOG_DIR="${PENPOT_MCP_LOG_DIR:-${MULTICA_WORKSPACES_ROOT:-/workspaces}/.penpot/logs}"
mkdir -p "$PENPOT_MCP_LOG_DIR" 2>/dev/null || true

# The server resolves data/initial_instructions.md and data/base_instructions.md
# relative to the working directory. `pnpm run start` is run from the package
# directory for exactly this reason; reproduce that here. Starting from / or
# /workspaces throws before the HTTP listener exists (and the logger may exit
# before it flushes, leaving an empty log).
cd "${ROOT}/packages/server"

exec node dist/index.js "$@"
