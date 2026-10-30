#!/usr/bin/env bash
# Regression check; no Docker required.
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../images/base/lib/git.sh
. "$root/images/base/lib/git.sh"
warn() { printf '%s\n' "$*" >&2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export MULTICA_WORKSPACES_ROOT="$tmp/workspaces"
mr_prune_worktrees # No cache yet.

repo="$MULTICA_WORKSPACES_ROOT/.repos/workspace/repo.git"
git init --bare -q "$repo"
commit="$(printf 'test\n' | git -c user.name=Test -c user.email=test@example.invalid \
    --git-dir="$repo" commit-tree "$(git --git-dir="$repo" mktree </dev/null)")"
git --git-dir="$repo" update-ref HEAD "$commit"
for name in stale valid locked; do
    git --git-dir="$repo" worktree add -q --detach "$tmp/$name" HEAD
done
git --git-dir="$repo" worktree lock "$tmp/locked"
rm "$tmp/stale/.git" "$tmp/locked/.git"
printf 'keep\n' >"$tmp/stale/task-data"

mr_prune_worktrees
[ ! -d "$repo/worktrees/stale" ]
[ -d "$repo/worktrees/locked" ]
[ "$(cat "$tmp/stale/task-data")" = keep ]
git -C "$tmp/valid" rev-parse --is-inside-work-tree | grep -qx true
printf 'Worktree pruning OK.\n'
