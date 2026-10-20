#!/usr/bin/env bash
# Shared helpers for the Multica runtime entrypoint.
# This file is sourced; it must not execute anything on its own.

# shellcheck shell=bash

MR_LOG_PREFIX="${MR_LOG_PREFIX:-multica}"

log()  { printf '[%s] %s\n' "$MR_LOG_PREFIX" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "$MR_LOG_PREFIX" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$MR_LOG_PREFIX" "$*" >&2; exit 1; }

# True for 1/true/yes/on (case-insensitive). Bash 3.2 compatible.
is_true() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Remove one or more trailing slashes.
strip_slashes() {
    local value="${1:-}"
    while [ "${value%/}" != "$value" ]; do value="${value%/}"; done
    printf '%s' "$value"
}

# Remove a trailing /v1 from an endpoint, leaving the router origin.
router_origin() {
    local value
    value="$(strip_slashes "${1:-}")"
    case "$value" in
        */v1) value="${value%/v1}" ;;
    esac
    printf '%s' "$(strip_slashes "$value")"
}

# Print the first non-empty value among the named environment variables.
first_env() {
    local name
    for name in "$@"; do
        if [ -n "${!name:-}" ]; then
            printf '%s' "${!name}"
            return 0
        fi
    done
    return 1
}

# Export a default only when the variable is unset or empty.
export_default() {
    local name="$1" value="$2"
    if [ -z "${!name:-}" ]; then
        export "${name}=${value}"
    fi
}

# Best-effort version probe. A hanging CLI must never block startup.
probe_version() {
    local out
    out="$(timeout 5 "$@" 2>/dev/null | head -n1)" || out=""
    printf '%s' "${out:-unavailable}"
}

# Run optional variant hooks after the agent CLIs have been configured.
# A variant image drops executable shell files into ${MR_LIB_DIR}/hooks/ in
# lexical order and gets the fully resolved environment (CLAUDE_CONFIG_DIR,
# OPENCODE config path, MR_*) — without the base image knowing about it.
mr_run_hooks() {
    local hook
    for hook in "${MR_LIB_DIR}"/hooks/*.sh; do
        [ -f "$hook" ] || continue
        # shellcheck disable=SC1090
        if ! . "$hook"; then
            warn "hook $(basename "$hook") failed; continuing"
        fi
    done
}

# Print a compact, secret-free environment summary.
redact_url() {
    local url="${1:-}"
    # Keep scheme + host + port, drop path/query/userinfo. Never print keys.
    printf '%s' "$url" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]+).*#\1#' 2>/dev/null || printf '<set>'
}
