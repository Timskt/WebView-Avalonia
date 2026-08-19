#!/usr/bin/env bash
set -euo pipefail

# Build a pinned CEF line with Chromium proprietary H.264 and platform HEVC
# paths enabled. Exact pins and package versions live in config/cef-lines.json.
CEF_LINE="${CEF_LINE:-${1:-134}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

eval "$(python3 - "${REPO_ROOT}" "${CEF_LINE}" <<'PY'
import json, shlex, sys
from pathlib import Path
root = Path(sys.argv[1])
line = sys.argv[2]
config = json.loads((root / 'config/cef-lines.json').read_text(encoding='utf-8'))[line]
values = {
    'CEF_BRANCH': config['cef_branch'],
    'CEF_CHECKOUT': config['cef_checkout'],
    'CHROMIUM_CHECKOUT': config['chromium_checkout'],
    'EXPECTED_GN_DEFINES': ' '.join(config['gn_defines']),
}
for key, value in values.items():
    print(f'{key}={shlex.quote(value)}')
PY
)"

: "${CEF_SOURCE_DIR:=${PWD}/.cef-cache/cef-${CEF_LINE}}"
: "${DEPOT_TOOLS_DIR:=${CEF_SOURCE_DIR}/depot_tools}"
: "${CEF_BINARY_DISTRIB_DIR:=${CEF_SOURCE_DIR}/chromium/src/cef/binary_distrib}"
: "${CEF_ARCH:=x64}"
: "${GN_DEFINES:=${EXPECTED_GN_DEFINES}}"
: "${GN_ARGUMENTS:=}"
: "${AUTOMATE_GIT_URL:=https://bitbucket.org/chromiumembedded/cef/raw/${CEF_CHECKOUT}/tools/automate/automate-git.py}"

case "${CEF_PLATFORM:-${RUNNER_OS:-$(uname -s)}}" in
  Windows*|MINGW*|MSYS*|CYGWIN*) CEF_PLATFORM=Windows ;;
  macOS|Darwin) CEF_PLATFORM=macOS ;;
  Linux) CEF_PLATFORM=Linux ;;
  *) echo "Unsupported CEF platform: ${CEF_PLATFORM:-unknown}" >&2; exit 2 ;;
esac

for required in ${EXPECTED_GN_DEFINES}; do
  if [[ " ${GN_DEFINES} " != *" ${required} "* ]]; then
    echo "GN_DEFINES is missing required codec flag: ${required}" >&2
    exit 2
  fi
done

if [[ ! -x "${DEPOT_TOOLS_DIR}/gclient" ]]; then
  echo "depot_tools not found at ${DEPOT_TOOLS_DIR}" >&2
  echo "Set DEPOT_TOOLS_DIR or bootstrap depot_tools before running this script." >&2
  exit 2
fi

if [[ "${CEF_PLATFORM}" == "macOS" && "${CEF_ARCH}" == "x64" ]]; then
  export CEF_ENABLE_AMD64=1
fi
export GN_DEFINES

mkdir -p "${CEF_SOURCE_DIR}"
cd "${CEF_SOURCE_DIR}"

curl --fail --silent --show-error --location \
  "${AUTOMATE_GIT_URL}" \
  --output automate-git.py

build_flag=--x64-build
if [[ "${CEF_ARCH}" == "arm64" ]]; then
  build_flag=--arm64-build
elif [[ "${CEF_ARCH}" != "x64" ]]; then
  echo "Unsupported CEF architecture: ${CEF_ARCH}" >&2
  exit 2
fi

extra_args=()
if [[ -n "${GN_ARGUMENTS}" ]]; then
  # shellcheck disable=SC2206
  extra_args=( ${GN_ARGUMENTS} )
fi

python3 automate-git.py \
  --download-dir="${CEF_SOURCE_DIR}" \
  --depot-tools-dir="${DEPOT_TOOLS_DIR}" \
  --branch="${CEF_BRANCH}" \
  --checkout="${CEF_CHECKOUT}" \
  --chromium-checkout="refs/tags/${CHROMIUM_CHECKOUT}" \
  --minimal-distrib-only \
  --no-chromium-history \
  --no-debug-build \
  --build-target=cefsimple \
  "${build_flag}" \
  "${extra_args[@]}"

args_gn="$(find "${CEF_SOURCE_DIR}/chromium/src/out" -mindepth 2 -maxdepth 2 \
  -type f -name args.gn -path '*Release*' -print -quit)"
if [[ -z "${args_gn}" ]]; then
  echo "Unable to find the generated Release args.gn" >&2
  exit 2
fi
normalized_args="$(sed -e 's/[[:space:]"]//g' "${args_gn}")"
for required in ${EXPECTED_GN_DEFINES}; do
  if ! grep -Fxq "${required}" <<<"${normalized_args}"; then
    echo "Generated args.gn is missing required codec flag: ${required}" >&2
    echo "args.gn: ${args_gn}" >&2
    exit 2
  fi
done
args_gn_sha256="$(python3 - "${args_gn}" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], 'rb').read()).hexdigest())
PY
)"

mkdir -p "${CEF_BINARY_DISTRIB_DIR}"
cat > "${CEF_BINARY_DISTRIB_DIR}/CEF_CODEC_BUILD_INFO.txt" <<MARKER
CEF_LINE=${CEF_LINE}
CEF_BRANCH=${CEF_BRANCH}
CEF_CHECKOUT=${CEF_CHECKOUT}
CHROMIUM_CHECKOUT=${CHROMIUM_CHECKOUT}
CEF_ARCH=${CEF_ARCH}
CEF_PLATFORM=${CEF_PLATFORM}
GN_DEFINES=${GN_DEFINES}
ARGS_GN=${args_gn}
ARGS_GN_SHA256=${args_gn_sha256}
AUTOMATE_GIT_URL=${AUTOMATE_GIT_URL}
MARKER

echo "CEF ${CEF_LINE} codec-enabled distribution: ${CEF_BINARY_DISTRIB_DIR}"
find "${CEF_BINARY_DISTRIB_DIR}" -maxdepth 2 -type f -print | sort | sed -n '1,80p'
