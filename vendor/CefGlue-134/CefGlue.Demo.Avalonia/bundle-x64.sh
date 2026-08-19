#!/bin/sh

dotnet msbuild -t:BundleApp -p:RuntimeIdentifier=osx-x64 -p:Platform=x64

TARGETAPP=bin/x64/Debug/net8.0/osx-x64/publish/CefGlueDemoAvalonia.app/Contents/MacOS
chmod +x "$TARGETAPP/CefGlueBrowserProcess/9n1m.webview"
chmod +x "$TARGETAPP/Xilium.CefGlue.Demo.Avalonia"
