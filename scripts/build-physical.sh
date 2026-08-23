#!/usr/bin/env bash
set -euo pipefail

# Git for Windows can inherit a malformed Windows PATH when launched from
# PowerShell. Keep Git Bash's POSIX tools available before resolving paths.
export PATH="/usr/bin:/mingw64/bin:${PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
resolve_python
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: build-physical.sh [options]

Builds one or both pinned CEF lines on the current physical machine. The
native RID defaults to the host OS and x64 architecture.

Options:
  --line 106|134|both       Build one line or both (default: both).
  --rid RID|auto            Native RID; auto is recommended.
  --cache DIR               Persistent CEF checkout/build cache.
  --output DIR              Artifact directory (default: artifacts/physical).
  --skip-native             Repackage an existing binary_distrib only.
  --no-demo                 Skip publishing the html5test demo.
  --allow-low-disk          Override the 120 GiB fresh-build preflight.
  --preflight-only          Validate the host and stop before checkout.
  -h, --help                Show this help.

Windows builds run through Git Bash's bash.exe, but use the native Windows
compiler/toolchain. Linux builds are native Linux builds; this script does not
pretend that Linux Docker can produce a Windows CEF runtime.
USAGE
}

line_selection="both"
rid="auto"
cache_root=""
output_root=""
extra_args=()
while (($#)); do
  case "$1" in
    --line) line_selection="${2:?missing value for --line}"; shift 2 ;;
    --rid) rid="${2:?missing value for --rid}"; shift 2 ;;
    --cache) cache_root="${2:?missing value for --cache}"; shift 2 ;;
    --output) output_root="${2:?missing value for --output}"; shift 2 ;;
    --skip-native|--no-demo|--allow-low-disk|--preflight-only) extra_args+=("$1"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$line_selection" in 106) lines=(106) ;; 134) lines=(134) ;; both) lines=(106 134) ;; *) echo '--line must be 106, 134, or both' >&2; exit 2 ;; esac

host_name="${RUNNER_OS:-$(uname -s)}"
case "$host_name" in
  Windows*|MINGW*|MSYS*|CYGWIN*) host_prefix=win ;;
  Linux) host_prefix=linux ;;
  Darwin|macOS) host_prefix=osx ;;
  *) echo "Unsupported host operating system: $host_name" >&2; exit 2 ;;
esac

if [[ "$rid" == auto ]]; then
  machine="$(uname -m)"
  case "$machine" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) echo "Unsupported host architecture: $machine" >&2; exit 2 ;;
  esac
  rid="${host_prefix}-${arch}"
fi
case "$rid" in
  win-x64|win-arm64|linux-x64|linux-arm64|osx-x64|osx-arm64) ;;
  *) echo "Unsupported --rid: $rid" >&2; exit 2 ;;
esac
if [[ "$rid" != "$host_prefix-"* ]]; then
  echo "RID $rid does not match host $host_name. Use a native host for the requested platform." >&2
  exit 2
fi

cache_root="${cache_root:-$REPO_ROOT/.cef-cache/physical}"
output_root="${output_root:-$REPO_ROOT/artifacts/physical}"
if [[ "$host_prefix" == win ]] && command -v cygpath >/dev/null 2>&1; then
  cache_root="$(cygpath -u "$cache_root")"
  output_root="$(cygpath -u "$output_root")"
fi
mkdir -p "$cache_root" "$output_root/logs"
if [[ "$host_prefix" != win || "$cache_root" != /[a-zA-Z]/* ]]; then
  cache_root="$(cd "$cache_root" && pwd)"
fi
output_root="$(cd "$output_root" && pwd)"

for line in "${lines[@]}"; do
  args=(--line "$line" --rid "$rid" --cache "$cache_root/$line/$rid" --output "$output_root")
  if ((${#extra_args[@]})); then args+=("${extra_args[@]}"); fi
  log="$output_root/logs/cef-$line-$rid-$(date '+%Y%m%d-%H%M%S').log"
  echo "=== Physical build: CEF $line / $rid ==="
  echo "Log: $log"
  "$SCRIPT_DIR/build-portable-codec-bundle.sh" "${args[@]}" 2>&1 | tee "$log"
done
