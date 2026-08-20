# 2026-08-20 物理机构建与交付工具更新

## 新增功能

- 新增 Windows PowerShell 一键入口：`scripts/build-windows.ps1`；
- 新增 Windows CMD 入口：`scripts/build-windows.cmd`；
- 新增 Linux 一键入口：`scripts/build-linux.sh`；
- 新增统一物理机入口：`scripts/build-physical.sh`；
- 新增 Debian/Ubuntu bootstrap 依赖安装器；
- 新增物理机预检：OS/RID、CPU 架构、磁盘、RAM、Python 3.8+、Git、.NET SDK；
- Windows 额外检查 VS 2019/2022、MFC/ATL、Windows SDK、Debugging Tools；
- Windows Git Bash 自动兼容 `python` 与 `python3`；
- Windows NuGet.Config 中的 MSYS 路径显式转换为 Windows native path；
- 正式输出增加 preflight JSON、构建日志、manifest、SHA256SUMS、整包压缩文件和 sidecar hash；
- 新增 Docker Compose Linux native CEF 106/134 构建入口和持久化 cache；
- 文档明确 Linux Docker 不等于 Windows CEF 交叉编译。

## 保持不变的兼容项

- CEF 106 / Chromium 106.0.5249.91 精确 pin；
- CEF 134 / Chromium 134.0.6998.178 精确 pin；
- H.264/H.265 GN flags；
- Windows 7 专用的 CEF 106 产品线；
- BrowserProcess 文件名 `9n1m.webview(.exe)`；
- C# namespace `Xilium.CefGlue.BrowserProcess`；
- macOS ARM64 `libFixIME.dylib` 及其固定 SHA-256；
- Demo 默认打开 `https://html5test.com/`。

## 验证范围

本次提交能够在当前开发机完成：

- Bash syntax；
- Python bytecode compilation；
- CEF line config parsing；
- physical preflight smoke；
- Docker Compose config；
- synthetic package/managed consumer smoke；
- macOS IME dylib hash/layout checks；
- Git diff whitespace checks。

真实 Chromium/CEF 全量构建需要数小时和数百 GiB，必须在目标 Windows/Linux 物理机
按 `docs/PHYSICAL-MACHINE-BUILD.md` 执行；只有目标机成功生成真实 marker 和产物并完成
实际视频播放，才能声明 H.264/H.265 交付验收完成。

## 验证期间发现的已知 warning

CefGlue 两条 vendored 依赖基线仍使用 `System.Text.Json 6.0.1`，`dotnet restore` 会报告
`GHSA-8g4q-xg66-9fp4` 高严重性 advisory。此次更新没有未经兼容性验证就升级该依赖；
正式发布前必须由项目维护者决定升级并完成两条 CEF 线的完整验证，或明确记录风险接受。

## 远程构建失败修复

- 修复 CEF 134 / Chromium 134.0.6998.178 在 Windows 生成 GN 时因缺少 PGO `.profdata` 而失败的问题；
- 两条产品线显式加入 `chrome_pgo_phase=0`，关闭依赖额外下载 profile 的 PGO 优化；
- 该设置不改变 `proprietary_codecs`、`ffmpeg_branding=Chrome`、平台 HEVC parser/hardware decoder 等 codec 配置；
- 物理机构建输出的 `CEF_CODEC_BUILD_INFO.txt` 会记录该构建参数，便于后续复核。
