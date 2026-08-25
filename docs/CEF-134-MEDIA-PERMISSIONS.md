# CEF 134 media permissions

CEF 134 Alloy-style browsers deny camera and microphone requests by default
when no `CefPermissionHandler` is registered. WebViewControl keeps compatibility
with earlier releases by adding Chromium's `--enable-media-stream` switch by
default. This automatically grants the camera and microphone permissions
requested by `navigator.mediaDevices.getUserMedia()`.

No application change is required for the default behavior:

```csharp
var webView = new WebView();
```

To disable automatic camera and microphone permission grants, configure the
global setting before the first WebView is created:

```csharp
WebView.Settings.EnableMediaStream = false;
```

This switch controls browser permission only. Windows microphone privacy
settings, device drivers, device constraints, and hardware availability can
still cause `getUserMedia()` to fail.
