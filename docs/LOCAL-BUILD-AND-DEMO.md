# 本机编译、macOS Demo 与 CEF 原生构建边界

> 更新日期：2026-08-19

本文记录本项目在开发机上的可行验证方式，以及为什么不能把本机 macOS
构建结果当作 Windows codec runtime 交付结果。

## 结论先行

| 项目 | 当前结论 |
|---|---|
| Avalonia/CefGlue 托管代码 | 可以在本机 macOS ARM64 编译、打包和做 consumer/layout 验证 |
| macOS ARM64 原生 CEF | 本机理论上可以原生编译，但需要 Chromium/CEF 全源码、数百 GB 临时空间和数小时；本轮没有启动这项长任务 |
| Windows `libcef.dll` | Apple Silicon Mac 不能可靠地交叉编译 Windows CEF；应使用 Windows x64 self-hosted runner 或专用 Windows 构建机 |
| 本轮真实 codec native 产物 | 未完成。GitHub hosted runner 的 CEF 106/134 checkout 在 `gclient` 长时间无输出后被取消，因此不能宣称 H.264/H.265 已在 Windows 实际播放 |
| 本机 macOS Demo | 已用真实 stock CEF 134 ARM64 runtime 验证 UI、CEF 子进程改名和 IME 文件保留；该 Demo **不是** codec build 证明 |

## 为什么 GitHub Actions 会长时间停在 `gclient`

CEF 构建不是普通 .NET restore/build。`automate-git.py` 会同步 Chromium 的超大源码和
Git 对象，然后生成 GN、编译大量 C++ 目标。GitHub hosted runner 是临时机：任务取消
后 checkout、对象库和编译中间文件都会丢失。日志中的：

```text
Checking objects: 100% (67108864/67108864), done.
STALL DETECTED: gclient has been silent for 5 minutes.
Currently active tasks: src (Running ...)
```

不一定代表死锁，可能仍在 Git 校验、解包或磁盘 I/O；但 hosted runner 没有持久化缓存，
继续等待的成本很高。本仓库的构建 wrapper 现在会：

- 设置 `GIT_TERMINAL_PROMPT=0`，避免认证提示把任务挂住；
- 每 300 秒输出 CEF checkout/build heartbeat、磁盘剩余空间、源码目录大小、相关 Git/
  gclient/ninja 进程；
- 通过 `CEF_DIAGNOSTIC_INTERVAL_SECONDS` 可调整 heartbeat 周期；
- 只保留本轮交付的 `CEF 106/win-x64` 和 `CEF 134/win-x64` 矩阵。

## 远程构建复盘（2026-08-19）

我重新检查了 GitHub Actions 运行记录：

- `32251941588` 使用提交 `18a249c3`，`CEF 106 / win-x64` 与 `CEF 134 / win-x64`
  都停留在 `Build exact pinned CEF with codec paths`，最终于
  `2026-08-19 14:51:52 UTC` 取消；没有 runtime artifact，也没有 NuGet 包。
- Windows 日志显示 Chromium `src` clone 由远端发送约 `73.66 GiB`，对象检查数量为
  `67,108,864`。CEF 134 在对象检查完成后仍长时间处于 `gclient` 的 `src` 任务；CEF 106
  还出现多次 `git fetch origin` 重试并重新 clone。
- 日志开头还显示全新 Windows runner 没有 `C:/Users/runneradmin/.gitconfig`。这不是主因，
  但会产生误导性的 fatal-looking warning。当前 workflow 已在 depot_tools 之前创建最小的
  全局 Git 配置，并设置 Chromium 推荐的 checkout 参数。
- 在最新提交上手动运行 `32269156668`（`build_cef=false`）已通过 workflow 输入、脚本、
  精确 CEF 106/134 配置和 YAML 路径验证；它没有执行 native CEF checkout，因此不能替代
  Windows 原生构建验证。

结论是：问题不是 .NET 编译，而是 hosted runner 每次从空目录下载约 74 GiB 的 Chromium
Git 数据，且任务结束后缓存全部丢失。下一次真实构建应使用持久化 Windows runner，并先只构建
CEF 106；确认 runtime 包生成后再构建 CEF 134。

## 推荐的 Windows 构建方式

使用持久化的 Windows 10/11 或 Windows Server x64 构建机：

- 32--64 GB RAM；
- NVMe 可用空间至少 250--400 GB，建议更大；
- Visual Studio C++ 工具链、Windows SDK、Python、Git、depot_tools；
- 长期保留 depot_tools、CEF/Chromium checkout、Git object cache 和 `out/Release`；
- CEF 106、CEF 134 使用独立目录，不要并行首次 checkout；先完成 106，再完成 134。

建议把流程拆为 checkout/sync、GN generate、compile、package、verify 五个阶段。首次
同步仍可能耗时很久，但之后重试和修改 GN 参数可以复用对象库与编译结果，这比每次从
hosted runner 的临时目录重新开始可靠得多。

## 本机托管代码构建

默认 CEF 134 / .NET 8 / ARM64：

```bash
cd WebView

dotnet restore SampleWebView.Avalonia/SampleWebView.Avalonia.csproj \
  -r osx-arm64 -p:CefLine=134

dotnet build SampleWebView.Avalonia/SampleWebView.Avalonia.csproj \
  -c ReleaseAvalonia -p:Platform=ARM64 -p:CefLine=134
```

Windows 7 兼容线使用 CEF 106 / .NET 6：

```bash
cd WebView

dotnet restore SampleWebView.Avalonia/SampleWebView.Avalonia.csproj \
  -r win-x64 -p:CefLine=106 -p:Platform=x64

dotnet build SampleWebView.Avalonia/SampleWebView.Avalonia.csproj \
  -c ReleaseAvalonia -p:Platform=x64 -p:CefLine=106
```

第二组命令只能在 Windows x64 上完成真实 Windows runtime 验证；在 Mac 上只能验证
项目文件、托管引用和静态脚本逻辑，不能生成可交付的 `libcef.dll`。

## Demo 行为

Demo 默认打开：

```text
https://html5test.com/
```

窗口提供：

- `Check H.264/HEVC`：调用 `HTMLVideoElement.canPlayType()` 做能力预检；
- `Show DevTools`：查看 `chrome://gpu`、console 和媒体错误；
- 地址栏和前进/后退操作。

为了让开发机 Demo 不弹出 Chromium Safe Storage 钥匙串授权框，Demo 在 CEF 初始化前
加入：

```text
--password-store=basic
--use-mock-keychain
```

这是 Demo 的本地运行策略，不会强制业务应用使用 mock keychain。业务应用仍可通过
`WebView.Settings.AddCommandLineSwitch` 自行设置策略。

## 如何区分 stock Demo 与 codec Demo

本机 Demo 目录可以写入 `DEMO_RUNTIME_INFO.txt`：

```text
DEMO_TYPE=stock-cef
CODEC_BUILD_VERIFIED=false
```

只有同时满足以下条件，才可以把 runtime 称为本轮 codec native build：

1. runtime 包含真实的 `CEF_CODEC_BUILD_INFO.txt`；
2. marker 中的 CEF/Chromium exact pin 与 `config/cef-lines.json` 完全一致；
3. marker 包含全部 codec GN flags；
4. 不存在 `SYNTHETIC_FIXTURE=true`；
5. `verify-package-layout.py` 与 `verify-nuget-consumer.sh` 通过；
6. 在目标 Windows 7/Windows 10 设备上实际播放授权测试视频。

`canPlayType()` 返回 `maybe` 或 `probably` 只能作为预检，不能代替真实视频播放。
尤其 HEVC/H.265 还受 Windows HEVC 组件、GPU、驱动、profile 和硬件能力影响。

## macOS 兼容项验收

CEF 134 ARM64 Demo/包必须保留：

```text
WebView/WebViewControl.Avalonia/native/osx-arm64/libFixIME.dylib
SHA-256: bbf45fd8ee8941248d806cea89366db14eb8802219111b3b1c8eeecefe573a7a
```

并在构建 target 中保留：

```text
ExtensionDropdownHandler -> CEFExtensionDropdownHand
codesign --force --sign - <patched libcef.dylib>
```

检查命令：

```bash
file <demo>/libcef.dylib <demo>/CefGlueBrowserProcess/9n1m.webview
ps -axo pid,ppid,command | grep -E '[9]n1m.webview'
shasum -a 256 <demo>/libFixIME.dylib
```

验证时应看到 macOS 子进程名为 `9n1m.webview`，而不是旧的
`Xilium.CefGlue.BrowserProcess`；IME dylib 的哈希必须与上面的固定值一致。

## 本次构建事故处理记录

Run `32251941588` 的两个 native job 均在 CEF checkout/build 阶段运行约 2 小时 33 分钟，
没有生成 runtime artifact，随后主动取消。该次运行的取消不代表源码或 pipeline 失败，
但它证明 GitHub hosted runner 不适合本项目的首次 CEF 全量 checkout。后续应在持久化
Windows runner 上单独运行 CEF 106，再运行 CEF 134，并保留 heartbeat/诊断输出。
