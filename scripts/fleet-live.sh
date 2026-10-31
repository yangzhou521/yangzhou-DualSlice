#!/bin/sh
#
# fleet-live.sh —— 「全队此刻在干什么」，**不依赖任何人写黑板**。
#
# 为什么另起一个：board.tsv 是「自觉上报」，谁忘了写就看不见谁（用户 05:41 原话：
# 「我不说你们都不知道对方在干嘛」）。而 Apelin 自己就在给每个对话写 events.jsonl，
# 里面逐条记着：
#   toolCallStarted  → 工具名 + arguments，arguments 里有 `reason`（中文，就是意图）
#   messageFinished  → 那条回复的正文
#   finished         → 这一回合怎么结束的（failed 里能看到额度/限流）
# 这些是**副产物**，不需要任何 agent 配合。本脚本把它们读出来拼成一张表。
#
# 用法：
#   sh scripts/fleet-live.sh [分钟数]      # 默认 15 分钟内有活动的
#   sh scripts/fleet-live.sh 60            # 看一小时内的
#
# 输出一行一个对话：对话 | 最后活动 | 状态 | 最后动作（工具 · 意图） | 最后一句
#
# 2026-10-31 05:5x：这是**唯一**的全队视图。原来的共享黑板 board.tsv + fleet.sh +
# launchd 看护 + wake-needed.tsv + 心跳环形互跳已全部删除（用户原话：「删掉本地和云端
# 失败的那几种同步工作进展和内容的方法！」）——它们都要人写、还要推断别人死活，必然误报。
# 本脚本只读副产物，谁都不用配合，也不会漏。

SESS="$HOME/Documents/wiki.qaq.apelin/sessions"
WIN=${1:-15}
NOW=$(date +%s)
CUT=$((NOW - WIN * 60))

[ -d "$SESS" ] || { echo "fleet-live: 找不到 $SESS"; exit 1; }

# 先用 mtime 把不活跃的对话整个跳过：events.jsonl 动辄几万行，
# 全量 tail+反转义要 30 秒，只碰「这个窗口内写过字」的能压到几秒。
MARK="/tmp/.fleet-live-mark.$$"
trap 'rm -f "$MARK"' EXIT INT TERM
touch -d "-${WIN} minutes" "$MARK" 2>/dev/null || touch "$MARK"

# JSON 里 arguments 是转义过的（\"reason\":\"…\"），先反转义再按普通 JSON 抓
unesc() { sed 's/\\"/"/g'; }

printf '%-9s %-8s %-6s %s\n' "对话" "最后活动" "状态" "最后动作（工具 · 意图） ｜ 最后一句"
printf '%s\n' "--------------------------------------------------------------------------------"

for d in "$SESS"/*/; do
    f="$d/events.jsonl"
    [ -f "$f" ] || continue
    [ "$f" -nt "$MARK" ] || continue
    sid=$(basename "$d")

    # 只读文件尾 80 行：足够覆盖最后几次工具调用，又不至于扫整个几万行
    flat=$(tail -n 80 "$f" | unesc)
    [ -n "$flat" ] || continue

    ts=$(printf '%s\n' "$flat" | sed -n 's/.*"date":"\([0-9T:-]*Z\)".*/\1/p' | tail -1)
    [ -n "$ts" ] || continue
    epoch=$(date -u -d "$ts" +%s 2>/dev/null)
    [ -n "$epoch" ] || continue
    [ "$epoch" -ge "$CUT" ] || continue
    mins=$(( (NOW - epoch) / 60 ))

    # 状态判据：**看最后一个事件，不是看有没有 finished**。
    # 一个对话跑过很多回合，文件尾必然有上一回合的 finished —— 原来那句
    # `grep finished | tail -1` 会把正在跑的对话也判成「收工」（2026-10-31 12:27 实测：
    # 6c78afa4 正在跑 shell_run，表里却写「收工」，等于把最该看见的那条藏起来了）。
    # 正确做法：把「回合结束」事件剔掉，看剩下最后一个事件是什么；
    # 只有它在文件末尾时才是真收工。
    last_ev=$(printf '%s\n' "$flat" | grep -o '"\(toolCallStarted\|messageFinished\|finished\|reconnecting\|started\)"' | tail -1)
    fin=$(printf '%s\n' "$flat" | grep -o '"finished":{"reason":"[^"]*"' | tail -1 |
          sed 's/.*"reason":"//;s/"//')
    fin_epoch=""
    if [ -n "$fin" ]; then
        # finished 那一行的时间戳：只有它 ≥ 最后一个工具调用，才说明「真的停在收工」
        finline=$(printf '%s\n' "$flat" | grep '"finished"' | tail -1)
        fts=$(printf '%s' "$finline" | sed -n 's/.*"date":"\([0-9T:-]*Z\)".*/\1/p')
        [ -n "$fts" ] && fin_epoch=$(date -u -d "$fts" +%s 2>/dev/null)
    fi
    # 最后一个工具调用 / 消息的时间戳，用来判断「谁在后」
    ts_ev=$(printf '%s\n' "$flat" | grep -o '"date":"[0-9T:-]*Z"' | tail -1 | sed 's/.*"date":"//;s/"//')
    ev_epoch=$(date -u -d "$ts_ev" +%s 2>/dev/null)

    case "$fin" in
        failed) state="失败" ;;
        "")
            state="在跑" ;;
        *)
            # 有 finished，但只有它确实晚于最后一条工作事件才算收工；否则就是「又开工了」
            if [ -n "$fin_epoch" ] && [ -n "$ev_epoch" ] && [ "$ev_epoch" -gt "$fin_epoch" ]; then
                state="在跑"
            else
                state="收工"
            fi
            ;;
    esac

    # 最后一个工具调用那一行：名字 + 它自己写的中文 reason
    tline=$(printf '%s\n' "$flat" | grep '"toolCallStarted"' | tail -1)
    tool=$(printf '%s\n' "$tline" | grep -o '"name":"[a-z_]*"' | head -1 |
           sed 's/"name":"//;s/"//')
    reason=$(printf '%s\n' "$tline" | grep -o '"reason":"[^"]*"' | tail -1 |
             sed 's/"reason":"//;s/"$//')

    # 最后一条回复正文
    txt=$(printf '%s\n' "$flat" | grep '"messageFinished"' |
          grep -o '"text":"[^"]\{4,\}"' | tail -1 |
          sed 's/^"text":"//;s/"$//')

    act="$tool"
    [ -n "$reason" ] && act="$act · $reason"
    [ -z "$act" ] && act="(无工具调用)"
    if [ -n "$txt" ]; then
        act=$(printf '%s' "$act" | cut -c1-70)
        txt=$(printf '%s' "$txt" | cut -c1-45)
        act="$act ｜ $txt"
    fi

    printf '%-9s %3d分钟前 %-6s %s\n' "$(printf '%s' "$sid" | cut -c1-8)" "$mins" "$state" "$act"
done

printf '%s\n' "--------------------------------------------------------------------------------"
echo "（数据来自 Apelin 的 sessions/*/events.jsonl，无需任何 agent 配合；窗口 ${WIN} 分钟）"
