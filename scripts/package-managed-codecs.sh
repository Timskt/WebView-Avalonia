#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
resolve_python
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ALL_RIDS=(win-x64 win-arm64 osx-x64 osx-arm64 linux-x64 linux-arm64)

usage() {
  cat <<'USAGE'
Usage: package-managed-codecs.sh --line 106|134 --feed DIR --config FILE [--rids LIST]

Builds and packs the matching vendored CefGlue and WebView packages using the
real or synthetic CEF runtime packages already present in DIR.

LIST is comma- or space-separated. It defaults to all supported RIDs. Example:
  --rids win-x64
USAGE
}

line=""
feed=""
nuget_config=""
rids_value=""
while (($#)); do
  case "$1" in
    --line) line="${2:?missing value for --line}"; shift 2 ;;
    --feed) feed="${2:?missing value for --feed}"; shift 2 ;;
    --config) nuget_config="${2:?missing value for --config}"; shift 2 ;;
    --rids) rids_value="${2:?missing value for --rids}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$line" != "106" && "$line" != "134" ]]; then
  echo "--line must be 106 or 134" >&2
  exit 2
fi
if [[ -z "$feed" || -z "$nuget_config" ]]; then
  usage >&2
  exit 2
fi

if [[ -z "$rids_value" ]]; then
  rids=("${ALL_RIDS[@]}")
else
  rids_value="${rids_value//,/ }"
  read -r -a requested_rids <<< "$rids_value"
  rids=()
  for rid in "${requested_rids[@]}"; do
    case " ${ALL_RIDS[*]} " in
      *" $rid "*) ;;
      *) echo "Unsupported RID: $rid" >&2; exit 2 ;;
    esac
    case " ${rids[*]-} " in
      *" $rid "*) ;;
      *) rids+=("$rid") ;;
    esac
  done
fi
((${#rids[@]})) || { echo "--rids must select at least one RID" >&2; exit 2; }

codec_runtime_rids="$(IFS=\| ; echo "${rids[*]}")"
platforms=()
for rid in "${rids[@]}"; do
  if [[ "$rid" == *-arm64 ]]; then platform="ARM64"; else platform="x64"; fi
  case " ${platforms[*]-} " in
    *" $platform "*) ;;
    *) platforms+=("$platform") ;;
  esac
done

feed="$(mkdir -p "$feed" && cd "$feed" && pwd)"
nuget_config="$(cd "$(dirname "$nuget_config")" && pwd)/$(basename "$nuget_config")"
[[ -f "$nuget_config" ]] || { echo "NuGet config not found: $nuget_config" >&2; exit 2; }

eval "$("${PYTHON_BIN}" "$SCRIPT_DIR/cef_line_config.py" "$line" --format shell)"
cefglue_root="$REPO_ROOT/$CEFGLUE_DIR"
[[ -d "$cefglue_root" ]] || { echo "Vendored CefGlue source not found: $cefglue_root" >&2; exit 2; }

common_project="$cefglue_root/CefGlue.Common/CefGlue.Common.csproj"
avalonia_project="$cefglue_root/CefGlue.Avalonia/CefGlue.Avalonia.csproj"
webview_project="$REPO_ROOT/WebView/WebViewControl.Avalonia/WebViewControl.Avalonia.csproj"

for platform in "${platforms[@]}"; do
  dotnet restore "$common_project" --force --configfile "$nuget_config" \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true \
    -p:CodecRuntimeRids="$codec_runtime_rids"
  dotnet build "$common_project" -c Release --no-restore \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true \
    -p:CodecRuntimeRids="$codec_runtime_rids"
  dotnet pack "$common_project" -c Release --no-restore --output "$feed" \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true \
    -p:CodecRuntimeRids="$codec_runtime_rids"

  dotnet restore "$avalonia_project" --force --configfile "$nuget_config" \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true \
    -p:CodecRuntimeRids="$codec_runtime_rids"
  dotnet build "$avalonia_project" -c Release --no-restore \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true \
    -p:CodecRuntimeRids="$codec_runtime_rids"
  dotnet pack "$avalonia_project" -c Release --no-restore --output "$feed" \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true \
    -p:CodecRuntimeRids="$codec_runtime_rids"
done

for rid in "${rids[@]}"; do
  if [[ "$rid" == *-arm64 ]]; then
    cefglue_package="$feed/CefGlue.Common.ARM64.$CEFGLUE_VERSION.nupkg"
  else
    cefglue_package="$feed/CefGlue.Common.$CEFGLUE_VERSION.nupkg"
  fi
  "${PYTHON_BIN}" "$SCRIPT_DIR/verify-package-layout.py" \
    "$cefglue_package" --kind cefglue --line "$line" --rid "$rid"
done

for platform in "${platforms[@]}"; do
  dotnet restore "$webview_project" --force --configfile "$nuget_config" \
    -p:CefLine="$line" -p:Platform="$platform" -p:PlatformTarget="$platform" \
    -p:CodecRuntimeRids="$codec_runtime_rids"
  dotnet build "$webview_project" -c ReleaseAvalonia --no-restore \
    -p:CefLine="$line" -p:Platform="$platform" -p:PlatformTarget="$platform" \
    -p:CodecRuntimeRids="$codec_runtime_rids"
  dotnet pack "$webview_project" -c ReleaseAvalonia --no-restore --output "$feed" \
    -p:CefLine="$line" -p:Platform="$platform" -p:PlatformTarget="$platform" \
    -p:CodecRuntimeRids="$codec_runtime_rids"

  if [[ "$platform" == "ARM64" ]]; then
    webview_package="$feed/WebViewControl-Avalonia-ARM64.$WEBVIEW_VERSION.nupkg"
    arch="arm64"
  else
    webview_package="$feed/WebViewControl-Avalonia.$WEBVIEW_VERSION.nupkg"
    arch="x64"
  fi
  "${PYTHON_BIN}" "$SCRIPT_DIR/verify-package-layout.py" \
    "$webview_package" --kind webview --line "$line" --arch "$arch"
done
