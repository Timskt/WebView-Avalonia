#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
resolve_python
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
selection="${1:-both}"
work="${2:-$REPO_ROOT/artifacts/synthetic-smoke}"

case "$selection" in
  106) lines=(106) ;;
  134) lines=(134) ;;
  both) lines=(106 134) ;;
  *) echo "CEF selection must be 106, 134, or both" >&2; exit 2 ;;
esac

rm -rf "$work"
mkdir -p "$work/feed" "$work/fixtures" "$work/consumer"
export NUGET_PACKAGES="$work/nuget-cache"
work="$(cd "$work" && pwd)"
feed="$work/feed"

for line in "${lines[@]}"; do
  eval "$("${PYTHON_BIN}" "$SCRIPT_DIR/cef_line_config.py" "$line" --format shell)"
  for rid in win-x64 win-arm64 osx-x64 osx-arm64 linux-x64 linux-arm64; do
    fixture="$work/fixtures/$line/$rid"
    "${PYTHON_BIN}" "$SCRIPT_DIR/create-synthetic-cef-fixture.py" --line "$line" --rid "$rid" --output "$fixture"
    "${PYTHON_BIN}" "$SCRIPT_DIR/package-cef-runtime.py" --line "$line" --rid "$rid" \
      --source "$fixture" --version "$CEF_RUNTIME_VERSION" --output "$feed" --codec-enabled --allow-synthetic
    package_id=""
    case "$rid" in
      win-x64) package_id=chromiumembeddedframework.runtime.win-x64 ;;
      win-arm64) package_id=chromiumembeddedframework.runtime.win-arm64 ;;
      osx-x64) package_id=cef.redist.osx64 ;;
      osx-arm64) package_id=cef.redist.osx.arm64 ;;
      linux-x64) package_id=cef.redist.linux64 ;;
      linux-arm64) package_id=cef.redist.linuxarm64 ;;
    esac
    "${PYTHON_BIN}" "$SCRIPT_DIR/verify-package-layout.py" \
      "$feed/$package_id.$CEF_RUNTIME_VERSION.nupkg" --kind runtime --line "$line" --rid "$rid" --allow-synthetic
  done
done

cat > "$work/NuGet.Config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <config>
    <add key="globalPackagesFolder" value="$work/nuget-cache" />
  </config>
  <packageSources>
    <clear />
    <add key="codec-feed" value="$feed" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
EOF

for line in "${lines[@]}"; do
  "$SCRIPT_DIR/package-managed-codecs.sh" --line "$line" --feed "$feed" --config "$work/NuGet.Config"
  "$SCRIPT_DIR/verify-nuget-consumer.sh" --line "$line" --config "$work/NuGet.Config" --work "$work/consumer"
done

cat > "$work/SYNTHETIC-ONLY.txt" <<'EOF'
These packages use text placeholders instead of CEF native binaries.
They validate package layout and managed builds only. NEVER RELEASE THEM.
EOF

echo "Synthetic-only smoke test passed: $work"
