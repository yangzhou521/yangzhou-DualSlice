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
FLEET_DIR=""
for d in /private/var/containers/Bundle/Application/.jbroot-*/var/mobile/Documents/wiki.qaq.apelin/fleet; do
  [ -d "$d" ] && [ -f "$d/board.tsv" ] && FLEET_DIR="$d" && break
done
[ -n "$FLEET_DIR" ] || exit 0

BOARD="$FLEET_DIR/board.tsv"
[ -s "$BOARD" ] || exit 0   # 空黑板 = 没人在跑，不报

# 2. 算活线（state 非 done/idle/handoff/waiting-user/waiting-approval 且近 THRESHOLD 分钟内更新过）
#    注意：waiting-approval（v7 审批接力）是等 icli 审批，不是睡死，必须跳过。
NOW=$(date +%s)
TAB="$(printf '\t')"
ALIVE=0
TOTAL=0
STALLED=""
INACTIVE=0   # done/idle/handoff/waiting-user（正常的非活跃）

while IFS="$TAB" read -r agent project state task step device updated; do
  [ -n "${agent:-}" ] || continue
  TOTAL=$((TOTAL + 1))
  case "$state" in
    done|idle|handoff|waiting-user|waiting-approval)
      INACTIVE=$((INACTIVE + 1)); continue ;;
  esac
  age=$(( (NOW - ${updated:-0}) / 60 ))
  if [ "$age" -lt "$THRESHOLD" ]; then
    ALIVE=$((ALIVE + 1))
  else
    STALLED="$STALLED $agent"
  fi
done < "$BOARD"

# 3. 判定与告警
# HUD 文件路径：launchd（root 命名空间）直接写 /var/mobile/...；
# agent shell（jbroot 命名空间）需要 /rootfs/var/mobile/...
if [ -d /rootfs ]; then
  HUD="/rootfs/var/mobile/Library/Preferences/.countdownhud-request"
else
  HUD="/var/mobile/Library/Preferences/.countdownhud-request"
fi
ts=$(date '+%H:%M')
LOG="$FLEET_DIR/watchdog.log"
stamp=$(date '+%Y-%m-%d %H:%M:%S')

# 有 stalled（应该干活却停了）且活线 ≤ 1 → 告警
if [ -n "$STALLED" ]; then
  if [ "$ALIVE" -eq 0 ]; then
    # 全员停摆
    printf '%s|8|!⚠全队停摆 %s\n' "$NOW" "$ts" > "$HUD"
    printf '%s STOPPAGE alive=0/%d inactive=%d stalled=%s\n' \
      "$stamp" "$TOTAL" "$INACTIVE" "$STALLED" >> "$LOG"
  elif [ "$ALIVE" -eq 1 ]; then
    # 只剩一条活线
    printf '%s|8|!⚠只剩一条活线 %s\n' "$NOW" "$ts" > "$HUD"
    printf '%s THIN alive=1/%d inactive=%d stalled=%s\n' \
      "$stamp" "$TOTAL" "$INACTIVE" "$STALLED" >> "$LOG"
  fi
fi

# 4. 心跳：每次运行都覆盖（含没告警的那些次），用来验证 launchd 守护还活着
#    查：读 watchdog-last-run 的 epoch 与当前时间差 < 600 秒即正常。
date +%s > "$FLEET_DIR/watchdog-last-run"

exit 0
