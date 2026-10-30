#!/usr/bin/env bash
# Multica runtime entrypoint.
#
#   1. Resolve the small public config surface into the variables the agent CLIs
#      and the Multica daemon expect.
#   2. Point Claude Code and OpenCode at the same AI router.
#   3. Park session state on the /workspaces volume.
#   4. Optionally configure GitHub access.
#   5. Log in to Multica headlessly and run the daemon in the foreground.
#
# The daemon detects `claude` and `opencode` on PATH and registers one runtime
# per CLI. Keep the container in the foreground: tini forwards SIGTERM and the
# daemon deregisters its runtimes before exiting.
#
# This file is deliberately readable. Helpers live in lib/ so each concern can
# be tested and reviewed on its own.

set -Eeuo pipefail

MR_LIB_DIR="${MR_LIB_DIR:-/usr/local/lib/multica}"

# shellcheck source=lib/common.sh
. "${MR_LIB_DIR}/common.sh"
# shellcheck source=lib/config.sh
. "${MR_LIB_DIR}/config.sh"
# shellcheck source=lib/claude.sh
. "${MR_LIB_DIR}/claude.sh"
# shellcheck source=lib/opencode.sh
. "${MR_LIB_DIR}/opencode.sh"
# shellcheck source=lib/git.sh
. "${MR_LIB_DIR}/git.sh"
# shellcheck source=lib/banner.sh
. "${MR_LIB_DIR}/banner.sh"

on_error() {
    local status=$?
    printf '[%s] ERROR: startup failed at line %s (exit %s)\n' \
        "$MR_LOG_PREFIX" "${BASH_LINENO[0]:-?}" "$status" >&2
    exit "$status"
}

mr_configure_multica() {
    if [ -n "${MULTICA_SERVER_URL:-}" ]; then
        log "Multica server → $(redact_url "$MULTICA_SERVER_URL")"
        multica config set server_url "$MULTICA_SERVER_URL" \
            || die "failed to set server_url"
    fi

    log "Logging in to Multica…"
    multica login --token "$MULTICA_TOKEN" \
        || die "login failed — check MULTICA_TOKEN and MULTICA_SERVER_URL"

    if [ -n "${MULTICA_WORKSPACE:-}" ]; then
        log "Default workspace → ${MULTICA_WORKSPACE}"
        multica workspace switch "$MULTICA_WORKSPACE" \
            || warn "workspace switch failed (continuing)"
    fi

    multica auth status >/dev/null 2>&1 || true

    if [ -n "${MULTICA_DAEMON_WORKSPACE_ALLOWLIST:-}" ]; then
        log "Workspace allowlist → ${MULTICA_DAEMON_WORKSPACE_ALLOWLIST}"
        export MULTICA_DAEMON_WORKSPACE_ALLOWLIST
    elif [ -n "${MULTICA_WORKSPACE:-}" ]; then
        warn "MULTICA_WORKSPACE sets the CLI default workspace only; the daemon may register in every workspace the token can reach. Set MULTICA_DAEMON_WORKSPACE_ALLOWLIST to scope registration."
    else
        log "Workspace allowlist unset — the daemon registers in every workspace the token can reach"
    fi
}

mr_start_daemon() {
    local -a args=(--foreground)

    if [ -n "${MULTICA_DAEMON_WORKSPACE_ALLOWLIST:-}" ] \
        && multica daemon start --help 2>/dev/null | grep -q -- '--workspace-allowlist'; then
        args+=(--workspace-allowlist "$MULTICA_DAEMON_WORKSPACE_ALLOWLIST")
    fi

    log "Starting Multica daemon (foreground)…"
    exec multica daemon start "${args[@]}"
}

main() {
    trap on_error ERR

    mr_config_validate_multica
    mr_config_resolve
    mr_config_tiers

    mr_configure_claude
    mr_configure_opencode
    mr_run_hooks
    mr_configure_git
    mr_print_banner

    if is_true "${MULTICA_DRY_RUN:-0}"; then
        log "MULTICA_DRY_RUN=1 — configuration resolved, not starting the daemon"
        return 0
    fi

    mr_configure_multica
    mr_prune_worktrees
    mr_start_daemon
}

# Allow `source entrypoint.sh` in tests without starting a daemon.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
