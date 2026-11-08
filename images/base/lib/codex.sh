#!/usr/bin/env bash
# Codex CLI configuration and session persistence.
#
# Codex reads neither ANTHROPIC_* nor the OpenCode config, so the entrypoint
# writes $CODEX_HOME/config.toml with a custom provider pointed at the router.
# Codex only speaks the OpenAI Responses API (upstream removed
# `wire_api = "chat"`), so the router must serve <base>/responses.
#
# The Multica daemon copies this config into a per-task CODEX_HOME and drives
# `codex app-server` itself; no exec wrapper is needed here.
#
# This file is sourced; it must not execute anything on its own.

# shellcheck shell=bash

# TOML basic strings accept JSON string escapes.
mr_toml_string() { jq -n --arg v "$1" '$v'; }

mr_configure_codex() {
    command -v codex >/dev/null 2>&1 || return 0

    local root="${MULTICA_WORKSPACES_ROOT:-/workspaces}"
    local base_url model config_file

    # The daemon keeps its per-issue session stores under the shared home, so
    # parking it on the volume is what makes Codex resume survive restarts.
    if [ -z "${CODEX_HOME:-}" ]; then
        CODEX_HOME="${root}/.codex"
    fi
    if ! mkdir -p "$CODEX_HOME" 2>/dev/null; then
        warn "cannot create ${CODEX_HOME}; Codex is not configured"
        unset CODEX_HOME
        return 0
    fi
    export CODEX_HOME
    log "Codex home → ${CODEX_HOME}"

    base_url="$(strip_slashes "${CODEX_BASE_URL:-$(router_origin "$MR_BASE_URL")/v1}")"
    model="${CODEX_MODEL:-${MR_MODEL:-}}"
    export CODEX_API_KEY="${CODEX_API_KEY:-$MR_API_KEY}"

    case "$base_url" in
        https://api.anthropic.com|https://api.anthropic.com/*)
            warn "Codex needs an OpenAI Responses endpoint; set CODEX_BASE_URL (api.anthropic.com does not serve /responses)"
            ;;
    esac

    # Regenerated at every start. The key stays in the environment (env_key),
    # never in the file; 0600 anyway because the daemon may add MCP secrets.
    config_file="${CODEX_HOME}/config.toml"
    if ( umask 077; {
        if [ -n "$model" ]; then printf 'model = %s\n' "$(mr_toml_string "$model")"; fi
        printf 'model_provider = "%s"\n' "$MR_PROVIDER_ID"
        printf 'check_for_update_on_startup = false\n\n'
        printf '[model_providers.%s]\n' "$MR_PROVIDER_ID"
        printf 'name = "Multica AI Router"\n'
        printf 'base_url = %s\n' "$(mr_toml_string "$base_url")"
        printf 'env_key = "CODEX_API_KEY"\n'
        printf 'wire_api = "responses"\n'
    } > "$config_file" ); then
        chmod 600 "$config_file" 2>/dev/null || true
        log "Codex config → ${config_file} (provider=${MR_PROVIDER_ID}, base=$(redact_url "$base_url"), model=${model:-default})"
    else
        warn "cannot write ${config_file}; Codex will use its defaults"
    fi
}
