#!/usr/bin/env bash
# Startup banner: the information you actually want in a log when a task
# misbehaves. Never prints tokens or full router URLs.
# This file is sourced; it must not execute anything on its own.

# shellcheck shell=bash

mr_print_banner() {
    local os_name arch variant version
    os_name="$( ( . /etc/os-release && printf '%s' "${PRETTY_NAME:-${NAME:-}}" ) 2>/dev/null || true )"
    arch="$(uname -m 2>/dev/null || printf 'unknown')"
    variant="${MULTICA_IMAGE_VARIANT:-base}"
    version="${MULTICA_IMAGE_VERSION:-dev}"

    log "Multica Runtime ${version} (${variant})"
    log "Versions  claude=$(probe_version claude --version) | opencode=$(probe_version opencode --version) | multica=$(probe_version multica --version) | node=$(probe_version node --version) | python=$(probe_version python3 --version)"
    log "Platform  os=${os_name:-unknown} | kernel=$(probe_version uname -r) | arch=${arch}"
    log "Runtime   name=${MULTICA_AGENT_RUNTIME_NAME:-unset} | id=${MULTICA_DAEMON_ID:-auto (${HOSTNAME:-unknown})} | max-tasks=${MULTICA_DAEMON_MAX_CONCURRENT_TASKS:-default}"
    log "AI        protocol=${MR_PROTOCOL} | provider=${MR_PROVIDER_ID} | auth=${MR_AUTH_MODE} | model=${MR_MODEL:-default} | tiers=${MR_LARGE:-default}/${MR_MEDIUM:-default}/${MR_SMALL:-default} | subagent=${MR_SUBAGENT:-default}"
    log "Paths     workspaces=${MULTICA_WORKSPACES_ROOT:-/workspaces} | claude=${CLAUDE_CONFIG_DIR:-${HOME}/.claude (ephemeral)} | opencode=${XDG_DATA_HOME:-${HOME}/.local/share (ephemeral)}"
}
