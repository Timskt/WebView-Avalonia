#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
  echo "This dependency installer only supports Linux." >&2
  exit 2
fi
if ! command -v apt-get >/dev/null 2>&1; then
  echo "Automatic dependency installation currently supports Debian/Ubuntu (apt-get) only." >&2
  echo "Install equivalent Chromium/CEF build dependencies manually, then omit --install-deps." >&2
  exit 2
fi

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  sudo_cmd=(env)
elif command -v sudo >/dev/null 2>&1; then
  sudo_cmd=(sudo)
else
  echo "sudo is required to install Linux build dependencies." >&2
  exit 2
fi

"${sudo_cmd[@]}" apt-get update
"${sudo_cmd[@]}" apt-get install -y --no-install-recommends \
  bash bzip2 ca-certificates clang curl file git git-lfs jq lld locales \
  make ninja-build openssh-client patch pkg-config python3 python3-pip \
  python3-setuptools rsync tar unzip xz-utils zip build-essential libc6-dev \
  libcups2-dev libasound2-dev libatk1.0-dev libatk-bridge2.0-dev \
  libcairo2-dev libdbus-1-dev libdrm-dev libexpat1-dev libfontconfig1-dev \
  libgbm-dev libglib2.0-dev libgtk-3-dev libnspr4-dev libnss3-dev \
  libpango1.0-dev libpci-dev libpulse-dev libssl-dev libx11-dev \
  libx11-xcb-dev libxcb1-dev libxcomposite-dev libxcursor-dev libxdamage-dev \
  libxext-dev libxfixes-dev libxi-dev libxkbcommon-dev libxrandr-dev \
  libxrender-dev libxshmfence-dev libxss-dev libxtst-dev xvfb zlib1g-dev

echo "Linux bootstrap dependencies installed. Chromium may check additional pinned dependencies during checkout."
