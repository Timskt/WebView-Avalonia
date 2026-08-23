#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/bin:/mingw64/bin:${PATH}"

# Chromium contains paths that exceed the legacy Win32 limit. Git for Windows
# supports them when this setting is enabled. Inject the network and URL rules
# into this process tree so the build does not mutate the user's Git config.
append_git_config() {
  local index="${GIT_CONFIG_COUNT:-0}"
  export "GIT_CONFIG_KEY_${index}=$1"
  export "GIT_CONFIG_VALUE_${index}=$2"
  export GIT_CONFIG_COUNT=$((index + 1))
}
append_git_config core.longpaths true
append_git_config http.version HTTP/1.1
append_git_config http.maxRequests 2
append_git_config http.sslBackend openssl
append_git_config http.lowSpeedLimit 1024
append_git_config http.lowSpeedTime 60
append_git_config url.https://github.com/.insteadOf \
  https://chromium.googlesource.com/external/github.com/
# Some historical Chromium DEPS entries expose directories from a monorepo as
# standalone Git repositories. Those URLs exist only on googlesource and must
# take precedence over the general GitHub mirror rewrite above.
append_git_config \
  url.https://chromium.googlesource.com/external/github.com/llvm/llvm-project/.insteadOf \
  https://chromium.googlesource.com/external/github.com/llvm/llvm-project/
append_git_config \
  url.https://chromium.googlesource.com/external/github.com/SeleniumHQ/selenium/.insteadOf \
  https://chromium.googlesource.com/external/github.com/SeleniumHQ/selenium/

# Build a pinned CEF line with Chromium proprietary H.264 and platform HEVC
# paths enabled. Exact pins and package versions live in config/cef-lines.json.
CEF_LINE="${CEF_LINE:-${1:-134}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
resolve_python
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

eval "$("${PYTHON_BIN}" - "${REPO_ROOT}" "${CEF_LINE}" <<'PY'
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

if [[ "${CEF_PLATFORM}" == Windows ]]; then
  # Public Chromium/CEF builders must use the locally installed Visual Studio
  # and Windows SDK instead of Google's internal downloadable toolchain.
  export DEPOT_TOOLS_WIN_TOOLCHAIN="${DEPOT_TOOLS_WIN_TOOLCHAIN:-0}"
  if [[ "${CEF_LINE}" == 106 ]]; then
    export GYP_MSVS_VERSION="${GYP_MSVS_VERSION:-2019}"
  else
    export GYP_MSVS_VERSION="${GYP_MSVS_VERSION:-2022}"
  fi
fi

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

# An interrupted initial gclient sync may leave chromium/src without Git
# metadata. automate-git.py treats that directory as an existing checkout and
# refuses to repair it, so discard only that incomplete cache directory.
if [[ -e "${CEF_SOURCE_DIR}/chromium/src" && ! -d "${CEF_SOURCE_DIR}/chromium/src/.git" ]]; then
  echo "Removing incomplete Chromium checkout: ${CEF_SOURCE_DIR}/chromium/src"
  rm -rf "${CEF_SOURCE_DIR}/chromium/src"
fi

if [[ -d "${CEF_SOURCE_DIR}/chromium/_bad_scm" ]]; then
  echo "Removing stale gclient conflict cache: ${CEF_SOURCE_DIR}/chromium/_bad_scm"
  rm -rf "${CEF_SOURCE_DIR}/chromium/_bad_scm"
fi

if [[ -d "${CEF_SOURCE_DIR}/chromium/src/.git" ]]; then
  git -C "${CEF_SOURCE_DIR}/chromium/src" reset --hard HEAD

  if [[ "${CEF_PLATFORM}" == Windows ]]; then
    dependency_script="${SCRIPT_DIR}/prepare-chromium-dependencies.ps1"
    chromium_source_native="${CEF_SOURCE_DIR}/chromium/src"
    if command -v cygpath >/dev/null 2>&1; then
      dependency_script="$(cygpath -w "${dependency_script}")"
      chromium_source_native="$(cygpath -w "${chromium_source_native}")"
    fi
    MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -ExecutionPolicy Bypass \
      -File "${dependency_script}" -ChromiumSource "${chromium_source_native}"
  fi
fi

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
"${PYTHON_BIN}" - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = "gclient sync --nohooks --with_branch_heads --jobs 16"
replacement = "gclient sync --nohooks --with_branch_heads --no-history --jobs 1"
if source.count(needle) != 1:
    raise SystemExit(
        "Unable to patch automate-git.py: expected one initial gclient sync"
    )
path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
print("Enabled shallow initial Chromium checkout (--no-history, 1 job)")
PY

"${PYTHON_BIN}" - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
source = source.replace("--jobs 16", "--jobs 1")
path.write_text(source, encoding="utf-8")
print("Limited Chromium sync/hooks to 1 job")
PY

# The CEF runtime build does not consume Chromium's documentation website.
# Exclude it from DEPS because its historical filenames exceed the Win32 path
# limit on machines where long-path policy is unavailable.
"${PYTHON_BIN}" - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
lines = source.splitlines(keepends=True)
matches = [
    index for index, line in enumerate(lines)
    if "'src/chrome/tools/test/reference_build/chrome_win': None" in line
]
if len(matches) != 1:
    raise SystemExit("Unable to patch Chromium documentation dependency")
index = matches[0]
indent = lines[index][:len(lines[index]) - len(lines[index].lstrip())]
excluded_dependencies = (
    'src/docs/website',
    'src/third_party/cros-components/src',
    'src/third_party/crossbench',
    'src/third_party/speedometer/main',
    'src/third_party/speedometer/v2.0',
    'src/third_party/speedometer/v2.1',
    'src/third_party/speedometer/v3.0',
    'src/third_party/vulkan_memory_allocator',
)
for offset, dependency in enumerate(excluded_dependencies, 1):
    lines.insert(
        index + offset,
        indent + f"\"'{dependency}': None, \"+\\\n",
    )
path.write_text("".join(lines), encoding="utf-8")
print("Excluded non-runtime Chromium dependencies")
PY

# The pinned Chromium commit is already present after a resumed shallow clone.
# Skip automate-git's broad pre-check fetch, which is unnecessary for this
# fixed checkout and is fragile through proxies. The later checkout/gclient
# sync still resolves the pinned source and required third-party dependencies.
"${PYTHON_BIN}" - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = '''if not options.nochromiumupdate and os.path.exists(chromium_src_dir):
  # Fetch updated sources.
  run("%s fetch" % (git_exe), chromium_src_dir, depot_tools_dir)
  # Also fetch tags, which are required for release branch builds.
  run("%s fetch --tags" % (git_exe), chromium_src_dir, depot_tools_dir)
'''
replacement = '''if not options.nochromiumupdate and os.path.exists(chromium_src_dir):
  # The requested pinned commit is supplied by the shallow checkout; avoid a
  # broad remote fetch here and let the later pinned sync resolve dependencies.
  msg("Skipping broad Chromium fetch; using the local pinned object")
'''
if source.count(needle) != 1:
    raise SystemExit("Unable to patch automate-git Chromium fetch block")
path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
print("Disabled broad Chromium pre-fetch")
PY

"${PYTHON_BIN}" - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = '''  if not cef_checkout_new:
    # Fetch updated sources.
    run('%s fetch' % (git_exe), cef_dir, depot_tools_dir)
'''
replacement = '''  if not cef_checkout_new:
    # The CEF checkout is pinned and the requested object is already present.
    # Avoid an unnecessary Bitbucket fetch when resuming through a proxy.
    msg("Skipping broad CEF fetch; using the local pinned object")
'''
if source.count(needle) != 1:
    raise SystemExit("Unable to patch CEF fetch block")
path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
print("Disabled broad CEF pre-fetch")
PY

"${PYTHON_BIN}" - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = '      run("gclient revert --nohooks", chromium_dir, depot_tools_dir)'
replacement = '      msg("Skipping gclient revert; resuming the interrupted dependency sync")'
if source.count(needle) != 1:
    raise SystemExit("Unable to patch gclient revert call")
path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
print("Enabled interrupted gclient sync resume")
PY

"${PYTHON_BIN}" - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = '''  chromium_checkout_changed = chromium_checkout_new or force_change or \\
                              chromium_current_hash != chromium_desired_hash
'''
replacement = '''  required_windows_tools = (
      os.path.join(chromium_src_dir, 'third_party', 'llvm-build',
                   'Release+Asserts', 'bin', 'clang-cl.exe'),
      os.path.join(chromium_src_dir, 'build', 'toolchain', 'win', 'rc', 'win',
                   'rc.exe'),
  )
  toolchain_incomplete = platform == 'windows' and any(
      not os.path.isfile(tool) for tool in required_windows_tools)
  chromium_checkout_changed = chromium_checkout_new or force_change or \\
                              chromium_current_hash != chromium_desired_hash or \\
                              toolchain_incomplete
'''
if source.count(needle) != 1:
    raise SystemExit("Unable to patch incomplete Chromium toolchain detection")
path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
print("Enabled automatic Chromium hooks repair")
PY

"${PYTHON_BIN}" - "automate-git.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = '''  # Generate project files.
  tool = os.path.join(cef_src_dir, 'tools', 'gclient_hook.py')
'''
replacement = '''  # A migrated or interrupted checkout can retain duplicate entries when a
  # dependency later becomes a custom_deps exclusion. GN only needs .gclient
  # and treats a missing generated entries file as recoverable, so discard the
  # stale cache before resolving the primary solution.
  gclient_entries_file = os.path.join(chromium_dir, '.gclient_entries')
  if os.path.exists(gclient_entries_file):
    msg("Removing stale gclient entries %s" % gclient_entries_file)
    if not options.dryrun:
      os.remove(gclient_entries_file)

  # Generate project files.
  tool = os.path.join(cef_src_dir, 'tools', 'gclient_hook.py')
'''
if source.count(needle) != 1:
    raise SystemExit("Unable to patch stale gclient entries cleanup")
path.write_text(source.replace(needle, replacement, 1), encoding="utf-8")
print("Enabled stale gclient entries cleanup")
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
  --no-depot-tools-update
  "${build_flag}"
)

# Reuse a completed Chromium checkout without fetching its very large history.
# A Git directory alone is insufficient after an interrupted gclient sync, so
# only skip the update after GN has generated the Release configuration.
if find "${CEF_SOURCE_DIR}/chromium/src/out" -mindepth 2 -maxdepth 2 \
  -type f -name args.gn -path '*Release*' -print -quit 2>/dev/null | grep -q .; then
  automate_args+=(--no-chromium-update)
else
  # Force gclient to replace the generated config and complete dependency
  # checkout after an interrupted migration/build.
  automate_args+=(--force-config)
fi
if [[ -n "${GN_ARGUMENTS}" ]]; then
  # GN_ARGUMENTS is an advanced CI escape hatch containing automate-git.py
  # arguments. Intentional shell-style splitting preserves existing usage.
  # shellcheck disable=SC2206
  extra_args=( ${GN_ARGUMENTS} )
  automate_args+=("${extra_args[@]}")
fi

if [[ ! -f "${CEF_BINARY_DISTRIB_DIR}/CEF_CODEC_BUILD_INFO.txt" ]]; then
  automate_args+=(--force-distrib)
fi

# Fail before the multi-hour checkout/build if a future pinned automate script
# removes an argument that this wrapper relies on.
"${PYTHON_BIN}" - automate-git.py "${automate_args[@]}" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
for option in sys.argv[2:]:
    name = option.split("=", 1)[0]
    if name.startswith("--") and re.search(r"[\"']" + re.escape(name) + r"[\"']", source) is None:
        raise SystemExit(f"pinned automate-git.py does not support {name}")
PY

# CEF_EXEC_UTIL_ENCODING_PATCH
for exec_util in \
  "${CEF_SOURCE_DIR}/cef/tools/exec_util.py" \
  "${CEF_SOURCE_DIR}/chromium/src/cef/tools/exec_util.py"; do
  if [[ -f "${exec_util}" ]]; then
    "${PYTHON_BIN}" - "${exec_util}" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
source = source.replace("out.decode('utf-8')", "out.decode('utf-8', errors='replace')")
source = source.replace("err.decode('utf-8')", "err.decode('utf-8', errors='replace')")
path.write_text(source, encoding="utf-8")
PY
  fi
done

make_cmake="${CEF_SOURCE_DIR}/chromium/src/cef/tools/make_cmake.py"
if [[ -f "${make_cmake}" ]]; then
  "${PYTHON_BIN}" "${SCRIPT_DIR}/patch-cef-cmake-paths.py" "${make_cmake}"
fi

automate_max_attempts="${CEF_NETWORK_MAX_ATTEMPTS:-20}"
automate_retry_delay="${CEF_NETWORK_RETRY_DELAY_SECONDS:-30}"
automate_attempt=1
while true; do
  automate_attempt_log="${CEF_SOURCE_DIR}/automate-git-attempt.log"
  : > "${automate_attempt_log}"
  set +e
  "${PYTHON_BIN}" automate-git.py "${automate_args[@]}" 2>&1 \
    | tee "${automate_attempt_log}"
  automate_status=${PIPESTATUS[0]}
  set -e
  if ((automate_status == 0)); then
    break
  fi
  if ((automate_attempt >= automate_max_attempts)) || \
    ! grep -Eqi 'error: RPC failed|fatal: expected .packfile.|server closed abruptly|Failed to connect|Connection reset( by peer)?|Connection timed out|Operation timed out|TLS (handshake|connection|error)|SSL_ERROR|HTTP (429|5[0-9][0-9])' "${automate_attempt_log}"; then
    exit "${automate_status}"
  fi
  echo "Transient network failure (attempt ${automate_attempt}/${automate_max_attempts}); retrying in ${automate_retry_delay}s..." >&2
  sleep "${automate_retry_delay}"
  automate_attempt=$((automate_attempt + 1))
done

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
args_gn_sha256="$("${PYTHON_BIN}" - "${args_gn}" <<'PY'
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
