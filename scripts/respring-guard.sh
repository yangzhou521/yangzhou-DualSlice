#!/bin/sh
#
# respring-guard.sh —— 注销的唯一入口，现在是五段：
#   警告 →（可选）屏幕上的系统确认框 → 用户决定 → 倒计时 → 注销。
#
# 用户 2026-10-31 05:33 原话：「以后注销事件给我一个警告⚠️弹窗 让我决定要不注销！」
# 05:35 补：「和 ios 系统桌面弹窗一样的弹窗！无论在任何界面有注销事件发生它就给我一个弹窗！」
# 所以默认行为改了：**不带 --confirm / 没在弹窗上点「立即注销」，就绝不注销**。
#
# 三种用法：
#   sh scripts/respring-guard.sh 5 注销             # ① 只警告：屏幕胶囊 + 终端正文，退出码 3，什么都不做
#   sh scripts/respring-guard.sh --ask 10 注销      # ② 屏幕上弹系统确认框，用户点「立即注销」才倒计时 + sbreload
#   sh scripts/respring-guard.sh --confirm 10 注销   # ③ 用户已在对话里明确答应，直接 10 秒倒计时 + sbreload
#
# 铁律：--confirm 只能用在「用户本轮明确答应了注销」之后。用户没回话、回的是「取消/先别」、
# 或者你只是自己觉得该注销了 —— 一律不准加 --confirm。没有他的答复，就停在①。
# --ask 更硬：屏幕上那个弹窗点了「取消」或超时没人理，脚本一律退出、什么都不做。
#
# 警告怎么让用户看见（三路一起走）：
#   1) 装了 CountdownHUD 1.5.0+（com.yangzhou.countdownhud）时，`--ask` 写一条 `?` 请求：
#      SpringBoard 里弹一个和 iOS 桌面同款的系统对话框（「⚠️ 即将注销」/「取消」/「立即注销」），
#      窗口层级高过一切 App 与灵动岛，任何界面都盖得住。用户点完把结果写进
#      `<真根>/var/mobile/Library/Preferences/.countdownhud-answer`（`<epoch>|confirm|cancel|timeout`）。
#   2) 老版本（1.4.x）或只想提醒时，写 `<epoch>|<秒数>|!<文案>`：灵动岛纯文案胶囊，不倒数、不震。
#   3) 终端里逐行打印，Apelin 正文/日志可见。
#
# 本机命令：
#   - 注销用 `sbreload`（不弹批准卡片）。2026-10-30 的写法 `icli sb respring` 仍然可用，
#     但本机开着 Apelin「使用屏幕前先询问」时每条 icli 都要用户点一次批准，所以换成 sbreload。
#   - 2026-10-30 实测 `icli respring` 报 "Unexpected argument 'respring'"；要用 icli 就得写 sb respring。
#
# 退出码：0 已执行 / 3 只警告 / 4 用户在弹窗上点了取消 / 5 弹窗超时没答复 / 6 弹窗请求写不出去
#
# 用法：
#   sh scripts/respring-guard.sh 5 注销                      # 只警告（退出码 3）
#   sh scripts/respring-guard.sh --ask 10 注销               # 弹系统确认框，点头才注销
#   sh scripts/respring-guard.sh --confirm 10 注销            # 用户答应后才：10 秒倒计时 + 注销
#   RESPRING_GUARD_NO_RESPRING=1 sh scripts/respring-guard.sh --confirm 5 装包   # 只倒计时
#
set -eu

# RESPRING_GUARD_NO_RESPRING=1：只倒计时，不注销（装包这类要自己接着做动作时用）。
NO_RESPRING=${RESPRING_GUARD_NO_RESPRING:-0}

# --confirm（用户已明确答应注销）/ --ask（在屏幕上问用户）必须写在最前面。
CONFIRM=0
ASK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) CONFIRM=1; shift ;;
    --ask) ASK=1; shift ;;
    *) break ;;
  esac
done

WAIT=${1:-10}
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
ANSWER="$REQ_DIR/.countdownhud-answer"
# v1.6.1 起：CountdownHUD 点了「立即注销」会自己 spawn sbreload（不再等本脚本）。
# 这个标记文件存在时插件只写答案、不注销 —— 即 RESPRING_GUARD_NO_RESPRING=1 的「只倒计时」安全验法。
NOMARK="$REQ_DIR/.countdownhud-no-respring"

hud_request() {   # $1=秒数 $2=标签
  [ -d "$REQ_DIR" ] || return 1
  printf '%s|%s|%s\n' "$(date +%s)" "$1" "$2" > "$REQ" 2>/dev/null
}

# 等用户在弹窗上做决定：只认比本次请求更新的答复（epoch 比较），返回
# confirm / cancel / timeout / none 四个词之一。
wait_answer() {   # $1=本次请求的 epoch $2=最多等几秒
  start=$1
  limit=$2
  waited=0
  while [ "$waited" -le "$limit" ]; do
    if [ -f "$ANSWER" ]; then
      line=$(cat "$ANSWER" 2>/dev/null || true)
      ans_epoch=${line%%|*}
      ans_verdict=${line#*|}
      case "$ans_epoch" in
        ''|*[!0-9]*) ans_epoch=0 ;;
      esac
      if [ "$ans_epoch" -ge "$start" ]; then
        case "$ans_verdict" in
          confirm|cancel|timeout) printf '%s\n' "$ans_verdict"; return 0 ;;
        esac
      fi
    fi
    sleep 1
    waited=$((waited + 1))
  done
  printf 'none\n'
  return 0
}

# ---------- ① 警告：不注销，等用户决定 ----------
if [ "$CONFIRM" != "1" ] && [ "$ASK" != "1" ]; then
  if hud_request 10 "!⚠️ 要注销吗？在 Apelin 回「注销」或「取消」"; then
    echo "respring-guard: 已在屏幕胶囊上弹出注销警告（10 秒）"
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

# ---------- ② 在屏幕上问用户：系统确认框 ----------
if [ "$ASK" = "1" ] && [ "$CONFIRM" != "1" ]; then
  # v1.6.1：插件点了「立即注销」会自己注销。只倒计时安全验法（NO_RESPRING=1）必须同时管住插件，
  # 否则「只倒计时」会变成真注销 —— 用标记文件，退出时（含异常）一定删掉。
  if [ "$NO_RESPRING" = "1" ]; then
    : > "$NOMARK" 2>/dev/null || true
    trap 'rm -f "$NOMARK"' EXIT INT TERM HUP
    echo "respring-guard: RESPRING_GUARD_NO_RESPRING=1 → 已置 $NOMARK（插件只写答案，不会真注销）"
  fi
  # 先清掉上一次的答复，免得到点读到旧答案。
  : > "$ANSWER" 2>/dev/null || true
  NOW=$(date +%s)
  if hud_request "$WAIT" "?${LABEL}"; then
    echo "respring-guard: 屏幕上已弹出注销确认框（${WAIT} 秒内有效）：点「立即注销」才注销，点「取消」什么都不做"
  else
    echo "respring-guard: 写弹窗请求失败（多半没装 CountdownHUD 1.5.0+）" >&2
    exit 6
  fi
  echo "respring-guard: 等你在弹窗上做决定…"
  VERDICT=$(wait_answer "$NOW" $((WAIT + 5)))
  echo "respring-guard: 你的选择：${VERDICT}"
  case "$VERDICT" in
    confirm) CONFIRM=1 ;;
    cancel)
      echo "respring-guard: 已取消，什么都不做（退出码 4）"
      exit 4
      ;;
    *)
      echo "respring-guard: 超时 / 没答复，什么都不做（绝不自动注销，退出码 5）"
      exit 5
      ;;
  esac
fi

if [ "$CONFIRM" != "1" ]; then
  echo "respring-guard: 没有用户批准，不注销（退出码 3）"
  exit 3
fi

# ---------- ③ 用户已答应：10 秒倒计时 ----------
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
