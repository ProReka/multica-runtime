#!/usr/bin/env bash
# Optional Git hosting setup.
# This file is sourced; it must not execute anything on its own.

# shellcheck shell=bash

mr_configure_git() {
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

    git config --global init.defaultBranch main 2>/dev/null || true
    git config --global --add safe.directory "${MULTICA_WORKSPACES_ROOT:-/workspaces}" 2>/dev/null || true

    if [ -n "${GIT_AUTHOR_NAME:-}" ]; then
        git config --global user.name "$GIT_AUTHOR_NAME" 2>/dev/null || true
    fi
    if [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then
        git config --global user.email "$GIT_AUTHOR_EMAIL" 2>/dev/null || true
    fi

    if [ -n "$token" ]; then
        export GH_TOKEN="$token"
        if gh auth setup-git 2>/dev/null; then
            log "GitHub CLI configured (git push/pull over HTTPS enabled)"
        else
            warn "gh auth setup-git failed; gh may still work from GH_TOKEN"
        fi
        gh auth status >/dev/null 2>&1 || warn "gh auth status did not report a valid login"
    fi
}
