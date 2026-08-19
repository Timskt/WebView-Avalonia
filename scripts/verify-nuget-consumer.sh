#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  echo "Usage: verify-nuget-consumer.sh --line 106|134 --config FILE --work DIR" >&2
}

line=""
nuget_config=""
work=""
while (($#)); do
  case "$1" in
    --line) line="${2:?missing value for --line}"; shift 2 ;;
    --config) nuget_config="${2:?missing value for --config}"; shift 2 ;;
    --work) work="${2:?missing value for --work}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$line" != "106" && "$line" != "134" ]] || [[ -z "$nuget_config" || -z "$work" ]]; then
  usage
  exit 2
fi

nuget_config="$(cd "$(dirname "$nuget_config")" && pwd)/$(basename "$nuget_config")"
[[ -f "$nuget_config" ]] || { echo "NuGet config not found: $nuget_config" >&2; exit 2; }
work="$(mkdir -p "$work" && cd "$work" && pwd)"
eval "$(python3 "$SCRIPT_DIR/cef_line_config.py" "$line" --format shell)"

for rid in win-x64 win-arm64 osx-x64 osx-arm64 linux-x64 linux-arm64; do
  if [[ "$rid" == *arm64 ]]; then
    package_id="WebViewControl-Avalonia-ARM64"
    platform="ARM64"
  else
    package_id="WebViewControl-Avalonia"
    platform="x64"
  fi
  project_dir="$work/$line/$rid"
  rm -rf "$project_dir"
  mkdir -p "$project_dir"
  cat > "$project_dir/Consumer.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>$TARGET_FRAMEWORK</TargetFramework>
    <RuntimeIdentifier>$rid</RuntimeIdentifier>
    <PlatformTarget>$platform</PlatformTarget>
    <Platform>$platform</Platform>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <!-- Real Avalonia applications reference Avalonia directly. The WebView
         package intentionally does not expose Avalonia compile assets transitively. -->
    <PackageReference Include="Avalonia" Version="11.0.10" />
    <PackageReference Include="$package_id" Version="[$WEBVIEW_VERSION]" />
  </ItemGroup>
</Project>
EOF
  printf '%s\n' 'Console.WriteLine("WebView codec package consumer smoke test");' > "$project_dir/Program.cs"
  dotnet restore "$project_dir/Consumer.csproj" --force --configfile "$nuget_config"
  dotnet build "$project_dir/Consumer.csproj" -c Release --no-restore
  python3 "$SCRIPT_DIR/verify-package-layout.py" \
    "$project_dir/bin/$platform/Release/$TARGET_FRAMEWORK/$rid" --kind consumer --line "$line" --rid "$rid"
done
