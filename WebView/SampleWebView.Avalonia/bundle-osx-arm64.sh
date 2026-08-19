#!/bin/sh
set -eu

CEF_LINE=${CEF_LINE:-134}
case "$CEF_LINE" in
  106) TARGET_FRAMEWORK=net6.0 ;;
  134) TARGET_FRAMEWORK=net8.0 ;;
  *) echo "Unsupported CEF_LINE: $CEF_LINE (use 106 or 134)" >&2; exit 2 ;;
esac

dotnet msbuild -t:BundleApp -p:CefLine="$CEF_LINE" -p:RuntimeIdentifier=osx-arm64 -p:Platform=ARM64

TARGETAPP="bin/ARM64/Debug/$TARGET_FRAMEWORK/osx-arm64/publish/SampleWebView.app/Contents/MacOS"
chmod +x "$TARGETAPP/CefGlueBrowserProcess/9n1m.webview"
chmod +x "$TARGETAPP/SampleWebView.Avalonia"
