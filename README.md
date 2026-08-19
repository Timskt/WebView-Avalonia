# WebView-Avalonia codec builds

本分支维护两条固定 CEF 产品线，并为 Windows、macOS、Linux 的 x64/ARM64
构建 H.264 与平台 H.265/HEVC 路径：

- 默认：CEF 134，`-p:CefLine=134`，WebView `net8.0`
- Windows 7 兼容线：CEF 106，`-p:CefLine=106`，WebView `net6.0`
- BrowserProcess：`9n1m.webview.exe`（Windows）或 `9n1m.webview`（macOS/Linux）

文档：

- `docs/CEF-106-CODECS.md`
- `docs/CEF-134-CODECS.md`
- `docs/RELEASE-NOTES-CODECS-AND-SUBPROCESS.md`
- `docs/CEF-CODEC-MAINTENANCE-GUIDE.md`
- `docs/MEDIA-CODEC-VALIDATION.md`
- `docs/LOCAL-BUILD-AND-DEMO.md`

> H.265 依赖平台硬件/系统媒体能力；H.264/H.265 分发可能涉及专利和商业许可。
