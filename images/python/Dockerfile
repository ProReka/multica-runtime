# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — python
# =============================================================================
# Python 3.13 (Debian trixie) with uv, Poetry, pip, ruff, mypy and pytest.
# System build headers are present so wheels that need to compile work without
# an extra apt-get at task time.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG UV_VERSION
ARG POETRY_VERSION
ARG RUFF_VERSION
ARG MYPY_VERSION
ARG PYTEST_VERSION
ARG TARGETARCH
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (python)" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=python \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON=/usr/bin/python3 \
    UV_LINK_MODE=copy

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3-pip \
        python3-dev \
        libpq-dev \
        libffi-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        libjpeg-dev \
        zlib1g-dev \
        libsqlite3-dev \
        libreadline-dev \
        libbz2-dev \
        liblzma-dev \
        libncurses-dev \
        libgdbm-dev \
        uuid-dev \
        libyaml-dev; \
    rm -rf /var/lib/apt/lists/*

# --- uv (pinned, checksum-verified) -----------------------------------------
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) uv_arch="x86_64" ;; \
        arm64) uv_arch="aarch64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    asset="uv-${uv_arch}-unknown-linux-gnu.tar.gz"; \
    url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${asset}"; \
    curl -fsSL "$url" -o /tmp/uv.tar.gz; \
    curl -fsSL "${url}.sha256" -o /tmp/uv.sha256; \
    echo "$(awk '{print $1}' /tmp/uv.sha256)  /tmp/uv.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/uv; \
    tar -xzf /tmp/uv.tar.gz -C /opt/uv --strip-components=1; \
    ln -sf /opt/uv/uv /usr/local/bin/uv; \
    ln -sf /opt/uv/uvx /usr/local/bin/uvx; \
    rm -f /tmp/uv.tar.gz /tmp/uv.sha256; \
    uv --version; \
    uvx --version

# --- Python tooling ----------------------------------------------------------
RUN set -eux; \
    uv tool install --python /usr/bin/python3 "poetry==${POETRY_VERSION}"; \
    uv tool install --python /usr/bin/python3 "ruff==${RUFF_VERSION}"; \
    uv tool install --python /usr/bin/python3 "mypy==${MYPY_VERSION}"; \
    uv tool install --python /usr/bin/python3 "pytest==${PYTEST_VERSION}"; \
    rm -rf /root/.cache/uv; \
    poetry --version; \
    ruff --version; \
    mypy --version; \
    pytest --version; \
    pip3 --version

USER runner
WORKDIR /home/runner

# Base ENTRYPOINT (tini → multica-entrypoint) is inherited.
