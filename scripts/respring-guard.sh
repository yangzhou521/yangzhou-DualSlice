#!/bin/sh
#
# respring-guard.sh —— 注销前的强制闸门：先让屏幕上出现 5 秒倒计时，再 respring。
#
# 为什么要有这个脚本：用户 2026-10-30 反复要求「注销 / 装包 / 杀进程前必须通知 + 倒计时 5 秒」，
# 仍然漏过。光靠记性不行，所以把倒计时做成只有一条路的脚本：只要注销就走它，走它就有 5 秒。
#
# 倒计时怎么显示：两路一起走，哪一路通都不用等。
#   1) 装了 CountdownHUD（com.yangzhou.countdownhud）时，把请求写进
#      `<真根>/var/mobile/Library/Preferences/.countdownhud-request`
#      （格式 `<epoch>|<秒数>|<标签>`），SpringBoard 里那个插件自己画胶囊。
#      **通知那条路不可靠**（Apelin 发通知会把 App 拉回前台、横幅被自己吞掉），所以不指望它。
#   2) 没有 HUD 时，脚本自己在终端里逐秒打印，用户能从 Apelin 的正文/日志看到。
#
# 通知仍然必须先发：apelin_notification_send 由会话调用，脚本发不了。
#
# 本机命令是 `icli sb respring`（2026-10-30 实测：`icli respring` 报
# "Unexpected argument 'respring'"）；切记。
#
# 用法：
#   sh scripts/respring-guard.sh                 # 5 秒倒计时后 icli sb respring
#   RESPRING_GUARD_NO_RESPRING=1 sh scripts/respring-guard.sh 5 装包   # 只倒计时
#   sh scripts/respring-guard.sh 8 装包           # 8 秒，标签「装包」
#
set -eu

# RESPRING_GUARD_NO_RESPRING=1：只倒计时，不注销（装包这类要自己接着做动作时用）。
NO_RESPRING=${RESPRING_GUARD_NO_RESPRING:-0}

WAIT=${1:-5}
LABEL=${2:-注销}

case "$WAIT" in
  ''|*[!0-9]*)
    echo "respring-guard: 秒数必须是数字（收到 '$WAIT'）" >&2
    exit 2
    ;;
esac

# shell 跑在 bootstrap 命名空间里，写系统路径要加真根前缀 /rootfs；
# 插件在 SpringBoard 里读的是系统原路径 /var/mobile/...（见 apelin-bootstrap-paths）。
REQ_DIR=/rootfs/var/mobile/Library/Preferences
REQ="$REQ_DIR/.countdownhud-request"

if [ -d "$REQ_DIR" ]; then
  EPOCH=$(date +%s)
  printf '%s|%s|%s\n' "$EPOCH" "$WAIT" "$LABEL" > "$REQ" 2>/dev/null \
    && echo "respring-guard: 已请求 CountdownHUD 显示 ${WAIT} 秒（$LABEL）" \
    || echo "respring-guard: 写 HUD 请求失败（多半没装 CountdownHUD），只用终端倒计时"
else
  echo "respring-guard: $REQ_DIR 不存在，只用终端倒计时"
fi

echo "respring-guard: 通知发过了吗？没发就别往下走（apelin_notification_send）。"
echo "respring-guard: ${WAIT} 秒后${LABEL}"
i=$WAIT
while [ "$i" -gt 0 ]; do
  echo "  $i…"
  sleep 1
  i=$((i - 1))
done
echo "respring-guard: 执行${LABEL}"
if [ "$NO_RESPRING" = "1" ]; then
  echo "respring-guard: 只倒计时，不注销（RESPRING_GUARD_NO_RESPRING=1）"
  exit 0
fi
exec icli sb respring