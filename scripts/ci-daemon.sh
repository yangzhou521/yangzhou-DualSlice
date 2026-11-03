#!/bin/sh
#
# ci-daemon.sh —— 独立云编译守护（agent 不活动时也定时查）。
#
# 为什么要有它：agent 对话会睡死/被压缩/换人，云端编译完成后没人第一时间知道。
# 本脚本后台常驻，每 N 分钟用 icli probe 查 GitHub Actions 最新一次运行，
# 结论一旦变化（pending/in_progress -> success/failure/cancelled），就用
# CountdownHUD 灵动岛胶囊主动通知，并把结论写进状态文件防止重复通知。
#
# 用法：
#   启动：nohup sh scripts/ci-daemon.sh [分钟间隔] > scripts/.tmp/ci-daemon.log 2>&1 &
#   查看：tail -f scripts/.tmp/ci-daemon.log
#   停止：pkill -f ci-daemon.sh
#
# 依赖：icli、hud-notify.sh、CountdownHUD（已装 v1.6.11，能显示纯文案胶囊）。
#   若 CountdownHUD 不在跑，胶囊不显示，但结论仍会写进状态文件 + 日志。
#
# 局限：
#   1. apelin_notification_send（真 iOS 系统通知）是 agent 工具，shell 守护脚本
#      不能直接调；需要 agent 下次活动时补发，或由另一条对话触发。
#   2. 重启/设备重越狱后后台进程会消失，需手动重启本脚本；要跨重启持久，
#      需改走 launchd LaunchDaemon（写系统路径，需 root + 用户同意）。
#   3. shell_run 后台进程是否随会话结束而存活，取决于 Apelin 的 shell 实现；
#      建议启动后用 `ps | grep ci-daemon` 或看日志确认进程还在。
#
set -u

HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PROJ="${APELIN_PROJECT_ROOT:-$(cd "$HERE/.." 2>/dev/null && pwd)}"
STATE="$PROJ/scripts/.tmp/ci-daemon.state"
LOG="$PROJ/scripts/.tmp/ci-daemon.log"
INTERVAL="${1:-10}"
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=10;; esac
[ "$INTERVAL" -lt 2 ] && INTERVAL=2
[ "$INTERVAL" -gt 120 ] && INTERVAL=120

mkdir -p "$PROJ/scripts/.tmp"
echo "ci-daemon: 启动，间隔 ${INTERVAL} 分钟，状态文件 $STATE" >> "$LOG" 2>&1

while true; do
  OUT=$(icli probe "$HERE/ci-last-state.js" 2>/dev/null)
  NEW=$(printf '%s' "$OUT" | sed -n 's/.*concl=\([^ ]*\).*/\1/p')
  ID=$(printf '%s' "$OUT" | sed -n 's/.*id=\([^ ]*\).*/\1/p')
  SHA=$(printf '%s' "$OUT" | sed -n 's/.*sha=\([^ ]*\).*/\1/p')
  OLD=$(cat "$STATE" 2>/dev/null)

  if [ -n "$NEW" ] && [ "$NEW" != "$OLD" ]; then
    printf '%s' "$NEW" > "$STATE"
    echo "ci-daemon: 状态变 $OLD -> $NEW (id=$ID sha=$SHA) $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG" 2>&1
    case "$NEW" in
      success)  TEXT="!云编译完成✅ id=$ID sha=${SHA:0:7}" ;;
      failure)  TEXT="!云编译失败❌ id=$ID concl=$NEW" ;;
      cancelled) TEXT="!云编译被取消⚠️ id=$ID" ;;
      *)        TEXT="!云编译状态：$NEW id=$ID" ;;
    esac
    sh "$HERE/hud-notify.sh" 8 "$TEXT" >> "$LOG" 2>&1 || true
  fi

  sleep $((INTERVAL * 60))
done
