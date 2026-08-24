#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/bin:/mingw64/bin:${PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
resolve_python
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: build-portable-codec-bundle.sh --line 106|134 --rid RID [options]

Builds one pinned CEF/Chromium line, packages the native runtime and managed
NuGet packages, verifies a consumer, and emits a runnable demo bundle.

Required:
  --line 106|134            Pinned CEF product line.
  --rid RID                 win-x64, win-arm64, osx-x64, osx-arm64,
                            linux-x64, or linux-arm64.

Options:
  --cache DIR               Persistent checkout/build cache.
                            Default: .cef-cache/portable/<line>/<rid>
  --output DIR              Final artifact root.
                            Default: artifacts/portable
  --skip-native             Reuse an existing binary_distrib in the cache.
  --no-demo                 Do not publish the html5test demo bundle.
  --allow-low-disk           Override the 120 GiB fresh-build disk preflight.
  --preflight-only           Check host/tools/disk/RAM and stop before checkout.
  -h, --help                Show this help.

The requested RID must match the host operating system. Docker/Compose builds
Linux native outputs only; Windows DLLs require a Windows host and macOS dylibs
require a macOS host.
USAGE
}

line=""
rid=""
cache_root=""
output_root=""
skip_native=false
build_demo=true
allow_low_disk=false
preflight_only=false
while (($#)); do
  case "$1" in
    --line) line="${2:?missing value for --line}"; shift 2 ;;
    --rid) rid="${2:?missing value for --rid}"; shift 2 ;;
    --cache) cache_root="${2:?missing value for --cache}"; shift 2 ;;
    --output) output_root="${2:?missing value for --output}"; shift 2 ;;
    --skip-native) skip_native=true; shift ;;
    --no-demo) build_demo=false; shift ;;
    --allow-low-disk) allow_low_disk=true; shift ;;
    --preflight-only) preflight_only=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$line" in 106|134) ;; *) echo "--line must be 106 or 134" >&2; exit 2 ;; esac
case "$rid" in
  win-x64|win-arm64|osx-x64|osx-arm64|linux-x64|linux-arm64) ;;
  *) echo "Unsupported --rid: ${rid:-<empty>}" >&2; exit 2 ;;
esac

host_name="${RUNNER_OS:-$(uname -s)}"
case "$host_name" in
  Windows*|MINGW*|MSYS*|CYGWIN*) host_platform=Windows; expected_prefix=win ;;
  macOS|Darwin) host_platform=macOS; expected_prefix=osx ;;
  Linux) host_platform=Linux; expected_prefix=linux ;;
  *) echo "Unsupported host operating system: $host_name" >&2; exit 2 ;;
esac
if [[ "$rid" != "$expected_prefix-"* ]]; then
  echo "RID $rid cannot be built on $host_platform; expected a $expected_prefix-* RID" >&2
  exit 2
fi

if [[ "$host_platform" == Windows ]]; then
  # Chromium public builds use the locally installed Visual Studio/Windows SDK.
  export DEPOT_TOOLS_WIN_TOOLCHAIN="${DEPOT_TOOLS_WIN_TOOLCHAIN:-0}"
  if [[ "$line" == 106 ]]; then
    export GYP_MSVS_VERSION="${GYP_MSVS_VERSION:-2019}"
  else
    export GYP_MSVS_VERSION="${GYP_MSVS_VERSION:-2022}"
  fi
fi

arch="${rid##*-}"
[[ "$arch" == x64 || "$arch" == arm64 ]] || { echo "Unsupported architecture: $arch" >&2; exit 2; }

cache_root="${cache_root:-$REPO_ROOT/.cef-cache/portable/$line/$rid}"
output_root="${output_root:-$REPO_ROOT/artifacts/portable}"
mkdir -p "$cache_root" "$output_root"
if [[ "$host_platform" != Windows || "$cache_root" != /[a-zA-Z]/* ]]; then
  cache_root="$(cd "$cache_root" && pwd)"
fi
output_root="$(cd "$output_root" && pwd)"
line_output="$output_root/cef-$line/$rid"
feed="$line_output/nuget"
consumer_work="$cache_root/consumer"
demo_output="$line_output/demo"
source_root="$cache_root/source"
depot_tools="$cache_root/depot_tools"
nuget_cache="$cache_root/nuget-cache"
mkdir -p "$line_output" "$feed" "$nuget_cache"
export NUGET_PACKAGES="$nuget_cache"

preflight_args=(
  --line "$line"
  --rid "$rid"
  --cache "$cache_root"
  --output "$output_root"
  --json-output "$line_output/PHYSICAL_BUILD_PREFLIGHT.json"
)
if [[ "$skip_native" == true ]]; then preflight_args+=(--skip-native); fi
if [[ "$allow_low_disk" == true ]]; then preflight_args+=(--allow-low-disk); fi
"${PYTHON_BIN}" "$SCRIPT_DIR/preflight-physical-build.py" "${preflight_args[@]}"
if [[ "$preflight_only" == true ]]; then
  echo "Preflight completed: $line_output/PHYSICAL_BUILD_PREFLIGHT.json"
  exit 0
fi

# Do not let packages from a previous version make a failed build appear whole.
"${PYTHON_BIN}" - "$feed" "$demo_output" <<'PY'
import pathlib
import shutil
import sys
for raw in sys.argv[1:]:
    path = pathlib.Path(raw)
    if path.exists():
        shutil.rmtree(path)
pathlib.Path(sys.argv[1]).mkdir(parents=True, exist_ok=True)
PY

eval "$("${PYTHON_BIN}" "$SCRIPT_DIR/cef_line_config.py" "$line" --format shell)"

if [[ "$skip_native" != true ]]; then
  if [[ ! -d "$depot_tools/.git" ]]; then
    echo "Bootstrapping persistent depot_tools cache: $depot_tools"
    git clone --filter=blob:none \
      https://chromium.googlesource.com/chromium/tools/depot_tools.git \
      "$depot_tools"
  fi

  # A fresh depot_tools checkout contains the batch entry points but not the
  # generated git/python wrappers. Those are normally created by
  # update_depot_tools.bat; this build intentionally disables auto-update, so
  # bootstrap them explicitly on the first run after migration.
  if [[ "$host_platform" == Windows && ( ! -f "$depot_tools/git.bat" || ! -f "$depot_tools/python3.bat" ) ]]; then
    echo "Bootstrapping depot_tools Windows wrappers: $depot_tools"
    bootstrap_script="$SCRIPT_DIR/bootstrap-depot-tools.ps1"
    depot_tools_native="$depot_tools"
    if command -v cygpath >/dev/null 2>&1; then
      bootstrap_script="$(cygpath -w "$bootstrap_script")"
      depot_tools_native="$(cygpath -w "$depot_tools")"
    fi
    MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -ExecutionPolicy Bypass \
      -File "$bootstrap_script" -DepotTools "$depot_tools_native"
  fi

  [[ -f "$depot_tools/git.bat" && -f "$depot_tools/python3.bat" ]] || {
    echo "depot_tools is incomplete: git.bat/python3.bat were not generated" >&2
    exit 1
  }
  export PATH="$depot_tools:$PATH"
  export DEPOT_TOOLS_DIR="$depot_tools"
  export CEF_SOURCE_DIR="$source_root"
  export CEF_ARCH="$arch"
  export CEF_PLATFORM="$host_platform"
  export GIT_TERMINAL_PROMPT=0
  "$SCRIPT_DIR/build-cef-codecs.sh"
fi

binary_distrib="$source_root/chromium/src/cef/binary_distrib"
marker="$binary_distrib/CEF_CODEC_BUILD_INFO.txt"
[[ -f "$marker" ]] || {
  echo "Missing real codec build marker: $marker" >&2
  echo "Run without --skip-native or copy the matching binary_distrib into the cache." >&2
  exit 1
}
if grep -q '^SYNTHETIC_FIXTURE=true$' "$marker"; then
  echo "Synthetic fixtures cannot be emitted as portable build products." >&2
  exit 1
fi

"${PYTHON_BIN}" "$SCRIPT_DIR/package-cef-runtime.py" \
  --line "$line" --rid "$rid" --source "$binary_distrib" \
  --version "$CEF_RUNTIME_VERSION" --output "$feed" --codec-enabled
case "$rid" in
  win-x64) runtime_package_id=chromiumembeddedframework.runtime.win-x64 ;;
  win-arm64) runtime_package_id=chromiumembeddedframework.runtime.win-arm64 ;;
  osx-x64) runtime_package_id=cef.redist.osx64 ;;
  osx-arm64) runtime_package_id=cef.redist.osx.arm64 ;;
  linux-x64) runtime_package_id=cef.redist.linux64 ;;
  linux-arm64) runtime_package_id=cef.redist.linuxarm64 ;;
esac
runtime_package="$feed/$runtime_package_id.$CEF_RUNTIME_VERSION.nupkg"
[[ -n "$runtime_package" ]] || { echo "Runtime NuGet was not produced" >&2; exit 1; }
[[ -f "$runtime_package" ]] || { echo "Runtime NuGet was not produced: $runtime_package" >&2; exit 1; }
if [[ "$rid" == win-* ]]; then
  meta_package="$feed/chromiumembeddedframework.runtime.$CEF_RUNTIME_VERSION.nupkg"
  [[ -f "$meta_package" ]] || { echo "Windows runtime meta NuGet was not produced: $meta_package" >&2; exit 1; }
fi
"${PYTHON_BIN}" "$SCRIPT_DIR/verify-package-layout.py" "$runtime_package" \
  --kind runtime --line "$line" --rid "$rid"

nuget_config="$line_output/NuGet.Codecs.Config"
nuget_feed_path="$(native_path "$feed")"
nuget_cache_path="$(native_path "$nuget_cache")"
cat > "$nuget_config" <<EOF_CONFIG
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <config>
    <add key="globalPackagesFolder" value="$nuget_cache_path" />
  </config>
  <packageSources>
    <clear />
    <add key="codec-feed" value="$nuget_feed_path" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
EOF_CONFIG

"$SCRIPT_DIR/package-managed-codecs.sh" \
  --line "$line" --feed "$feed" --config "$nuget_config" --rids "$rid"
"$SCRIPT_DIR/verify-nuget-consumer.sh" \
  --line "$line" --config "$nuget_config" --work "$consumer_work" --rids "$rid"

if [[ "$build_demo" == true ]]; then
  platform=x64
  [[ "$arch" == arm64 ]] && platform=ARM64
  project="$REPO_ROOT/WebView/SampleWebView.Avalonia/SampleWebView.Avalonia.csproj"
  dotnet restore "$project" --force --configfile "$nuget_config" -r "$rid" \
    -p:CefLine="$line" -p:Platform="$platform" -p:PlatformTarget="$platform" \
    -p:CodecRuntimeRids="$rid"
  dotnet publish "$project" -c ReleaseAvalonia --no-restore -r "$rid" \
    --self-contained true -o "$demo_output" \
    -p:CefLine="$line" -p:Platform="$platform" -p:PlatformTarget="$platform" \
    -p:CodecRuntimeRids="$rid"
  "${PYTHON_BIN}" "$SCRIPT_DIR/verify-package-layout.py" "$demo_output" \
    --kind consumer --line "$line" --rid "$rid"
  tar -C "$demo_output" -czf "$line_output/html5test-demo-$rid.tar.gz" .
  if [[ "$rid" == win-* ]]; then
    "${PYTHON_BIN}" "$SCRIPT_DIR/create-portable-windows-demo.py" \
      --source "$demo_output" \
      --output "$line_output/SampleWebView-Avalonia-portable-$rid.zip" \
      --line "$line" --rid "$rid"
  fi
fi

cp "$marker" "$line_output/CEF_CODEC_BUILD_INFO.txt"
"${PYTHON_BIN}" - "$REPO_ROOT" "$line_output" "$line" "$rid" <<'PY'
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

repo = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
line = sys.argv[3]
rid = sys.argv[4]
try:
    commit = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "HEAD"], text=True
    ).strip()
except Exception:
    commit = "unknown"
try:
    dirty = bool(subprocess.check_output(
        ["git", "-C", str(repo), "status", "--porcelain"], text=True
    ).strip())
except Exception:
    dirty = None
files = []
for path in sorted(out.rglob("*")):
    if not path.is_file() or path.name in {"SHA256SUMS", "build-manifest.json"}:
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    files.append({
        "path": path.relative_to(out).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": digest,
    })
manifest = {
    "schema": 1,
    "cef_line": line,
    "rid": rid,
    "repository_commit": commit,
    "repository_dirty": dirty,
    "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "synthetic": False,
    "files": files,
}
(out / "build-manifest.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
with (out / "SHA256SUMS").open("w", encoding="utf-8") as sums:
    for item in files:
        sums.write(f"{item['sha256']}  {item['path']}\n")
PY

archive_format=gztar
[[ "$rid" == win-* ]] && archive_format=zip
archive_output="$("${PYTHON_BIN}" "$SCRIPT_DIR/create-delivery-archive.py" \
  --source "$line_output" \
  --output-base "$output_root/cef-$line-$rid-bundle" \
  --format "$archive_format" | sed -n '1p')"

echo
printf 'Portable codec bundle completed:\n  line: %s\n  rid: %s\n  output: %s\n  archive: %s\n' \
  "$line" "$rid" "$line_output" "$archive_output"
find "$line_output" -maxdepth 2 -type f -print | sort
