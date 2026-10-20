#!/usr/bin/env bash
# Claude Code configuration and session persistence.
# This file is sourced; it must not execute anything on its own.

# shellcheck shell=bash

mr_configure_claude() {
    local root="${MULTICA_WORKSPACES_ROOT:-/workspaces}"

    # Keep conversations on the workspaces volume so `claude --resume` still
    # finds its transcript after a restart or a scale-to-zero.
    if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
        CLAUDE_CONFIG_DIR="${root}/.claude"
    fi
    if mkdir -p "$CLAUDE_CONFIG_DIR" 2>/dev/null; then
        export CLAUDE_CONFIG_DIR
        log "Claude config dir → ${CLAUDE_CONFIG_DIR}"
    else
        warn "cannot create ${CLAUDE_CONFIG_DIR}; falling back to \$HOME/.claude (sessions will not persist)"
        unset CLAUDE_CONFIG_DIR
    fi

    # Runtimes are long-lived and image-pinned: an in-place auto-update would
    # silently change the CLI under the operator's feet.
    export_default DISABLE_AUTOUPDATER 1
    # Avoid optional telemetry/update traffic on locked-down routers.
    export_default CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1

    # Pass-through overrides for the daemon. (Use `if`, not `test && export`:
    # the latter makes the function return 1 when the variable is unset, which
    # under `set -e` aborts startup at the call site.)
    if [ -n "${MULTICA_CLAUDE_MODEL:-}" ]; then
        export MULTICA_CLAUDE_MODEL
    fi
    if [ -n "${MULTICA_CLAUDE_ARGS:-}" ]; then
        export MULTICA_CLAUDE_ARGS
    fi
}
