CEF 134 NuGet Media Device Diagnostics

1. Run Cef134NugetMediaDeviceDemo.exe.
2. The startup list shows audio input, audio output, and video input devices.
3. Click Test microphone, Test camera, or Test desktop capture.
4. Check media-device-result.json and cef-media-device.log for raw results.

Packages:
- WebViewControl-Avalonia 3.134.178-codecs.11
- CefGlue.Common/Avalonia 134.6998.178-9n1m.11
- chromiumembeddedframework.runtime.win-x64 134.3.9-codecs.1

The native runtime and libcef.dll are unchanged in this release. The media
device enumeration fix is in the CefGlue browser window runtime style.

Windows does not create a virtual camera automatically. If Video input is 0,
install and enable a physical camera driver or a virtual camera such as OBS
Virtual Camera, then click Refresh devices.
