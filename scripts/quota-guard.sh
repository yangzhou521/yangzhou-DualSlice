#!/bin/sh
# quota-guard.sh —— 额度守护：查各会话是否被限流，自动切线 + 记录队列状态
#
# 背景（2026-10-31 20:4x 实测）：
#   Apelin 的限流是**账号/网关层**的 —— 换模型无效。实测 deepseek-v4.1-flash / minimax-m3.1-flash /
#   glm-5.2 三个不同厂商的模型在同一时刻给出**完全相同**的提示与重置时间：
#   「您的使用量已超出频率限制，将在 2026-11-01 01:07:36 UTC+8 重置，您也可以切换其他模型继续使用。」
#   所以「换模型绕过限流」这条路不通，只能：① 等窗口重置；② 把有限额度集中给最关键的活；
#   ③ 少开并发、少发长消息（每次请求都吃额度）。
#
# 用法：
#   sh scripts/quota-guard.sh status      # 列出所有会话：模型 / 是否被限流 / 最后一次结果
#   sh scripts/quota-guard.sh sweep       # 扫描并把被限流的会话切到备用模型（不切回）
#   sh scripts/quota-guard.sh watch [分]  # 每分钟扫一次，打印被限流的会话（不自动切模型）
#
# 判据：events.jsonl 尾部出现「超出频率限制」或 Credits exhausted / reason=failed → 视为「限流中」。
# 恢复判据：其后出现一次 reason=completed → 视为恢复。
set -eu

SESS="${HOME}/Documents/wiki.qaq.apelin/sessions"
STATE_DIR="${APELIN_PROJECT_ROOT:?}/.tmp/quota"
mkdir -p "$STATE_DIR"

# 备用模型（按成本从低到高；换模型只是让恢复后能立刻干活，不是绕过限流）
FALLBACK="deepseek-flash"
BACKUP_MODEL="${QUOTA_BACKUP_MODEL:-deepseek-flash}"

list_sessions() {
  for d in "$SESS"/*/; do
    [ -f "$d/session.json" ] || continue
    sid=$(basename "$d")
    model=$(grep -o '"model":"[^"]*"' "$d/session.json" 2>/dev/null | head -1 | sed 's/.*:"//;s/"//')
    last=$(tail -c 4000 "$d/events.jsonl" 2>/dev/null | grep -o '"reason":"[a-z]*"' | tail -1 | sed 's/.*:"//;s/"//')
    # 限流判据：尾部有中文限流提示，或最后一次是 failed
    if tail -c 2000 "$d/events.jsonl" 2>/dev/null | grep -q '超出频率限制'; then
      st="LIMITED"
    elif [ "$last" = "failed" ]; then
      st="FAILED"
    elif [ "$last" = "completed" ]; then
      st="OK"
    else
      st="idle"
    fi
    printf '%s\t%s\t%s\t%s\n' "$sid" "$model" "$st" "$last"
  done
}

cmd_status() {
  printf '%-38s %-22s %-8s %s\n' SESSION MODEL STATE LAST
  list_sessions | sort -k3,3 | while IFS="$(printf '\t')" read -r sid model st last; do
    printf '%-38s %-22s %-8s %s\n' "$sid" "$model" "$st" "$last"
  done
}

cmd_sweep() {
  echo "quota-guard: 备用模型 = $BACKUP_MODEL"
  list_sessions | while IFS="$(printf '\t')" read -r sid model st last; do
    case "$st" in
      LIMITED|FAILED)
        if [ "$model" != "$BACKUP_MODEL" ]; then
          f="$SESS/$sid/session.json"
          cp "$f" "$f.bak-quota-$(date +%H%M%S)" 2>/dev/null || true
          newm=$(grep -o '"model":"[^"]*"' "$f" | head -1)
          sed "s/$newm/\"model\":\"$BACKUP_MODEL\"/" "$f" > "$f.new" 2>/dev/null || true
          if [ -s "$f.new" ]; then mv "$f.new" "$f"; echo "  切 $sid: $model → $BACKUP_MODEL"; fi
          rm -f "$f.new" 2>/dev/null || true
        fi
        ;;
    esac
  done
}

cmd_watch() {
  mins="${1:-10}"
  echo "quota-guard: 监控 $mins 分钟，每 60 秒一次"
  i=0
  while [ "$i" -lt "$mins" ]; do
    n=$(list_sessions | grep -c 'LIMITED' || true)
    echo "[$(date +%H:%M:%S)] 被限流的会话数：$n"
    list_sessions | grep 'LIMITED' | while IFS="$(printf '\t')" read -r sid model st last; do
      echo "    $sid  model=$model"
    done
    sleep 60
    i=$((i + 1))
  done
}

case "${1:-status}" in
  status) cmd_status ;;
  sweep) cmd_sweep ;;
  watch) cmd_watch "${2:-10}" ;;
  *) echo "用法: sh scripts/quota-guard.sh [status|sweep|watch [分]]" >&2; exit 2 ;;
esac
