# CEF 134 主线 H.264/H.265 构建

> 更新日期：2026-08-19

CEF 134 是本仓库默认产品线。未指定 `CefLine` 时，WebView 默认构建该版本：

```bash
dotnet build WebView/WebViewControl.Avalonia/WebViewControl.Avalonia.csproj \
  -c ReleaseAvalonia -p:Platform=x64
```

## 精确源码与包版本

| 组件 | 固定值 |
|---|---|
| CEF branch | `6998` |
| CEF checkout | `5dc6f2f29c7466f6e9ab9773e36de4b28e59c1f3` |
| Chromium checkout | `134.0.6998.178` |
| CefGlue checkout | `OutSystems/CefGlue@2e308b350e2c1955dd35a0a3a5d7383cdcf76649` |
| CEF API version | `13401` |
| CEF runtime | `134.3.9-codecs.1` |
| CefGlue | `134.6998.178-9n1m.10` |
| WebView | `3.134.178-codecs.10` |
| WebView TFM | `net8.0` |

平台 API hashes：

```text
Windows: 751255204f006b8b883a8baf552a2da792f8aa44
macOS:   b54732b528bc2669481ec0cf17c7b97b033720b9
Linux:   b14bee2c0fd250da67faea421f620b58e5dea9a2
```

## Codec flags

```text
is_official_build=true
proprietary_codecs=true
ffmpeg_branding=Chrome
enable_platform_hevc=true
enable_hevc_parser_and_hw_decoder=true
chrome_pgo_phase=0
```

- `chrome_pgo_phase=0`：关闭依赖额外下载 `.profdata` 的 PGO 优化，避免固定源码缺失 profile 时 GN 生成失败。
- H.264：启用 Chromium proprietary codec/Chrome FFmpeg branding 路径。
- H.265/HEVC：启用 parser 和平台硬件解码路径。
- HEVC 结果依赖操作系统、GPU、driver、系统媒体组件和 Chromium 对该平台的实现。
- 不承诺 Linux 机器、虚拟机或无硬件能力的 ARM 板卡具有通用软件 HEVC 解码。

## 平台、包和 BrowserProcess

运行时 RID：

```text
win-x64       chromiumembeddedframework.runtime.win-x64
win-arm64     chromiumembeddedframework.runtime.win-arm64
osx-x64       cef.redist.osx64
osx-arm64     cef.redist.osx.arm64
linux-x64     cef.redist.linux64
linux-arm64   cef.redist.linuxarm64
```

CefGlue/WebView 各生成 x64 和 ARM64 两组包；每组依赖三个对应平台的 runtime 包。
BrowserProcess 部署名为：

```text
Windows:      CefGlueBrowserProcess/9n1m.webview.exe
macOS/Linux:  CefGlueBrowserProcess/9n1m.webview
```

程序集名已改为 `9n1m.webview`，但 namespace 保持
`Xilium.CefGlue.BrowserProcess`。macOS/Linux targets 会补 execute bit。

## 构建和验证

```bash
# 真实 CEF 构建
CEF_LINE=134 CEF_ARCH=arm64 CEF_PLATFORM=macOS \
DEPOT_TOOLS_DIR=/path/to/depot_tools \
CEF_SOURCE_DIR=/large/disk/cef-134 \
./scripts/build-cef-codecs.sh

# 单 RID runtime 打包
python3 scripts/package-cef-runtime.py \
  --line 134 --rid osx-arm64 \
  --source /large/disk/cef-134/chromium/src/cef/binary_distrib \
  --version 134.3.9-codecs.1 \
  --output artifacts/feed --codec-enabled

# CefGlue + WebView
./scripts/package-managed-codecs.sh \
  --line 134 --feed artifacts/feed --config artifacts/NuGet.Codecs.Config

# 真实 NuGet consumer 的六 RID 输出布局
./scripts/verify-nuget-consumer.sh \
  --line 134 --config artifacts/NuGet.Codecs.Config --work artifacts/consumer
```

## 已验证与未验证

本地 synthetic smoke test 可以验证：

- 12 个 runtime package 的布局和 marker 规则；
- CefGlue/WebView 的两个架构包；
- 六 RID 的 `9n1m.webview[.exe]` 部署路径；
- Unix execute bit；
- Demo/consumer managed build。

它不能证明 native CEF 能加载，也不能证明 H.264/H.265 实际解码。只有使用真实
codec-enabled CEF binary，并执行 `docs/MEDIA-CODEC-VALIDATION.md` 中的播放测试，
才能形成运行时结论。

## 法律提示

H.264/H.265 可能涉及专利和商业许可。项目分发方负责确认所在地区、用途、终端数量、
编码/解码场景以及 Chromium/CEF/FFmpeg 许可义务。此仓库仅提供构建技术路径，不提供
任何专利许可或法律保证。
