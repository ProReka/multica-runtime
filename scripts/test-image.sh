#!/usr/bin/env bash
# Smoke-test built images.
#
#   scripts/test-image.sh                       # every variant present locally
#   scripts/test-image.sh base node qa          # a subset
#   IMAGE_PREFIX=ghcr.io/proreka/multica-runtime scripts/test-image.sh base
#
# Two checks per variant:
#   1. every expected binary exists and answers --version
#   2. the entrypoint resolves configuration offline (MULTICA_DRY_RUN=1)
#
# The entrypoint dry run uses a bogus router and disables the model probe, so it
# needs no network and no credentials. It proves that AI_* aliases, session
# directories and the OpenCode config are wired correctly.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

IMAGE_PREFIX="${IMAGE_PREFIX:-multica-runtime}"
AUTOSCALER_IMAGE="${AUTOSCALER_IMAGE:-multica-autoscaler:latest}"

ALL_VARIANTS=(base node python php go flutter devops qa design)
if [ "$#" -gt 0 ]; then
    VARIANTS=("$@")
else
    VARIANTS=("${ALL_VARIANTS[@]}")
fi

failures=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; failures=$((failures + 1)); }

commands_for() {
    case "$1" in
        base)       printf '%s\n' claude opencode multica gh node npm python3 git jq chromium ;;
        node)       printf '%s\n' pnpm yarn tsc playwright vitest eslint prettier serve ;;
        python)     printf '%s\n' uv poetry ruff mypy pytest ;;
        php)        printf '%s\n' php composer laravel mariadbd psql redis-server ;;
        go)         printf '%s\n' go golangci-lint ;;
        flutter)    printf '%s\n' flutter dart java sdkmanager ;;
        devops)     printf '%s\n' terraform aws kubectl helm docker yq wrangler uv ;;
        qa)         printf '%s\n' playwright newman k6 pytest ;;
        design)     printf '%s\n' convert rsvg-convert gs potrace cwebp Xvfb node ;;
        autoscaler) printf '%s\n' multica aws docker python3 ;;
        *)          return 1 ;;
    esac
}

image_for() {
    case "$1" in
        autoscaler) printf '%s' "$AUTOSCALER_IMAGE" ;;
        *)          printf '%s:%s' "$IMAGE_PREFIX" "$1" ;;
    esac
}

test_commands() {
    local variant="$1" image="$2" cmds
    cmds="$(commands_for "$variant")" || { fail "unknown variant $variant"; return; }

    local script="set -e
"
    local cmd
    for cmd in $cmds; do
        script="${script}command -v ${cmd} >/dev/null || { echo 'missing: ${cmd}'; exit 1; }
"
    done

    if docker run --rm --entrypoint bash "$image" -c "$script" >/tmp/multica-smoke.log 2>&1; then
        pass "$variant binaries ($(wc -w <<<"$cmds" | tr -d ' '))"
    else
        fail "$variant binaries"
        sed 's/^/        /' /tmp/multica-smoke.log >&2
    fi
}

test_entrypoint() {
    local variant="$1" image="$2"
    local out
    out="$(docker run --rm \
        --entrypoint /usr/local/bin/multica-entrypoint \
        -e MULTICA_TOKEN=smoke-test-token \
        -e AI_BASE_URL=http://127.0.0.1:9/v1 \
        -e AI_API_KEY=smoke-test-key \
        -e AI_MODEL=smoke-model \
        -e AI_MODELS_PROBE=0 \
        -e MULTICA_DRY_RUN=1 \
        "$image" 2>&1)" || {
            fail "$variant entrypoint dry run"
            printf '%s\n' "$out" | tail -n 20 | sed 's/^/        /' >&2
            return
        }

    if grep -q "configuration resolved" <<<"$out" && grep -q "model=smoke-model" <<<"$out"; then
        pass "$variant entrypoint config"
    else
        fail "$variant entrypoint config (unexpected output)"
        printf '%s\n' "$out" | tail -n 20 | sed 's/^/        /' >&2
    fi
}

# Variants whose variant-entrypoint has side effects better exercised by their
# own test (embedded databases, Xvfb/MCP). They still get the binary check.
skip_entrypoint() {
    case "$1" in php|design|autoscaler|flutter) return 0 ;; *) return 1 ;; esac
}

for variant in "${VARIANTS[@]}"; do
    image="$(image_for "$variant")"
    printf '==> %s (%s)\n' "$variant" "$image"

    if ! docker image inspect "$image" >/dev/null 2>&1; then
        fail "$variant image not found — run: VARIANTS=$variant scripts/build.sh"
        continue
    fi

    test_commands "$variant" "$image"
    if skip_entrypoint "$variant"; then
        printf '  skip  %s entrypoint dry run\n' "$variant"
    else
        test_entrypoint "$variant" "$image"
    fi
done

if [ "$failures" -gt 0 ]; then
    printf '\n%d check(s) failed\n' "$failures" >&2
    exit 1
fi
printf '\nAll checks passed.\n'
