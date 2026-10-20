# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — design
# =============================================================================
# UI/design runtime:
#   ImageMagick, librsvg, ghostscript, potrace, webp  → asset production
#   Playwright + Chromium                            → visual QA, Penpot driving
#   Pillow, fontTools, cairoSVG                      → image/SVG work
#   Penpot MCP server + plugin (built into the image) → design-file automation
#
# Penpot's official MCP server only works while a Penpot file is open in a real
# browser with its plugin connected. The entrypoint therefore starts:
#
#   Xvfb :99  →  Chromium (headed, driven by the agent)  →  Penpot web app
#                                                          ↕ plugin (ws :4402)
#   agent  ⇄  http://127.0.0.1:4401/mcp  ⇄  Penpot MCP server
#
# Everything runs as the unprivileged `runner` user. No root, no setpriv, no
# gosu — the image works under Fargate's default seccomp profile.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG PLAYWRIGHT_VERSION
ARG PENPOT_MCP_VERSION
ARG PILLOW_VERSION
ARG FONTTOOLS_VERSION
ARG CAIROSVG_VERSION
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (design)" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=design \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright \
    PENPOT_MCP_ROOT=/opt/penpot-mcp/node_modules/@penpot/mcp

USER root

# --- System packages ---------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        imagemagick \
        librsvg2-bin \
        ghostscript \
        potrace \
        webp \
        xvfb \
        xauth \
        python3-pip \
        python3-venv \
        libcairo2 \
        libpango-1.0-0 \
        libpangoft2-1.0-0 \
        libjpeg62-turbo \
        libopenjp2-7; \
    rm -rf /var/lib/apt/lists/*

# --- Python image tooling ----------------------------------------------------
RUN set -eux; \
    pip3 install --break-system-packages --no-cache-dir \
        "Pillow==${PILLOW_VERSION}" \
        "fonttools==${FONTTOOLS_VERSION}" \
        "cairosvg==${CAIROSVG_VERSION}"; \
    python3 -c 'import PIL, fontTools, cairosvg; print("python image tooling OK")'

# --- Playwright --------------------------------------------------------------
RUN set -eux; \
    npm install -g --no-fund --no-audit "@playwright/test@${PLAYWRIGHT_VERSION}"; \
    npm cache clean --force; \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"; \
    playwright install --with-deps chromium; \
    chown -R runner:runner "${PLAYWRIGHT_BROWSERS_PATH}"; \
    rm -rf /root/.cache/ms-playwright /var/lib/apt/lists/*

# --- Penpot MCP (built once, at image build time) ----------------------------
# The npm package ships TypeScript sources and `penpot-mcp` rebuilds them on
# every launch. We install it into a dedicated prefix, run the monorepo build
# once, and then start the compiled server directly (mcp-launch.sh). Runtime
# needs no network and no compiler.
RUN set -eux; \
    mkdir -p /opt/penpot-mcp; \
    npm install --prefix /opt/penpot-mcp --no-fund --no-audit \
        "@penpot/mcp@${PENPOT_MCP_VERSION}"; \
    npm cache clean --force; \
    pkg="${PENPOT_MCP_ROOT}"; \
    pnpm_version="$(jq -r '.packageManager // empty' "${pkg}/packages/server/package.json" | sed -e 's/^pnpm@//' -e 's/+.*$//')"; \
    [ -n "$pnpm_version" ] || { echo "cannot determine pnpm version for @penpot/mcp" >&2; exit 1; }; \
    npm install -g --no-fund --no-audit "pnpm@${pnpm_version}"; \
    chown -R runner:runner /opt/penpot-mcp; \
    chmod 0755 /opt/penpot-mcp

# Build as `runner`: the pnpm store and build outputs must stay writable by the
# same user that owns them at runtime. Switching USER is cheaper and safer than
# a setpriv/gosu privilege drop, and keeps the image free of those helpers.
USER runner
RUN set -eux; \
    pkg="${PENPOT_MCP_ROOT}"; \
    cd "$pkg"; \
    cp -n pnpm-lock.dist.yaml pnpm-lock.yaml 2>/dev/null || true; \
    printf "packages:\n  - \"packages/*\"\n" > pnpm-workspace.yaml; \
    printf "dangerouslyAllowAllBuilds=true\n" > .npmrc; \
    pnpm -r install --no-frozen-lockfile; \
    pnpm run build; \
    test -f "${PENPOT_MCP_ROOT}/packages/server/dist/index.js"; \
    test -f "${PENPOT_MCP_ROOT}/packages/plugin/dist/manifest.json"; \
    rm -rf /home/runner/.local/share/pnpm/store

# Back to root only for COPY/chmod, which are build-time operations.
USER root

# --- Entrypoint helpers ------------------------------------------------------
COPY mcp-launch.sh /usr/local/bin/penpot-mcp-launch
COPY plugin-launch.sh /usr/local/bin/penpot-plugin-launch
COPY variant-entrypoint.sh /usr/local/bin/multica-variant-entrypoint
COPY hooks/60-penpot.sh /usr/local/lib/multica/hooks/60-penpot.sh
RUN chmod 0755 \
        /usr/local/bin/penpot-mcp-launch \
        /usr/local/bin/penpot-plugin-launch \
        /usr/local/bin/multica-variant-entrypoint \
        /usr/local/lib/multica/hooks/60-penpot.sh

# --- Runtime defaults --------------------------------------------------------
ENV PENPOT_URL="https://design.penpot.app" \
    PENPOT_MCP_SERVER_HOST=127.0.0.1 \
    PENPOT_MCP_SERVER_PORT=4401 \
    PENPOT_MCP_WEBSOCKET_PORT=4402 \
    PENPOT_MCP_REMOTE_MODE=true \
    PENPOT_MCP_LOG_LEVEL=info \
    PENPOT_MCP_PLUGIN_SERVER_HOST=127.0.0.1 \
    PENPOT_MCP_PLUGIN_PORT=4400 \
    PENPOT_DISPLAY=:99 \
    PENPOT_SCREEN=1440x1024x24 \
    PENPOT_BROWSER_PROFILE=/workspaces/.penpot-browser \
    DISPLAY=:99

# MCP, plugin and Xvfb talk over loopback inside the container. No port is
# published: the runtime is an outbound worker.

USER runner
WORKDIR /home/runner

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/multica-variant-entrypoint"]
