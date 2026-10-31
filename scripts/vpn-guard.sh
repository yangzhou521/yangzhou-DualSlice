#!/bin/sh
#
# vpn-guard.sh —— 需要用户开 VPN 时，在屏幕上弹窗让他做选择（不注销、不装包）。
#
# 用户 2026-10-31 21:26 硬指令：「注销装包VPN弹窗」—— 这三类事情一律走弹窗，
# 不许只在对话里等文字回复。
#
# 与 respring-guard.sh 的区别：这个**不做任何设备动作**，只是把「要不要开 VPN」搬到屏幕上，
# 答案写进同一个 answer 文件，调用方据此决定要不要重试（比如重试 git push）。
#
# 用法：
#   sh scripts/vpn-guard.sh 20 "push 失败，需要开 VPN"      # 弹窗，最多等 20 秒
#   sh scripts/vpn-guard.sh 30 "GitHub 连不上，要开 VPN 吗"
#
# 退出码：
#   0 = 用户点了确认（开 VPN）
#   4 = 用户点了取消
#   5 = 超时没答复
#   6 = 请求写不出去（多半没装 CountdownHUD）
#
set -eu

REQ_DIR=/rootfs/var/mobile/Library/Preferences
REQ="$REQ_DIR/.countdownhud-request"
ANSWER="$REQ_DIR/.countdownhud-answer"

WAIT=${1:-20}
LABEL=${2:-需要开 VPN}

case "$WAIT" in
  ''|*[!0-9]*)
    echo "vpn-guard: 秒数必须是数字（收到 '$WAIT'）" >&2
    exit 2
    ;;
esac

[ -d "$REQ_DIR" ] || { echo "vpn-guard: $REQ_DIR 不存在" >&2; exit 6; }

# 清掉上一次的答复，免得到点读到旧答案。
: > "$ANSWER" 2>/dev/null || true
NOW=$(date +%s)

# `?` 前缀 = 确认弹窗（按钮「立即注销」；这里借它表示「确认开 VPN」——
# 窗上的按钮文案是插件固定的，所以标签里写清楚要确认的是什么）。
if ! printf '%s|%s|?%s\n' "$NOW" "$WAIT" "$LABEL" > "$REQ" 2>/dev/null; then
  echo "vpn-guard: 写弹窗请求失败（多半没装 CountdownHUD 1.5.0+）" >&2
  exit 6
fi
echo "vpn-guard: 屏幕上已弹出确认框（${WAIT} 秒）：$LABEL"

# 等用户在屏幕上做决定：只认比本次请求更新的答复。
waited=0
while [ "$waited" -le $((WAIT + 5)) ]; do
  if [ -f "$ANSWER" ]; then
    line=$(cat "$ANSWER" 2>/dev/null || true)
    ans_epoch=${line%%|*}
    ans_verdict=${line#*|}
    case "$ans_epoch" in
      ''|*[!0-9]*) ans_epoch=0 ;;
    esac
    if [ "$ans_epoch" -ge "$NOW" ]; then
      case "$ans_verdict" in
        confirm)
          echo "vpn-guard: 用户确认（开 VPN）"
          exit 0
          ;;
        cancel|timeout)
          echo "vpn-guard: 用户取消 / 超时（$ans_verdict）"
          exit 4
          ;;
      esac
    fi
  fi
  sleep 1
  waited=$((waited + 1))
done

echo "vpn-guard: 超时没答复（退出码 5）"
exit 5
