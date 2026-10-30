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
LOG="$FLEET_DIR/watchdog.log"
WAKE_FILE="$FLEET_DIR/wake-needed.tsv"

# 2. 算活线：只有 working|assigned|blocked 三种算「应该在干活」；
#    done/idle/handoff/waiting-user/waiting-approval 是有意停下（waiting-approval＝等 icli 审批卡，
#    不是睡死，必须跳过）；其它任何状态都当字段错位的畸形行，不告警、不进唤醒清单、只记一笔。
#    近 THRESHOLD 分钟内更新过 = 活线，超了 = 睡死。
NOW=$(date +%s)
TAB="$(printf '\t')"
ALIVE=0
TOTAL=0
STALLED=""
STALLED_N=0
INACTIVE=0   # done/idle/handoff/waiting-user（正常的非活跃）

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
  else
    STALLED="$STALLED $agent"
    STALLED_N=$((STALLED_N + 1))
  fi
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

# 有 stalled（应该干活却停了）→ 写唤醒清单 + 按严重程度告警
if [ -n "$STALLED" ]; then
  # 写唤醒清单：每行 <agent>\t<project>\t<task>\t<step>\t<minutes>\t<session_id_hint>
  # 协调群下次收到消息时读这个文件批量唤醒
  while IFS="$TAB" read -r ag proj st tk sp dev upd; do
    [ -n "${ag:-}" ] || continue
    case "$st" in
      done|idle|handoff|waiting-user|waiting-approval) continue ;;
      working|assigned|blocked) : ;;
      *) continue ;;   # 畸形行不进唤醒清单
    esac
    age_min=$(( (NOW - ${upd:-0}) / 60 ))
    if [ "$age_min" -ge "$THRESHOLD" ]; then
      printf '%s\t%s\t%s\t%s\t%sm\n' "$ag" "${proj:-?}" "${tk:-?}" "${sp:-?}" "$age_min" >> "$WAKE_FILE"
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
