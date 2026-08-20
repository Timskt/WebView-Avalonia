# Docker / Docker Compose 构建说明

> 更新日期：2026-08-20

Docker Compose 是可选的 **Linux x64 原生构建环境**，用于把 Linux 依赖固定在容器内并
持久化 Chromium/CEF cache。它不能在 Linux 容器中生成可交付的 Windows `libcef.dll`。
Windows 成品请使用 `docs/PHYSICAL-MACHINE-BUILD.md` 的 Windows 物理机流程。

## 服务

```text
cef106-linux-x64  -> Ubuntu 20.04 image -> CEF 106 / linux-x64
cef134-linux-x64  -> Ubuntu 22.04 image -> CEF 134 / linux-x64
```

## 运行

```bash
# 只构建 CEF 134
./scripts/docker-compose-cef.sh 134

# 只构建 CEF 106
./scripts/docker-compose-cef.sh 106

# 顺序构建两条线
./scripts/docker-compose-cef.sh both
```

容器进程使用当前主机的 UID/GID 写入 bind mount；镜像会兼容 Ubuntu 中已存在的同号用户组，避免 macOS 常见 GID 20 或 root GID 0 导致镜像构建失败。

持久化目录：

```text
.cef-docker/106-linux-x64
.cef-docker/134-linux-x64
```

输出目录：

```text
artifacts/docker/cef-106/linux-x64
artifacts/docker/cef-134/linux-x64
```

## 验证 Compose 配置

```bash
docker compose -f docker-compose.cef.yml --profile all config
```

## 限制

- 推荐 AMD64 Linux host；ARM host 的 amd64 模拟构建非常慢；
- Compose 默认拒绝非 AMD64 host，除非显式设置 `ALLOW_EMULATION=1`；
- 容器只是复现 Linux build host，不改变 CEF 的目标平台；
- 不包含 Windows SDK、Visual Studio libraries 或 Windows resource/link tools；
- 不能代替 Windows 7/10 实机运行和媒体播放验证。
