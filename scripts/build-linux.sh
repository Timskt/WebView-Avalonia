#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_deps=false
forward=(--line both --rid auto)
if (($#)); then forward=(); fi
while (($#)); do
  case "$1" in
    --install-deps) install_deps=true; shift ;;
    *) forward+=("$1"); shift ;;
  esac
done

if [[ "$(uname -s)" != Linux ]]; then
  echo "build-linux.sh must run on Linux." >&2
  exit 2
fi
if [[ "$install_deps" == true ]]; then
  "$SCRIPT_DIR/install-linux-build-deps.sh"
fi
if ((${#forward[@]})); then
  exec "$SCRIPT_DIR/build-physical.sh" "${forward[@]}"
else
  exec "$SCRIPT_DIR/build-physical.sh"
fi
