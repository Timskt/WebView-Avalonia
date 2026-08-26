# Codec 与 BrowserProcess 更新说明

> 版本说明日期：2026-08-19

## 新功能

1. 默认产品线升级为固定的 CEF 134 / Chromium `134.0.6998.178`。
2. 保留 CEF 106 / Chromium `106.0.5249.91` 作为 Windows 7 兼容线。
3. 两条线都使用 codec GN flags 构建 H.264 与平台 HEVC/H.265 路径。
4. 代码和脚本保留 `win-x64`, `win-arm64`, `osx-x64`, `osx-arm64`, `linux-x64`,
   `linux-arm64` 的跨平台支持；本轮真实 native 交付先构建 `win-x64`。
5. BrowserProcess 从 `Xilium.CefGlue.BrowserProcess[.exe]` 改名为：
   - Windows：`9n1m.webview.exe`
   - macOS/Linux：`9n1m.webview`
6. Demo 默认打开 `https://html5test.com/`，并提供 H.264/HEVC `canPlayType()`
   preflight 按钮。
7. 新增 runtime/CefGlue/WebView/consumer 多层 package layout verifier。
8. synthetic fixture 现在默认禁止进入正式 package/release 路径。

## 包版本

| 产品线 | CEF runtime | CefGlue | WebView | TFM |
|---|---|---|---|---|
| CEF 134 默认线 | `134.3.9-codecs.1` | `134.6998.178-9n1m.11` | `3.134.178-codecs.11` | `net8.0` |
| CEF 106 Win7 线 | `106.0.26-codecs.1` | `106.5249.19-9n1m.3` | `3.120.11-cef106-codecs.3` | `net6.0` |

## 使用方式

默认 CEF 134：

```bash
dotnet restore -p:CefLine=134 -p:Platform=x64
dotnet build -c ReleaseAvalonia -p:CefLine=134 -p:Platform=x64
```

Windows 7/CEF 106：

```bash
dotnet restore -p:CefLine=106 -p:Platform=x64
dotnet build -c ReleaseAvalonia -p:CefLine=106 -p:Platform=x64
```

ARM64 使用 `-p:Platform=ARM64 -p:PlatformTarget=ARM64`。

## 兼容性与 breaking considerations

- 如果应用写死了旧 BrowserProcess 文件名或路径，必须更新为
  `CefGlueBrowserProcess/9n1m.webview[.exe]`。
- 不要修改 C# namespace；本次只修改 assembly/apphost 名称。
- CEF 106 WebView 包改为 `net6.0`，用于保留 Win7 部署可能性；.NET 6 已 EOL。
- CEF 134 使用 `net8.0`，不用于 Windows 7。
- HEVC 是平台能力，不能把 package 成功或 `canPlayType()` 非空当作真实播放成功。
- macOS 继续保留 libcef ObjC class 冲突 patch 和 ARM64 IME fix：
  `WebView/WebViewControl.Avalonia/native/osx-arm64/libFixIME.dylib`。
  原始文件 SHA-256 固定为 `bbf45fd8ee8941248d806cea89366db14eb8802219111b3b1c8eeecefe573a7a`；package/consumer verifier 会校验该哈希，防止漏包或误替换。

## 发布门禁

GitHub prerelease 仅允许在以下条件全部满足后创建：

1. 所选 CEF line 的当前 native 矩阵全部成功（本轮为 `win-x64`）；
2. runtime marker 与精确 pins/GN flags 一致；
3. synthetic marker 不存在；
4. CefGlue/WebView package verifier 通过；
5. 当前选择的 RID（本轮为 `win-x64`）NuGet consumer build/layout 通过；
6. html5test Demo managed build 通过。

真实媒体播放仍必须在目标 OS/GPU/driver 上另行验证，不由 package layout CI 代替。

## 法律提示

H.264/H.265 的专利与商业许可责任属于最终分发方。构建参数和包本身不构成专利授权。

详细的本轮 Windows-only 矩阵、脚本参数和恢复跨平台构建方法见 `docs/WINDOWS-CODEC-BUILD.md`。
