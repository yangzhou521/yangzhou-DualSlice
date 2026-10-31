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
#   HUD_SID=<对话 id> sh scripts/hud-notify.sh 8 "完成：…"       # 1.6.0 起：胶囊可点，点一下跳到该对话
#
# 手机上看到的形如：胶囊里一行绿字「完成：ThemeControl 设置面板」。
# 带 HUD_SID 时（CountdownHUD ≥ 1.6.0）胶囊只在自身矩形里吃触摸，点一下用
# apelin://conversation/<id> 打开那条对话；不带就是老样子（不吃任何触摸）。
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

# v1.6.0：可选的对话 id —— 有它胶囊才可点（点一下跳回发消息的对话）。
# 只认 UUID 那种形状（十六进制 + 连字符），别的内容一律当没有，免得拼出奇怪的 URL。
SID="${HUD_SID:-}"

# 没给 HUD_SID 时自己认出「本会话」：Apelin 的会话目录里，每个会话的 events.jsonl
# 会记录它自己发起的 toolCall。**本脚本当前这次调用**（命令里含 hud-notify.sh）正被写进
# 正在跑它的那个会话的事件流里 —— 取「最后一次提到 hud-notify.sh 的事件」最新的那个会话，
# 就是发这条通知的对话（点胶囊要回到这里）。
# 注意：不能用「全局最近一条用户消息」来认 —— 别的对话一说话就会把链接抢走。
# 并发跑几条线时可能认错 —— 那种场合用 HUD_SID 显式指定。
auto_sid() {
  DIR="$HOME/Documents/wiki.qaq.apelin/sessions"
  [ -d "$DIR" ] || return 0
  LIST=""
  for d in $(ls -t "$DIR" 2>/dev/null | head -12); do
    f="$DIR/$d/events.jsonl"
    [ -f "$f" ] || continue
    line=$(tail -c 600000 "$f" 2>/dev/null | grep -F 'hud-notify.sh' | grep -F 'toolCall' | tail -1)
    [ -n "$line" ] || continue
    dt=$(printf '%s' "$line" | sed 's/.*"date":"\([^"]*\)".*/\1/')
    [ -n "$dt" ] || continue
    LIST="$LIST$dt $d
"
  done
  [ -n "$LIST" ] || return 0
  printf '%s' "$LIST" | sort -r | head -1 | awk '{print $2}'
}

if [ -z "$SID" ]; then
  SID=$(auto_sid)
  if [ -n "$SID" ]; then
    echo "hud-notify: 未给 HUD_SID，自动认出发消息的对话 $SID"
  fi
fi

case "$SID" in
  ''|*[!0-9a-fA-F-]*) SID="" ;;
esac
if [ -n "$SID" ] && { [ "${#SID}" -lt 8 ] || [ "${#SID}" -gt 64 ]; }; then
  SID=""
fi

EPOCH=$(date +%s)
if [ -n "$SID" ]; then
  printf '%s|%s|!%s|%s\n' "$EPOCH" "$WAIT" "$TEXT" "$SID" > "$REQ" 2>/dev/null && OK=1 || OK=0
  SHOWN="${WAIT} 秒（可点 → 对话 $SID）：$TEXT"
else
  printf '%s|%s|!%s\n' "$EPOCH" "$WAIT" "$TEXT" > "$REQ" 2>/dev/null && OK=1 || OK=0
  SHOWN="${WAIT} 秒：$TEXT"
fi
if [ "$OK" = 1 ]; then
  echo "hud-notify: 已请求胶囊显示 $SHOWN"
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