# CEF 134 media permissions

CEF 134 Alloy-style browsers deny media requests by default when no
`CefPermissionHandler` is registered. WebViewControl registers an internal
permission handler by default and automatically grants camera, microphone,
desktop video, and desktop audio requests.

No application change is required for the default behavior:

```csharp
var webView = new WebView();
```

To disable automatic camera and microphone permission grants, configure the
global setting before the first WebView is created:

```csharp
WebView.Settings.EnableMediaStream = false;
```

Desktop capture is enabled by default as well:

```csharp
WebView.Settings.EnableDesktopCapture = true;
```

To disable desktop video and system audio capture:

```csharp
WebView.Settings.EnableDesktopCapture = false;
```

`getDisplayMedia()` still needs to be called from a user gesture. The optional
source switch can automatically choose a source whose title matches the value:

```csharp
WebView.Settings.DesktopCaptureSource = "Entire screen";
```

Set `DesktopCaptureSource` to `null` or an empty string to keep Chromium's
normal desktop source picker. Automatic permission does not bypass Windows
privacy policy, source availability, or user-gesture requirements.

These settings control browser permission only. Windows microphone privacy
settings, device drivers, device constraints, source availability, and
hardware availability can still cause capture requests to fail.

## Hardware acceleration

Hardware acceleration is enabled by default. The settings must be assigned
before the first WebView is created:

```csharp
WebView.Settings.EnableGpuAcceleration = true;
WebView.Settings.EnableHardwareVideoDecoding = true;
WebView.Settings.EnableHardwareVideoEncoding = true;
```

To disable a capability:

```csharp
WebView.Settings.EnableGpuAcceleration = false;
WebView.Settings.EnableHardwareVideoDecoding = false;
WebView.Settings.EnableHardwareVideoEncoding = false;
```

These options control Chromium switches only. Actual hardware use still
depends on the operating system, GPU driver, codec profile, and CEF build.
There is no general CEF switch for "hardware audio acceleration". Audio input
and output use the platform audio stack; device permissions and endpoint
availability are separate from GPU/video acceleration.
