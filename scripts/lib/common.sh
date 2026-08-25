#!/usr/bin/env bash
# Shared helpers for Bash entry points. Compatible with the macOS system Bash 3.2.

resolve_python() {
  if [[ -n "${PYTHON_BIN:-}" ]]; then
    if [[ "${PYTHON_BIN}" == */* ]]; then
      if [[ ! -f "${PYTHON_BIN}" ]]; then
        echo "Configured PYTHON_BIN was not found: ${PYTHON_BIN}" >&2
        return 2
      fi
    elif ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
      echo "Configured PYTHON_BIN was not found: ${PYTHON_BIN}" >&2
      return 2
    fi
    if ! "${PYTHON_BIN}" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
      echo "Configured PYTHON_BIN is not Python 3: ${PYTHON_BIN}" >&2
      return 2
    fi
    export PYTHON_BIN
    return 0
  fi

  local candidate
  for candidate in python3.bat python3 python.bat python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
      PYTHON_BIN="$candidate"
      export PYTHON_BIN
      return 0
    fi
  done

  echo "Python 3 is required (python3.bat, python3, python.bat, or python)." >&2
  return 2
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

clear_nuget_package_cache() {
  local package_id="$1"
  local package_version="$2"
  local packages_root="${NUGET_PACKAGES:-${HOME}/.nuget/packages}"

  if command -v cygpath >/dev/null 2>&1; then
    packages_root="$(cygpath -w "$packages_root")"
  fi

  "${PYTHON_BIN}" - "$packages_root" "$package_id" "$package_version" <<'PY'
import os
import pathlib
import shutil
import sys

root = pathlib.Path(sys.argv[1]).resolve()
package_id = sys.argv[2].lower()
package_version = sys.argv[3].lower()
if any(part in ('', '.', '..') or '/' in part or '\\' in part
       for part in (package_id, package_version)):
    raise SystemExit('Invalid NuGet package cache coordinates')

target = (root / package_id / package_version).resolve()
if os.path.commonpath((str(root), str(target))) != str(root):
    raise SystemExit(f'Refusing to remove NuGet cache outside {root}: {target}')
if target.is_dir():
    shutil.rmtree(str(target))
    print(f'Removed stale NuGet package cache: {target}')
PY
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
