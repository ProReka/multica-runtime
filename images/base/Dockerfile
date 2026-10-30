# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — base image
# =============================================================================
# Everything an agent needs to pick up a task and work:
#   Debian 13 + Node.js LTS + git/gh + Chromium + Python + build tools
#   Claude Code + OpenCode + Multica CLI
#
# The Multica daemon auto-detects both agent CLIs on PATH and registers one
# runtime per CLI. Sessions are parked on /workspaces so they survive restarts.
#
# Tool versions come from versions.env at the repo root. Every ARG below has NO
# default on purpose: a bare `docker build` fails fast instead of silently
# producing an unpinned image. Use scripts/build.sh or `make build`.
# =============================================================================

# --- Node.js stage -----------------------------------------------------------
# Downloaded once from the official tarball and copied into the final image.
# Checksum verification is mandatory: a corrupted download must fail the build,
# not produce a broken runtime.
FROM debian:trixie-slim AS node

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NODE_VERSION
ARG TARGETARCH

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl xz-utils libatomic1; \
    rm -rf /var/lib/apt/lists/*; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) node_arch="x64" ;; \
        arm64) node_arch="arm64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    base="node-v${NODE_VERSION}-linux-${node_arch}"; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" -o /tmp/SHASUMS256.txt; \
    expected="$(awk -v f="${base}.tar.xz" '$2 == f { print $1 }' /tmp/SHASUMS256.txt)"; \
    [ -n "${expected}" ] || { echo "no checksum for ${base}.tar.xz" >&2; exit 1; }; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/${base}.tar.xz" -o /tmp/node.tar.xz; \
    echo "${expected}  /tmp/node.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1; \
    rm -f /tmp/node.tar.xz /tmp/SHASUMS256.txt; \
    node --version; \
    npm --version

# --- Runtime image -----------------------------------------------------------
FROM debian:trixie-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NODE_VERSION
ARG GH_CLI_VERSION
ARG MULTICA_CLI_VERSION
ARG CLAUDE_CODE_VERSION
ARG OPENCODE_VERSION
ARG TARGETARCH
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (base)" \
      org.opencontainers.image.description="Run Multica agents in Docker: Claude Code + OpenCode, batteries included." \
      org.opencontainers.image.source="https://github.com/ProReka/multica-runtime" \
      org.opencontainers.image.url="https://github.com/ProReka/multica-runtime" \
      org.opencontainers.image.documentation="https://github.com/ProReka/multica-runtime/tree/main/docs" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

# Puppeteer/Playwright helpers point at the system Chromium; agent tasks should
# not download a second browser.
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/home/runner \
    NODE_VERSION="${NODE_VERSION}" \
    MULTICA_IMAGE_VARIANT=base \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    MULTICA_WORKSPACES_ROOT=/workspaces \
    PUPPETEER_SKIP_DOWNLOAD=1 \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    CHROME_BIN=/usr/bin/chromium \
    PATH="/home/runner/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

# --- System packages ---------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libatomic1 \
        curl \
        wget \
        gnupg \
        git \
        git-lfs \
        openssh-client \
        jq \
        less \
        procps \
        psmisc \
        tini \
        util-linux \
        file \
        unzip \
        zip \
        xz-utils \
        tar \
        build-essential \
        pkg-config \
        python3 \
        python3-venv \
        sqlite3 \
        ripgrep \
        fd-find \
        bat \
        tree \
        vim-tiny \
        nano \
        htop \
        chromium \
        fonts-liberation \
        fonts-noto-color-emoji; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    ln -sf /usr/bin/batcat /usr/local/bin/bat; \
    rm -rf /var/lib/apt/lists/*

# --- Node.js -----------------------------------------------------------------
COPY --from=node /usr/local /usr/local

# --- Agent CLIs --------------------------------------------------------------
# Pinned npm installs. Node lives in its own layer above, so bumping an agent
# version only re-runs the npm layer, not the apt setup.
RUN set -eux; \
    npm install -g --no-fund --no-audit \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "opencode-ai@${OPENCODE_VERSION}"; \
    npm cache clean --force; \
    claude --version; \
    opencode --version

# --- GitHub CLI --------------------------------------------------------------
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) march="amd64" ;; \
        arm64) march="arm64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    base="gh_${GH_CLI_VERSION}_linux_${march}"; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_checksums.txt" -o /tmp/gh.sha256; \
    expected="$(awk -v f="${base}.tar.gz" '$2 == f { print $1 }' /tmp/gh.sha256)"; \
    [ -n "${expected}" ] || { echo "no checksum for ${base}.tar.gz" >&2; exit 1; }; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/${base}.tar.gz" -o /tmp/gh.tar.gz; \
    echo "${expected}  /tmp/gh.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gh.tar.gz -C /tmp; \
    install -m 0755 "/tmp/${base}/bin/gh" /usr/local/bin/gh; \
    rm -rf /tmp/gh.tar.gz /tmp/gh.sha256 "/tmp/${base}"; \
    gh --version | head -n1

# --- Multica CLI -------------------------------------------------------------
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) march="amd64" ;; \
        arm64) march="arm64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    asset="multica-cli-${MULTICA_CLI_VERSION}-linux-${march}.tar.gz"; \
    curl -fsSL "https://github.com/multica-ai/multica/releases/download/v${MULTICA_CLI_VERSION}/checksums.txt" -o /tmp/multica.sha256; \
    expected="$(awk -v f="${asset}" '$2 == f { print $1 }' /tmp/multica.sha256)"; \
    [ -n "${expected}" ] || { echo "no checksum for ${asset}" >&2; exit 1; }; \
    curl -fsSL "https://github.com/multica-ai/multica/releases/download/v${MULTICA_CLI_VERSION}/${asset}" -o /tmp/multica.tar.gz; \
    echo "${expected}  /tmp/multica.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/multica.tar.gz -C /tmp multica; \
    install -m 0755 /tmp/multica /usr/local/bin/multica; \
    rm -f /tmp/multica.tar.gz /tmp/multica.sha256 /tmp/multica; \
    multica --version

# --- Non-root runtime user ---------------------------------------------------
# npm may have created $HOME while installing as root; recreate it so the
# account owns it and useradd does not warn about an existing directory.
RUN set -eux; \
    rm -rf /home/runner; \
    useradd --create-home --uid 1000 --user-group --shell /bin/bash runner; \
    mkdir -p /workspaces /home/runner/.config /home/runner/.local/share; \
    chown -R runner:runner /workspaces /home/runner

# --- Entrypoint --------------------------------------------------------------
COPY entrypoint.sh /usr/local/bin/multica-entrypoint
COPY multica-wrapper.py /usr/local/bin/multica-wrapper
RUN mv /usr/local/bin/multica /usr/local/lib/multica-cli; \
    mv /usr/local/bin/multica-wrapper /usr/local/bin/multica; \
    chmod 0755 /usr/local/bin/multica
COPY lib/ /usr/local/lib/multica/
RUN chmod 0755 /usr/local/bin/multica-entrypoint /usr/local/lib/multica/*.sh

USER runner
WORKDIR /home/runner

# The daemon runs in the foreground; pgrep is a cheap liveness check.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["pgrep", "-f", "multica daemon"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/multica-entrypoint"]
