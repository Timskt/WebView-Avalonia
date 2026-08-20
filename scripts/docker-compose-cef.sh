#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
selection="${1:-both}"
case "$selection" in 106|134|both) ;; *) echo "Usage: $0 [106|134|both]" >&2; exit 2 ;; esac

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 2; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is required" >&2; exit 2; }

machine="$(uname -m)"
if [[ "$machine" != x86_64 && "$machine" != amd64 && "${ALLOW_EMULATION:-0}" != 1 ]]; then
  cat >&2 <<EOF_WARNING
This Compose build targets linux/amd64. Host architecture is $machine.
Chromium compilation under CPU emulation is impractically slow and may fail.
Use an AMD64 Linux machine, or set ALLOW_EMULATION=1 to accept that risk.
EOF_WARNING
  exit 2
fi

mkdir -p \
  "$REPO_ROOT/artifacts/docker" \
  "$REPO_ROOT/.cef-docker/106-linux-x64" \
  "$REPO_ROOT/.cef-docker/134-linux-x64"

export LOCAL_UID="${LOCAL_UID:-$(id -u)}"
export LOCAL_GID="${LOCAL_GID:-$(id -g)}"
compose=(docker compose -f "$REPO_ROOT/docker-compose.cef.yml")

run_line() {
  local line="$1"
  local service="cef${line}-linux-x64"
  echo "=== Building CEF $line / linux-x64 with persistent cache ==="
  "${compose[@]}" --profile "$line" build "$service"
  "${compose[@]}" --profile "$line" run --rm "$service"
}

if [[ "$selection" == both ]]; then
  # Deliberately sequential: two fresh Chromium builds in parallel commonly
  # exhaust RAM and disk on developer workstations.
  run_line 106
  run_line 134
else
  run_line "$selection"
fi

echo "Artifacts: $REPO_ROOT/artifacts/docker"
find "$REPO_ROOT/artifacts/docker" -maxdepth 4 -type f -print | sort
