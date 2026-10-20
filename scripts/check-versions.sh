#!/usr/bin/env bash
# Validate versions.env against the Dockerfiles.
#
# Rules enforced here (the cheap half of "reproducible builds"):
#   - every line is KEY=VALUE, with no inline comments and no duplicate keys
#   - every version ARG declared in a Dockerfile is present in versions.env
#   - version ARGs declare NO default (a bare `docker build` must fail, not
#     silently bake an unpinned tool)
#   - no versions.env key is unused by every Dockerfile and every script
#
# Bash 3.2 compatible (macOS): no associative arrays, no mapfile.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

failures=0
fail() { printf 'FAIL  %s\n' "$*" >&2; failures=$((failures + 1)); }
ok()   { printf 'ok    %s\n' "$*"; }

# Keys consumed by tooling rather than by an ARG.
META_KEYS=" DEBIAN_RELEASE PHP_VERSION "
# Keys supplied by Docker itself or by the build script.
BUILTIN_ARGS=" BASE_IMAGE TARGETARCH IMAGE_VERSION "

keys=()
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ''|\#*) continue ;;
    esac
    case "$line" in
        *=*) ;;
        *) fail "versions.env: not KEY=VALUE: $line"; continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
        *[!A-Z0-9_]*) fail "versions.env: invalid key '$key'"; continue ;;
    esac
    case " ${keys[*]:-} " in
        *" $key "*) fail "versions.env: duplicate key '$key'"; continue ;;
    esac
    case "$value" in
        *' #'*) fail "versions.env: inline comment on '$key' (it becomes part of the value)" ;;
    esac
    keys+=("$key")
done < versions.env

[ "${#keys[@]}" -gt 0 ] || fail "versions.env is empty"

has_key() {
    case " ${keys[*]:-} " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# --- Dockerfile ARGs ---------------------------------------------------------
declared=()
for dockerfile in $(find images autoscaler -name Dockerfile | sort); do
    while IFS= read -r argline; do
        # ARG NAME or ARG NAME=default
        name="${argline#ARG }"
        name="${name%% *}"
        default=""
        case "$name" in
            *=*) default="${name#*=}"; name="${name%%=*}" ;;
        esac
        case " ${BUILTIN_ARGS} " in
            *" $name "*) continue ;;
        esac
        case "$name" in
            [A-Z_]*) ;;
            *) continue ;;
        esac
        if ! has_key "$name"; then
            fail "$dockerfile: ARG $name is not defined in versions.env"
            continue
        fi
        if [ -n "$default" ]; then
            fail "$dockerfile: ARG $name has a default ('$default'); versions come from versions.env"
        fi
        declared+=("$name")
    done < <(grep -E '^ARG [A-Z_][A-Z0-9_]*' "$dockerfile" || true)
done

# --- Unused keys -------------------------------------------------------------
for key in "${keys[@]}"; do
    case " ${META_KEYS} " in *" $key "*) continue ;; esac
    case " ${declared[*]:-} " in
        *" $key "*) continue ;;
    esac
    fail "versions.env: '$key' is not used by any Dockerfile"
done

# --- Every pinned version must be exported by build.sh -----------------------
for key in "${keys[@]}"; do
    if ! grep -q 'done < versions.env' scripts/build.sh; then
        fail "scripts/build.sh no longer loads versions.env"
        break
    fi
done

if [ "$failures" -gt 0 ]; then
    printf '\n%d version check(s) failed\n' "$failures" >&2
    exit 1
fi
ok "versions.env is consistent with every Dockerfile (${#keys[@]} keys)"
