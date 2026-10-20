# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — node
# =============================================================================
# Web/frontend stack: Node.js LTS + pnpm + yarn + TypeScript + Playwright.
# The base image already provides Node and Chromium; this variant adds the
# package managers and test tooling a frontend agent expects.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG PNPM_VERSION
ARG YARN_VERSION
ARG TYPESCRIPT_VERSION
ARG PLAYWRIGHT_VERSION
ARG PLAYWRIGHT_MCP_VERSION
ARG VITEST_VERSION
ARG ESLINT_VERSION
ARG SERVE_VERSION
ARG PRETTIER_VERSION
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (node)" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=node \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright

USER root

RUN set -eux; \
    npm install -g --no-fund --no-audit \
        "pnpm@${PNPM_VERSION}" \
        "yarn@${YARN_VERSION}" \
        "typescript@${TYPESCRIPT_VERSION}" \
        "@playwright/test@${PLAYWRIGHT_VERSION}" \
        "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
        "vitest@${VITEST_VERSION}" \
        "eslint@${ESLINT_VERSION}" \
        "prettier@${PRETTIER_VERSION}" \
        "serve@${SERVE_VERSION}"; \
    npm cache clean --force; \
    pnpm --version; \
    yarn --version; \
    tsc --version

# Install Playwright's own Chromium build. Relying on the distro Chromium is
# faster to build but breaks on Playwright upgrades; a browser that matches the
# test runner is worth the layers.
RUN set -eux; \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"; \
    npx --yes playwright@"${PLAYWRIGHT_VERSION}" install --with-deps chromium; \
    chown -R runner:runner "${PLAYWRIGHT_BROWSERS_PATH}"; \
    rm -rf /var/lib/apt/lists/* /root/.cache/ms-playwright

USER runner
WORKDIR /home/runner

# Base ENTRYPOINT (tini → multica-entrypoint) is inherited.
