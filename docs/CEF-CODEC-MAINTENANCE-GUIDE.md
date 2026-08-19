# CEF Codec 双版本维护手册

> 更新日期：2026-08-19

本文用于下一次升级 CEF、CefGlue、codec package 或 BrowserProcess 名称时快速复用。
唯一配置入口是 `config/cef-lines.json`。

## 目录职责

```text
config/cef-lines.json                 精确 pins、API hashes、包版本、TFM、GN flags
scripts/build-cef-codecs.sh           原生 CEF 构建
scripts/package-cef-runtime.py        单 RID runtime NuGet
scripts/package-managed-codecs.sh     CefGlue + WebView 打包
scripts/verify-package-layout.py      runtime/CefGlue/WebView/consumer 门禁
scripts/verify-nuget-consumer.sh      真正从 nupkg 消费的六 RID smoke test
scripts/smoke-test-codec-packages.sh  synthetic-only 托管构建 smoke test
vendor/CefGlue                        CEF 106 精确 CefGlue vendor
vendor/CefGlue-134                    CEF 134 精确 CefGlue vendor
.github/workflows/build-cef-codecs.yml 六 RID、双版本、release gate
```

## 升级流程

### 1. 确定精确 CEF/Chromium pin

不要只记录 branch。必须记录：

```text
CEF branch
CEF git checkout SHA
Chromium exact tag/version
CEF runtime package version
```

从目标 CEF checkout 查看：

```bash
git show <cef-sha>:include/cef_version.h
git show <cef-sha>:CHROMIUM_BUILD_COMPATIBILITY.txt
```

`cef_version.h` 用于确认 CEF/Chromium 版本；
`CHROMIUM_BUILD_COMPATIBILITY.txt` 用于确认 CEF 期望的 Chromium checkout。

### 2. 固定 CefGlue source

1. 选择与目标 CEF API 相符的 OutSystems/CefGlue commit；
2. 记录 commit SHA，而不是移动 branch；
3. 重新生成或引入对应 `Classes.g`/interop；
4. 对齐 `CefApiHash`/generated API version；
5. 在目标平台调用 `CefRuntime.CheckVersionByApiHash()` 验证。

若 API hash 不匹配，不要通过删除 runtime check 来“修复”。应重新对齐 CEF 与 CefGlue。

### 3. 更新 API hash

从 CEF headers/generated sources 取得 universal/Windows/macOS/Linux hashes，写入
`config/cef-lines.json` 和对应版本文档。CEF 134 还应记录 API version（当前为
`13401`）。

### 4. 保留 codec flags

升级时逐项确认目标 Chromium/CEF 仍识别：

```text
is_official_build=true
proprietary_codecs=true
ffmpeg_branding=Chrome
enable_platform_hevc=true
enable_hevc_parser_and_hw_decoder=true
```

GN flag 被删除、重命名或变为 no-op 时必须停止发布并调查，不可仅凭构建成功继续。

### 5. 六 RID 映射

每条 CEF line 都要生成：

```text
win-x64 / win-arm64
osx-x64 / osx-arm64
linux-x64 / linux-arm64
```

修改 package ID 时同步更新：

- `scripts/package-cef-runtime.py`
- `scripts/verify-package-layout.py`
- 两套 CefGlue package references/targets
- GitHub Actions runtime verification
- 文档和 consumer test

### 6. CefGlue vendor 更新

建议在临时目录 checkout 精确 commit，然后复制干净 worktree。不要复制：

```text
.git
bin/
obj/
packages/
NuGet/output/
*.nupkg
.DS_Store
```

改动至少包括：

- runtime package versions；
- x64/ARM64 与 Linux package references；
- `AssemblyName=9n1m.webview`；
- `RootNamespace=Xilium.CefGlue.BrowserProcess`；
- `InternalsVisibleTo("9n1m.webview")`；
- package targets 中新进程名和 Unix `chmod +x`；
- bundle scripts 中新进程名。

只改 apphost/assembly 名称，不要无理由改 namespace，否则会造成更大 breaking change。

### 7. 保留 macOS 输入法与 ObjC 冲突修复

以下兼容资产和流程属于发布门禁，不得在升级 CEF/CefGlue 时顺手删除：

```text
WebView/WebViewControl.Avalonia/native/osx-arm64/libFixIME.dylib
SHA-256: bbf45fd8ee8941248d806cea89366db14eb8802219111b3b1c8eeecefe573a7a
ExtensionDropdownHandler -> CEFExtensionDropdownHand
codesign --force --sign - <patched libcef.dylib>
```

`scripts/verify-package-layout.py` 同时校验 ARM64 WebView nupkg 和 `osx-arm64` consumer 输出中的
dylib 格式与精确哈希。如果必须重新编译该 dylib，应先完成中文/日文输入法回归，再明确更新哈希和发布说明；
不能仅为了让 CI 通过而改哈希。

ProjectReference 场景不会自动导入 NuGet 的 `buildTransitive` 文件，因此 Demo 项目还必须显式导入
`WebViewControl-Avalonia.targets`，否则源代码运行时可能漏掉 IME dylib、ObjC patch 或 codesign。

### 8. WebView API 差异

CEF 106 与 CEF 134 callback signature 不同。使用 `CEF_106`/`CEF_134` 条件编译隔离，
并分别构建。当前差异集中在：

```text
WebView.Extensions.cs
WebView.InternalDialogHandler.cs
WebView.InternalDownloadHandler.cs
WebView.InternalLifeSpanHandler.cs
WebView.InternalRequestHandler.cs
```

默认主线为 134；Win7 线显式 `-p:CefLine=106`。同步检查 TFM：106 为 `net6.0`，
134 为 `net8.0`。

### 9. 运行本地 smoke test

```bash
./scripts/smoke-test-codec-packages.sh both artifacts/synthetic-smoke
```

该命令会构造 12 个文本占位 runtime，打包两套 CefGlue/WebView，再以临时 NuGet
consumer 构建六 RID。它只验证托管构建与布局。

保护规则：

- synthetic marker 为 `SYNTHETIC_FIXTURE=true`；
- packager/verifier 默认拒绝 synthetic；
- 只有 smoke script 显式传 `--allow-synthetic`；
- synthetic package 永远不能上传 artifact feed、NuGet 或 GitHub Release。

### 10. 真实构建和发布

workflow：`build-cef-codecs.yml`

输入：

```text
cef_line: 106 | 134 | both
build_cef: true | false
publish_release: true | false
```

`publish_release=true` 必须同时 `build_cef=true`。Release job 会重新验证六个 runtime
marker，且 verifier 默认拒绝 synthetic。

Chromium build 往往超过 hosted runner 的磁盘或 6 小时上限。若失败：

1. 查看是否在 checkout/build 前耗尽磁盘；
2. 使用具备足够 SSD（建议至少 200 GB 可用空间）、内存和对应 OS toolchain 的
   self-hosted/larger runner；
3. 不要用 stock CEF binary 替换后继续标注 `codecs`；
4. 不要用 synthetic artifact 补齐失败平台；
5. 记录每个平台的 compiler/Xcode/Visual Studio/sysroot。

### 11. 发布后实机测试

完成 `docs/MEDIA-CODEC-VALIDATION.md`。特别是：

- Win7 必须实机；
- HEVC 必须记录 OS/GPU/driver；
- `canPlayType()` 不是播放证明；
- 需要 `loadeddata`, `playing`, advancing `currentTime`, non-zero dimensions,
  `video.error === null`。

## 常见故障

### `MSB3030` 找不到 macOS EGL/GLES dylib

CefGlue targets 可能先添加 `$(OutDir)/libEGL.dylib` 等尚未存在的 `None` item。
WebView targets 会移除这些错误 item，再由 `_CopyMacCefFiles` 复制。升级 CefGlue targets
后要重新检查是否还需要该兼容处理。

### BrowserProcess 存在但不能启动

- 确认文件名不是旧的 `Xilium.CefGlue.BrowserProcess`；
- 确认 macOS/Linux execute bit；
- 检查 self-contained apphost 与 RID；
- 检查 loader/command line 指向 `CefGlueBrowserProcess/9n1m.webview[.exe]`。

### Avalonia feed 不可用

当前构建只依赖本地 codec feed 与 `nuget.org`；不要重新引入不稳定的私有 Avalonia
feed，除非目标 package 确实只存在于该 feed，并且 CI 有明确可用性保障。

## 法律与发布 checklist

- [ ] H.264/H.265 专利/商业许可已由分发方审查；
- [ ] Chromium/CEF/FFmpeg notices 已保留；
- [ ] 精确 source pins 已记录；
- [ ] 六 RID 真实 runtime 已构建；
- [ ] synthetic guard 通过；
- [ ] CefGlue/WebView/consumer verifier 通过；
- [ ] Win7 实机结果已记录；
- [ ] H.264/H.265 真实播放结果已记录；
- [ ] HEVC OS/GPU/driver 条件已记录。
