#!/usr/bin/env bash
# Build Multica Runtime images.
#
# Versions come from versions.env (single source of truth) and are passed to
# every Dockerfile as build args. To upgrade a tool, edit versions.env only.
#
# Usage:
#   scripts/build.sh                            # all images, local Docker
#   VARIANTS=base,node scripts/build.sh         # subset
#   VARIANTS=base PUSH=1 scripts/build.sh       # multi-arch, push to registry
#   VARIANTS=base USE_BUILDX=1 scripts/build.sh # buildx + --load, no push
#
# Environment:
#   REGISTRY    image registry/owner prefix (default: ghcr.io/proreka)
#   IMAGE       repository name (default: multica-runtime)
#   VARIANTS    comma-separated targets (default: all)
#   PUSH        1 = buildx multi-arch and push (default: 0)
#   USE_BUILDX  1 = use buildx without pushing (for CI cache)
#   PLATFORMS   buildx platforms when pushing (default: linux/amd64,linux/arm64)
#   PLATFORM    single platform for buildx --load (default: host)
#   BASE_IMAGE  optional parent image override (default: repository's :base)
#   VERSION     release version, used in tags and the OCI version label
#   SHA         git sha used in tags (default: current short sha)
#   CACHE_FROM  optional buildx cache source (type=gha,scope=...)
#   CACHE_TO    optional buildx cache destination (type=gha,mode=max,scope=...)
#   NO_CACHE    1 = disable layer cache
set -Eeuo pipefail
cd "$(dirname "$0")/.."

# --- Load versions.env -------------------------------------------------------
# Bash 3.2 compatible (macOS): no associative arrays, no mapfile.
VERSION_KEYS=()
VERSION_VALUES=()
while IFS='=' read -r key value; do
    case "$key" in ''|\#*) continue ;; esac
    # Explicit environment overrides win over versions.env.
    if [ -n "${!key+x}" ]; then
        value="${!key}"
    fi
    export "${key}=${value}"
    VERSION_KEYS+=("$key")
    VERSION_VALUES+=("$value")
done < versions.env

[ "${#VERSION_KEYS[@]}" -gt 0 ] || { echo "ERROR: versions.env is empty" >&2; exit 1; }

BUILD_ARGS=()
i=0
while [ "$i" -lt "${#VERSION_KEYS[@]}" ]; do
    BUILD_ARGS+=(--build-arg "${VERSION_KEYS[$i]}=${VERSION_VALUES[$i]}")
    i=$((i + 1))
done

REGISTRY="${REGISTRY:-ghcr.io/proreka}"
IMAGE="${IMAGE:-multica-runtime}"
PUSH="${PUSH:-0}"
USE_BUILDX="${USE_BUILDX:-0}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
VERSION="${VERSION:-}"
SHA="${SHA:-$(git rev-parse --short HEAD 2>/dev/null || true)}"
# The OCI version label should identify the exact build. On a branch push there
# is no release version, so use the commit sha rather than a meaningless "dev".
IMAGE_VERSION="${VERSION:-${SHA:-dev}}"
NO_CACHE="${NO_CACHE:-0}"
CACHE_FROM="${CACHE_FROM:-}"
CACHE_TO="${CACHE_TO:-}"
VARIANTS="${VARIANTS:-base,node,python,php,go,flutter,devops,qa,design,autoscaler}"

if [ "$PUSH" = "1" ]; then
    REPO="${REGISTRY}/${IMAGE}"
else
    REPO="${IMAGE}"
fi
BASE_IMAGE="${BASE_IMAGE:-${REPO}:base}"

IFS=',' read -r -a WANTED <<< "$VARIANTS"

CACHE_FLAG=()
[ "$NO_CACHE" = "1" ] && CACHE_FLAG=(--no-cache)
[ -n "$CACHE_FROM" ] && CACHE_FLAG+=(--cache-from "$CACHE_FROM")
[ -n "$CACHE_TO" ] && CACHE_FLAG+=(--cache-to "$CACHE_TO")

context_for() {
    case "$1" in
        base)       printf 'images/base' ;;
        node)       printf 'images/node' ;;
        python)     printf 'images/python' ;;
        php)        printf 'images/php' ;;
        go)         printf 'images/go' ;;
        flutter)    printf 'images/flutter' ;;
        devops)     printf 'images/devops' ;;
        qa)         printf 'images/qa' ;;
        design)     printf 'images/design' ;;
        autoscaler) printf 'autoscaler' ;;
        *) return 1 ;;
    esac
}

tags_for() {
    local variant="$1" tag
    local -a tags=("${REPO}:${variant}")
    [ -n "$SHA" ] && tags+=("${REPO}:sha-${SHA}-${variant}")
    [ -n "$VERSION" ] && tags+=("${REPO}:v${VERSION}-${variant}")
    if [ "$variant" = "base" ]; then
        tags+=("${REPO}:latest")
        [ -n "$VERSION" ] && tags+=("${REPO}:v${VERSION}")
    fi
    for tag in "${tags[@]}"; do printf '%s\n' "$tag"; done
}

buildx_platform_args() {
    if [ "$PUSH" = "1" ]; then
        printf '%s\n' "--platform" "$PLATFORMS"
    elif [ -n "${PLATFORM:-}" ]; then
        printf '%s\n' "--platform" "$PLATFORM"
    fi
}

build_target() {
    local variant="$1" context="$2" tag
    local -a tag_args=() platform_args=()
    while IFS= read -r tag; do
        [ -n "$tag" ] && tag_args+=(-t "$tag")
    done < <(tags_for "$variant")

    while IFS= read -r line; do
        [ -n "$line" ] && platform_args+=("$line")
    done < <(buildx_platform_args)

    echo
    echo "==> ${variant}: ${tag_args[*]}"

    if [ "$PUSH" = "1" ]; then
        local -a base_arg=()
        [ "$variant" != "base" ] && base_arg=(--build-arg "BASE_IMAGE=${BASE_IMAGE}")
        docker buildx build "${platform_args[@]}" --push --provenance=true --sbom=true \
            --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
            "${base_arg[@]+"${base_arg[@]}"}" \
            "${BUILD_ARGS[@]}" "${CACHE_FLAG[@]+"${CACHE_FLAG[@]}"}" \
            "${tag_args[@]}" "$context"
    elif [ "$USE_BUILDX" = "1" ]; then
        local -a base_arg=()
        [ "$variant" != "base" ] && base_arg=(--build-arg "BASE_IMAGE=${BASE_IMAGE}")
        docker buildx build "${platform_args[@]}" --load \
            --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
            "${base_arg[@]+"${base_arg[@]}"}" \
            "${BUILD_ARGS[@]}" "${CACHE_FLAG[@]+"${CACHE_FLAG[@]}"}" \
            "${tag_args[@]}" "$context"
    else
        local -a base_arg=() platform_arg=()
        [ "$variant" != "base" ] && base_arg=(--build-arg "BASE_IMAGE=${BASE_IMAGE}")
        [ -n "${PLATFORM:-}" ] && platform_arg=(--platform "$PLATFORM")
        docker build --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
            "${base_arg[@]+"${base_arg[@]}"}" "${platform_arg[@]+"${platform_arg[@]}"}" \
            "${BUILD_ARGS[@]}" "${CACHE_FLAG[@]+"${CACHE_FLAG[@]}"}" \
            "${tag_args[@]}" "$context"
    fi
}

build_autoscaler() {
    local repo tag
    local -a tags=() tag_args=() platform_args=()
    if [ "$PUSH" = "1" ]; then
        repo="${REPO%/*}/multica-autoscaler"
    else
        repo="multica-autoscaler"
    fi
    tags=("${repo}:latest")
    [ -n "$SHA" ] && tags+=("${repo}:sha-${SHA}")
    [ -n "$VERSION" ] && tags+=("${repo}:v${VERSION}")

    for tag in "${tags[@]}"; do tag_args+=(-t "$tag"); done
    while IFS= read -r line; do
        [ -n "$line" ] && platform_args+=("$line")
    done < <(buildx_platform_args)

    echo
    echo "==> autoscaler: ${tag_args[*]}"

    if [ "$PUSH" = "1" ]; then
        docker buildx build "${platform_args[@]}" --push --provenance=true --sbom=true \
            --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
            --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
            "${BUILD_ARGS[@]}" "${CACHE_FLAG[@]+"${CACHE_FLAG[@]}"}" \
            "${tag_args[@]}" autoscaler
    elif [ "$USE_BUILDX" = "1" ]; then
        docker buildx build "${platform_args[@]}" --load \
            --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
            --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
            "${BUILD_ARGS[@]}" "${CACHE_FLAG[@]+"${CACHE_FLAG[@]}"}" \
            "${tag_args[@]}" autoscaler
    else
        docker build --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
            --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
            "${BUILD_ARGS[@]}" "${CACHE_FLAG[@]+"${CACHE_FLAG[@]}"}" \
            "${tag_args[@]}" autoscaler
    fi
}

# --- Validate variants -------------------------------------------------------
needs_base=0
for variant in "${WANTED[@]}"; do
    [ -n "$variant" ] || continue
    context_for "$variant" >/dev/null || { echo "ERROR: unknown variant '$variant'" >&2; exit 1; }
    [ "$variant" = "base" ] || needs_base=1
done

# When base is part of the same push build, publish it before anything that
# inherits from it. CI builds base in its own job, so a variant-only invocation
# here relies on that base already existing in the registry.
if [ "$needs_base" = "1" ] && [ "$PUSH" = "1" ]; then
    for variant in "${WANTED[@]}"; do
        if [ "$variant" = "base" ]; then
            build_target base "$(context_for base)"
            break
        fi
    done
fi

for variant in "${WANTED[@]}"; do
    [ -n "$variant" ] || continue
    if [ "$variant" = "base" ] && [ "$needs_base" = "1" ] && [ "$PUSH" = "1" ]; then
        continue
    fi
    if [ "$variant" = "autoscaler" ]; then
        build_autoscaler
    else
        build_target "$variant" "$(context_for "$variant")"
    fi
done

echo
echo "== Done =="
