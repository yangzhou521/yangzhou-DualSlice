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
#   sh scripts/fleet-live.sh 30 alerts     # 只看「需要我处理的」：失败 / 卡住
#   sh scripts/fleet-live.sh 30 ping       # 打印「该催谁」的现成消息文本（不发送，自己复制或照抄）
#   sh scripts/fleet-live.sh 30 handoff <对方sid>   # 打印「对齐回执」模板（带本线 sid + 本仓库下一步，复制即发）
#
# ⚠️ 2026-11-02 05:2x 实测（别误判「它死了」）：表里写「在跑」**不等于**它此刻能收消息 ——
#   它可能正好停在回合边界，此时 apelin_conversation_send 会回
#   `no conversation <sid> ... not running any more`。这**不是**对方结束了：
#   先 apelin_conversation_list 核它的 state —— `open` 就直接重发（实测一分钟后就发出去了）；
#   只有 `ended` 才要先 `icli url open "apelin://conversation/<sid>"` 重开，再 send。
#   状态是快照、几秒就变：**核 state + 重发**，别凭一次被拒就放弃对接。
#
# list 模式下，属于「跑这条命令的那个对话」的那一行末尾标 `← 本线`（认法见 mine_sid）。
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
    alerts|ping|handoff) MODE="$2" ;;
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

# 认出「正在跑这条命令的对话」（同 hud-notify.sh 的 auto_sid 手法）：本脚本这次调用
# 正被写进它的 events.jsonl，所以「最后一次提到 fleet-live.sh 的事件」所属的对话就是自己。
# 可用 FLEET_SELF=<sid> 显式指定（认错时）。
mine_sid() {
    [ -n "${FLEET_SELF:-}" ] && { printf '%s' "$FLEET_SELF"; return 0; }
    [ -d "$SESS" ] || return 0
    MS=""
    for d in $(ls -t "$SESS" 2>/dev/null | head -12); do
        f="$SESS/$d/events.jsonl"
        [ -f "$f" ] || continue
        line=$(tail -c 600000 "$f" 2>/dev/null | grep -F 'fleet-live.sh' | grep -F 'toolCall' | tail -1)
        [ -n "$line" ] || continue
        dt=$(printf '%s' "$line" | sed 's/.*"date":"\([^"]*\)".*/\1/')
        [ -n "$dt" ] || continue
        MS="$MS$dt $d
"
    done
    [ -n "$MS" ] || return 0
    printf '%s' "$MS" | sort -r | head -1 | awk '{print $2}'
}

# 从 WORK-STATE.json 抓一个顶层字符串字段（本机没有 python3/jq，这个 plutil 的 -extract 不支持 -o -）
WS="${APELIN_PROJECT_ROOT:-$PWD}/scripts/WORK-STATE.json"
ws_field() {
    [ -f "$WS" ] || return 0
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$WS" 2>/dev/null | head -1 |
        sed 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//;s/"$//'
}

MINE=$(mine_sid)
MYSHORT=$(printf '%s' "$MINE" | cut -c1-8)
OTHERS=0

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

    short=$(printf '%s' "$sid" | cut -c1-8)
    row=$(printf '%-9s %3d分钟前 %-6s %s' "$short" "$mins" "$state" "$act")
    case "$state" in
        失败|卡住?) printf '%s\n' "$sid|$state|$mins|$act" >> "$ALERTS" ;;
    esac
    if [ -n "$MYSHORT" ] && [ "$short" = "$MYSHORT" ]; then
        row="$row  ← 本线"
    elif [ "$state" = "在跑" ]; then
        OTHERS=$((OTHERS + 1))
    fi
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
    if [ "$OTHERS" -gt 0 ]; then
        echo "⚡ 除本线外还有 ${OTHERS} 条线在跑 —— 动码/动设备前先对齐：sh scripts/fleet-live.sh ${WIN} handoff <对方sid>"
    elif [ -n "$MYSHORT" ]; then
        echo "（除本线外没有别的线在跑）"
    fi
    echo "（数据来自 Apelin 的 sessions/*/events.jsonl，无需任何 agent 配合；窗口 ${WIN} 分钟）"
    exit 0
fi

# ── alerts：只列需要处理的（handoff 模式下整段静默 —— 直接跳到文件末尾）──
n=$(wc -l < "$ALERTS" | tr -d ' ')
if [ "${n:-0}" -eq 0 ] && [ "$MODE" != "handoff" ]; then
    echo "✅ 没有失败或卡住的对话（窗口 ${WIN} 分钟）"
    exit 0
fi
if [ "${n:-0}" -gt 0 ]; then
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
fi

# ── ping：生成可直接发送的催办文本（只打印，不发送）──────────────────────
if [ "$MODE" = "alerts" ]; then
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

# ── handoff：生成「对齐回执」模板（只打印，不发送）──────────────────────
# 为什么要有：撞车的根因不是「谁在跑」看不见（list 能满足），而是**「谁在改哪些文件」没人声明**。
# 回执统一带三样：本线 sid + 我刚做完什么 + 本仓库的下一步（从 WORK-STATE.json 读，现成）。
# 2026-11-02：配合「每回合起手第 0 问」用，看见别的线在跑就照抄这段发过去。
if [ "$MODE" != "handoff" ]; then
    exit 0
fi
TARGET=${3:-}
echo "════ 对齐回执模板（复制下面整段 → apelin_conversation_send 的 text）════"
echo "发给：${TARGET:-<对方 sid，即上面表里那一行的前 8 位要核完整 id>}"
echo
echo "对齐回执（${MYSHORT:-<本线 sid>}）："
echo "进度：<改成你刚做完的那一件事>"
echo "下一步：$(ws_field step)"
echo "我改的文件：<列路径，例：scripts/fleet-live.sh；别人的文件我不碰>"
echo "你手上在做的我不动；要动同一文件先说一声。"
echo
echo "（若 send 被拒「not running any more」：先 apelin_conversation_list 核 state，open 就重发，ended 才 icli url open 重开）"
