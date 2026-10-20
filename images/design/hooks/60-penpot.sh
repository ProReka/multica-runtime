#!/usr/bin/env bash
# Entrypoint hook (design image): register the local Penpot MCP server with
# both agent CLIs. Sourced by the base entrypoint after Claude Code and OpenCode
# have been configured, so it can amend the files they just wrote.
#
# Disable with MULTICA_PENPOT_MCP=0.

# shellcheck shell=bash

if is_true "${MULTICA_PENPOT_MCP:-1}"; then
    url="http://127.0.0.1:${PENPOT_MCP_SERVER_PORT:-4401}/mcp"

    if command -v claude >/dev/null 2>&1; then
        if CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" \
            claude mcp add --scope user --transport http penpot "$url" >/dev/null 2>&1; then
            log "Claude Code MCP → penpot (${url})"
        else
            warn "could not register the Penpot MCP server with Claude Code; run: claude mcp add --transport http penpot ${url}"
        fi
    fi

    config_file="${OPENCODE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json}"
    if [ -f "$config_file" ] && command -v jq >/dev/null 2>&1; then
        tmp="$(mktemp "${config_file}.XXXXXX" 2>/dev/null || true)"
        if [ -n "$tmp" ] && jq --arg url "$url" \
            '.mcp = ((.mcp // {}) + {penpot: {type: "remote", url: $url, enabled: true}})' \
            "$config_file" >"$tmp" 2>/dev/null; then
            chmod 600 "$tmp" 2>/dev/null || true
            mv "$tmp" "$config_file"
            log "OpenCode MCP → penpot (${url})"
        else
            rm -f "${tmp:-}"
            warn "could not register the Penpot MCP server with OpenCode"
        fi
    fi
fi
