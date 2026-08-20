# Windows / Linux 物理机一键构建手册

> 更新日期：2026-08-20
> 适用分支：`feature/h264-h265-codecs`

本文说明如何在**真实 Windows 或 Linux 物理机**上构建本仓库固定的 CEF 106/134，
生成带 H.264 与平台 H.265/HEVC 路径的原生 CEF runtime、CefGlue/WebView NuGet、
`html5test.com` Demo、校验文件和完整交付压缩包。

## 1. 先理解构建边界

### 1.1 必须在目标系统本机构建

| 目标产物 | 构建主机 | 典型 RID |
|---|---|---|
| Windows DLL/EXE | Windows 10/11 x64 物理机 | `win-x64` |
| Linux SO/ELF | Linux 物理机 | `linux-x64` |
| macOS dylib/Mach-O | macOS 物理机 | `osx-x64` / `osx-arm64` |

本仓库的一键脚本不会把普通 Linux Docker 构建伪装成 Windows CEF 交叉编译。
Linux 主机运行 `build-linux.sh` 只会输出 Linux runtime；Windows runtime 应在 Windows
主机运行 `build-windows.ps1`。如果必须由 Linux 统一调度 Windows 构建，推荐让 Linux
通过 CI、SSH/WinRM 或虚拟化管理一台 Windows self-hosted builder，而不是用 MinGW
替代 Chromium 的 Windows 工具链。

### 1.2 两条固定产品线

| CEF line | CEF branch | Chromium | WebView TFM | 主要用途 |
|---:|---:|---:|---:|---|
| `106` | `5249` | `106.0.5249.91` | `net6.0` | Windows 7 兼容交付线 |
| `134` | `6998` | `134.0.6998.178` | `net8.0` | Windows 10/现代系统主线 |

CEF 106 的**构建主机仍应是 Windows 10 或更高版本**；“Windows 7 兼容线”指最终产物
需要在 Windows 7 SP1 实机做运行验收，不表示应在 Windows 7 上编译 Chromium。

两条线都固定启用以下 GN 参数：

```text
is_official_build=true
proprietary_codecs=true
ffmpeg_branding=Chrome
enable_platform_hevc=true
enable_hevc_parser_and_hw_decoder=true
```

H.264 使用 Chromium proprietary codec 路径。H.265/HEVC 是平台解析和硬件解码路径，
实际播放仍受操作系统媒体组件、GPU、驱动、视频 profile 和授权条件影响。构建成功不等于
所有设备上都能软件解码 HEVC。

## 2. 推荐硬件与磁盘布局

### 2.1 推荐配置

- CPU：x86-64，至少 8 核，推荐 16 核以上；
- RAM：至少 16 GiB，推荐 32–64 GiB；
- 磁盘：SSD/NVMe；
- 单条 CEF line 的新缓存建议预留至少 250 GiB；
- 脚本的硬门槛是 120 GiB 可用空间，低于此值默认停止；
- Windows 缓存盘必须使用 NTFS，不要使用 FAT32；
- 同时保留 CEF 106 和 134 时，建议给缓存盘预留 400–600 GiB。

缓存和交付目录必须分开：

```text
D:\cef-cache                 # Windows：源码、Git objects、out/Release
D:\cef-artifacts             # Windows：最终交付文件
/mnt/nvme/cef-cache          # Linux：源码和编译缓存
/mnt/nvme/cef-artifacts      # Linux：最终交付文件
```

`.cef-cache` 很大，但可以让中断后的重跑继续复用。不要把它提交到 Git，也不要每次成功后
立即删除。`artifacts` 是可复制到其他电脑的最终结果。

## 3. Windows 环境准备

### 3.1 通用软件

安装：

1. Git for Windows，并确保包含 Git Bash；
2. Python **3.8 或更高版本**；Windows Python 常见命令名是 `python`，脚本会自动兼容 `python3`/`python`；
3. .NET SDK：
   - CEF 106：安装 .NET 6 SDK；
   - CEF 134：安装 .NET 8 SDK；
   - `-Line both`：两者都安装；
4. 足够大的 NTFS SSD。

确认：

```powershell
git --version
bash --version
python --version
# 必须是 3.8+
dotnet --list-sdks
```

### 3.2 CEF 106 / Chromium 106 工具链

安装 **Visual Studio 2019**，包含：

- Desktop development with C++；
- MFC/ATL support；
- Windows 10 SDK `10.0.20348.0` 或更高版本；
- Debugging Tools for Windows。

脚本对 CEF 106 设置：

```text
DEPOT_TOOLS_WIN_TOOLCHAIN=0
GYP_MSVS_VERSION=2019
```

这表示使用本机 Visual Studio/Windows SDK，而不是 Google 内部工具链。

### 3.3 CEF 134 / Chromium 134 工具链

安装 **Visual Studio 2022**，包含：

- Desktop development with C++；
- MFC/ATL support；
- Windows SDK `10.0.22621.0` 或更高版本；
- Debugging Tools for Windows。

脚本对 CEF 134 设置：

```text
DEPOT_TOOLS_WIN_TOOLCHAIN=0
GYP_MSVS_VERSION=2022
```

要在同一台机器运行 `-Line both`，建议 Visual Studio 2019 和 2022 并存，并同时保留上述
两个 Windows SDK。预检通过 `vswhere.exe` 按版本范围分别查找，不会只接受最新 VS。

### 3.4 Windows 首次预检

在仓库根目录打开 PowerShell：

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\scripts\build-windows.ps1 `
  -Line both `
  -Rid win-x64 `
  -Cache D:\cef-cache `
  -Output D:\cef-artifacts `
  -PreflightOnly
```

也可从 CMD 使用：

```bat
scripts\build-windows.cmd -Line both -Rid win-x64 -Cache D:\cef-cache -Output D:\cef-artifacts -PreflightOnly
```

预检会生成：

```text
D:\cef-artifacts\cef-106\win-x64\PHYSICAL_BUILD_PREFLIGHT.json
D:\cef-artifacts\cef-134\win-x64\PHYSICAL_BUILD_PREFLIGHT.json
```

重点确认 `ok: true`，并检查：

- `host_os` 是 `Windows`；
- `host_arch` 是 `x64`；
- 两个 .NET SDK 都已识别；
- CEF 106 找到 VS 2019 和 SDK 10.0.20348.0+；
- CEF 134 找到 VS 2022 和 SDK 10.0.22621.0+；
- cache volume 有足够可用空间。

### 3.5 Windows 一键正式构建

推荐先逐条构建，便于定位问题：

```powershell
# Windows 7 兼容产物
.\scripts\build-windows.ps1 `
  -Line 106 `
  -Rid win-x64 `
  -Cache D:\cef-cache `
  -Output D:\cef-artifacts

# Windows 10/现代 Windows 产物
.\scripts\build-windows.ps1 `
  -Line 134 `
  -Rid win-x64 `
  -Cache D:\cef-cache `
  -Output D:\cef-artifacts
```

两条一起顺序执行：

```powershell
.\scripts\build-windows.ps1 -Line both -Rid win-x64 -Cache D:\cef-cache -Output D:\cef-artifacts
```

双击入口是 `scripts\build-windows.cmd`，但正式构建建议在终端执行，以便看到报错和日志。

## 4. Linux 环境准备

### 4.1 推荐系统

- CEF 106 legacy 构建环境：优先 Ubuntu 20.04 x64 或等价兼容环境；
- CEF 134：优先 Ubuntu 22.04 x64 或相近环境；
- 非 Debian/Ubuntu 发行版可以使用，但需要自行映射依赖包名；
- ARM64 必须使用真实 ARM64 Linux 主机；不要在 Apple Silicon 上用 amd64 模拟器做长期
  Chromium 全量编译。

### 4.2 安装 .NET SDK

安装与产品线匹配的 SDK：

```bash
dotnet --list-sdks
# CEF 106 需要 6.x
# CEF 134 需要 8.x
```

### 4.3 Linux 一键预检

```bash
chmod +x scripts/*.sh scripts/lib/*.sh

./scripts/build-linux.sh \
  --line both \
  --rid linux-x64 \
  --cache /mnt/nvme/cef-cache \
  --output /mnt/nvme/cef-artifacts \
  --preflight-only
```

`--rid auto` 会根据当前 Linux CPU 自动选择 `linux-x64` 或 `linux-arm64`：

```bash
./scripts/build-linux.sh --line 134 --rid auto --preflight-only
```

### 4.4 安装 Linux bootstrap 依赖并构建

Ubuntu/Debian 可让脚本调用 `apt-get`：

```bash
./scripts/build-linux.sh \
  --install-deps \
  --line 134 \
  --rid linux-x64 \
  --cache /mnt/nvme/cef-cache \
  --output /mnt/nvme/cef-artifacts
```

如果依赖已经安装，去掉 `--install-deps`：

```bash
./scripts/build-linux.sh \
  --line 134 \
  --rid linux-x64 \
  --cache /mnt/nvme/cef-cache \
  --output /mnt/nvme/cef-artifacts
```

构建两条线：

```bash
./scripts/build-linux.sh \
  --line both \
  --rid linux-x64 \
  --cache /mnt/nvme/cef-cache \
  --output /mnt/nvme/cef-artifacts
```

脚本顺序执行 CEF 106、CEF 134，避免两个 Chromium 编译同时耗尽内存和磁盘 I/O。

## 4.5 macOS 物理机构建（保留 IME 修复）

虽然本次交付重点是 Windows 7/10 x64 与 Linux x64，仓库仍支持在 macOS 物理机生成
`osx-x64`/`osx-arm64` 产物。macOS 不能生成 Windows CEF DLL；请使用本机 RID：

```bash
# Apple Silicon
./scripts/build-physical.sh \
  --line 134 --rid osx-arm64 \
  --cache /Volumes/Build/cef-cache \
  --output /Volumes/Build/cef-artifacts

# Intel Mac
./scripts/build-physical.sh \
  --line 134 --rid osx-x64 \
  --cache /Volumes/Build/cef-cache \
  --output /Volumes/Build/cef-artifacts
```

构建前会检查仓库中的 `libFixIME.dylib`。该文件属于已有的 macOS 输入法冲突修复，
不能因为重新打包 CEF 或更新 WebView package 而删除。

## 5. 一键脚本实际执行的阶段

`build-windows.ps1`、`build-windows.cmd` 和 `build-linux.sh` 最终统一进入：

```text
build-physical.sh
  -> preflight-physical-build.py
  -> build-portable-codec-bundle.sh
      -> clone/reuse depot_tools
      -> build-cef-codecs.sh
      -> automate-git.py checkout exact CEF/Chromium
      -> verify generated args.gn codec flags
      -> package-cef-runtime.py
      -> verify-package-layout.py runtime verification
      -> package-managed-codecs.sh
      -> verify-nuget-consumer.sh
      -> dotnet publish html5test demo
      -> build-manifest.json + SHA256SUMS
      -> platform delivery archive + .sha256
```

原生构建 marker 必须是：

```text
CEF_CODEC_BUILD_INFO.txt
```

正式流程拒绝包含下列内容的测试 fixture：

```text
SYNTHETIC_FIXTURE=true
```

## 6. 输出目录与成品说明

以 CEF 134 / Windows x64 为例：

```text
D:\cef-artifacts\
├─ logs\
│  └─ cef-134-win-x64-YYYYMMDD-HHMMSS.log
├─ cef-134\
│  └─ win-x64\
│     ├─ nuget\
│     │  ├─ chromiumembeddedframework.runtime.win-x64.134.3.9-codecs.1.nupkg
│     │  ├─ CefGlue.Common.134.6998.178-9n1m.1.nupkg
│     │  ├─ CefGlue.Avalonia.134.6998.178-9n1m.1.nupkg
│     │  └─ WebViewControl-Avalonia.3.134.178-codecs.1.nupkg
│     ├─ demo\
│     │  ├─ SampleWebView.Avalonia.exe
│     │  ├─ CefGlueBrowserProcess\9n1m.webview.exe
│     │  ├─ libcef.dll
│     │  └─ ... CEF resources
│     ├─ html5test-demo-win-x64.tar.gz
│     ├─ CEF_CODEC_BUILD_INFO.txt
│     ├─ PHYSICAL_BUILD_PREFLIGHT.json
│     ├─ NuGet.Codecs.Config
│     ├─ build-manifest.json
│     └─ SHA256SUMS
├─ cef-134-win-x64-bundle.zip
└─ cef-134-win-x64-bundle.zip.sha256
```

Linux 完整交付包使用：

```text
cef-134-linux-x64-bundle.tar.gz
cef-134-linux-x64-bundle.tar.gz.sha256
```

### 6.1 交付前校验

Windows PowerShell：

```powershell
Get-FileHash D:\cef-artifacts\cef-134-win-x64-bundle.zip -Algorithm SHA256
Get-Content D:\cef-artifacts\cef-134-win-x64-bundle.zip.sha256
```

Linux：

```bash
cd /mnt/nvme/cef-artifacts
sha256sum -c cef-134-linux-x64-bundle.tar.gz.sha256
```

`build-manifest.json` 记录：

- CEF line 和 RID；
- 仓库 commit；
- 构建时仓库是否有未提交修改；
- UTC 生成时间；
- 每个成品文件的大小和 SHA-256；
- `synthetic: false`。

## 7. 中断、重跑和复用缓存

### 7.1 checkout/build 中断

使用**完全相同的 `-Cache`/`--cache` 目录重新执行同一命令**。脚本会复用 depot_tools、
Chromium Git object、CEF checkout 和已有构建输出。不要删除缓存，也不要换目标 RID。

`gclient` 长时间无新日志不一定是死锁。脚本每 5 分钟输出 heartbeat，包括磁盘占用和
活跃 git/gclient/ninja 进程。判断是否真的卡住时同时观察：

- git/python/ninja 的 CPU；
- cache 目录大小是否变化；
- SSD 读写；
- 网络流量；
- 是否存在凭据弹窗；
- 是否有 Git lock 文件或磁盘已满。

### 7.2 native 已成功，只重做打包

如果 `binary_distrib/CEF_CODEC_BUILD_INFO.txt` 已存在且真实有效，可跳过多小时原生构建：

Windows：

```powershell
.\scripts\build-windows.ps1 -Line 134 -Rid win-x64 -Cache D:\cef-cache -Output D:\cef-artifacts -SkipNative
```

Linux：

```bash
./scripts/build-linux.sh --line 134 --rid linux-x64 \
  --cache /mnt/nvme/cef-cache --output /mnt/nvme/cef-artifacts --skip-native
```

`--skip-native` 不会放宽 marker 检查；版本、平台、架构、GN flags 或 synthetic 标记不匹配
仍会失败。

### 7.3 低磁盘覆盖

只有在缓存中已经存在绝大部分 checkout，且你确认空间足够时才使用：

```text
-AllowLowDisk       # PowerShell
--allow-low-disk    # Bash
```

这个参数只跳过本项目的 120 GiB 预检门槛，不会解决真实的磁盘不足。

## 8. Demo 和 H.264/H.265 实机验证

Demo 默认打开：

```text
https://html5test.com/
```

运行：

```powershell
D:\cef-artifacts\cef-134\win-x64\demo\SampleWebView.Avalonia.exe
```

```bash
/mnt/nvme/cef-artifacts/cef-134/linux-x64/demo/SampleWebView.Avalonia
```

Demo 中：

1. 点击 `Check H.264/HEVC`；
2. 记录 `canPlayType()` 的 H.264/H.265 结果；
3. 打开 DevTools 检查 console/media 错误；
4. 再播放你有权使用的真实 H.264 MP4 和 H.265/HEVC 样本；
5. 确认画面、声音、时间轴持续推进，而不只是 `canPlayType()` 返回 `maybe`；
6. Windows 可进一步检查 `chrome://gpu` 和系统 HEVC 组件状态。

必须分别验收：

- CEF 106：Windows 7 SP1 目标机；
- CEF 134：Windows 10/11 目标机；
- Linux：最终部署发行版、桌面环境、GPU/驱动组合。

`html5test.com` 是能力预检站点，不是 HEVC 在所有平台都可播放的证明。

## 9. 项目兼容项检查

### 9.1 BrowserProcess 名称

最终 Demo/consumer 输出必须包含：

```text
Windows: CefGlueBrowserProcess/9n1m.webview.exe
Linux:   CefGlueBrowserProcess/9n1m.webview
```

不得残留旧文件：

```text
Xilium.CefGlue.BrowserProcess.exe
Xilium.CefGlue.BrowserProcess
```

C# namespace 仍保留：

```text
Xilium.CefGlue.BrowserProcess
```

### 9.2 macOS IME 修复不能删除

虽然本文重点是 Windows/Linux 物理机，仓库仍必须保留：

```text
WebView/WebViewControl.Avalonia/native/osx-arm64/libFixIME.dylib
SHA-256: bbf45fd8ee8941248d806cea89366db14eb8802219111b3b1c8eeecefe573a7a
```

NuGet verifier 会检查该 arm64 Mach-O 文件及固定哈希；不要在 Windows/Linux 改动中删除。

## 10. 常见故障

### 10.1 `python3: command not found`

Windows 常只有 `python.exe`。新脚本会自动选择 `python3` 或 `python`。如果需要强制：

```powershell
$env:PYTHON_BIN = 'python'
```

### 10.2 `Visual Studio ... required`

确认对应 VS 版本已安装，且包含 Desktop C++ 和 MFC/ATL。CEF 106 默认找 VS 2019；
CEF 134 默认找 VS 2022。安装后重新打开终端再运行预检。

### 10.3 `Windows SDK ... required`

CEF 106 和 134 使用不同的最低 SDK 基线。确认 Visual Studio Installer 或独立 SDK 安装器中已安装
对应版本，且 `C:\Program Files (x86)\Windows Kits\10\Include\<version>` 存在。

### 10.4 `Debugging Tools for Windows ... required`

在 Windows SDK 安装项中执行 Change/Modify，勾选 Debugging Tools for Windows。
预检检查 `Windows Kits\10\Debuggers\x64\cdb.exe`。

### 10.5 `dep_type: gcs` / `Missing keys: packages`

这通常表示旧 CEF 106 depot_tools 错误解析了 Chromium main。当前 wrapper 会：

- 将 Chromium URL 固定到 `refs/tags/106.0.5249.91`；
- 给 automate 脚本的首次 gclient sync 加 `--no-history`；
- 在 automate 参数不再兼容时提前失败。

不要手工删除这些 pin，也不要把 checkout 改回移动的 branch HEAD。

### 10.6 还原时出现 `NU1903 System.Text.Json 6.0.1`

当前 vendored CefGlue 两条产品线都固定使用 `System.Text.Json 6.0.1`，NuGet 还原可能报告
GitHub Advisory `GHSA-8g4q-xg66-9fp4` 的高严重性漏洞。这是现有 CefGlue 依赖基线的已知
警告，不是本次 CEF codec 打包脚本引入的编译错误；本次没有擅自升级它，以免改变 CEF 106
/ CEF 134 的兼容性。正式发布前请按你的安全策略评估：

- 如果只是验证构建，可记录该 warning，并确认最终没有 error；
- 如果要修复，分别在 CEF 106 和 134 做完整 restore/build/pack/consumer 验证；
- 不要仅为了消除 warning 直接修改 vendored `Directory.Packages.props` 并发布。

### 10.7 H.264 正常但 H.265 失败

这不一定是打包失败。检查：

- Windows HEVC 系统扩展/媒体组件；
- GPU 是否支持样本的 HEVC profile/level/bit depth；
- 驱动；
- 是否在远程桌面、虚拟机或无 GPU 环境；
- Linux VA-API/Vulkan/驱动能力；
- 样本封装与 MIME type。

先查看 `CEF_CODEC_BUILD_INFO.txt` 和 `args.gn` 校验，再做目标机媒体诊断。

### 10.8 Python 版本过低

物理机构建预检与打包工具支持 Python 3.8+（含 Ubuntu 20.04 默认 Python 3.8）。若提示版本过低，请升级
Python 后重新打开终端，再运行同一个预检命令。

## 11. 发布门禁清单

只有以下项目全部通过，才应把文件交给其他项目使用：

- [ ] `PHYSICAL_BUILD_PREFLIGHT.json` 的 `ok` 为 `true`；
- [ ] `CEF_CODEC_BUILD_INFO.txt` 精确匹配 CEF/Chromium pins；
- [ ] marker 包含全部 5 个 codec GN flags；
- [ ] marker 不含 `SYNTHETIC_FIXTURE=true`；
- [ ] runtime NuGet layout verifier 通过；
- [ ] CefGlue/WebView managed pack 通过；
- [ ] consumer restore/build/layout verifier 通过；
- [ ] 子进程名称为 `9n1m.webview(.exe)`；
- [ ] macOS IME dylib 仍在仓库且哈希未改变；
- [ ] `SHA256SUMS` 与整包 `.sha256` 校验通过；
- [ ] CEF 106 已在 Windows 7 SP1 实机验证；
- [ ] CEF 134 已在 Windows 10/11 实机验证；
- [ ] H.264 实际样本播放通过；
- [ ] H.265/HEVC 在声明支持的目标机上实际样本播放通过；
- [ ] 已完成 H.264/H.265/HEVC 专利、许可和商业分发审查；
- [ ] 已处理或书面接受 `System.Text.Json 6.0.1` 的 `GHSA-8g4q-xg66-9fp4` 安全 warning。
