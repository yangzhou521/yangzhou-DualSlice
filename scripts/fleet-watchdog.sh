#!/bin/sh
# fleet-watchdog.sh — launchd 定时守护：检测全员停摆 → 写 HUD 提醒
#
# 由 launchd 每 5 分钟（300 秒）调用，运行在 root 命名空间（非 jbroot）。
# 读 fleet/board.tsv，如果近 N 分钟内没有任何 agent 更新黑板（活线=0），
# 且存在「应该在干活却停了」的 agent，就写 CountdownHUD 纯文案请求，
# 让用户在屏幕上看到「⚠ 全队停摆」。
#
# jbroot 前缀会变（重新越狱），用 glob 运行时解析，不写死路径。
# 重新越狱后 launchd plist 会丢失（在 jbroot /Library/LaunchDaemons 里），
# 需要重跑 scripts/install-watchdog.sh。
#
# v2（2026-10-31 03:4x，根治「看护误报」）：
#   旧版只看 board.tsv 那行的 updated 时间戳 + state，**不查会话真实状态**，
#   于是「Apelin 侧早已 ended 的会话」只要黑板行还停在 working、时间戳又老，
#   每 5 分钟就被当睡死写进 wake-needed.tsv 排第一，全队被带着误判停摆
#   （日志里出现过 STOPPAGE alive=0/10）。案例：docs/cases/fleet-watchdog-false-positive.md
#
#   现在的判活依据（两条都满足才算「真停摆」）：
#     ① 黑板行本身超过 THRESHOLD 分钟没更新；
#     ② **该 agent 的会话文件 sessions/<session_id>/events.jsonl 也超过 THRESHOLD
#        分钟没有新内容**（会话文件是 Apelin 每次工具调用/消息都落盘的地方，
#        它不动 = 这个 agent 真的没在干活，与黑板状态无关）。
#   会话 id 从名册 fleet/agents.tsv 第 3 列取；名册里没有的（黑板有行但没登记）
#   一律当「不可核实」→ 不写进唤醒清单，避免白唤醒一个不存在的会话。
#
#   注意：会话的**真实状态**（ended / waitingForApproval / running 卡死）
#   只有 apelin_conversation_list 能查，脚本拿不到；所以看护只负责缩小名单，
#   真正发唤醒之前，发起方必须先 apelin_conversation_read 核 state
#   （ended 不能靠消息唤醒，只能用户在侧栏重开）。
#
# 环境：root 命名空间里 /usr/bin 是 GNU coreutils（date -d / find -newermt 可用）；
#      脚本只用 POSIX sh + 这些 GNU 扩展，不写死 jbroot 前缀。

set -u

THRESHOLD=${1:-20}   # 分钟：超过这个没更新就算「停摆」

# 1. 找 fleet 目录（jbroot 在 /private/var/containers/Bundle/Application/.jbroot-*）
#    测试时可以用 FLEET_DIR / HUD 环境变量覆盖，免得动真黑板、弹真胶囊。
if [ -z "${FLEET_DIR:-}" ]; then
  for d in /private/var/containers/Bundle/Application/.jbroot-*/var/mobile/Documents/wiki.qaq.apelin/fleet; do
    [ -d "$d" ] && [ -f "$d/board.tsv" ] && FLEET_DIR="$d" && break
  done
fi
[ -n "${FLEET_DIR:-}" ] || exit 0

BOARD="$FLEET_DIR/board.tsv"
[ -s "$BOARD" ] || exit 0   # 空黑板 = 没人在跑，不报
ROSTER="$FLEET_DIR/agents.tsv"
LOG="$FLEET_DIR/watchdog.log"
WAKE_FILE="$FLEET_DIR/wake-needed.tsv"

# 1b. 会话目录：fleet 同级的 sessions/<session_id>/
SESSIONS_DIR="$(dirname "$FLEET_DIR")/sessions"
[ -d "$SESSIONS_DIR" ] || SESSIONS_DIR=""

NOW=$(date +%s)
TAB="$(printf '\t')"
ALIVE=0
TOTAL=0
STALLED=""
STALLED_N=0
INACTIVE=0   # done/idle/handoff/waiting-user（正常的非活跃）

# 名册里的 agent → 全 session id
full_id_of() {
  [ -s "$ROSTER" ] || return 0
  awk -F"$TAB" -v k="$1" '$1 == k { print $3; exit }' "$ROSTER"
}

# 该 agent 的会话最近 THRESHOLD 分钟内有没有活动：
#   0 = 有活动（人还在干活）；THRESHOLD = 同样老（确实停摆）；-1 = 无法核实
session_active() {
  sid=$1
  [ -n "$sid" ] || { echo "-1"; return 0; }
  [ -n "$SESSIONS_DIR" ] || { echo "-1"; return 0; }
  f="$SESSIONS_DIR/$sid/events.jsonl"
  if [ ! -f "$f" ]; then
    d="$SESSIONS_DIR/$sid"
    if [ -d "$d" ]; then f="$d"; else echo "-1"; return 0; fi
  fi
  ref=$(date -d "@$((NOW - THRESHOLD * 60))" '+%Y-%m-%d %H:%M' 2>/dev/null)
  [ -n "$ref" ] || { echo "-1"; return 0; }
  if find "$f" -newermt "$ref" 2>/dev/null | grep -q .; then
    echo 0
  else
    echo "$THRESHOLD"
  fi
}

while IFS="$TAB" read -r agent project state task step device updated; do
  [ -n "${agent:-}" ] || continue
  case "$state" in
    done|idle|handoff|waiting-user|waiting-approval)
      TOTAL=$((TOTAL + 1))
      INACTIVE=$((INACTIVE + 1)); continue ;;
    working|assigned|blocked)
      TOTAL=$((TOTAL + 1)) ;;   # 这三种才是「应该在干活」
    *)
      # 字段错位的畸形行（例如 agent 列写成了工程名）：既不告警也不写唤醒清单，
      # 只记一笔，免得白唤醒一个不存在的会话。
      printf '%s MALFORMED agent=%s state=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$agent" "$state" >> "$LOG"
      continue ;;
  esac
  age=$(( (NOW - ${updated:-0}) / 60 ))
  if [ "$age" -lt "$THRESHOLD" ]; then
    ALIVE=$((ALIVE + 1))
    continue
  fi
  # 黑板老 → 再看会话文件：会话最近仍在动 ⇒ 这个人其实在干活（只是没打心跳）
  sid=$(full_id_of "$agent")
  if [ -z "$sid" ]; then
    printf '%s NO-ROSTER agent=%s state=%s age=%sm（名册里没有，不写唤醒清单）\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$agent" "$state" "$age" >> "$LOG"
    continue
  fi
  act=$(session_active "$sid")
  if [ "$act" != "-1" ] && [ "$act" -lt "$THRESHOLD" ]; then
    ALIVE=$((ALIVE + 1))
    printf '%s BOARD-STALE-ONLY agent=%s board_age=%sm session_active=1（活线，不算睡死）\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$agent" "$age" >> "$LOG"
    continue
  fi
  STALLED="$STALLED $agent"
  STALLED_N=$((STALLED_N + 1))
done < "$BOARD"

# 3. 判定与告警
# HUD 文件路径：launchd（root 命名空间）直接写 /var/mobile/...；
# agent shell（jbroot 命名空间）需要 /rootfs/var/mobile/...
if [ -z "${HUD:-}" ]; then
  if [ -d /rootfs ]; then
    HUD="/rootfs/var/mobile/Library/Preferences/.countdownhud-request"
  else
    HUD="/var/mobile/Library/Preferences/.countdownhud-request"
  fi
fi
stamp=$(date '+%Y-%m-%d %H:%M:%S')

# 清空上次的唤醒清单（每次运行重建）
: > "$WAKE_FILE"

# 有 stalled（黑板与会话都没动静）→ 写唤醒清单 + 按严重程度告警
if [ -n "$STALLED" ]; then
  # 写唤醒清单：每行 <agent>\t<project>\t<task>\t<step>\t<minutes>\t<session_id>
  # 协调群下次收到消息时读这个文件批量唤醒
  # 注意：发之前必须先核会话真实状态（ended 收不到消息，只能用户重开）。
  while IFS="$TAB" read -r ag proj st tk sp dev upd; do
    [ -n "${ag:-}" ] || continue
    case "$st" in
      done|idle|handoff|waiting-user|waiting-approval) continue ;;
      working|assigned|blocked) : ;;
      *) continue ;;   # 畸形行不进唤醒清单
    esac
    age_min=$(( (NOW - ${upd:-0}) / 60 ))
    if [ "$age_min" -ge "$THRESHOLD" ]; then
      sid=$(full_id_of "$ag")
      [ -n "$sid" ] || continue
      printf '%s\t%s\t%s\t%s\t%sm\t%s\n' "$ag" "${proj:-?}" "${tk:-?}" "${sp:-?}" "$age_min" "$sid" >> "$WAKE_FILE"
    fi
  done < "$BOARD"

  if [ "$ALIVE" -eq 0 ]; then
    # 全员停摆：胶囊里必须带「几条、怎么唤醒」——用户在屏幕上就能照做
    # （CountdownHUD 纯文案模式 32 字截断，文案要短）
    printf '%s|8|!⚠全队停摆%d条 说"开工"\n' "$NOW" "$STALLED_N" > "$HUD"
    printf '%s STOPPAGE alive=0/%d inactive=%d stalled=%s\n' \
      "$stamp" "$TOTAL" "$INACTIVE" "$STALLED" >> "$LOG"
  elif [ "$ALIVE" -eq 1 ]; then
    # 只剩一条活线
    printf '%s|8|!⚠只剩1条活线 %d条已停\n' "$NOW" "$STALLED_N" > "$HUD"
    printf '%s THIN alive=1/%d inactive=%d stalled=%s\n' \
      "$stamp" "$TOTAL" "$INACTIVE" "$STALLED" >> "$LOG"
  else
    # 有个体睡死但还有 ≥2 条活线：写唤醒清单让协调群处理，不弹 HUD（避免打扰）
    printf '%s STALLED alive=%d/%d inactive=%d stalled=%s (wake-needed.tsv written)\n' \
      "$stamp" "$ALIVE" "$TOTAL" "$INACTIVE" "$STALLED" >> "$LOG"
  fi
fi

# 4. 心跳：每次运行都覆盖（含没告警的那些次），用来验证 launchd 守护还活着
#    查：读 watchdog-last-run 的 epoch 与当前时间差 < 600 秒即正常。
date +%s > "$FLEET_DIR/watchdog-last-run"

exit 0
