#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: package-managed-codecs.sh --line 106|134 --feed DIR --config FILE

Builds and packs the matching vendored CefGlue and WebView packages using the
real or synthetic CEF runtime packages already present in DIR.
EOF
}

line=""
feed=""
nuget_config=""
while (($#)); do
  case "$1" in
    --line) line="${2:?missing value for --line}"; shift 2 ;;
    --feed) feed="${2:?missing value for --feed}"; shift 2 ;;
    --config) nuget_config="${2:?missing value for --config}"; shift 2 ;;
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

feed="$(mkdir -p "$feed" && cd "$feed" && pwd)"
nuget_config="$(cd "$(dirname "$nuget_config")" && pwd)/$(basename "$nuget_config")"
[[ -f "$nuget_config" ]] || { echo "NuGet config not found: $nuget_config" >&2; exit 2; }

eval "$(python3 "$SCRIPT_DIR/cef_line_config.py" "$line" --format shell)"
cefglue_root="$REPO_ROOT/$CEFGLUE_DIR"
[[ -d "$cefglue_root" ]] || { echo "Vendored CefGlue source not found: $cefglue_root" >&2; exit 2; }

common_project="$cefglue_root/CefGlue.Common/CefGlue.Common.csproj"
avalonia_project="$cefglue_root/CefGlue.Avalonia/CefGlue.Avalonia.csproj"
webview_project="$REPO_ROOT/WebView/WebViewControl.Avalonia/WebViewControl.Avalonia.csproj"

for platform in x64 ARM64; do
  dotnet restore "$common_project" --force --configfile "$nuget_config" \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true
  dotnet build "$common_project" -c Release --no-restore \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true
  dotnet pack "$common_project" -c Release --no-restore --output "$feed" \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true

  dotnet restore "$avalonia_project" --force --configfile "$nuget_config" \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true
  dotnet build "$avalonia_project" -c Release --no-restore \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true
  dotnet pack "$avalonia_project" -c Release --no-restore --output "$feed" \
    -p:Platform="$platform" -p:PlatformTarget="$platform" -p:EnableCefLinux=true

done

for rid in win-x64 osx-x64 linux-x64; do
  python3 "$SCRIPT_DIR/verify-package-layout.py" \
    "$feed/CefGlue.Common.$CEFGLUE_VERSION.nupkg" --kind cefglue --line "$line" --rid "$rid"
done
for rid in win-arm64 osx-arm64 linux-arm64; do
  python3 "$SCRIPT_DIR/verify-package-layout.py" \
    "$feed/CefGlue.Common.ARM64.$CEFGLUE_VERSION.nupkg" --kind cefglue --line "$line" --rid "$rid"
done

for platform in x64 ARM64; do
  dotnet restore "$webview_project" --force --configfile "$nuget_config" \
    -p:CefLine="$line" -p:Platform="$platform" -p:PlatformTarget="$platform"
  dotnet build "$webview_project" -c ReleaseAvalonia --no-restore \
    -p:CefLine="$line" -p:Platform="$platform" -p:PlatformTarget="$platform"
  dotnet pack "$webview_project" -c ReleaseAvalonia --no-restore --output "$feed" \
    -p:CefLine="$line" -p:Platform="$platform" -p:PlatformTarget="$platform"
done

python3 "$SCRIPT_DIR/verify-package-layout.py" \
  "$feed/WebViewControl-Avalonia.$WEBVIEW_VERSION.nupkg" --kind webview --line "$line" --arch x64
python3 "$SCRIPT_DIR/verify-package-layout.py" \
  "$feed/WebViewControl-Avalonia-ARM64.$WEBVIEW_VERSION.nupkg" --kind webview --line "$line" --arch arm64
