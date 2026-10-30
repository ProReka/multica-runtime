#!/usr/bin/env bash
# Git hosting setup and cached worktree maintenance.
# This file is sourced; it must not execute anything on its own.

# shellcheck shell=bash

# Interrupted tasks can leave stale registrations on the persistent volume.
# Keep Git's default expiry; never remove task directories or valid worktrees.
mr_prune_worktrees() {
    local repos_root="${MULTICA_WORKSPACES_ROOT:-/workspaces}/.repos"
    local bare_repo

    [ -d "$repos_root" ] || return 0
    while IFS= read -r -d '' bare_repo; do
        git --git-dir="$bare_repo" worktree prune -v \
            || warn "Could not prune stale Git worktrees"
    done < <(find "$repos_root" -mindepth 2 -maxdepth 2 -name '*.git' -type d -print0 2>/dev/null)
}

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
