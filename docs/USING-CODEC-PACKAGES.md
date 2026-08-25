# Using the Codec-Enabled Avalonia Package

## Install From a Private Feed

Configure the feed and install the top-level package:

```powershell
dotnet nuget add source \\server\cef-nuget --name CompanyCef
dotnet add package WebViewControl-Avalonia `
  --version 3.134.178-codecs.10 `
  --source CompanyCef
```

The package brings in the matching CEF runtime, CefGlue packages and
browser-process executable. Do not mix package versions from another CEF line.

## Project File

For a normal Windows x64 Avalonia application:

```xml
<PropertyGroup>
  <TargetFramework>net8.0</TargetFramework>
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <PlatformTarget>x64</PlatformTarget>
</PropertyGroup>

<ItemGroup>
  <PackageReference Include="WebViewControl-Avalonia"
                    Version="3.134.178-codecs.10" />
</ItemGroup>
```

Build and publish the application normally:

```powershell
dotnet restore
dotnet publish -c Release -r win-x64 --self-contained true
```

The package targets place CEF resources under the expected `locales`
directory and copy the browser process to
`CefGlueBrowserProcess/9n1m.webview.exe`.

## Runtime Checklist

The application must deploy all files produced by `dotnet publish`, including:

- `libcef.dll`, CEF `.pak` files and `icudtl.dat`;
- the `locales` directory;
- `CefGlueBrowserProcess/9n1m.webview.exe`;
- the native support DLLs copied by the runtime package.

Do not remove the locale files or rename the browser-process executable.
The CEF runtime is initialized by the WebView library before the first
browser control is created.

## Media Validation

Test an actual H.264 and H.265 stream in the target application. Chromium's
`HTMLMediaElement.canPlayType()` is useful as a preflight check but does not
prove that a specific stream will decode.

H.265 playback can fail even with the codec-enabled CEF build when the target
machine lacks one of the following:

- the Windows HEVC Video Extensions component;
- a compatible GPU driver and DXVA path;
- hardware support for the stream profile, bit depth or chroma format.

Collect `chrome://gpu` output and the CEF log when diagnosing a failure.

## CEF Lines

Use CEF 134 for supported current Windows systems and .NET 8. Use CEF 106
only for the Windows 7 compatibility line and .NET 6. The lines have separate
runtime, CefGlue and WebView package versions and must not be combined.
