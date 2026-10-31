#!/bin/sh
# quota-guard.sh —— 额度守护：只扫「在跑」的会话，判断是否被限流
#
# 背景（2026-10-31 20:4x 实测）：Apelin 的限流是**账号/网关层**的 —— 换模型绕不过。
#   实测 deepseek-v4.1-flash / minimax-m3.1-flash / glm-5.2 三个不同厂商的模型在同一时刻
#   给出**完全相同**的提示与重置时间：
#   「您的使用量已超出频率限制，将在 2026-11-01 01:07:36 UTC+8 重置，您也可以切换其他模型继续使用。」
#   所以能做的只有：① 等窗口重置；② 把有限额度集中给最关键的活；③ 少开并发、少发长消息。
#   `sweep` 切模型只是让窗口重置后能立刻干活，**不是**绕过限流。
#
# 为什么要「只扫在跑」：早期的版本扫全部 ~100 个会话、每个都 grep 大体积 events.jsonl，
#   在 shell_run 里被 60 秒超时杀过一次（exit 137）。现在默认只看最近 N 分钟内有写入的会话，
#   并且只看文件尾部 4KB。
#
# 用法：
#   sh scripts/quota-guard.sh status [分钟]   # 列出最近 N 分钟活跃的会话（默认 60）
#   sh scripts/quota-guard.sh sweep  [分钟]   # 把被限流的会话切到备用模型（默认 60）
#   sh scripts/quota-guard.sh watch  [分钟]   # 只看不改，给定时长内打印被限流的会话
set -eu

SESS="${HOME}/Documents/wiki.qaq.apelin/sessions"
BACKUP_MODEL="${QUOTA_BACKUP_MODEL:-deepseek-flash}"
WINDOW="${1:-60}"
TAB=$(printf '\t')

# 秒数：最近 N 分钟的会话才算「在跑」
recent_sessions() {
  mins="$1"
  [ -d "$SESS" ] || return 0
  # find -mmin 比自己遍历快得多，也不会碰到无关的大文件
  find "$SESS" -maxdepth 2 -name events.jsonl -mmin "-$mins" 2>/dev/null | head -40
}

# 输出：sid <TAB> model <TAB> state <TAB> 证据
scan_one() {
  ev="$1"
  sid=$(basename "$(dirname "$ev")")
  sj="$(dirname "$ev")/session.json"
  model=$(grep -o '"model":"[^"]*"' "$sj" 2>/dev/null | head -1 | sed 's/.*:"//;s/"//') || model="?"
  [ -n "${model:-}" ] || model="?"
  tail4k=$(tail -c 4096 "$ev" 2>/dev/null) || tail4k=""

  # 限流提示优先（比 reason 准：reason=failed 也可能是别的原因）
  if printf '%s' "$tail4k" | grep -q '超出频率限制'; then
    # 抓重置时间，方便一眼看出什么时候恢复
    reset=$(printf '%s' "$tail4k" | grep -o '将在 [0-9-]* [0-9:]* UTC+8 重置' | tail -1 | sed 's/^将在 //;s/ 重置$//')
    printf '%s\t%s\tLIMITED\t%s\n' "$sid" "$model" "${reset:--}"
    return 0
  fi

  last=$(printf '%s' "$tail4k" | grep -o '"reason":"[a-z]*"' | tail -1 | sed 's/.*:"//;s/"//') || last=""
  case "${last:-}" in
    failed) printf '%s\t%s\tFAILED\t%s\n' "$sid" "$model" "reason=failed" ;;
    completed) printf '%s\t%s\tOK\t%s\n' "$sid" "$model" "reason=completed" ;;
    *) printf '%s\t%s\tidle\t%s\n' "$sid" "$model" "-" ;;
  esac
}

scan_all() {
  recent_sessions "$WINDOW" | while read -r ev; do
    [ -n "$ev" ] || continue
    scan_one "$ev"
  done
}

cmd_status() {
  printf '最近 %s 分钟内活跃的会话：\n' "$WINDOW"
  printf '%-38s %-22s %-8s %s\n' SESSION MODEL STATE 证据
  scan_all | sort -k3,3 | while IFS="$TAB" read -r sid model st why; do
    printf '%-38s %-22s %-8s %s\n' "$sid" "$model" "$st" "$why"
  done
}

cmd_sweep() {
  echo "quota-guard: 窗口 ${WINDOW} 分钟，备用模型 = $BACKUP_MODEL"
  echo "           （切模型不是绕过限流；窗口重置后才有用）"
  scan_all | while IFS="$TAB" read -r sid model st why; do
    case "$st" in
      LIMITED|FAILED)
        [ "$model" = "$BACKUP_MODEL" ] && continue
        f="$SESS/$sid/session.json"
        [ -r "$f" ] || continue
        cp "$f" "$f.bak-quota" 2>/dev/null || true
        # 只替换 model 字段的值，其余原样保留
        sed "s/\"model\":\"[^\"]*\"/\"model\":\"$BACKUP_MODEL\"/" "$f" > "$f.new" 2>/dev/null || continue
        if [ -s "$f.new" ]; then
          mv "$f.new" "$f"
          echo "  切 $sid: $model → $BACKUP_MODEL"
        fi
        rm -f "$f.new" 2>/dev/null || true
        ;;
    esac
  done
}

cmd_watch() {
  echo "quota-guard: 窗口 ${WINDOW} 分钟"
  scan_all | grep 'LIMITED' | while IFS="$TAB" read -r sid model st why; do
    echo "  $sid  $model  重置: $why"
  done
  n=$(scan_all | grep -c 'LIMITED' || true)
  echo "被限流：${n:-0} 个"
}

case "${1:-status}" in
  status) WINDOW="${2:-60}"; cmd_status ;;
  sweep) WINDOW="${2:-60}"; cmd_sweep ;;
  watch) WINDOW="${2:-60}"; cmd_watch ;;
  *) echo "用法: sh scripts/quota-guard.sh [status|sweep|watch] [分钟数]" >&2; exit 2 ;;
esac
