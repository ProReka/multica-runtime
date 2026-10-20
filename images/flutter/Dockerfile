# syntax=docker/dockerfile:1.7
# =============================================================================
# Multica Runtime — flutter
# =============================================================================
# Flutter stable + Dart, with the Android build toolchain (JDK 21 + Android SDK)
# so `flutter test`, `flutter build web` and `flutter build apk` work end to end.
#
# ARCH NOTE: Android build-tools are x86_64 binaries. An arm64 build still gives
# a working web/Linux Flutter image, but not `flutter build apk`. CI builds this
# variant for linux/amd64 only.
# =============================================================================

ARG BASE_IMAGE=multica-runtime:base
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG FLUTTER_VERSION
ARG ANDROID_CMDLINE_TOOLS_VERSION
ARG ANDROID_PLATFORMS
ARG ANDROID_BUILD_TOOLS
ARG ANDROID_NDK_VERSION
ARG TARGETARCH
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="Multica Runtime (flutter)" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV MULTICA_IMAGE_VARIANT=flutter \
    MULTICA_IMAGE_VERSION="${IMAGE_VERSION}" \
    FLUTTER_ROOT=/opt/flutter \
    JAVA_HOME=/opt/java \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_USER_HOME=/home/runner/.android \
    GRADLE_USER_HOME=/home/runner/.gradle \
    PATH="/opt/flutter/bin:/opt/java/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:${PATH}"

USER root

# --- System dependencies + JDK ----------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        clang \
        cmake \
        ninja-build \
        pkg-config \
        libgtk-3-dev \
        libunwind-dev \
        fonts-noto-color-emoji \
        openjdk-21-jdk-headless; \
    rm -rf /var/lib/apt/lists/*; \
    ln -s "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" /opt/java; \
    java -version

# --- Android SDK (amd64 only) ------------------------------------------------
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) android_arch="amd64" ;; \
        arm64) android_arch="arm64" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    if [ "$android_arch" != "amd64" ]; then \
        echo "WARN: arch=${android_arch} — skipping Android SDK (build-tools are x86_64-only)."; \
        echo "      Flutter web/Linux work; 'flutter build apk' does not."; \
        exit 0; \
    fi; \
    url="https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip"; \
    echo "Downloading ${url}"; \
    mkdir -p "${ANDROID_HOME}/cmdline-tools"; \
    curl -fsSL "$url" -o /tmp/cmdline-tools.zip; \
    unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools; \
    mv /tmp/cmdline-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest"; \
    rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools; \
    yes | sdkmanager --licenses >/dev/null || true; \
    sdkmanager --install "platform-tools" ${ANDROID_PLATFORMS} ${ANDROID_BUILD_TOOLS} >/dev/null; \
    if [ -n "${ANDROID_NDK_VERSION}" ]; then \
        sdkmanager --install "ndk;${ANDROID_NDK_VERSION}" >/dev/null; \
    fi; \
    rm -rf /root/.android; \
    chown -R runner:runner "${ANDROID_HOME}"; \
    sdkmanager --list_installed

# --- Flutter SDK -------------------------------------------------------------
RUN set -eux; \
    url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"; \
    echo "Downloading ${url}"; \
    curl -fsSL "$url" -o /tmp/flutter.tar.xz; \
    tar -xJf /tmp/flutter.tar.xz -C /opt; \
    rm -f /tmp/flutter.tar.xz; \
    git config --system --add safe.directory /opt/flutter; \
    flutter config --no-analytics >/dev/null; \
    flutter config --enable-web >/dev/null; \
    flutter config --enable-linux-desktop >/dev/null; \
    if [ -d "${ANDROID_HOME}/platform-tools" ]; then \
        flutter config --enable-android >/dev/null 2>&1 || true; \
        flutter config --android-sdk "${ANDROID_HOME}" >/dev/null 2>&1 || true; \
        flutter precache --web --linux --android >/dev/null 2>&1 || true; \
    else \
        flutter precache --web --linux >/dev/null 2>&1 || true; \
    fi; \
    flutter --version | head -n2; \
    chown -R runner:runner /opt/flutter

# --- Gradle defaults ---------------------------------------------------------
RUN set -eux; \
    mkdir -p "${GRADLE_USER_HOME}" "${ANDROID_USER_HOME}"; \
    printf '%s\n' \
        'org.gradle.jvmargs=-XX:MaxRAMPercentage=60 -XX:+UseContainerSupport' \
        'org.gradle.parallel=true' \
        'org.gradle.caching=true' \
        > "${GRADLE_USER_HOME}/gradle.properties"; \
    chown -R runner:runner "${GRADLE_USER_HOME}" "${ANDROID_USER_HOME}"

USER runner
WORKDIR /home/runner

# Base ENTRYPOINT (tini → multica-entrypoint) is inherited.
