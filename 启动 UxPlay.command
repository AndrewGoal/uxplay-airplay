#!/bin/bash
# 双击即可启动 AirPlay 接收端；关闭窗口即停止。
#
# 这里【不启用 -hls】。
# 原因：-hls 让 YouTube App 的 AirPlay 图标直接把视频流推给本机（HLS），
# 但 UxPlay 的 HLS 分片代理在上游仍是实验功能，会在重新请求 master.m3u8 时
# 丢失播放列表状态 -> 404 -> 流水线报错卡死（上游 issue #596）。
# 不启用时 YouTube App 会自动退回屏幕镜像，稳定可用。

: "${LANG:=zh_CN.UTF-8}"
export LANG

# 清理遗留实例，避免多个 uxplay 同时广播同一个 AirPlay 名字
pkill -f "$HOME/Applications/UxPlay/build/uxplay" 2>/dev/null
sleep 1

exec /usr/local/bin/uxplay -n "iMac" -nh -vsync no "$@" 2>&1 | tee "$HOME/Library/Logs/uxplay.log"
