# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — devops
# =============================================================================
# Infrastructure toolkit: Terraform, AWS CLI v2, kubectl, Helm, Docker CLI,
# Cloudflare Wrangler, yq and uv.
#
# Credentials are passed at runtime (AWS_*, CLOUDFLARE_API_TOKEN, ...). Nothing
# is baked into the image.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TERRAFORM_VERSION
ARG KUBECTL_VERSION
ARG HELM_VERSION
ARG AWS_CLI_VERSION
ARG DOCKER_CLI_VERSION
ARG DOCKER_COMPOSE_VERSION
ARG YQ_VERSION
ARG WRANGLER_VERSION
ARG UV_VERSION
ARG TARGETARCH
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (devops)" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=devops \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    AWS_PAGER="" \
    TF_IN_AUTOMATION=1

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends unzip; \
    rm -rf /var/lib/apt/lists/*; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) march="amd64"; aws_arch="x86_64"; helm_arch="amd64"; compose_arch="x86_64"; yq_arch="amd64"; docker_arch="x86_64" ;; \
        arm64) march="arm64"; aws_arch="aarch64"; helm_arch="arm64"; compose_arch="aarch64"; yq_arch="arm64"; docker_arch="aarch64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    # --- Terraform --- \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${march}.zip" -o /tmp/terraform.zip; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" -o /tmp/terraform.sha256; \
    expected="$(awk -v f="terraform_${TERRAFORM_VERSION}_linux_${march}.zip" '$2 == f { print $1 }' /tmp/terraform.sha256)"; \
    echo "${expected}  /tmp/terraform.zip" | sha256sum -c -; \
    unzip -q /tmp/terraform.zip -d /usr/local/bin; \
    rm -f /tmp/terraform.zip /tmp/terraform.sha256; \
    # --- AWS CLI v2 --- \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}-${AWS_CLI_VERSION}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update; \
    rm -rf /tmp/aws /tmp/awscliv2.zip; \
    # --- kubectl --- \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${march}/kubectl" -o /usr/local/bin/kubectl; \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${march}/kubectl.sha256" -o /tmp/kubectl.sha256; \
    echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/kubectl; \
    rm -f /tmp/kubectl.sha256; \
    # --- Helm --- \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${helm_arch}.tar.gz" -o /tmp/helm.tar.gz; \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${helm_arch}.tar.gz.sha256sum" -o /tmp/helm.sha256; \
    ( cd /tmp && echo "$(awk '{print $1}' /tmp/helm.sha256)  helm.tar.gz" | sha256sum -c - ); \
    tar -xzf /tmp/helm.tar.gz -C /tmp; \
    install -m 0755 "/tmp/linux-${helm_arch}/helm" /usr/local/bin/helm; \
    rm -rf /tmp/helm.tar.gz /tmp/helm.sha256 "/tmp/linux-${helm_arch}"; \
    # --- Docker CLI + compose plugin --- \
    curl -fsSL "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${DOCKER_CLI_VERSION}.tgz" -o /tmp/docker.tgz; \
    tar -xzf /tmp/docker.tgz -C /tmp; \
    install -m 0755 /tmp/docker/docker /usr/local/bin/docker; \
    rm -rf /tmp/docker /tmp/docker.tgz; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${compose_arch}" -o /usr/local/lib/docker/cli-plugins/docker-compose; \
    curl -fsSL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${compose_arch}.sha256" -o /tmp/compose.sha256; \
    echo "$(awk '{print $1}' /tmp/compose.sha256)  /usr/local/lib/docker/cli-plugins/docker-compose" | sha256sum -c -; \
    chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose; \
    rm -f /tmp/compose.sha256; \
    # --- yq --- \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yq_arch}" -o /usr/local/bin/yq; \
    chmod 0755 /usr/local/bin/yq; \
    # --- uv (for MCP servers) --- \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) uv_arch="x86_64" ;; \
        arm64) uv_arch="aarch64" ;; \
    esac; \
    uv_asset="uv-${uv_arch}-unknown-linux-gnu.tar.gz"; \
    uv_url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${uv_asset}"; \
    curl -fsSL "$uv_url" -o /tmp/uv.tar.gz; \
    curl -fsSL "${uv_url}.sha256" -o /tmp/uv.sha256; \
    echo "$(awk '{print $1}' /tmp/uv.sha256)  /tmp/uv.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/uv; \
    tar -xzf /tmp/uv.tar.gz -C /opt/uv --strip-components=1; \
    ln -sf /opt/uv/uv /usr/local/bin/uv; \
    ln -sf /opt/uv/uvx /usr/local/bin/uvx; \
    rm -f /tmp/uv.tar.gz /tmp/uv.sha256; \
    # --- Versions --- \
    terraform version; \
    aws --version; \
    kubectl version --client 2>/dev/null | head -n1; \
    helm version --short; \
    docker --version; \
    docker compose version; \
    yq --version; \
    uv --version

# --- Cloudflare Wrangler -----------------------------------------------------
RUN set -eux; \
    npm install -g --no-fund --no-audit "wrangler@${WRANGLER_VERSION}"; \
    npm cache clean --force; \
    wrangler --version

USER runner
WORKDIR /home/runner

# Base ENTRYPOINT (tini → multica-entrypoint) is inherited.
