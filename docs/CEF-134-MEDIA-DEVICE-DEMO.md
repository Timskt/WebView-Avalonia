# CEF 134 media device Demo

`samples/Cef134NugetMediaDeviceDemo` is a standalone NuGet consumer. It references
`WebViewControl-Avalonia 3.134.178-codecs.11` and does not reference the source
projects under `WebView` or `vendor`.

From the repository root, restore and publish it with:

```powershell
dotnet restore .\samples\Cef134NugetMediaDeviceDemo\Cef134NugetMediaDeviceDemo.csproj `
  --configfile .\samples\Cef134NugetMediaDeviceDemo\NuGet.config
dotnet publish .\samples\Cef134NugetMediaDeviceDemo\Cef134NugetMediaDeviceDemo.csproj `
  -c Release -r win-x64 --self-contained true `
  -o .\dist\cef-134\win-x64\media-device-demo-nuget
```

Run `Cef134NugetMediaDeviceDemo.exe` from the publish directory. The page shows
`audioinput`, `audiooutput`, and `videoinput` entries with `label`, `deviceId`,
and `groupId`, and it records `devicechange` events. The latest report is also
written to `media-device-result.json` and the CEF log to `cef-media-device.log`.

The runtime package is still `chromiumembeddedframework.runtime.win-x64
134.3.9-codecs.1`; this Demo validates the Glue `.11` fix against that unchanged
`libcef.dll`.

The equivalent one-command publisher is:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\publish-cef134-media-device-demo.ps1 `
  -CreateZip
```

Windows does not create a virtual camera when no camera driver is installed.
Install and enable a virtual camera such as OBS Virtual Camera before running the
camera test if the machine has no physical camera.
