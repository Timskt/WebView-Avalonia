# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000

ENV DOTNET_ROOT=/opt/dotnet \
    PATH=/opt/dotnet:/opt/dotnet/tools:${PATH} \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    NUGET_XMLDOC_MODE=skip \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash bzip2 ca-certificates clang curl file git git-lfs jq lld locales \
      make ninja-build openssh-client patch pkg-config python3 python3-pip \
      python3-setuptools python-is-python3 rsync sudo tar unzip xz-utils zip \
      build-essential libc6-dev libcups2-dev libasound2-dev libatk1.0-dev \
      libatk-bridge2.0-dev libcairo2-dev libdbus-1-dev libdrm-dev libexpat1-dev \
      libfontconfig1-dev libgbm-dev libglib2.0-dev libgtk-3-dev libnspr4-dev \
      libnss3-dev libpango1.0-dev libpci-dev libpulse-dev libssl-dev \
      libx11-dev libx11-xcb-dev libxcb1-dev libxcomposite-dev libxcursor-dev \
      libxdamage-dev libxext-dev libxfixes-dev libxi-dev libxkbcommon-dev \
      libxrandr-dev libxrender-dev libxshmfence-dev libxss-dev libxtst-dev \
      xvfb zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /opt/dotnet --no-path \
    && bash /tmp/dotnet-install.sh --channel 6.0 --install-dir /opt/dotnet --no-path \
    && rm /tmp/dotnet-install.sh \
    && if ! getent group "${BUILDER_GID}" >/dev/null; then groupadd --gid "${BUILDER_GID}" builder; fi \
    && if ! getent passwd "${BUILDER_UID}" >/dev/null; then useradd --uid "${BUILDER_UID}" --gid "${BUILDER_GID}" --home-dir /home/builder --shell /bin/bash builder; fi \
    && mkdir -p /home/builder \
    && chown "${BUILDER_UID}:${BUILDER_GID}" /home/builder \
    && git config --system core.autocrlf false \
    && git config --system core.filemode false \
    && git config --system core.longpaths true \
    && git config --system core.deltaBaseCacheLimit 2g \
    && git config --system fetch.parallel 1 \
    && git config --system http.version HTTP/1.1

ENV HOME=/home/builder
USER ${BUILDER_UID}:${BUILDER_GID}
WORKDIR /workspace
ENTRYPOINT ["/workspace/scripts/build-portable-codec-bundle.sh"]
