#!/bin/sh
#
# hud-notify.sh —— 把一句话挂到灵动岛胶囊上（任务完成 ✅ / 阶段进度提醒），不注销。
#
# 为什么要有它：Apelin 的本地通知在发送瞬间会把 App 拉回前台、横幅被自己吞掉，用户去别的对话 /
# 桌面 / 别的 App 时基本看不到。CountdownHUD 1.2.0 起支持「纯文案」：请求文件里标签以 `!` 开头，
# 屏幕上就是这句话本身（没有「N 秒后」前缀、不跳数字），显示 N 秒后淡出。
#
# 它只是「通知用户」用，**不做任何破坏性动作**：不 respring、不装包、不杀进程。
# 注销/装包/杀进程仍旧一律走 scripts/respring-guard.sh（那条路要通知 + 5 秒 + 先同步别的对话）。
#
# 用法（仓库根目录，shell_run 直接跑）：
#   sh scripts/hud-notify.sh "完成：ThemeControl 设置面板"        # 默认 8 秒
#   sh scripts/hud-notify.sh 12 "完成：修好注销前同步"           # 12 秒
#
# 手机上看到的形如：胶囊里一行绿字「完成：ThemeControl 设置面板」。
#
set -eu

WAIT=8
case "${1:-}" in
  ''|*[!0-9]*) ;;
  *) WAIT=$1; shift ;;
esac

TEXT="$*"
if [ -z "$TEXT" ]; then
  echo "usage: sh scripts/hud-notify.sh [秒数] <文案>" >&2
  exit 2
fi
if [ "$WAIT" -lt 3 ]; then WAIT=3; fi
if [ "$WAIT" -gt 60 ]; then WAIT=60; fi

# shell 跑在 bootstrap 命名空间里，写系统路径要加真根前缀 /rootfs；
# SpringBoard 里的插件读的是系统原路径（见 apelin-bootstrap-paths）。
REQ_DIR=/rootfs/var/mobile/Library/Preferences
REQ="$REQ_DIR/.countdownhud-request"

if [ ! -d "$REQ_DIR" ]; then
  echo "hud-notify: $REQ_DIR 不存在，写不了请求（本机没装 CountdownHUD 时就没有胶囊）" >&2
  exit 3
fi

EPOCH=$(date +%s)
if printf '%s|%s|!%s\n' "$EPOCH" "$WAIT" "$TEXT" > "$REQ" 2>/dev/null; then
  echo "hud-notify: 已请求胶囊显示 ${WAIT} 秒：$TEXT"
else
  echo "hud-notify: 写 $REQ 失败（没装 CountdownHUD，或权限不对）" >&2
  exit 3
fi

# 自检：CountdownHUD ≥ 1.2.0 才有 mode=plain；旧版会把「!文案」显示成「N 秒后!文案」。
DIAG=$(icli prefs read com.apple.springboard CountdownHUDDiagnostics 2>/dev/null || true)
case "$DIAG" in
  *mode=plain*) echo "hud-notify: 插件版本 OK（$DIAG）" ;;
  *v1.0*|*v1.1*) echo "hud-notify: 装的是旧版胶囊（$DIAG），它会显示「N 秒后!…」；装 1.2.0 起才有纯文案" >&2 ;;
  '') echo "hud-notify: 读不到 CountdownHUDDiagnostics（插件没在 SpringBoard 里跑？）" >&2 ;;
  *) echo "hud-notify: 诊断：$DIAG" ;;
esac