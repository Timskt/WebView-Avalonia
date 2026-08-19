# H.264 / H.265 真实播放验证规范

> 更新日期：2026-08-19

## 结论分级

必须区分三种结论：

1. **Build enabled**：GN flags 和精确 source pin 已进入真实 CEF build。
2. **Capability preflight**：`HTMLMediaElement.canPlayType()` 返回 `maybe`/`probably`。
3. **Playback verified**：真实媒体成功解码、出现画面并持续推进时间轴。

前两项不能替代第三项。

## Demo / html5test 步骤

1. 使用真实 codec-enabled runtime 安装 CefGlue/WebView 包，不能使用 synthetic fixture。
2. 构建并启动：

   ```bash
   dotnet run --project WebView/SampleWebView.Avalonia/SampleWebView.Avalonia.csproj \
     -c ReleaseAvalonia -p:CefLine=134 -p:Platform=ARM64 -r osx-arm64
   ```

3. Demo 默认打开 `https://html5test.com/`。
4. 点击 `Check H.264/HEVC`，记录：
   - `video/mp4; codecs="avc1.42E01E"`
   - `video/mp4; codecs="hvc1.1.6.L93.B0"`
5. 保存 html5test 页面结果和 Demo preflight 结果截图。
6. 继续执行下面的真实媒体播放测试。

## 真实播放判据

对 H.264 和 H.265 各准备一个已知有效、可直接访问、允许测试分发的短视频。
不要只观察 controls 是否出现。至少记录：

```javascript
const video = document.querySelector('video');
const result = {
  error: video.error && {
    code: video.error.code,
    message: video.error.message
  },
  readyState: video.readyState,
  networkState: video.networkState,
  currentTime: video.currentTime,
  duration: video.duration,
  videoWidth: video.videoWidth,
  videoHeight: video.videoHeight,
  paused: video.paused,
  ended: video.ended
};
console.log(result);
```

通过条件：

- 收到 `loadeddata`；
- 收到 `playing`；
- 至少收到多个 `timeupdate`；
- `currentTime` 在观测窗口内持续增长；
- `videoWidth > 0` 且 `videoHeight > 0`；
- `video.error === null`；
- 实际看到画面，而不是只有音频或黑帧。

建议在 DevTools 中运行：

```javascript
for (const name of ['loadedmetadata', 'loadeddata', 'canplay', 'playing', 'timeupdate', 'error']) {
  video.addEventListener(name, () => console.log(name, {
    t: video.currentTime,
    width: video.videoWidth,
    height: video.videoHeight,
    error: video.error && [video.error.code, video.error.message]
  }));
}
```

## 测试矩阵记录

每个结果必须关联：

```text
CEF line / exact checkout
WebView/CefGlue/runtime package version
OS edition and exact version
CPU architecture
GPU model
GPU driver version
Hardware acceleration enabled/disabled
Video codec/profile/level/bit depth/chroma
Container and transport (file/http/https/HLS/etc.)
CEF command-line flags and policy
```

HEVC 还要记录：

- Windows：是否安装/提供 HEVC Video Extensions，GPU 是否支持对应 profile；
- macOS：VideoToolbox 能力、机型和 macOS 版本；
- Linux：VA-API implementation、driver、`vainfo` 能力、桌面会话；
- VM/CI：是否有 GPU passthrough。没有硬件能力的 hosted runner 不能作为 HEVC 否定结论。

## 建议测试样本

至少覆盖：

- H.264 AVC Baseline/Main/High 中项目实际使用的 profile；
- H.265 Main 8-bit；如业务需要再测 Main10；
- 静态 MP4 文件和业务实际使用的 streaming 协议；
- 有音频和无音频两种文件；
- x64 与 ARM64 目标设备。

所有样本必须有清晰来源和合法测试/再分发权限。不要把受版权保护的视频提交到仓库。

## 失败排查

1. 检查 package 中 `CEF_CODEC_BUILD_INFO.txt`，确认不是 synthetic。
2. 检查 `chrome://gpu`、CEF log 和 DevTools console。
3. 确认硬件加速没有被 command line、远程桌面、sandbox 或 policy 禁用。
4. 确认 codec/profile/bit depth 与平台硬件能力匹配。
5. H.264 成功、HEVC 失败时，优先检查系统 HEVC 组件和 GPU driver，而不是直接判断 build flags 无效。
6. Windows 7 单独检查 VC++ runtime、系统补丁和旧 GPU driver。
