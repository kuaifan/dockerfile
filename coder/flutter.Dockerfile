ARG BASE_IMAGE=kuaifan/coder:latest
FROM ${BASE_IMAGE}

ARG FLUTTER_VERSION=3.35.6

ARG ANDROID_SDK_VERSION=13114758
ARG ANDROID_BUILD_TOOLS_VERSION=35.0.0
ARG ANDROID_PLATFORM=android-35

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends --no-install-suggests \
        libgl1 \
        libglu1-mesa \
        openjdk-17-jdk \
        xz-utils \
        zip; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    rm -rf /opt/flutter; \
    git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter; \
    chown -R coder:coder /opt/flutter

RUN set -eux; \
    sdk_root=/opt/android-sdk; \
    mkdir -p "${sdk_root}/cmdline-tools"; \
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip" -o /tmp/android_cmdline_tools.zip; \
    unzip -q /tmp/android_cmdline_tools.zip -d "${sdk_root}/cmdline-tools"; \
    mv "${sdk_root}/cmdline-tools/cmdline-tools" "${sdk_root}/cmdline-tools/latest"; \
    rm /tmp/android_cmdline_tools.zip; \
    export ANDROID_SDK_ROOT="${sdk_root}"; \
    yes | "${sdk_root}/cmdline-tools/latest/bin/sdkmanager" --sdk_root="${sdk_root}" --licenses; \
    "${sdk_root}/cmdline-tools/latest/bin/sdkmanager" --sdk_root="${sdk_root}" \
        "platform-tools" \
        "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
        "platforms;${ANDROID_PLATFORM}"; \
    chown -R coder:coder "${sdk_root}"

ENV FLUTTER_HOME=/opt/flutter \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:${PATH}

USER coder

RUN set -eux; \
    flutter --version
