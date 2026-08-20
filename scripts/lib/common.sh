#!/usr/bin/env bash
# Shared helpers for Bash entry points. Compatible with the macOS system Bash 3.2.

resolve_python() {
  if [[ -n "${PYTHON_BIN:-}" ]]; then
    if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
      echo "Configured PYTHON_BIN was not found: ${PYTHON_BIN}" >&2
      return 2
    fi
    export PYTHON_BIN
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
  else
    echo "Python 3 is required (python3 or python)." >&2
    return 2
  fi
  export PYTHON_BIN
}

native_path() {
  # Paths embedded inside NuGet.Config are not argv values, so MSYS cannot
  # translate them for dotnet. Convert those paths explicitly on Windows.
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

command_version_line() {
  local command_name="$1"
  shift
  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" "$@" 2>&1 | sed -n '1p'
  else
    printf 'not found\n'
  fi
}
