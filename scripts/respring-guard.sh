#!/bin/sh
#
# respring-guard.sh —— 注销前的强制闸门：先打印 5 秒倒计时，再 respring。
#
# 为什么要有这个脚本：用户 2026-10-30 两次要求「注销前必须通知 + 倒计时 5 秒」，都漏过。
# 光靠记性不行，所以把倒计时做成只有一条路的脚本：只要注销就走它，走它就有 5 秒。
# **它发不了通知**：通知必须先由会话里的 apelin_notification_send 工具发出，再调这个脚本。
#
# 用法：
#   sh scripts/respring-guard.sh          # 5 秒倒计时后 icli respring
#   sh scripts/respring-guard.sh 8        # 8 秒
#
set -eu

WAIT=${1:-5}
case "$WAIT" in
  ''|*[!0-9]*)
    echo "respring-guard: 秒数必须是数字（收到 '$WAIT'）" >&2
    exit 2
    ;;
esac

echo "respring-guard: 通知发过了吗？没发就别往下走。"
echo "respring-guard: ${WAIT} 秒后注销"
i=$WAIT
while [ "$i" -gt 0 ]; do
  echo "  $i…"
  sleep 1
  i=$((i - 1))
done
echo "respring-guard: 注销"
icli respring