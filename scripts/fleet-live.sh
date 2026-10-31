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
#   sh scripts/fleet-live.sh 30 alerts     # 只看「需要我处理的」：失败 / 等你批准 / 长跑可能卡死
#   sh scripts/fleet-live.sh 30 ping       # 打印「该催谁」的现成消息文本（不发送，自己复制或照抄）
#
# 输出一行一个对话：对话 | 最后活动 | 状态 | 最后动作（工具 · 意图） | 最后一句
#
# 状态含义（2026-10-31 12:28 修正判据）：
#   在跑 = 最后一条工作事件晚于这一回合的 finished（它正在干活）
#   收工 = 真的停在 finished 上（回合结束，发消息它会排队到下一回合）
#   失败 = finished.reason=failed（额度耗尽 / 限流 / 工具报错）——**这种必须有人去看**
#   卡住 = 判成「在跑」但已经 N 分钟没有任何新事件（N 见 STALL_MIN，默认 8 分钟）
#
# 2026-10-31 05:5x：这是**唯一**的全队视图。原来的共享黑板 board.tsv + fleet.sh +
# launchd 看护 + wake-needed.tsv + 心跳环形互跳已全部删除（用户原话：「删掉本地和云端
# 失败的那几种同步工作进展和内容的方法！」）——它们都要人写、还要推断别人死活，必然误报。
# 本脚本只读副产物，谁都不用配合，也不会漏。
#
# 2026-10-31 12:30 加 alerts / ping 两个视图：光看得见没用，得让它直接告诉你「现在该干什么」。
#   alerts = 只列出要人处理的（失败 / 卡住），别的行不打印，一眼看完。
#   ping   = 给每个需要催的对话生成一段可直接发的话，复制粘贴即可，省掉每次现编。

SESS="$HOME/Documents/wiki.qaq.apelin/sessions"
MODE="list"
case "${2:-}" in
    alerts|ping) MODE="$2" ;;
esac
WIN=${1:-15}
STALL_MIN=${FLEET_STALL_MIN:-8}
NOW=$(date +%s)
CUT=$((NOW - WIN * 60))

[ -d "$SESS" ] || { echo "fleet-live: 找不到 $SESS"; exit 1; }

# 临时文件只写项目内（本机 /tmp 常写不进，见 AGENTS.md 硬规矩）
TMPD="${APELIN_PROJECT_ROOT:-$PWD}/.tmp"
mkdir -p "$TMPD" || { echo "fleet-live: 建不了临时目录 $TMPD" >&2; exit 1; }

# 收集「需要处理」的行，供 alerts / ping 用
ALERTS="$TMPD/.fleet-alerts.$$"
trap 'rm -f "$MARK" "$ALERTS"' EXIT INT TERM
: > "$ALERTS"

# 先用 mtime 把不活跃的对话整个跳过：events.jsonl 动辄几万行，
# 全量 tail+反转义要 30 秒，只碰「这个窗口内写过字」的能压到几秒。
MARK="$TMPD/.fleet-live-mark.$$"
trap 'rm -f "$MARK" "$ALERTS"' EXIT INT TERM
touch -d "-${WIN} minutes" "$MARK" 2>/dev/null || touch "$MARK"

# JSON 里 arguments 是转义过的（\"reason\":\"…\"），先反转义再按普通 JSON 抓
unesc() { sed 's/\\"/"/g'; }

if [ "$MODE" = "list" ]; then
    printf '%-9s %-8s %-6s %s\n' "对话" "最后活动" "状态" "最后动作（工具 · 意图） ｜ 最后一句"
    printf '%s\n' "--------------------------------------------------------------------------------"
fi

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

    # 失败判定：**只有最后一次 finished 晚于最后一条工作事件时才算**
    # （那个 failed 是「这一回合怎么结束的」）。历史轮次撞过限流的对话，
    # 文件尾里永远留着旧的 failed——原来直接 grep 最后一条 failed 就报「失败」，
    # 于是把已经正常收工的对话误报成出事（2026-10-31 12:31 实测 6c78afa4 被误报）。
    last_fin_reason=$(printf '%s\n' "$flat" | grep '"finished":{"reason":"[^"]*"' | tail -1 |
          sed 's/.*"reason":"//;s/"//')
    fin_newest=""
    if [ -n "$last_fin_reason" ]; then
        finline=$(printf '%s\n' "$flat" | grep '"finished":{"reason":"[^"]*"' | tail -1)
        fts=$(printf '%s' "$finline" | sed -n 's/.*"date":"\([0-9T:-]*Z\)".*/\1/p')
        [ -n "$fts" ] && fin_newest=$(date -u -d "$fts" +%s 2>/dev/null)
    fi

    case "$last_fin_reason" in
        failed)
            # 只有它确实是这一回合的收尾（没人再接活）才报失败
            if [ -n "$fin_newest" ] && [ -n "$ev_epoch" ] && [ "$ev_epoch" -gt "$fin_newest" ]; then
                state="在跑"
            else
                state="失败"
            fi
            ;;
        "")
            state="在跑" ;;
        *)
            # 有 finished，但只有它确实晚于最后一条工作事件才算收工；否则就是「又开工了」
            if [ -n "$fin_newest" ] && [ -n "$ev_epoch" ] && [ "$ev_epoch" -gt "$fin_newest" ]; then
                state="在跑"
            else
                state="收工"
            fi
            ;;
    esac

    # 「卡住」判定：状态是「在跑」但已经 STALL_MIN 分钟没有任何新事件。
    # 这不是猜死活，是「它这一轮里很久没动」——值得去看一眼，但不等于它死了（长编译/长下载会这样）。
    if [ "$state" = "在跑" ] && [ "$mins" -ge "$STALL_MIN" ]; then
        state="卡住?"
    fi

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

    row=$(printf '%-9s %3d分钟前 %-6s %s' "$(printf '%s' "$sid" | cut -c1-8)" "$mins" "$state" "$act")
    case "$state" in
        失败|卡住?) printf '%s\n' "$sid|$state|$mins|$act" >> "$ALERTS" ;;
    esac
    [ "$MODE" = "list" ] && printf '%s\n' "$row"
done

if [ "$MODE" = "list" ]; then
    printf '%s\n' "--------------------------------------------------------------------------------"
    n=$(wc -l < "$ALERTS" | tr -d ' ')
    if [ "${n:-0}" -gt 0 ]; then
        echo "⚠️ 有 $n 个对话需要处理（失败 / 卡住），看详情：sh scripts/fleet-live.sh ${WIN} alerts"
    else
        echo "✅ 没有失败或卡住的对话"
    fi
    echo "（数据来自 Apelin 的 sessions/*/events.jsonl，无需任何 agent 配合；窗口 ${WIN} 分钟）"
    exit 0
fi

# ── alerts：只列需要处理的 ────────────────────────────────────────────────
n=$(wc -l < "$ALERTS" | tr -d ' ')
if [ "${n:-0}" -eq 0 ]; then
    echo "✅ 没有失败或卡住的对话（窗口 ${WIN} 分钟）"
    exit 0
fi
echo "需要处理的对话：$n 个"
printf '%s\n' "--------------------------------------------------------------------------------"
while IFS='|' read -r sid state mins act; do
    case "$state" in
        失败) why="这一回合失败（多半额度耗尽 / 限流），它自己不会再动，得有人去看或让用户充值" ;;
        *)    why="判为在跑但 ${mins} 分钟没动新事件；可能是长编译/长下载，也可能真卡住了" ;;
    esac
    printf '%s  %s\n   %s\n   最后动作：%s\n' "$sid" "$state" "$why" "$act"
done < "$ALERTS"
printf '%s\n' "--------------------------------------------------------------------------------"
echo "要给它发话：sh scripts/fleet-live.sh ${WIN} ping"

# ── ping：生成可直接发送的催办文本（只打印，不发送）──────────────────────
if [ "$MODE" != "ping" ]; then
    exit 0
fi
echo
echo "════ 下面每段可直接复制到 apelin_conversation_send 的 text ════"
while IFS='|' read -r sid state mins act; do
    echo
    echo "--- $sid ---"
    case "$state" in
        失败)
            echo "【对账·检测到你这回合失败】你上一次 finished.reason=failed（常见于额度耗尽/限流，不是你代码的问题）。"
            echo "如果还有没做完的活：先回一句「收到，我还在，下一步是 X」，再重试那条命令；如果确实做完了，忽略本条。"
            ;;
        *)
            echo "【对账·你已 ${mins} 分钟没有新动作】你现在判为在跑（最后动作：${act}）。"
            echo "如果卡在等某个东西（编译/下载/别人的回话），回一句「在等 X，预计 N 分钟」；"
            echo "如果已经卡死或做不下去，回一句「我卡在 X」，别让它一直挂着。"
            ;;
    esac
done < "$ALERTS"
echo
echo "（本段只是文本，没有发送任何消息）"
