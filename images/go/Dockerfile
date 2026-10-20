# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — go
# =============================================================================
# Go toolchain + golangci-lint. Module cache and build cache live under the
# runner home so they are writable without root.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GO_VERSION
ARG GOLANGCI_LINT_VERSION
ARG TARGETARCH
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (go)" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=go \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    GOROOT=/usr/local/go \
    GOPATH=/home/runner/go \
    GOBIN=/home/runner/go/bin \
    GOCACHE=/home/runner/.cache/go-build \
    PATH="/usr/local/go/bin:/home/runner/go/bin:${PATH}"

USER root

# --- Go toolchain (checksum-verified) ---------------------------------------
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) go_arch="amd64" ;; \
        arm64) go_arch="arm64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    asset="go${GO_VERSION}.linux-${go_arch}.tar.gz"; \
    url="https://go.dev/dl/${asset}"; \
    curl -fsSL "$url" -o /tmp/go.tar.gz; \
    curl -fsSL "https://go.dev/dl/?mode=json&include=all" -o /tmp/go.json; \
    expected="$(jq -r --arg f "$asset" '.[] | .files[] | select(.filename == $f) | .sha256' /tmp/go.json | head -n1)"; \
    [ -n "$expected" ] || { echo "no checksum for ${asset}" >&2; exit 1; }; \
    echo "${expected}  /tmp/go.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/go.tar.gz -C /usr/local; \
    rm -f /tmp/go.tar.gz /tmp/go.json; \
    go version

# --- golangci-lint -----------------------------------------------------------
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) lint_arch="amd64" ;; \
        arm64) lint_arch="arm64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    asset="golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${lint_arch}.tar.gz"; \
    base="https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}"; \
    curl -fsSL "${base}/golangci-lint-${GOLANGCI_LINT_VERSION}-checksums.txt" -o /tmp/golangci.sha256; \
    expected="$(awk -v f="$asset" '$2 == f { print $1 }' /tmp/golangci.sha256)"; \
    [ -n "$expected" ] || { echo "no checksum for ${asset}" >&2; exit 1; }; \
    curl -fsSL "${base}/${asset}" -o /tmp/golangci.tar.gz; \
    echo "${expected}  /tmp/golangci.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/golangci.tar.gz -C /tmp; \
    install -m 0755 "/tmp/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${lint_arch}/golangci-lint" /usr/local/bin/golangci-lint; \
    rm -rf /tmp/golangci.tar.gz /tmp/golangci.sha256 "/tmp/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${lint_arch}"; \
    golangci-lint --version

# --- Writable caches ---------------------------------------------------------
RUN set -eux; \
    mkdir -p "$GOPATH" "$GOCACHE" /home/runner/go/bin; \
    chown -R runner:runner "$GOPATH" /home/runner/.cache

USER runner
WORKDIR /home/runner

# Base ENTRYPOINT (tini → multica-entrypoint) is inherited.
