# CEF 106 / Windows 7 编解码兼容线

> 更新日期：2026-08-19

该产品线固定使用 **CEF branch 5249 / Chromium 106**，用于保留 Windows 7
兼容方案。它与默认的 CEF 134 主线并存；构建时显式传入
`-p:CefLine=106`。CEF 106 WebView 包面向 `net6.0`，避免默认主线
`net8.0` 本身阻断 Windows 7。

## 精确源码与包版本

| 组件 | 固定值 |
|---|---|
| CEF branch | `5249` |
| CEF checkout | `e1054005e45a4b2e18e80edd6813dcc4c018d9c9` |
| Chromium checkout | `106.0.5249.91` |
| CefGlue checkout | `OutSystems/CefGlue@393f0fb4f218e1a0f15e79055eb86ab4193a79a2` |
| CEF API version | `experimental` |
| CEF runtime | `106.0.26-codecs.1` |
| CefGlue | `106.5249.19-9n1m.1` |
| WebView | `3.120.11-cef106-codecs.1` |
| WebView TFM | `net6.0` |

API hashes：

```text
Universal: 44197292401010f8fce5b053733edd8642d01095
Windows:   95bf7fa1356070be95b7a6fee958355c6619fb63
macOS:     8ec5426d7aa0418fca147380e97623a49cd8eaf4
Linux:     b2cbc2e6a3048d2415566d35ba434967fd796491
```

必须使用上面的 checkout，不能使用会移动的 branch HEAD。否则 CefGlue 生成代码
可能与 CEF 导出的 API hash 不匹配，并在 `CefRuntime.CheckVersionByApiHash()` 失败。

## Codec 构建开关

```text
is_official_build=true
proprietary_codecs=true
ffmpeg_branding=Chrome
enable_platform_hevc=true
enable_hevc_parser_and_hw_decoder=true
```

H.264 通过 Chromium proprietary codec 路径启用。H.265/HEVC 在该版本主要是
**平台硬件解码路径**；上述开关不等于在每台 Windows、macOS、Linux、虚拟机或
ARM 设备上都提供软件 HEVC 解码器。

构建脚本会写入 `CEF_CODEC_BUILD_INFO.txt`。正式打包必须校验精确 checkout、
平台、架构和全部 GN flags。包含 `SYNTHETIC_FIXTURE=true` 的测试 fixture 默认会被
packager/verifier 拒绝，只有显式 `--allow-synthetic` 才能用于布局 smoke test。

## 平台与进程名

支持六个 RID：

- `win-x64`, `win-arm64`
- `osx-x64`, `osx-arm64`
- `linux-x64`, `linux-arm64`

BrowserProcess 的程序集/可执行文件改为：

- Windows：`CefGlueBrowserProcess/9n1m.webview.exe`
- macOS/Linux：`CefGlueBrowserProcess/9n1m.webview`

C# namespace 仍为 `Xilium.CefGlue.BrowserProcess`，以降低源代码兼容性影响。
NuGet ZIP 不能可靠保留 Unix execute bit，因此 targets 在 build/publish 后执行
`chmod +x`。

## 构建

```bash
# CEF 原生构建（需要 Chromium 级别的磁盘、内存和时间）
CEF_LINE=106 \
CEF_ARCH=x64 \
CEF_PLATFORM=Linux \
DEPOT_TOOLS_DIR=/path/to/depot_tools \
CEF_SOURCE_DIR=/large/disk/cef-106 \
./scripts/build-cef-codecs.sh

# 已有真实 binary_distrib 后打包单个 RID
python3 scripts/package-cef-runtime.py \
  --line 106 \
  --rid linux-x64 \
  --source /large/disk/cef-106/chromium/src/cef/binary_distrib \
  --version 106.0.26-codecs.1 \
  --output artifacts/feed \
  --codec-enabled
```

托管包：

```bash
./scripts/package-managed-codecs.sh \
  --line 106 \
  --feed artifacts/feed \
  --config artifacts/NuGet.Codecs.Config
```

## Windows 7 验证边界

CEF 106 是本项目保留的 Win7 CEF 线，但仍必须在真实 Windows 7 SP1 环境验证：

1. 安装并使用可运行于 Win7 的 .NET 6 runtime/apphost；
2. 验证 VC++ runtime、GPU driver、系统补丁和 native DLL loader；
3. 验证 `9n1m.webview.exe` 可启动且 renderer/GPU 子进程正常；
4. 播放真实 H.264 样本；
5. HEVC 只在系统确实暴露解码能力时判定支持。

.NET 6 已结束官方支持，因此该兼容线需要项目方自行承担运行时安全维护和部署风险。
GitHub hosted runner 不能替代 Windows 7 实机结论。

## 法律提示

H.264 与 H.265/HEVC 的分发可能涉及专利池、地区专利权、FFmpeg/Chromium/CEF
许可及商业授权。开启 GN flag **不是**专利许可。最终应用分发方必须自行完成法律
和商业许可审查。
