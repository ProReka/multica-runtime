# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica autoscaler
# =============================================================================
# Reads each runtime-role's pending task count and scales the matching service
# between 0 and 1 replica. Small, stateless, and safe to run as a single task.
#
# Built FROM the base image so the `multica` CLI and Python are already present.
# Adds the AWS CLI (Debian package — only ECS calls are used) and the Docker CLI
# (Swarm adapter). The AWS CLI v2 bundle is ~1.2 GB and would dwarf this image;
# the distro package is the right size for six API calls.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DOCKER_CLI_VERSION
ARG TARGETARCH
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Autoscaler" \
      org.opencontainers.image.description="Task-driven autoscaler for Multica runtime services." \
      org.opencontainers.image.source="https://github.com/ProReka/multica-runtime" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=autoscaler \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    AWS_PAGER="" \
    PYTHONUNBUFFERED=1

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends awscli; \
    rm -rf /var/lib/apt/lists/*; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) docker_arch="x86_64" ;; \
        arm64) docker_arch="aarch64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_CLI_VERSION}.tgz" -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /tmp; \
    install -m 0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker /tmp/docker.tgz; \
    aws --version; \
    docker --version

COPY autoscaler.py /usr/local/bin/multica-autoscaler
RUN chmod 0755 /usr/local/bin/multica-autoscaler

# The autoscaler is a loop, not a Multica daemon: override the base entrypoint.
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD ["python3", "/usr/local/bin/multica-autoscaler", "--health"]

# The base image ends as `runner`; this Dockerfile switched to root only to
# install packages. Switch back: the autoscaler is a network client, not a
# system service.
USER runner

ENTRYPOINT ["/usr/bin/tini", "--", "python3", "/usr/local/bin/multica-autoscaler"]
