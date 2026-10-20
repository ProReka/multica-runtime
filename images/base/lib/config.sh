#!/usr/bin/env bash
# Configuration resolution for the Multica runtime.
#
# The public surface is deliberately small:
#
#   MULTICA_TOKEN            connect to Multica
#   AI_BASE_URL              Anthropic-compatible endpoint
#   AI_API_KEY               credential for that endpoint
#   AI_MODEL                 model name used by both agent CLIs
#
# Native variables (ANTHROPIC_*, MULTICA_*) keep working and win when both are
# set, so existing deployments can move over without changing anything.
#
# This file is sourced; it must not execute anything on its own.

# shellcheck shell=bash

# Resolve aliases into the variables the agent CLIs and daemon read.
mr_config_resolve() {
    local native_base="${ANTHROPIC_BASE_URL:-}"
    local alias_base="${AI_BASE_URL:-}"
    local native_auth="${ANTHROPIC_AUTH_TOKEN:-}"
    local native_api_key="${ANTHROPIC_API_KEY:-}"
    local alias_key="${AI_API_KEY:-}"
    local native_model="${ANTHROPIC_MODEL:-}"
    local alias_model="${AI_MODEL:-}"

    if [ -n "$native_base" ] && [ -n "$alias_base" ] && [ "$native_base" != "$alias_base" ]; then
        warn "Both ANTHROPIC_BASE_URL and AI_BASE_URL are set and differ; using ANTHROPIC_BASE_URL (native wins)."
    fi
    if [ -n "$native_model" ] && [ -n "$alias_model" ] && [ "$native_model" != "$alias_model" ]; then
        warn "Both ANTHROPIC_MODEL and AI_MODEL are set and differ; using ANTHROPIC_MODEL (native wins)."
    fi
    if [ -n "$native_auth" ] && [ -n "$alias_key" ]; then
        warn "Both ANTHROPIC_AUTH_TOKEN and AI_API_KEY are set; using ANTHROPIC_AUTH_TOKEN (native wins)."
    fi

    MR_BASE_URL="${native_base:-$alias_base}"
    MR_MODEL="${native_model:-$alias_model}"
    MR_AUTH_MODE=""

    # Credential handling. Anthropic's own API expects x-api-key; gateways and
    # routers expect a bearer token. Getting this wrong produces a 401 that
    # looks like a bad key, so pick deliberately:
    #
    #   1. native ANTHROPIC_AUTH_TOKEN      → bearer (explicit operator choice)
    #   2. native ANTHROPIC_API_KEY         → x-api-key (explicit operator choice)
    #   3. AI_API_KEY + api.anthropic.com   → x-api-key
    #   4. AI_API_KEY + anything else       → bearer
    if [ -n "$native_auth" ]; then
        MR_API_KEY="$native_auth"
        MR_AUTH_MODE="bearer"
    elif [ -n "$native_api_key" ]; then
        MR_API_KEY="$native_api_key"
        MR_AUTH_MODE="api-key"
    elif [ -n "$alias_key" ]; then
        MR_API_KEY="$alias_key"
        case "$MR_BASE_URL" in
            https://api.anthropic.com|https://api.anthropic.com/*) MR_AUTH_MODE="api-key" ;;
            *) MR_AUTH_MODE="bearer" ;;
        esac
    else
        MR_API_KEY=""
    fi

    MR_PROTOCOL="${AI_PROTOCOL:-auto}"
    MR_PROVIDER_ID="${AI_PROVIDER_ID:-multica}"

    case "$MR_PROTOCOL" in
        auto|openai|anthropic) ;;
        *) die "AI_PROTOCOL must be auto, openai or anthropic (got '$MR_PROTOCOL')" ;;
    esac

    # OpenCode provider ids are used in model references; keep them boring.
    if ! printf '%s' "$MR_PROVIDER_ID" | grep -Eq '^[a-z0-9][a-z0-9_-]*$'; then
        die "AI_PROVIDER_ID must match [a-z0-9][a-z0-9_-]* (got '$MR_PROVIDER_ID')"
    fi

    [ -n "$MR_BASE_URL" ] || die "AI_BASE_URL (or ANTHROPIC_BASE_URL) is required — see .env.example"
    [ -n "$MR_API_KEY" ]  || die "AI_API_KEY (or ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY) is required — see .env.example"

    MR_BASE_URL="$(strip_slashes "$MR_BASE_URL")"
    export ANTHROPIC_BASE_URL="$MR_BASE_URL"

    case "$MR_AUTH_MODE" in
        bearer)
            export ANTHROPIC_AUTH_TOKEN="$MR_API_KEY"
            unset ANTHROPIC_API_KEY
            ;;
        api-key)
            export ANTHROPIC_API_KEY="$MR_API_KEY"
            unset ANTHROPIC_AUTH_TOKEN
            ;;
        *) die "internal error: unresolved auth mode" ;;
    esac

    if [ -n "$MR_MODEL" ]; then
        export ANTHROPIC_MODEL="$MR_MODEL"
    fi
}

# Claude Code resolves four model slots. A router only knows its own catalogue,
# so anything the operator did not pin is derived from AI_MODEL instead of
# falling back to upstream sonnet/haiku ids the router cannot serve.
mr_config_tiers() {
    MR_LARGE=""
    MR_MEDIUM=""
    MR_SMALL=""
    MR_SUBAGENT=""

    if [ -n "${ANTHROPIC_MODEL:-}" ]; then
        MR_LARGE="${ANTHROPIC_DEFAULT_OPUS_MODEL:-${AI_MODEL_LARGE:-$ANTHROPIC_MODEL}}"
        MR_MEDIUM="${ANTHROPIC_DEFAULT_SONNET_MODEL:-${AI_MODEL_MEDIUM:-$ANTHROPIC_MODEL}}"
        MR_SMALL="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-${AI_MODEL_SMALL:-$ANTHROPIC_MODEL}}"
        MR_SUBAGENT="${CLAUDE_CODE_SUBAGENT_MODEL:-${AI_SUBAGENT_MODEL:-$MR_MEDIUM}}"

        export ANTHROPIC_DEFAULT_OPUS_MODEL="$MR_LARGE"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="$MR_MEDIUM"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MR_SMALL"
        export CLAUDE_CODE_SUBAGENT_MODEL="$MR_SUBAGENT"
    else
        # Stock Anthropic endpoint: leave the built-in aliases alone.
        MR_LARGE="${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
        MR_MEDIUM="${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
        MR_SMALL="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
        MR_SUBAGENT="${CLAUDE_CODE_SUBAGENT_MODEL:-}"
    fi
}

mr_config_validate_multica() {
    [ -n "${MULTICA_TOKEN:-}" ] || die \
        "MULTICA_TOKEN is required — create one at https://multica.ai/settings?tab=tokens"
}

# Normalize a model name for OpenCode: OpenCode requires "provider/model".
mr_qualify_model() {
    local model="${1:-}"
    [ -n "$model" ] || { printf ''; return 0; }
    case "$model" in
        */*) printf '%s' "$model" ;;
        *)   printf '%s/%s' "$MR_PROVIDER_ID" "$model" ;;
    esac
}
