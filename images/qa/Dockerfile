# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — qa
# =============================================================================
# Testing toolkit for an agent that has to prove something works:
#   Playwright (E2E, with its MCP server)  •  axe-core (accessibility)
#   newman (Postman collections)           •  k6 (load)
#   pytest + requests (API/service tests)
#
# Browsers live under /opt/playwright so the version always matches the test
# runner. The base image's distro Chromium stays available as a fallback.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG PLAYWRIGHT_VERSION
ARG PLAYWRIGHT_MCP_VERSION
ARG AXE_PLAYWRIGHT_VERSION
ARG NEWMAN_VERSION
ARG K6_VERSION
ARG PYTEST_VERSION
ARG REQUESTS_VERSION
ARG HTTPX_VERSION
ARG TARGETARCH
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (qa)" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=qa \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright

USER root

# --- Node tooling ------------------------------------------------------------
RUN set -eux; \
    npm install -g --no-fund --no-audit \
        "@playwright/test@${PLAYWRIGHT_VERSION}" \
        "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
        "@axe-core/playwright@${AXE_PLAYWRIGHT_VERSION}" \
        "newman@${NEWMAN_VERSION}"; \
    npm cache clean --force; \
    playwright --version; \
    newman --version

# --- Browsers ----------------------------------------------------------------
# `install --with-deps` also pulls the shared libraries Chromium needs, which
# the distro package list in the base image does not fully cover.
RUN set -eux; \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"; \
    playwright install --with-deps chromium; \
    chown -R runner:runner "${PLAYWRIGHT_BROWSERS_PATH}"; \
    rm -rf /root/.cache/ms-playwright /var/lib/apt/lists/*

# --- Python test tooling -----------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3-pip python3-venv; \
    rm -rf /var/lib/apt/lists/*; \
    pip3 install --break-system-packages --no-cache-dir \
        "pytest==${PYTEST_VERSION}" \
        "requests==${REQUESTS_VERSION}" \
        "httpx==${HTTPX_VERSION}"; \
    pytest --version

# --- k6 (checksum-verified) --------------------------------------------------
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) k6_arch="amd64" ;; \
        arm64) k6_arch="arm64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    asset="k6-v${K6_VERSION}-linux-${k6_arch}.tar.gz"; \
    base="https://github.com/grafana/k6/releases/download/v${K6_VERSION}"; \
    curl -fsSL "${base}/k6-v${K6_VERSION}-checksums.txt" -o /tmp/k6.sha256; \
    expected="$(awk -v f="$asset" '$2 == f { print $1 }' /tmp/k6.sha256)"; \
    [ -n "$expected" ] || { echo "no checksum for ${asset}" >&2; exit 1; }; \
    curl -fsSL "${base}/${asset}" -o /tmp/k6.tar.gz; \
    echo "${expected}  /tmp/k6.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/k6.tar.gz -C /tmp; \
    install -m 0755 "/tmp/k6-v${K6_VERSION}-linux-${k6_arch}/k6" /usr/local/bin/k6; \
    rm -rf /tmp/k6.tar.gz /tmp/k6.sha256 "/tmp/k6-v${K6_VERSION}-linux-${k6_arch}"; \
    k6 version

USER runner
WORKDIR /home/runner

# Base ENTRYPOINT (tini → multica-entrypoint) is inherited.
