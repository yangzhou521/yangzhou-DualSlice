#!/bin/sh
# 断点自愈看护：WORK-STATE.json 是 running 但超时没更新 → 灵动岛上提醒一句。
# 只提醒，不拍板、不自动继续、不动设备。用法： sh scripts/work-state-watch.sh [超时分钟数，默认30]
set -u
D="${APELIN_PROJECT_ROOT:?}/scripts/WORK-STATE.json"
LIMIT="${1:-30}"

[ -f "$D" ] || exit 0
ST=$(sed -n 's/.*"status":[[:space:]]*"\([^"]*\)".*/\1/p' "$D" | head -1)
[ "$ST" = "running" ] || exit 0

UP=$(sed -n 's/.*"updated":[[:space:]]*"\([^"]*\)".*/\1/p' "$D" | head -1)
TASK=$(sed -n 's/.*"task":[[:space:]]*"\([^"]*\)".*/\1/p' "$D" | head -1)

# updated 是 "YYYY-MM-DDTHH:MM+08:00"，用 date 转成 epoch，失败就当作过期但不打扰
EP=$(date -j -f "%Y-%m-%dT%H:%M%z" "$UP" +%s 2>/dev/null || echo "")
NOW=$(date +%s)
if [ -n "$EP" ]; then
  AGE=$(( (NOW - EP) / 60 ))
else
  AGE=$LIMIT
fi

if [ "$AGE" -ge "$LIMIT" ]; then
  MSG="断点 ${AGE} 分钟没更新：${TASK}"
  [ ${#MSG} -gt 30 ] && MSG="${MSG%????????????????????}…"
  sh "${APELIN_PROJECT_ROOT:?}/scripts/hud-notify.sh" 10 "!${MSG}" >/dev/null 2>&1 || true
  echo "stale=${AGE}min task=${TASK}"
else
  echo "ok=${AGE}min task=${TASK}"
fi
