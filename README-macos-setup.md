# UxPlay 1.74 — macOS AirPlay 接收端（本机定制版）

目标机器：iMac (iMac18,3, 2017) / macOS 13.7.8 (22H730) / Intel x86_64。
用途：让这台 iMac 当 AirPlay 接收端，接收 iPhone 的屏幕镜像。

> 本仓库是 [FDH2/UxPlay](https://github.com/FDH2/UxPlay) 的分支备份：
> 基于上游 master `48f5ce4`（2026-11-17），加上本机调试中的补丁与构建文档。
> 上游 README 见 `README.md`。

## 构建环境

| 组件 | 版本 / 位置 |
|---|---|
| Xcode CLT | CommandLineTools, clang 14.0.3 |
| cmake | `/usr/local/bin/cmake` (Homebrew) |
| pkg-config | `/usr/local/bin/pkg-config` (Homebrew) |
| GStreamer | **官方 macOS 框架 1.28.9** → `/Library/Frameworks/GStreamer.framework` |
| libplist | 2.8.1，**静态库** → `/usr/local/lib/libplist-2.0.a` |
| openssl | Homebrew `openssl@3`（用其 `libcrypto.a` 静态链接） |
| 安装包 | `gstreamer-1.0-1.28.9-universal.pkg` + `gstreamer-1.0-devel-1.28.9-universal.pkg` |

**不要用 Homebrew 的 `gstreamer` formula**：macOS 13 已不在支持层级内（Tier 3），
会从源码编译 ffmpeg / gtk4 / rustc，耗时以小时计。官方框架包几分钟装完。

### libplist 静态编译（上游要求 `libplist-2.0.a`）

```sh
curl -LO https://github.com/libimobiledevice/libplist/releases/download/2.8.1/libplist-2.8.1.tar.bz2
tar xjf libplist-2.8.1.tar.bz2 && cd libplist-2.8.1
./configure --prefix=/usr/local --enable-static --disable-shared --without-cython
make -j4 && make install
```

（发布包的 tarball 自带 `configure`，无需 autoconf/automake。）

### 编译 UxPlay

```sh
cd UxPlay && mkdir -p build && cd build
export PKG_CONFIG_LIBDIR=/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/pkgconfig:/usr/local/opt/openssl@3/lib/pkgconfig:/usr/local/lib/pkgconfig
export CMAKE_PREFIX_PATH=/Library/Frameworks/GStreamer.framework/Versions/1.0:/usr/local/opt/openssl@3
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_INSTALL_RPATH=/Library/Frameworks/GStreamer.framework/Versions/1.0/lib \
         -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
make -j4
```

`PKG_CONFIG_LIBDIR`（而不是 `PKG_CONFIG_PATH`）很关键：官方框架自带的 pkg-config
默认会先搜 `/usr/local/lib/pkgconfig`，从而解析到 Homebrew 的 `glib-2.0.pc`。

## 运行（有两个 must）

```sh
./build/uxplay -n "iMac" -nh -vsync no
```

1. **可执行文件不要放进 `/usr/local/bin`。**
   框架里 `libgstsdp` 等库的第一条 rpath 是 `@executable_path/../lib`；程序放在
   `/usr/local/bin` 时该路径解析成 `/usr/local/lib`，那里有 Homebrew 的
   `libgio-2.0.0.dylib → ../Cellar/glib/...` 软链，于是进程里同时加载两份
   GLib/GObject，首次走 HTTPS（HLS）时在 `souphttpsrc` 建 TLS 会话处崩溃：

   ```
   parameter 1 of type 'GstMemory' for signal "GstSoupHTTPSrc::accept-certificate"
   is not a value type  →  Segmentation fault: 11
   ```

   放在 `~/Applications/UxPlay/build/` 下运行即可；或显式
   `DYLD_LIBRARY_PATH=/Library/Frameworks/GStreamer.framework/Versions/1.0/lib`。

2. 若用 `-hls`，需要 `LANG` 有值，否则 `uxplay.cpp` 里的
   `g_assert(!lang_system.empty())` 会直接 abort（见本节末尾的补丁 5）。

`/usr/local/bin/uxplay` 是一个包装脚本，设置 `DYLD_LIBRARY_PATH` 后转调 build 目录里的
真实二进制。

## 本地补丁（相对上游 master 48f5ce4）

见 `patches/local-fixes.patch`，共 5 处，全部集中在 `renderers/video_renderer.c`：

1. **buffering 不再永久暂停**：`hlsdemux2`（GStreamer ≥1.24）在播放期持续上报
   buffering 且到不了 100%，原逻辑把流水线 PAUSED 后再也等不到 100%，表现为
   「播几秒永久冻住、日志无报错」。改为只在首次起播（`!hls_playing`）时暂停。
2. **处理 `GST_MESSAGE_LATENCY`**：HLS 变体切换后重算流水线延迟，避免 sink
   沿用旧延迟丢帧（对应上游 PR #627）。
3. **伪造 Apple TV User-Agent**：`source-setup` 里给 source 设
   `AppleCoreMedia/1.0.0.21L569 (...)`，规避 CDN 对 `GStreamer souphttpsrc`
   UA 的限速/拒绝（对应上游 PR #625）。
4. **音频固定 48 kHz**：audio-sink 前串 `audioconvert ! audioresample !
   audio/x-raw,rate=48000`，避免变体切换改变采样率导致 sink 重建后无声
   （对应上游 PR #619）。
5. *未包含在 patch 中*：`-hls` 无 `LANG` 时断言 abort（`uxplay.cpp:3478`），
   属于上游 bug，见 `upstream/issue-hls-lang-assert.md`。

## 已验证 / 已知限制

- ✅ 屏幕镜像（照片、Safari、游戏、任意 App）：视频+声音稳定，延迟约 0.2s。
- ⚠️ YouTube「App 内 AirPlay 视频」（HLS 直推，`-hls`）：**默认关闭**。
  加上 `-hls 2 -custom "AVC:720;HEVC:0;VP9:0;AV1:0"` 后可以长播（这是本机实测
  最好的一组参数），但上游 HLS 状态管理会在续播/切集后丢播放列表：

  ```
  *** ERROR: requested master playlist /master.m3u8 not found
  GStreamer error (video): hlsdemux2 Invalid manifest
  *** ERROR: airplay_video playlist  not found
  ```

  见上游 issue #596。关闭 `-hls` 时 YouTube App 会自动退回屏幕镜像。
- ✅ 关闭 `-hls` 后，启动脚本为：
  `uxplay -n "iMac" -nh -vsync no`

## 已提交给上游的报告

- [#640 macOS: uxplay started from /usr/local/bin loads two GLib copies and segfaults on HLS playback](https://github.com/FDH2/UxPlay/issues/640)
- [#641 HLS (playbin3): hlsdemux2 buffering never reaches 100%, so the pipeline stays paused forever](https://github.com/FDH2/UxPlay/issues/641)
- [#642 -hls aborts on an assertion when no locale environment variable is set](https://github.com/FDH2/UxPlay/issues/642)
- [PR #643 -hls: fall back to a default language preference when no locale is set](https://github.com/FDH2/UxPlay/pull/643)

`upstream/` 目录保留了草稿原文；`comment-596-playlist-lost.md` 未提交（证据不足以归因）。

## 目录

```
启动 UxPlay.command   双击启动（关窗口即停）
patches/              本地补丁
upstream/             准备提交上游的 issue 草稿
README-macos-setup.md 本文件
```
