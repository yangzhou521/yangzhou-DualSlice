#!/bin/sh
#
# respring-guard.sh —— 注销的唯一入口，现在是四段：警告 → 用户决定 → 倒计时 → 注销。
#
# 用户 2026-10-31 05:33 原话：「以后注销事件给我一个警告⚠️弹窗 让我决定要不注销！」
# 所以默认行为改了：**不带 --confirm 就只警告、绝不注销**。
#
#   sh scripts/respring-guard.sh 5 注销            # ① 警告：屏幕胶囊 + 终端正文，退出码 3，什么都不做
#   sh scripts/respring-guard.sh --confirm 5 注销  # ② 用户已明确说「注销/确定」之后才这样跑：5 秒倒计时 + sbreload
#
# 铁律：--confirm 只能用在「用户本轮明确答应了注销」之后。用户没回话、回的是「取消/先别」、
# 或者你只是自己觉得该注销了 —— 一律不准加 --confirm。没有他的答复，就停在①。
#
# 警告怎么让用户看见（两路一起走）：
#   1) 装了 CountdownHUD（com.yangzhou.countdownhud）时，把纯文案请求写进
#      `<真根>/var/mobile/Library/Preferences/.countdownhud-request`
#      （格式 `<epoch>|<秒数>|<标签>`，标签以 `!` 开头 = 纯文案、不倒数、不震、到时淡出）。
#      用户在别的 App / 桌面也看得见，比通知可靠（Apelin 通知会把 App 拉回前台、横幅被自己吞掉）。
#   2) 终端里逐行打印，Apelin 正文/日志可见。
#
# 本机命令：
#   - 注销用 `sbreload`（不弹批准卡片）。2026-10-30 的写法 `icli sb respring` 仍然可用，
#     但本机开着 Apelin「使用屏幕前先询问」时每条 icli 都要用户点一次批准，所以换成 sbreload。
#   - 2026-10-30 实测 `icli respring` 报 "Unexpected argument 'respring'"；要用 icli 就得写 sb respring。
#
# 用法：
#   sh scripts/respring-guard.sh 5 注销                      # 只警告（退出码 3）
#   sh scripts/respring-guard.sh --confirm 5 注销            # 用户答应后才：5 秒倒计时 + 注销
#   RESPRING_GUARD_NO_RESPRING=1 sh scripts/respring-guard.sh --confirm 5 装包   # 只倒计时
#
set -eu

# RESPRING_GUARD_NO_RESPRING=1：只倒计时，不注销（装包这类要自己接着做动作时用）。
NO_RESPRING=${RESPRING_GUARD_NO_RESPRING:-0}

# --confirm 必须写在最前面（用户已明确答应注销）。
CONFIRM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) CONFIRM=1; shift ;;
    *) break ;;
  esac
done

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

hud_request() {   # $1=秒数 $2=标签
  [ -d "$REQ_DIR" ] || return 1
  printf '%s|%s|%s\n' "$(date +%s)" "$1" "$2" > "$REQ" 2>/dev/null
}

# ---------- ① 警告：不注销，等用户决定 ----------
if [ "$CONFIRM" != "1" ]; then
  if hud_request 45 "!⚠️ 要注销吗？在 Apelin 回「注销」或「取消」"; then
    echo "respring-guard: 已在屏幕胶囊上弹出注销警告（45 秒）"
  else
    echo "respring-guard: 写 HUD 请求失败（多半没装 CountdownHUD），只在这里警告"
  fi
  echo "respring-guard: ==============================================="
  echo "respring-guard: ⚠️  注销警告：${LABEL}（原计划 ${WAIT} 秒后）"
  echo "respring-guard: ⚠️  现在什么都不做。要真的注销，必须等用户明确回一句"
  echo "respring-guard:    「注销」或「确定」，然后才："
  echo "respring-guard:      sh scripts/respring-guard.sh --confirm ${WAIT} ${LABEL}"
  echo "respring-guard:    用户回「取消」/ 没回话 → 就停在这里，不准自己往下走。"
  echo "respring-guard: ==============================================="
  echo "respring-guard: 退出码 3 = 只警告，未注销"
  exit 3
fi

# ---------- ② 用户已答应：5 秒倒计时 ----------
if hud_request "$WAIT" "$LABEL"; then
  echo "respring-guard: 已请求 CountdownHUD 显示 ${WAIT} 秒（$LABEL）"
else
  echo "respring-guard: 写 HUD 请求失败（多半没装 CountdownHUD），只用终端倒计时"
fi

echo "respring-guard: 通知发过了吗？没发就别往下走（apelin_notification_send）。"
echo "respring-guard: 别的对话同步过了吗？没同步就别往下走（apelin_project_list，再对每个工程"
echo "                 apelin_conversation_list project: <folder>，running/waitingForApproval 的先"
echo "                 apelin_conversation_send 打招呼并等它收尾）。"
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

# sbreload 不弹批准卡（icli sb respring 在不点卡片时会被卡住，见仓库 scripts/device.sh 的说明）。
exec sbreload
