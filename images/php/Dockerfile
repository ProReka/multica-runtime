# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — php
# =============================================================================
# PHP 8.4 + Composer + Laravel installer, with MariaDB, PostgreSQL and Redis
# running *inside the container* (ephemeral, one set per runtime).
#
# Everything runs as the non-root `runner` user. The database data directories
# live under /tmp, so they are recreated on every container start and never
# leak state between tasks.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG PHP_VERSION
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (php)" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=php \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    COMPOSER_HOME=/home/runner/.config/composer \
    PATH="/home/runner/.config/composer/vendor/bin:${PATH}"

USER root

# --- PHP + extensions --------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        php8.4-cli \
        php8.4-common \
        php8.4-curl \
        php8.4-mbstring \
        php8.4-xml \
        php8.4-zip \
        php8.4-bcmath \
        php8.4-gd \
        php8.4-intl \
        php8.4-mysql \
        php8.4-pgsql \
        php8.4-redis \
        php8.4-sqlite3 \
        php8.4-opcache \
        unzip; \
    rm -rf /var/lib/apt/lists/*; \
    php --version | head -n1

# --- Composer (installer signature verified) --------------------------------
RUN set -eux; \
    expected="$(curl -fsSL https://composer.github.io/installer.sig)"; \
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php; \
    actual="$(php -r 'echo hash_file("sha384", "/tmp/composer-setup.php");')"; \
    [ "$expected" = "$actual" ] || { echo "composer installer signature mismatch" >&2; exit 1; }; \
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer; \
    rm -f /tmp/composer-setup.php; \
    composer --version

# --- Embedded database servers ----------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        mariadb-server \
        postgresql \
        redis-server; \
    rm -rf /var/lib/apt/lists/*

# --- Laravel installer (as runner, in the runner's composer home) -----------
# The base image may leave ~/.config root-owned; create the composer home as
# root and hand it over before dropping privileges for the install.
USER root
RUN set -eux; \
    mkdir -p "$COMPOSER_HOME"; \
    chown -R runner:runner /home/runner/.config

USER runner
RUN set -eux; \
    composer global require laravel/installer --no-interaction --no-progress; \
    laravel --version 2>/dev/null | head -n1 || true

USER root

COPY start-databases.sh /usr/local/bin/multica-start-databases
COPY variant-entrypoint.sh /usr/local/bin/multica-variant-entrypoint
RUN chmod 0755 /usr/local/bin/multica-start-databases /usr/local/bin/multica-variant-entrypoint

# Databases bind 127.0.0.1; no port is published. EXPOSE is intentionally absent:
# the runtime has no inbound surface.

USER runner
WORKDIR /home/runner

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/multica-variant-entrypoint"]
