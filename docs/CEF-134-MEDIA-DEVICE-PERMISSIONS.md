# CEF 134 Media Device Permissions

## Symptom

CEF 134 could successfully open the default microphone while
`navigator.mediaDevices.enumerateDevices()` continued to expose only anonymous
audio devices. Applications that converted the empty device ID to an exact
constraint then failed with `OverconstrainedError`.

## Root Cause

CEF 134 treats an unspecified window runtime style as Chrome style when the
Chrome bootstrap is used. The Chrome runtime forwards
`RequestMediaAccessPermission` to the CEF permission handler, but its separate
`CheckMediaAccessPermission` path still consults Chrome content settings.

The result was inconsistent permission state:

- `getUserMedia({ audio: true })` was allowed by the CEF handler;
- `enumerateDevices()` considered the same origin unapproved and removed IDs
  and labels;
- an exact empty device ID could not match the default device.

The warning about `media.default_audio_capture_device` is not evidence of a
WASAPI enumeration failure. CEF logs and direct tests showed that the real
capture devices and the default WASAPI input stream were available.

## Fix

`CefGlue.Common 134.6998.178-9n1m.11` explicitly creates normal child browsers
with `CefRuntimeStyle.Alloy`. Alloy uses CEF's media permission implementation
for both permission requests and permission checks, restoring consistent device
enumeration without fake-media command-line switches.

`WebViewControl-Avalonia 3.134.178-codecs.11` keeps automatic media permission
handling enabled through `WebView.Settings.EnableMediaStream`, which defaults to
`true`. Applications do not need to implement an additional permission handler.

The native runtime remains `134.3.9-codecs.1`; its `libcef.dll` is unchanged.

## Application Guidance

Applications should still avoid exact empty constraints. Prefer one of:

```javascript
navigator.mediaDevices.getUserMedia({ audio: true })
```

```javascript
navigator.mediaDevices.getUserMedia({
  audio: { deviceId: selectedDeviceId || undefined }
})
```

If a saved device no longer exists, retry once without `deviceId`. This handles
normal device removal and profile changes independently of the CEF fix.
