#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CEF_LINE=106 exec "${SCRIPT_DIR}/build-cef-codecs.sh" "$@"
