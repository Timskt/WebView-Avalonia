# Windows H.264/H.265 交付范围

> 更新日期：2026-08-19

本轮先交付 Windows x64，避免在 GitHub Actions 上同时消耗六个平台的 CEF/Chromium
构建资源。仓库仍保留 macOS/Linux/ARM64 的配置、打包脚本、输入法修复和校验逻辑，
后续只需要扩展 workflow 的 native target 列表即可恢复这些原生构建。

## 两条 Windows 产品线

| Windows 目标 | CEF line | Chromium | .NET TFM | 用途 |
|---|---:|---:|---:|---|
| Windows 7 SP1 兼容线 | 106 | 106.0.5249.91 | net6.0 | 旧系统兼容 |
| Windows 10/现代 Windows | 134 | 134.0.6998.178 | net8.0 | 当前主线 |

两条线均使用 `win-x64`，并在 `config/cef-lines.json` 中启用：

```text
is_official_build=true
proprietary_codecs=true
ffmpeg_branding=Chrome
enable_platform_hevc=true
enable_hevc_parser_and_hw_decoder=true
chrome_pgo_phase=0
```

构建还显式使用 `chrome_pgo_phase=0`，避免固定 Chromium 源码缺少 PGO profile 时
`gn gen` 失败。

这些构建参数用于启用 Chromium 的 H.264 路径，并启用平台 HEVC/H.265 解析与硬件
解码路径；它们不代表完成专利、系统组件或商业授权。H.265 是否实际可播仍取决于
目标系统、GPU、驱动和 HEVC 组件。

## 当前 GitHub Actions 矩阵

`.github/workflows/build-cef-codecs.yml` 当前只生成：

```text
CEF 106 / win-x64
CEF 134 / win-x64
```

Managed package job 也只下载并验证 `chromiumembeddedframework.runtime.win-x64`，然后
构建：

```text
CefGlue.Common.<version>.nupkg
CefGlue.Avalonia.<version>.nupkg
WebViewControl-Avalonia.<version>.nupkg
```

`--rids` 是脚本级的范围开关：

```bash
# 本轮 Windows 交付
./scripts/package-managed-codecs.sh \
  --line 134 --feed artifacts/feed --config artifacts/NuGet.Config \
  --rids win-x64
./scripts/verify-nuget-consumer.sh \
  --line 134 --config artifacts/NuGet.Config --work artifacts/consumer \
  --rids win-x64

# 默认仍支持全量 RID（未来恢复跨平台打包时使用）
./scripts/package-managed-codecs.sh \
  --line 134 --feed artifacts/feed --config artifacts/NuGet.Config
```

当只选择 `win-x64` 时，CefGlue 项目通过 `CodecRuntimeRids` 只声明已构建的 Windows
runtime package，避免因为尚未生成的 macOS/Linux native 包导致 restore 失败。该属性
为空时仍保持六 RID 的原有默认行为。

## 首次 gclient checkout 防护

CEF 的 `automate-git.py` 默认会先执行一次未指定 revision 的 `gclient sync`，再处理
`--chromium-checkout`。对于 CEF 106，这会把 pinned 旧版 `depot_tools` 带到当前
Chromium `main` 的 DEPS schema，常见报错是：

```text
src/third_party/js_code_coverage/node_modules
Missing keys: 'packages'
```

`build-cef-codecs.sh` 会在 runner 临时目录中对下载的 automate 脚本做最小补丁，并传入
带 `@refs/tags/<exact Chromium tag>` 的 `--chromium-url`，同时让首次 sync 使用
`--no-history`。这样第一次解析 DEPS 的就是 CEF 106/134 对应的历史 Chromium tag，
而不是当前 main。这个补丁不修改上游 CEF 源码；如果未来 CEF automate 脚本改变了
初始 sync 命令，脚本会主动失败而不是静默退回未锁定 checkout。

## 必做验证

### 静态检查

```bash
bash -n scripts/*.sh
python3 -m py_compile scripts/*.py
python3 scripts/cef_line_config.py 106 --format json
python3 scripts/cef_line_config.py 134 --format json
git diff --check
```

### Windows-only synthetic smoke

```bash
./scripts/smoke-test-codec-packages.sh both artifacts/synthetic-smoke
```

这条命令默认仍验证六个 RID，是打包逻辑和跨平台布局的 synthetic-only 回归；它不
生成真实 CEF native 二进制，不能作为 H.264/H.265 播放证明。

### 真实 native CI

只有 GitHub Actions 的 `Build exact pinned CEF with codec paths` 产物中存在真实
`CEF_CODEC_BUILD_INFO.txt`，且不含 `SYNTHETIC_FIXTURE=true` 时，才可声称 native
构建完成。当前需要观察四个 job：

```text
CEF 106 / win-x64
CEF 134 / win-x64
Managed Windows x64 packages / CEF 106
Managed Windows x64 packages / CEF 134
```

## Windows 7 实机门禁

CI 使用 Windows Server 2022 只能验证构建链，不能代替 Windows 7 SP1 实机。发布前
还必须在真实 Windows 7 SP1 上验证：

1. `9n1m.webview.exe`、renderer/GPU 子进程可以启动；
2. VC++ runtime、CEF sandbox 和 GPU/软件渲染策略符合部署环境；
3. H.264 短视频能够出现画面并持续推进时间轴；
4. HEVC/H.265 的系统组件、GPU profile/driver 满足要求。

CEF 106 的 .NET 6 依赖已结束官方支持，因此 Windows 7 项目必须由业务方自行承担
运行时安全维护和部署验证。
