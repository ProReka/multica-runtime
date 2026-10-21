#!/usr/bin/env bash
# Runtime smoke tests for variants whose value is in what they start, not only
# in the binaries they contain. Requires a Docker daemon and a built/pulled image.
#
#   IMAGE=ghcr.io/proreka/multica-runtime:php scripts/test-runtime.sh php
#   IMAGE=ghcr.io/proreka/multica-runtime:design scripts/test-runtime.sh design
#
# `scripts/test-image.sh` covers binaries and the base entrypoint. This script
# covers the two variant entrypoints that mutate state: the embedded PHP
# databases and the design Xvfb/MCP/plugin stack.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

variant="${1:-}"
case "$variant" in
    php|design) ;;
    *) echo "usage: IMAGE=... $0 php|design" >&2; exit 2 ;;
esac

image="${IMAGE:-ghcr.io/proreka/multica-runtime:${variant}}"

pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; exit 1; }

echo "==> ${variant} runtime (${image})"

if ! docker image inspect "$image" >/dev/null 2>&1; then
    fail "image not found: ${image}"
fi

case "$variant" in
    php)
        # Start the databases inside the container and prove all three answer.
        # The defaults come from start-databases.sh: laravel/secret/laravel.
        out="$(timeout 240 docker run --rm --entrypoint bash "$image" -c '
            set -euo pipefail
            /usr/local/bin/multica-start-databases
            psql_bin="$(command -v psql || find /usr/lib/postgresql -maxdepth 3 -name psql | sort | head -n1)"
            mariadb -h127.0.0.1 -ularavel -psecret laravel -N -e "SELECT 1"
            PGPASSWORD=secret "$psql_bin" -h127.0.0.1 -Ularavel -dlaravel -tAc "SELECT 1"
            redis-cli ping
        ' 2>&1)" || { printf '%s\n' "$out" | tail -n 30 >&2; fail "php databases"; }

        grep -qx '1' <<<"$out" || { printf '%s\n' "$out" | tail -n 30 >&2; fail "php MariaDB/PostgreSQL query"; }
        grep -qx 'PONG' <<<"$out" || { printf '%s\n' "$out" | tail -n 30 >&2; fail "php Redis ping"; }
        pass "php embedded MariaDB, PostgreSQL, Redis"
        ;;

    design)
        # The design entrypoint starts Xvfb, the Penpot MCP server and the
        # plugin server, then hands off to the base entrypoint. The dry run
        # stops before login, so no real token is needed.
        out="$(timeout 180 docker run --rm \
            -e MULTICA_TOKEN=smoke-test-token \
            -e AI_BASE_URL=http://127.0.0.1:9/v1 \
            -e AI_API_KEY=smoke-test-key \
            -e AI_MODEL=smoke-model \
            -e AI_MODELS_PROBE=0 \
            -e MULTICA_DRY_RUN=1 \
            "$image" 2>&1)" || { printf '%s\n' "$out" | tail -n 40 >&2; fail "design entrypoint"; }

        grep -q 'Penpot MCP server is up' <<<"$out" \
            || { printf '%s\n' "$out" | tail -n 40 >&2; fail "design MCP server"; }
        grep -q 'Plugin manifest http=200' <<<"$out" \
            || { printf '%s\n' "$out" | tail -n 40 >&2; fail "design plugin server"; }
        grep -q 'MULTICA_DRY_RUN=1' <<<"$out" \
            || { printf '%s\n' "$out" | tail -n 40 >&2; fail "design base entrypoint"; }
        pass "design Xvfb, Penpot MCP, plugin server, base entrypoint"
        ;;
esac
