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

if [[ ! -f "${DEPOT_TOOLS_DIR}/gclient" \
   && ! -f "${DEPOT_TOOLS_DIR}/gclient.py" \
   && ! -f "${DEPOT_TOOLS_DIR}/gclient.bat" ]]; then
  echo "depot_tools not found at ${DEPOT_TOOLS_DIR}" >&2
  echo "Set DEPOT_TOOLS_DIR or bootstrap depot_tools before running this script." >&2
  exit 2
fi

if [[ "${CEF_PLATFORM}" == "macOS" && "${CEF_ARCH}" == "x64" ]]; then
  export CEF_ENABLE_AMD64=1
fi
export GN_DEFINES
export GIT_TERMINAL_PROMPT="${GIT_TERMINAL_PROMPT:-0}"

mkdir -p "${CEF_SOURCE_DIR}"
cd "${CEF_SOURCE_DIR}"

diagnostic_pid=""
cleanup_diagnostics() {
  if [[ -n "${diagnostic_pid}" ]]; then
    kill "${diagnostic_pid}" 2>/dev/null || true
    wait "${diagnostic_pid}" 2>/dev/null || true
  fi
}
trap cleanup_diagnostics EXIT INT TERM

# automate-git.py/gclient may legitimately be silent for a long time while Git
# verifies or resolves Chromium objects. Emit runner-side diagnostics so a
# stalled checkout can be distinguished from active disk/CPU work.
(
  while sleep "${CEF_DIAGNOSTIC_INTERVAL_SECONDS:-300}"; do
    printf '[%s] CEF build heartbeat (line=%s platform=%s arch=%s)\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "${CEF_LINE}" "${CEF_PLATFORM}" "${CEF_ARCH}"
    if command -v df >/dev/null 2>&1; then df -h "${CEF_SOURCE_DIR}" || true; fi
    if command -v du >/dev/null 2>&1; then du -sh "${CEF_SOURCE_DIR}" 2>/dev/null || true; fi
    if command -v ps >/dev/null 2>&1; then
      ps -Ao pid,ppid,etime,%cpu,%mem,command 2>/dev/null \
        | grep -E '[g]client|[g]it( |$)|[p]ython.*automate-git|[n]inja|[a]utoninja' \
        | sed -n '1,80p' || true
    fi
  done
) &
diagnostic_pid=$!

curl --fail --silent --show-error --location \
  "${AUTOMATE_GIT_URL}" \
  --output automate-git.py

# CEF's automate-git.py performs an initial `gclient sync` before it applies
# --chromium-checkout. The upstream script leaves that first solution
# unpinned, so gclient follows Chromium main and can download tens of GiB
# before it ever reaches the requested historical tag. Pin the solution URL in
# the automate arguments and make that first clone shallow. This is important
# for CEF 106: its pinned depot_tools cannot parse the modern Chromium main
# DEPS schema (`dep_type: gcs`), while the CEF-compatible tag can be parsed.
# The patch is local to the downloaded, pinned automation script and does not
# modify the upstream CEF checkout or the repository's source tree.
python3 - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = "gclient sync --nohooks --with_branch_heads --jobs 16"
replacement = "gclient sync --nohooks --with_branch_heads --no-history --jobs 16"
if source.count(needle) != 1:
    raise SystemExit(
        "Unable to patch automate-git.py: expected one initial gclient sync"
    )
path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
print("Enabled shallow initial Chromium checkout (--no-history)")
PY

build_flag=--x64-build
if [[ "${CEF_ARCH}" == "arm64" ]]; then
  build_flag=--arm64-build
elif [[ "${CEF_ARCH}" != "x64" ]]; then
  echo "Unsupported CEF architecture: ${CEF_ARCH}" >&2
  exit 2
fi

# Keep this array non-empty. macOS ships Bash 3.2, where expanding an empty
# array under `set -u` fails with "unbound variable".
automate_args=(
  --download-dir="${CEF_SOURCE_DIR}"
  --depot-tools-dir="${DEPOT_TOOLS_DIR}"
  --branch="${CEF_BRANCH}"
  --checkout="${CEF_CHECKOUT}"
  --chromium-checkout="refs/tags/${CHROMIUM_CHECKOUT}"
  --chromium-url="https://chromium.googlesource.com/chromium/src.git@refs/tags/${CHROMIUM_CHECKOUT}"
  --minimal-distrib-only
  --no-debug-build
  --build-target=cefsimple
  "${build_flag}"
)
if [[ -n "${GN_ARGUMENTS}" ]]; then
  # GN_ARGUMENTS is an advanced CI escape hatch containing automate-git.py
  # arguments. Intentional shell-style splitting preserves existing usage.
  # shellcheck disable=SC2206
  extra_args=( ${GN_ARGUMENTS} )
  automate_args+=("${extra_args[@]}")
fi

# Fail before the multi-hour checkout/build if a future pinned automate script
# removes an argument that this wrapper relies on.
python3 - automate-git.py "${automate_args[@]}" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
for option in sys.argv[2:]:
    name = option.split("=", 1)[0]
    if name.startswith("--") and re.search(r"[\"']" + re.escape(name) + r"[\"']", source) is None:
        raise SystemExit(f"pinned automate-git.py does not support {name}")
PY

python3 automate-git.py "${automate_args[@]}"

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
