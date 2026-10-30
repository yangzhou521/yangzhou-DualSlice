#!/bin/sh
#
# fleet.sh v6 —— 本机所有对话共用的「任务黑板 + 收件箱 + 唤醒器 + 看护接管」。
#
# 为什么要有它：对话之间靠 apelin_conversation_send 一问一答太慢 —— 发的人要等回复、
# 收的人要停下手里的活，一轮几分钟，还常常两边一起空转。而**绝大多数信息只需要被看见、
# 不需要被回应**：谁在做哪个工程、做到哪一步、下一步打算干什么、此刻有没有占着设备
# （注销 / 装包 / 杀进程 / 用屏幕做界面取证）。这些写进一个共享文件就够了：
# 只写不打扰，谁想知道随时读，读的时候别人照常干活。
#
# v2（2026-10-31 00:1x，用户要求「优化闲时协助效率 + 唤醒睡死的机器人」）新增：
#   * 收件箱（inbox.tsv）：派活不再覆盖对方的状态行，可以积压；对方醒来先看收件箱。
#   * 唤醒器（sweep / wake / roster）：算出「该唤醒谁」，并打印**照抄就能发**的唤醒指令
#     （脚本不能替 agent 调 apelin_conversation_send，只能把文案与全 id 备好）。
#   * want：空闲的 agent 一行声明自己能接什么活 —— 别人不必再发消息问「你有空吗」。
#   * 并发写锁（mkdir 锁）：多个 agent 同时 post 不再互相丢行。
#   * done 改为覆盖自己的行（v1 是追加，同一 agent 会出现在 list 里两行）。
#
# v3（2026-10-31 00:1x，用户要求「保持、保证一两个机器人睡死不工作的前提下，
# 还有别的机器人能同步接收它接下来的工作，不至于任何机器都睡死」）新增：
#   * beat：心跳 —— 只刷新自己那行的时间，不动状态、不打扰别人（长活期间每隔几分钟打一次，
#     看护者由此区分「还在干」和「睡死了」）。
#   * care：看护报告 —— 一次列出 ①疑似睡死（连同**照抄就能执行**的接管/唤醒指令）
#     ②等用户点头的 ③空闲可派的 ④设备占用 ⑤全队活线数（=0 就是全体停摆，必须立刻有人接）。
#   * takeover：接管 —— 把睡死那名 agent 的任务接到自己名下，写明「接着谁、原来到哪」，
#     并把它那行标成 handoff，它回来时一眼看见自己不用再接着干（一文件一写者，不撞车）。
#   * 接管只接「随时能停、不冲突」的部分：只读查询、云端 CI/Release 查询、下载校验、
#     设备取证、文档与三样同步。**改别人工程源码 / 装包 / 注销 / 杀进程不接管**，
#     除非用户当次明确同意。
#
# v4（2026-10-31 00:2x，用户要求「优化闲时协助的能力与响应执行效率」）新增：
#   * handout：一条命令把「小任务」派给最合适的空闲者 —— 自动挑人（按 want 声明的能力、
#     挑收件箱最少的那位）、投进它的收件箱、把它的黑板行改成 assigned，并打印**照抄就能发**
#     的唤醒指令。省掉「问谁有空 → 等回执 → 再派」那两三分钟。
#   * wake_send_line：唤醒文案的统一出处，sweep / care / wake / handout 共用一条。
#
# v5（2026-10-31 00:3x，用户要求「机器人防睡死和及时唤醒能力马上提上任务中去」，全部到位）新增：
#   * brief：接手包 —— 一条命令把某人手上那件活看全（工程/状态/任务/下一步/停了多久/收件箱），
#     并把它专属的「照抄即发」唤醒行与「照抄即跑」接管命令备好，看护人不用自己想格式。
#   * wakeall：只打印「照抄即发的整行」，一次把全队该唤醒的都列出来，直接抄进工具调用。
#   * guard：收尾自检 —— 看护报告 + 收尾三件事（唤醒 / 60 秒后接管 / 把自己的行与接口落盘）。
#     每个 agent 在**每个回合收尾前**跑它，防睡死就不是靠某个人的记性，而是靠流程。
#
# v6（2026-10-31 00:4x，用户要求「实时发现和刷新、新增和减少的机器人的能力；及时给它们派活；
# 叫不醒的就把活及时交接出去；新活着的机器人智能分配任务」）新增：
#   * members：成员对账（只读）—— 黑板有心跳的、名册里有的、**新来的**（黑板有行但名册没登记）、
#     **疑似离场的**（名册有、黑板没行）一次看清，各自备好「照抄即跑」的登记 / 派活 / 清理行。
#   * intake：新机器人接入 —— 一条命令完成 登记名册 + 声明可接能力 + **从待派池挑一件最匹配的活
#     直接改派给它** + 打印唤醒行；新来的活机器人立刻有活干，不空转。
#   * rebalance：实时交接 —— 把「叫不醒 / 已离场」者手上的活，立刻改派给活着的候选（打印 add
#     行），并同时打印「自己接（takeover）」与「唤醒」行；三者择一，活不留在睡死的人手里。
#   * roster-drop：确认离场的成员从名册去掉（它的黑板行标 handoff）。
#   * refresh：资源刷新（写）—— prune 陈旧席位 + 落盘快照 + members 对账 + plan 统一调度，一条命令。
#   * plan：统一调度建议 —— 负载 / 撞车 / 待派配对 / 空闲 / 设备排队 / 结论三条，把全队当一份资源重排。
#   * start 现在也跑一次 members：**每个 agent 开工就自动发现新来的机器人**，不用等人通知。
#   * progress <一句话>：实时刷新自己那行的「进展/下一步」与时间 —— 只换 step 和 updated，
#     不动工程/状态/任务/设备。每跑完一小步就写一句，别的对话 `list` 立刻看见你到哪了，
#     不用 post 整行、也不用发消息；协调与实时同步就靠它高频更新。
#   * 唤醒闭环（v6）：脚本只算「该唤醒谁」并打印照抄行，但**真正发出去靠醒着的 agent 在回合内
#     立刻调 apelin_conversation_send**——跑完 care/wakeall 拿到列表，一次最多两条，真的把
#     「【继续任务】」发进对方的对话；发完 60 秒仍无动静才 takeover。不是只打印不动手。
#
# 怎么防「睡死」：本机上只有 agent 能唤醒 agent（脚本发不了 apelin_conversation_send），
# 所以规矩是**每个醒着的 agent 顺手当看护**：开工 `start`、收尾 `guard`，见谁心跳过期就
# 发一条照抄的 wake（一次最多两条），60 秒仍无动静就用 takeover 把「随时能停」的部分接到自己名下。
#
# 用法（本机路径固定，任何工程、任何对话都能跑）：
#   状态类：
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh list
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh busy
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh post <agent> <工程> <状态> <任务> <下一步> [动作]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh hold <agent> <工程> <动作> <任务>
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh free <agent> <工程> <任务> [下一步]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh done <agent> [结果]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh prune [分钟，默认 180]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh snapshot
#   派活 / 收件箱：
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh assign <agent> <工程> <任务> [下一步]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh claim  <agent> <工程> <任务> [下一步]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh add    <to> <工程> <任务> <验收> [from]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh inbox  [agent]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh take   <agent> <task#id>
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh finish <agent> [task#id] <结果>
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh want   <agent> <工程> [能力,用逗号]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh handout <能力|any> <工程> <任务> <验收>  # 一键派给最合适的空闲者
#   唤醒（防睡死）：
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh start  [agent]      # 开工一条命令：收件箱+全队+看护报告
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh sweep  [分钟，默认 20]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh care   [分钟，默认 20]  # 看护报告：谁睡死了、该谁接
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh relay                # 审批接力：谁卡在 icli 审批上、该谁替做
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh wakeall [分钟，默认 20] # 只列「照抄即发」的唤醒整行
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh brief  <短id>          # 接手包：它手上是什么 + 唤醒/接管命令
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh guard  [agent] [分钟]   # 收尾自检：看护报告 + 收尾三件事
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh beat   [agent]         # 心跳：我在干，别当我死了
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh takeover <me> <目标短id> [备注]  # 接管它的活
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh roster [短id] [全id] [工程] [备注]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh wake   <短id|全id> [from]
#
# v7（2026-10-31 01:2x，用户要求「卡在审批上的对话别空等，在线对话替它做」）新增：
#   * waiting-approval 状态：机器人调 icli 卡在 waitingForApproval 时，post 这个状态 +
#     在 step 里写 needs-icli:<需要什么>。区别于 waiting-user（等用户决策）：这是卡在工具审批上，
#     其他在线对话（用户在场、能批准 icli）可以替做。
#   * relay 命令：列出所有 waiting-approval 的对话，打印「照抄即发」的 apelin_conversation_send 行 ——
#     在线对话替它做需要 icli 的部分（查 CI、下载 deb、读诊断），结果回传，让卡住的对话继续做只读分析。
#     care 报告 ② 也区分两种：waiting-user 提醒用户，waiting-approval 建议在线对话 relay。
#
# agent：对话 id 前 8 位（apelin_conversation_list 里能看到），或 FLEET_AGENT 环境变量。
# 状态：working | assigned | blocked | waiting-user | waiting-approval | idle | done | handoff（已被别人接管）
# 动作：none | respring | install | kill | screen
#
# 每个 agent 只有一行：再 post 一次就覆盖自己那一行，所以不打扰别人、也不怕写乱。
# board.tsv 七列：agent 工程 状态 任务 下一步 动作 更新时间（TAB 分隔）
#
set -eu

TAB=$(printf '\t')
ROOT=${FLEET_HOME:-${HOME:?}/Documents/wiki.qaq.apelin/fleet}
BOARD=${FLEET_BOARD:-$ROOT/board.tsv}
INBOX=${FLEET_INBOX:-$ROOT/inbox.tsv}
ROSTER=${FLEET_ROSTER:-$ROOT/agents.tsv}
LINKS=${FLEET_LINKS:-$ROOT/links.tsv}
mkdir -p "$ROOT"
[ -f "$BOARD" ] || : > "$BOARD"
[ -f "$INBOX" ] || : > "$INBOX"
[ -f "$ROSTER" ] || : > "$ROSTER"
[ -f "$LINKS" ] || : > "$LINKS"

usage() {
  cat <<'EOF'
fleet.sh —— 黑板 + 收件箱 + 唤醒器（本机所有对话共用）
  状态类  list | busy | post | hold | free | done | prune | snapshot
  派活类  assign | claim | add | inbox | take | finish | want
  唤醒类  start | sweep | care | relay | wakeall | brief | decision | guard | beat | takeover | roster | wake
  派活类 还有 handout（一键派给最合适的空闲者）
  看护类  care | relay | brief | wakeall | guard | beat | takeover（防睡死：谁睡死了、谁接、怎么接）
  调度类  members | plan | rebalance | refresh | intake | roster-drop
          （成员实时增减 / 统一调度重排 / 叫不醒就交接 / 新机器人接入即派活 / 资源刷新）
  进展类  progress <一句话>（实时刷新自己那行的进展与时间；别的对话 list 立刻看见你到哪了）
  常走的两条：开工 start，收尾 guard（看护报告 + 收尾三件事）；干活时随手 progress，闲时 refresh
  帮助    help
语法见脚本头部注释（sed -n '1,60p' fleet.sh）或技能 fleet-shared-board。
EOF
}

now() { date +%s; }

# ---------- 并发写锁：mkdir 是原子的；持锁者死了（锁目录 > 60 秒）才抢 ----------
LOCK=$ROOT/.lock
_HELD=0
release() {
  if [ "$_HELD" = 1 ]; then
    rmdir "$LOCK" 2>/dev/null || true
    _HELD=0
  fi
}
lock() {
  i=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
      if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
        # 锁太老了：持有者已经死了，抢过来（LOCK 由 ROOT 拼出，一定非空）
        rmdir "$LOCK" 2>/dev/null || rm -rf "${LOCK:?}"
        continue
      fi
      echo "fleet: 等黑板锁超时（10 秒），稍后再试" >&2
      exit 3
    fi
    sleep 0.1
  done
  _HELD=1
  trap 'release' EXIT INT TERM
}

# ---------- 基础读写 ----------
# 写自己那一行：先删掉同 agent 的旧行，再追加新行（整份重写，避免半截状态）。
write_row() {
  agent=$1; project=$2; state=$3; task=$4; step=$5; device=$6
  lock
  tmp="$BOARD.tmp.$$"
  if [ -s "$BOARD" ]; then
    awk -F"$TAB" -v a="$agent" '$1 != a' "$BOARD" > "$tmp" || : > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$agent" "$project" "$state" "$task" "$step" "$device" "$(now)" >> "$tmp"
  mv "$tmp" "$BOARD"
  release
  printf 'fleet: %s [%s] %s | 下一步 %s | 设备 %s\n' \
    "$agent" "$project" "$state" "$step" "$device"
}

inbox_remove() {
  id=$1
  lock
  tmp="$INBOX.tmp.$$"
  if [ -s "$INBOX" ]; then
    awk -F"$TAB" -v id="$id" '$1 != id' "$INBOX" > "$tmp" || : > "$tmp"
  else
    : > "$tmp"
  fi
  mv "$tmp" "$INBOX"
  release
}

inbox_count() {
  awk -F"$TAB" -v a="${1:-}" '$4 == a { c++ } END { print c + 0 }' "$INBOX"
}

agent_of() {
  if [ -n "${1:-}" ]; then
    printf '%s' "$1"
  elif [ -n "${FLEET_AGENT:-}" ]; then
    printf '%s' "$FLEET_AGENT"
  else
    printf 'unknown'
  fi
}

check_action() {
  case "${1:-}" in
    none|respring|install|kill|screen) ;;
    *) echo "fleet: 动作只能是 none|respring|install|kill|screen（收到 '$1'）" >&2; exit 2 ;;
  esac
}

# ---------- 状态类 ----------
cmd_list() {
  printf '=== Apelin 任务黑板 %s ===\n' "$BOARD"
  if [ ! -s "$BOARD" ]; then
    echo '(空)'
  else
    nowt=$(now)
    LC_ALL=C sort -t "$TAB" -k7,7nr "$BOARD" | while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      box=$(inbox_count "$agent")
      printf '%-9s %-20s %-13s %-34s next=%-30s dev=%-8s %sm box=%s\n' \
        "$agent" "$project" "$state" "$task" "$step" "$device" "$age" "$box"
    done
  fi
  echo '--- 设备占用（5 分钟内才作数）:'
  cmd_busy
}

cmd_busy() {
  nowt=$(now)
  found=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      if [ -z "${device:-}" ] || [ "$device" = "none" ]; then
        continue
      fi
      age=$(( (nowt - ${updated:-0}) / 60 ))
      if [ "$age" -gt 5 ]; then
        continue
      fi
      printf '  %s 正在 %s（%s）：%s（%sm 前）\n' "$agent" "$device" "$project" "$task" "$age"
      found=1
    done < "$BOARD"
  fi
  if [ "$found" -eq 0 ]; then
    echo '  没有人在动设备'
  fi
  return 0
}

cmd_post() {
  agent=$(agent_of "${1:-}")
  write_row "$agent" "${2:-?}" "${3:-working}" "${4:-?}" "${5:-?}" "${6:-none}"
}

cmd_hold() {
  agent=$(agent_of "${1:-}")
  check_action "${3:-respring}"
  write_row "$agent" "${2:-?}" working "${4:-设备动作}" '设备动作中' "${3:-respring}"
}

cmd_free() {
  agent=$(agent_of "${1:-}")
  write_row "$agent" "${2:-?}" working "${3:-?}" "${4:-继续}" none
}

cmd_assign() {
  agent=$(agent_of "${1:-}")
  write_row "$agent" "${2:-?}" assigned "${3:-?}" "${4:-待认领}" none
}

cmd_claim() {
  agent=$(agent_of "${1:-}")
  write_row "$agent" "${2:-?}" working "${3:-?}" "${4:-进行中}" none
}

# 完成：覆盖自己那一行（v1 是追加，会在 list 里出现两行）。
cmd_done() {
  agent=$(agent_of "${1:-}")
  write_row "$agent" '-' done "${2:-已完成}" '-' none
}

cmd_prune() {
  limit=${1:-180}
  nowt=$(now)
  lock
  tmp="$BOARD.tmp.$$"
  : > "$tmp"
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      if [ "$state" = "done" ] || [ "$age" -gt "$limit" ]; then
        echo "fleet: 清掉 $agent（$state，${age}m）"
        continue
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$agent" "$project" "$state" "$task" "$step" "$device" "$updated" >> "$tmp"
    done < "$BOARD"
  fi
  mv "$tmp" "$BOARD"
  release
  echo "fleet: 黑板保留 $(wc -l < "$BOARD" | tr -d ' ') 行"
  # 收件箱里超过 6 小时的旧条目也清掉（多半是早就做完没人来收的）
  lock
  tmp2="$INBOX.tmp.$$"
  : > "$tmp2"
  if [ -s "$INBOX" ]; then
    while IFS="$TAB" read -r id ts from to project task accept; do
      [ -n "${id:-}" ] || continue
      age=$(( (nowt - ${ts:-0}) / 60 ))
      if [ "$age" -gt 360 ]; then
        echo "fleet: 清掉收件箱 task#$id（给 $to，${age}m）"
        continue
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$ts" "$from" "$to" "$project" "$task" "$accept" >> "$tmp2"
    done < "$INBOX"
  fi
  mv "$tmp2" "$INBOX"
  release
  echo "fleet: 收件箱保留 $(wc -l < "$INBOX" | tr -d ' ') 行"
  # 依赖表：父或子已经不在收件箱里的关系一并清掉（任务早被 take / 做完）
  lock
  tmp3="$LINKS.tmp.$$"
  : > "$tmp3"
  if [ -s "$LINKS" ]; then
    while IFS="$TAB" read -r child parent note ts; do
      [ -n "${child:-}" ] || continue
      if awk -F"$TAB" -v c="$child" '$1 == c { f = 1 } END { exit !f }' "$INBOX" 2>/dev/null &&
        awk -F"$TAB" -v p="$parent" '$1 == p { f = 1 } END { exit !f }' "$INBOX" 2>/dev/null; then
        printf '%s\t%s\t%s\t%s\n' "$child" "$parent" "$note" "$ts" >> "$tmp3"
      else
        echo "fleet: 清掉依赖 $child <- $parent（任务已不在收件箱）"
      fi
    done < "$LINKS"
  fi
  mv "$tmp3" "$LINKS"
  release
  echo "fleet: 依赖保留 $(wc -l < "$LINKS" | tr -d ' ') 条"
}

# 把黑板复制进本工程（仓库里那份只是快照，方便上云 / 换机时看见）。
cmd_snapshot() {
  root=${APELIN_PROJECT_ROOT:?}
  mkdir -p "$root/fleet"
  cp "$BOARD" "$root/fleet/board.tsv"
  cp "$INBOX" "$root/fleet/inbox.tsv"
  cp "$ROSTER" "$root/fleet/agents.tsv"
  echo "fleet: 快照 -> $root/fleet/{board,inbox,agents}.tsv"
}

# ---------- 收件箱：派活不覆盖状态行，可以积压，对方醒来即见 ----------
cmd_add() {
  to=${1:-}
  project=${2:-?}
  task=${3:-?}
  accept=${4:-未写验收标准}
  from=${5:-$(agent_of "")}
  if [ -z "$to" ] || [ "$to" = "unknown" ]; then
    echo "fleet: add <收件人 agent> <工程> <任务> <验收> [from]" >&2
    exit 2
  fi
  lock
  n=$(awk 'END { print NR + 1 }' "$INBOX")
  id="$(now)-$n"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$(now)" "$from" "$to" "$project" "$task" "$accept" >> "$INBOX"
  release
  printf 'fleet: 投递 task#%s -> %s（%s）：%s ｜ 验收：%s\n' "$id" "$to" "$project" "$task" "$accept"
}

cmd_inbox() {
  agent=$(agent_of "${1:-}")
  printf '=== %s 的收件箱 %s ===\n' "$agent" "$INBOX"
  n=0
  nowt=$(now)
  while IFS="$TAB" read -r id ts from to project task accept; do
    [ -n "${id:-}" ] || continue
    [ "$to" = "$agent" ] || continue
    n=$((n + 1))
    mark=$(block_mark "$id")
    printf '  task#%-14s 来自 %-9s %-18s %s%s\n      验收：%s（%sm 前投递）\n' \
      "$id" "$from" "$project" "$task" "$mark" "$accept" "$(( (nowt - ${ts:-0}) / 60 ))"
  done < "$INBOX"
  if [ "$n" -eq 0 ]; then
    echo '  （空）'
  else
    echo "  共 $n 件。做之前先 take <agent> <task#id>，做完 finish <agent> <task#id> <结果>。"
  fi
}

cmd_take() {
  agent=$(agent_of "${1:-}")
  id=${2:-}
  if [ -z "$id" ]; then
    echo "fleet: take <agent> <task#id>（先 inbox 看 id）" >&2
    exit 2
  fi
  info=$(awk -F"$TAB" -v id="$id" -v me="$agent" \
    '$1 == id && $4 == me { print $5 "\t" $6 "\t" $7; found = 1 } END { if (!found) exit 1 }' "$INBOX" 2>/dev/null) || info=""
  if [ -z "$info" ]; then
    echo "fleet: 收件箱里没有 task#$id（或它不是给 $agent 的）" >&2
    exit 2
  fi
  project=$(printf '%s' "$info" | cut -f1)
  task=$(printf '%s' "$info" | cut -f2)
  accept=$(printf '%s' "$info" | cut -f3)
  write_row "$agent" "$project" working "$task" "来自 task#$id ｜ 验收：$accept" none
  inbox_remove "$id"
}

cmd_finish() {
  agent=$(agent_of "${1:-}")
  if [ $# -ge 3 ]; then
    id=$2
    result=$3
  else
    id=""
    result=${2:-已完成}
  fi
  if [ -n "$id" ]; then
    inbox_remove "$id"
  fi
  write_row "$agent" '-' done "$result" '-' none
  if [ -n "$id" ]; then
    unlock_after "$agent" "$id"
  fi
}

# 依赖标记：这件活有没有被别的活挡着（父任务还在收件箱里就是还没做完）。
block_mark() {
  cid=${1:-}
  [ -s "$LINKS" ] || return 0
  par=$(awk -F"$TAB" -v c="$cid" '$1 == c { print $2; exit }' "$LINKS" 2>/dev/null) || par=""
  if [ -z "${par:-}" ]; then
    return 0
  fi
  if awk -F"$TAB" -v p="$par" '$1 == p { f = 1 } END { exit !f }' "$INBOX" 2>/dev/null; then
    printf ' ⏳等 task#%s' "$par"
  else
    printf ' ✅可动（task#%s 已完成）' "$par"
  fi
}

# 依赖解锁：一件活做完，把它挡着的子任务放出来，并给出「叫醒收件人」的那一行。
unlock_after() {
  finisher=$1
  pid=$2
  if [ ! -s "$LINKS" ]; then
    return 0
  fi
  kids=$(awk -F"$TAB" -v p="$pid" '$2 == p { print $1 }' "$LINKS" 2>/dev/null) || kids=""
  for cid in ${kids:-}; do
    row=$(awk -F"$TAB" -v c="$cid" '$1 == c { print $4 "\t" $5 "\t" $6; exit }' "$INBOX" 2>/dev/null) || row=""
    if [ -z "${row:-}" ]; then
      continue
    fi
    cto=$(printf '%s' "$row" | cut -f1)
    cproj=$(printf '%s' "$row" | cut -f2)
    ctask=$(printf '%s' "$row" | cut -f3)
    printf '解锁 task#%s（给 %s，%s）：%s\n' "$cid" "$cto" "$cproj" "$ctask"
    full=$(awk -F"$TAB" -v k="$cto" '$1 == k { print $3; exit }' "$ROSTER") || full=""
    wake_send_line "$cto" "${full:-}" "$finisher" '' "$(inbox_count "$cto")" '  '
  done
  lock
  tmp="$LINKS.tmp.$$"
  awk -F"$TAB" -v p="$pid" '$2 != p' "$LINKS" > "$tmp" 2>/dev/null || : > "$tmp"
  mv "$tmp" "$LINKS"
  release
}

# 空闲声明：一行写清「我现在没活、能接什么」——别人不必再发消息问。
cmd_want() {
  agent=$(agent_of "${1:-}")
  write_row "$agent" "${2:-?}" idle "空闲待派" "可接:${3:-只读,云端,取证,文档}" none
}

# 依赖：子任务要等父任务做完才动（两端都还在收件箱里，先 inbox 看 id）。
# 依赖只挡「动手做」那一步：接口先钉死（文件路径 / 诊断键与期望值 / 包名版本 / Release 资产 URL /
# CI run 号）这类准备动作照样可以并行先做，别为了等一件活把整条链子停住。
cmd_dep() {
  child=${1:-}
  parent=${2:-}
  note=${3:-}
  if [ -z "$child" ] || [ -z "$parent" ]; then
    echo "fleet: dep <子 task#id> <父 task#id> [备注]（两端都要在收件箱里）" >&2
    exit 2
  fi
  if [ "$child" = "$parent" ]; then
    echo 'fleet: 自己依赖自己没意义' >&2
    exit 2
  fi
  if ! awk -F"$TAB" -v c="$child" '$1 == c { f = 1 } END { exit !f }' "$INBOX" 2>/dev/null; then
    echo "fleet: 收件箱里没有 task#$child" >&2
    exit 2
  fi
  if ! awk -F"$TAB" -v p="$parent" '$1 == p { f = 1 } END { exit !f }' "$INBOX" 2>/dev/null; then
    echo "fleet: 收件箱里没有 task#$parent（父任务已被 take 走就等于没有依赖了）" >&2
    exit 2
  fi
  lock
  tmp="$LINKS.tmp.$$"
  awk -F"$TAB" -v c="$child" '$1 != c' "$LINKS" > "$tmp" 2>/dev/null || : > "$tmp"
  printf '%s\t%s\t%s\t%s\n' "$child" "$parent" "${note:-无}" "$(now)" >> "$tmp"
  mv "$tmp" "$LINKS"
  release
  printf 'fleet: task#%s 现在等 task#%s（%s）——父任务 finish 时会自动给出解锁指令\n' \
    "$child" "$parent" "${note:-无}"
}

# 决策屏（decision）：一屏说清「我接下来该干什么」，比 list + inbox + care 三连快。
# ① 我手上没被挡住的活 ② 我投出去没人动的（该催） ③ 心跳过期该唤醒/接管的 ④ 设备 ⑤ 顺序与心跳。
cmd_decision() {
  me=$(agent_of "${1:-}")
  lim=${2:-${SWEEP_MIN:-20}}
  nowt=$(now)
  printf '=== 决策屏 %s（%s，阈值 %sm）===\n' "$me" "$(date '+%H:%M:%S')" "$lim"
  echo '--- ① 我的收件箱（⏳ = 被别的活挡着）：'
  mine=0
  while IFS="$TAB" read -r id ts from to project task accept; do
    [ -n "${id:-}" ] || continue
    [ "$to" = "$me" ] || continue
    mine=$((mine + 1))
    printf '  task#%-14s 来自 %-9s %sms 前  %s%s\n      验收：%s\n' \
      "$id" "$from" "$(( (nowt - ${ts:-0}) / 60 ))" "$task" "$(block_mark "$id")" "$accept"
  done < "$INBOX"
  if [ "$mine" -eq 0 ]; then
    echo '  （空：没活就 want 一条声明空闲与可接能力，别人一条 handout 就派过来）'
  fi
  echo '--- ② 我投出去、对方还没动的（>10m 就该催一次）：'
  n=0
  while IFS="$TAB" read -r id ts from to project task accept; do
    [ -n "${id:-}" ] || continue
    [ "$from" = "$me" ] || continue
    age=$(( (nowt - ${ts:-0}) / 60 ))
    if [ "$age" -lt 10 ]; then
      continue
    fi
    n=$((n + 1))
    printf '  task#%s → %s（%sm，%s）：%s\n' "$id" "$to" "$age" "$project" "$task"
    full=$(awk -F"$TAB" -v k="$to" '$1 == k { print $3; exit }' "$ROSTER") || full=""
    wake_send_line "$to" "${full:-}" "$me" "$age" "$(inbox_count "$to")" '  '
  done < "$INBOX"
  if [ "$n" -eq 0 ]; then
    echo '  （无）'
  fi
  echo '--- ③ 没动静的（该唤醒，接得了就 takeover）：'
  n=0
  while IFS="$TAB" read -r a p state t step device updated; do
    [ -n "${a:-}" ] || continue
    if [ "$a" = "$me" ]; then
      continue
    fi
    case "$state" in
      done|idle|handoff|waiting-user|waiting-approval) continue ;;
    esac
    age=$(( (nowt - ${updated:-0}) / 60 ))
    if [ "$age" -lt "$lim" ]; then
      continue
    fi
    n=$((n + 1))
    printf '  · %s（%s，%sm）：%s\n' "$a" "$state" "$age" "$t"
    printf '    接：sh "$F" takeover %s %s "已接手"\n' "$me" "$a"
    full=$(awk -F"$TAB" -v k="$a" '$1 == k { print $3; exit }' "$ROSTER") || full=""
    wake_send_line "$a" "${full:-}" "$me" "$age" "" '    '
  done < "$BOARD"
  if [ "$n" -eq 0 ]; then
    echo '  （无）'
  fi
  echo '--- ④ 设备（动设备前先看，动时 hold、动完 free）：'
  cmd_busy
  echo '--- ⑤ 顺序：用户当前指令 > 我让别人在等的活 > 我自己的活 > 唤醒/接管/协助别人；'
  printf '    长活每 5 分钟 beat %s（别人借此区分「还在干」和「睡死」），收尾前 care 一次再 done。\n' "$me"
}

# ---------- 唤醒：roster（全 id 表）+ sweep（清单）+ wake（文案） ----------
cmd_roster() {
  if [ $# -eq 0 ]; then
    printf '=== 已知对话（%s）===\n' "$ROSTER"
    if [ ! -s "$ROSTER" ]; then
      echo '(空) 开工时登记自己：'
      echo '  sh "$F" roster <自己的短id> <自己的全id> <工程>'
      return 0
    fi
    nowt=$(now)
    while IFS="$TAB" read -r short ts full project note seen; do
      [ -n "${short:-}" ] || continue
      age=$(( (nowt - ${seen:-0}) / 60 ))
      row=$(awk -F"$TAB" -v a="$short" '$1 == a { print $3 "/" $7; exit }' "$BOARD")
      printf '  %-9s %s  %-18s %-24s 黑板:%s  登记 %sm 前\n' \
        "$short" "${full:-（无全id）}" "${project:-?}" "${note:-}" "${row:-无}" "$age"
    done < "$ROSTER"
    return 0
  fi
  short=$1
  full=${2:-}
  project=${3:-?}
  note=${4:-}
  lock
  tmp="$ROSTER.tmp.$$"
  if [ -s "$ROSTER" ]; then
    awk -F"$TAB" -v a="$short" '$1 != a' "$ROSTER" > "$tmp" || : > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$short" "$(now)" "$full" "$project" "$note" "$(now)" >> "$tmp"
  mv "$tmp" "$ROSTER"
  release
  printf 'fleet: roster %s -> %s（%s）\n' "$short" "${full:-无全id}" "$project"
}

# 唤醒一条：算出该唤谁，并把「照抄就能发」的 apelin_conversation_send 备好。
# 脚本替 agent 发不了消息（apelin_* 工具只在 agent 手里），所以这里只出清单和文案。
cmd_sweep() {
  limit=${1:-20}
  nowt=$(now)
  printf '=== 唤醒清单（阈值 %s 分钟，%s）===\n' "$limit" "$(date '+%H:%M:%S')"
  stale=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      [ "$state" = "done" ] && continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      [ "$age" -lt "$limit" ] && continue
      n=$(inbox_count "$agent")
      printf '  · %s（%s，%s，%sm 没更新，收件箱 %s 件）：%s\n' \
        "$agent" "$project" "$state" "$age" "$n" "$task"
      full=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $3; exit }' "$ROSTER")
      if [ -n "${full:-}" ]; then
        printf '    apelin_conversation_send(session_id: "%s", text: "【fleet-wake】%s：你那边停了 %sm。收件箱 %s 件。先 sh \\"$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh\\" start %s，有活就 take/finish，没活就 want 一条；30 秒内回一句进度。")\n' \
          "$full" "$(agent_of "")" "$age" "$n" "$agent"
      else
        printf '    （roster 里还没它的全 id：先 apelin_conversation_list 拿到全 id，再 sh "$F" roster %s <全id> <工程>）\n' "$agent"
      fi
      stale=$((stale + 1))
    done < "$BOARD"
  fi
  # roster 里有、黑板上没行的：刚登记过却一直没动静的
  if [ -s "$ROSTER" ]; then
    while IFS="$TAB" read -r short ts full project note seen; do
      [ -n "${short:-}" ] || continue
      if awk -F"$TAB" -v a="$short" '$1 == a { found = 1 } END { exit !found }' "$BOARD"; then
        continue
      fi
      age=$(( (nowt - ${seen:-0}) / 60 ))
      [ "$age" -lt "$limit" ] && continue
      printf '  · %s（%s）不在黑板上（%sm）——可能一直没醒\n' "$short" "$project" "$age"
      if [ -n "${full:-}" ]; then
        printf '    apelin_conversation_send(session_id: "%s", text: "【fleet-wake】%s：你在黑板上没有行。先 sh \\"$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh\\" start %s（它会打印收件箱与全队状态），再 post 一行说你手上在干什么；30 秒内回一句。")\n' \
          "$full" "$(agent_of "")" "$short"
      fi
      stale=$((stale + 1))
    done < "$ROSTER"
  fi
  if [ "$stale" -eq 0 ]; then
    echo '  （没有需要唤醒的）'
  fi
  echo '--- 有活可派的（空闲 / 可接 X）：'
  idle=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      case "$state" in
        idle) ;;
        *) case "${step:-}" in *可接:*) ;; *) continue ;; esac ;;
      esac
      printf '  · %-9s %-18s %s\n' "$agent" "$project" "$step"
      idle=$((idle + 1))
    done < "$BOARD"
  fi
  if [ "$idle" -eq 0 ]; then
    echo '  （没人声明空闲；用 want <agent> <工程> [能力] 声明）'
  fi
  echo '--- 等用户点头 / 卡在审批：'
  case "$(awk -F"$TAB" '$3 == "waiting-user" || $3 == "waiting-approval" { print $1 }' "$BOARD" 2>/dev/null)" in
    '') echo '  （无）' ;;
    *) awk -F"$TAB" '$3 == "waiting-user" || $3 == "waiting-approval" { printf "  · %s（%s）：%s\n", $1, $3, $4 }' "$BOARD" ;;
  esac
  echo '--- 设备占用：'
  cmd_busy
}

cmd_wake() {
  key=${1:-}
  if [ -z "$key" ]; then
    echo "fleet: wake <短id|全id> [from]（roster 里有全 id 才给得出完整命令）" >&2
    exit 2
  fi
  short=$(awk -F"$TAB" -v k="$key" '$1 == k || $3 == k { print $1; exit }' "$ROSTER")
  full=$(awk -F"$TAB" -v k="$key" '$1 == k || $3 == k { print $3; exit }' "$ROSTER")
  if [ -z "${short:-}" ]; then
    echo "fleet: roster 里没有 '$key'。先 apelin_conversation_list 找到它的全 id，再："
    echo "  sh \"\$F\" roster <短id> <全id> [工程]"
    exit 2
  fi
  from=${2:-$(agent_of "")}
  n=$(inbox_count "$short")
  detail=$(awk -F"$TAB" -v a="$short" '$1 == a { printf "%s / %s / %s", $3, $4, $5 }' "$BOARD")
  printf '目标 %s（%s）｜黑板：%s ｜收件箱 %s 件\n' "$short" "${full:-无全id}" "${detail:-无}" "$n"
  if [ -z "${full:-}" ]; then
    echo '  roster 里没有它的全 id，先在 apelin_conversation_list 里找到那条（state=open 的），再 roster 登记。'
    exit 0
  fi
  printf 'apelin_conversation_send(session_id: "%s", text: "【fleet-wake】%s：你那边没动静了。先 sh \\"$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh\\" start %s —— 它一次打印你的收件箱（%s 件）、全队状态、该唤醒谁。有活就 take/finish，没活就 want 一条；30 秒内回一句进度，别长篇。")\n' \
    "$full" "$from" "$short" "$n"
}

cmd_start() {
  agent=$(agent_of "${1:-}")
  cmd_inbox "$agent"
  echo
  cmd_list
  echo
  cmd_care "${SWEEP_MIN:-20}"
}

# ---------- 看护与接管（v3）：心跳 / 看护报告 / 接管 ----------
# 目的：一两个 agent 睡死（对话停了、等审批里睡过去、上下文被压缩后忘了自己在干嘛）时，
# 其余的照样把活接着干完 —— 任何一件已定接口的任务都不许因为「某个人不在了」而停摆。

# 心跳：只刷新自己那行的时间戳，状态/任务/下一步一律不动。
cmd_beat() {
  agent=$(agent_of "${1:-}")
  row=$(awk -F"$TAB" -v a="$agent" '$1 == a { print; exit }' "$BOARD") || row=""
  if [ -z "${row:-}" ]; then
    echo "fleet: $agent 在黑板没有行；先 post 一行（beat 只刷新时间，不会凭空造状态）"
    return 0
  fi
  project=$(printf '%s' "$row" | cut -f2)
  state=$(printf '%s' "$row" | cut -f3)
  task=$(printf '%s' "$row" | cut -f4)
  step=$(printf '%s' "$row" | cut -f5)
  device=$(printf '%s' "$row" | cut -f6)
  write_row "$agent" "$project" "$state" "$task" "$step" "$device"
}

# 接管：把睡死那名 agent 的任务接到自己名下，并把它那行标成 handoff。
# 只接「随时能停、不冲突」的部分；改别人工程源码 / 装包 / 注销 / 杀进程不接管。
cmd_takeover() {
  me=$(agent_of "${1:-}")
  target=${2:-}
  note=${3:-}
  if [ -z "$target" ] || [ "$target" = "$me" ]; then
    echo "fleet: takeover <你> <睡死那位的短id> [备注]" >&2
    exit 2
  fi
  row=$(awk -F"$TAB" -v a="$target" '$1 == a { print; exit }' "$BOARD") || row=""
  if [ -z "${row:-}" ]; then
    echo "fleet: 黑板上没有 $target 的行，没什么可接的（先 care 看谁真睡死了）"
    return 0
  fi
  tproject=$(printf '%s' "$row" | cut -f2)
  tstate=$(printf '%s' "$row" | cut -f3)
  ttask=$(printf '%s' "$row" | cut -f4)
  tstep=$(printf '%s' "$row" | cut -f5)
  if [ -n "$note" ]; then
    mytask="接管 $target: $ttask（$note）"
  else
    mytask="接管 $target: $ttask"
  fi
  write_row "$me" "$tproject" working "$mytask" "原状态 $tstate | 原下一步 $tstep" none
  write_row "$target" "$tproject" handoff "$ttask" "已由 $me 接管；你回来请先看黑板，别两手同改一份文件" none
  full=$(awk -F"$TAB" -v k="$target" '$1 == k { print $3; exit }' "$ROSTER") || full=""
  echo "接管已记账：$me 接着 $target 的「$ttask」"
  echo "  · 只做随时能停、不冲突的部分：只读查询 / 云端 CI·Release / 下载校验 / 设备取证 / 文档与三样同步"
  echo "  · 改对方工程源码、装包、注销、杀进程一律不接（除用户当次明确同意）"
  if [ -n "${full:-}" ]; then
    printf '  · 顺手告知它（不要求回执）：apelin_conversation_send(session_id: "%s", text: "【fleet-handoff】%s：你那边 20+ 分钟没动静，黑板「%s」我已接管，你回来别接着改同一份文件，看黑板 handoff 那行即可。")\n' \
      "$full" "$me" "$ttask"
  else
    echo "  · roster 里没有它的全 id：先 apelin_conversation_list 拿到，再 roster $target <全id> <工程>"
  fi
}

# relay：审批接力 —— 列出卡在 waiting-approval 的对话，打印「照抄即发」的 relay 指令。
# 当 Ask Before Using the Screen 开着时，机器人调 icli 会卡在 waitingForApproval；
# 其他在线对话（用户在场、能批准）替它做需要 icli 的部分，结果回传，让卡住的对话继续做只读分析。
cmd_relay() {
  me=$(agent_of "")
  nowt=$(now)
  printf '=== 审批接力（%s，看护人 %s）===\n' "$(date '+%H:%M:%S')" "$me"
  n=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      [ "$state" = "waiting-approval" ] || continue
      [ "$agent" = "$me" ] && continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      printf '  · %s（%s，%sm）卡在 icli 审批：%s\n' "$agent" "$project" "$age" "${step:-?}"
      full=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $3; exit }' "$ROSTER") || full=""
      if [ -n "${full:-}" ]; then
        printf '    → apelin_conversation_send(session_id: "%s", text: "【relay】我替你做了 icli 部分：<结果>。你继续做不需要审批的分析。收到后 sh \\"$F\\" free %s %s \\"%s\\" \\"继续分析\\"")\n' \
          "$full" "$agent" "$project" "$task"
      else
        printf '    → 先 roster %s <全id> 再 relay\n' "$agent"
      fi
      n=$((n + 1))
    done < "$BOARD"
  fi
  if [ "$n" -eq 0 ]; then
    echo '  （没有卡在审批上的对话）'
  fi
  echo '--- 规矩：relay 只替做需要 icli 的查询/下载/读诊断；改源码/装包/注销/杀进程不替做。'
}

# 看护报告：谁睡死了、该谁接、谁在等用户、谁空闲、设备谁占着、全队还有几条活线。
cmd_care() {
  limit=${1:-20}
  nowt=$(now)
  me=$(agent_of "")
  printf '=== 看护报告（阈值 %s 分钟，%s，看护人 %s）===\n' "$limit" "$(date '+%H:%M:%S')" "$me"
  alive=0
  stale=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      case "$state" in
        done) continue ;;
      esac
      [ "$age" -lt "$limit" ] && alive=$((alive + 1))
    done < "$BOARD"
  fi

  echo '--- ① 疑似睡死（≥'"$limit"'m 没更新；按顺序由第一个醒着的 agent 接）：'
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      case "$state" in
        done|idle|handoff|waiting-user|waiting-approval) continue ;;
      esac
      age=$(( (nowt - ${updated:-0}) / 60 ))
      [ "$age" -lt "$limit" ] && continue
      printf '  · %s（%s，%s，%sm）：%s ｜ 下一步 %s\n' "$agent" "$project" "$state" "$age" "$task" "$step"
      printf '    接：sh "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh" takeover %s %s "已接手"\n' "${me:-<你>}" "$agent"
      full=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $3; exit }' "$ROSTER") || full=""
      if [ -n "${full:-}" ]; then
        printf '    唤：apelin_conversation_send(session_id: "%s", text: "【fleet-wake】你那边 %sm 没动静。先 sh \\"$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh\\" start %s；没活就 want 一条，30 秒内回一句。")\n' \
          "$full" "$age" "$agent"
      fi
      stale=$((stale + 1))
    done < "$BOARD"
  fi
  if [ "$stale" -eq 0 ]; then echo '  （没有：每个活着的 agent 都还在更新）'; fi

  echo '--- ② 等用户点头 / 卡在审批（都不是睡死）：'
  n2=$(awk -F"$TAB" '$3 == "waiting-user" || $3 == "waiting-approval" { print $1 }' "$BOARD" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${n2:-0}" -eq 0 ]; then
    echo '  （无）'
  else
    awk -F"$TAB" '$3 == "waiting-user" || $3 == "waiting-approval" { printf "  · %s（%s，%s）：%s\n", $1, $3, $6, $4 }' "$BOARD"
    echo '    → waiting-user：apelin_notification_send 提醒用户 + sh scripts/hud-notify.sh 8 "!等你点一下"'
    echo '    → waiting-approval：在线对话替它做需要 icli 的部分（sh "$F" relay 看详情），结果用 apelin_conversation_send 回传'
  fi

  echo '--- ③ 空闲 / 可派（直接 assign，别发消息问）：'
  idle=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      case "$state" in
        idle) ;;
        *) case "${step:-}" in *可接:*) ;; *) continue ;; esac ;;
      esac
      printf '  · %-9s %-18s %s\n' "$agent" "$project" "$step"
      idle=$((idle + 1))
    done < "$BOARD"
  fi
  if [ "$idle" -eq 0 ]; then echo '  （没人声明空闲；用 want <agent> <工程> [能力] 声明）'; fi

  echo '--- ④ 设备占用（5 分钟内才作数；动设备前先看这里）：'
  cmd_busy

  echo '--- ⑤ 全队活线：'
  printf '  近 %sm 内更新过的 agent = %s（不含 done）；疑似睡死 = %s\n' "$limit" "$alive" "$stale"
  if [ "$alive" -eq 0 ]; then
    echo '  ⚠ 全员停摆：此刻没有任何一个 agent 在更新黑板。'
    echo '    轮到看护人自己顶上：先 restart 本对话（start），把最老那件 task 用 takeover 记账，'
    echo '    再做只读/云端/文档部分，装包与注销等用户点头。'
  elif [ "$alive" -le 1 ] && [ "$stale" -gt 0 ]; then
    echo '  ⚠ 只剩一条活线：看护人优先把睡死那位的「随时能停」部分接一接，别让活线也断。'
  fi
  echo '--- 规矩：接管只接随时能停、不冲突的部分（只读 / 云端 / 校验 / 取证 / 文档与三样同步）；'
  echo '    改别人工程源码、装包、注销、杀进程不接管（除用户当次明确同意）。一文件一写者，先看 handoff 行。'
}

# ---------- 唤醒文案的唯一出处 + 一键派活（v4） ----------
# 脚本替 agent 发不了消息（apelin_* 工具只在 agent 手里），所以这里只打印「照抄就能发」的一行。
# sweep / care / wake / handout 的「停了多久」类唤醒文案都调它 —— 改文案只改这一处。
# 参数：<短id> <全id> [from] [停了多少分钟] [收件箱件数] [缩进]
wake_send_line() {
  short=${1:-}
  full=${2:-}
  from=${3:-$(agent_of "")}
  age=${4:-}
  nbox=${5:-}
  ind=${6:-}
  if [ -z "${short:-}" ]; then
    echo 'wake_send_line <短id> <全id> [from] [停了几分钟] [收件箱件数] [缩进]' >&2
    return 2
  fi
  if [ -z "${full:-}" ]; then
    printf '%s（%s 在 roster 里还没有全 id：先 apelin_conversation_list 拿到，再 sh "$F" roster %s <全id> <工程>）\n' \
      "$ind" "$short" "$short"
    return 0
  fi
  why='你那边没动静了'
  if [ -n "${age:-}" ]; then why="你那边停了 ${age}m"; fi
  box=''
  if [ -n "${nbox:-}" ]; then box="（${nbox} 件）"; fi
  printf '%sapelin_conversation_send(session_id: "%s", text: "【fleet-wake】%s：%s。先 sh \\"$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh\\" start %s —— 它一次打印你的收件箱%s、全队状态和该唤醒谁。有活就 take/finish，没活就 want 一条；30 秒内回一句进度，别长篇。")\n' \
    "$ind" "$full" "$from" "$why" "$short" "$box"
}

# handout：一条命令把「小任务」派给最合适的空闲者（v4）。
# 挑人：① 空闲（idle，或 step 里声明了「可接:X」）；② 指定能力时必须声明包含它；
#       ③ 心跳最新的优先、一样新就挑收件箱最少的；④ done / handoff / waiting-user / waiting-approval 一律不派。
# 一件事分三步做完：投进它的收件箱、把它那行改成 assigned、打印照抄就能发的唤醒指令。
cmd_handout() {
  want=${1:-any}
  project=${2:-?}
  task=${3:-?}
  accept=${4:-未写验收标准}
  from=$(agent_of "")
  if [ ! -s "$BOARD" ]; then
    echo 'fleet: 黑板是空的，没人可派（先 list 看全队，或 post 一行）' >&2
    exit 2
  fi
  cand="$ROOT/.handout-cand.$$"
  : > "$cand"
  while IFS="$TAB" read -r a p state t step device updated; do
    [ -n "${a:-}" ] || continue
    case "$state" in
      idle) ;;
      *) case "${step:-}" in *可接:*) ;; *) continue ;; esac ;;
    esac
    if [ "$want" != any ] && [ -n "$want" ]; then
      case "${step:-}" in *"$want"*) ;; *) continue ;; esac
    fi
    printf '%s\t%s\t%s\n' "${updated:-0}" "$a" "$step" >> "$cand"
  done < "$BOARD"
  target=''
  if [ -s "$cand" ]; then
    bestbox=999999
    while IFS="$TAB" read -r u a step; do
      [ -n "${a:-}" ] || continue
      n=$(inbox_count "$a")
      [ "$n" -lt "$bestbox" ] && bestbox=$n
    done < "$cand"
    while IFS="$TAB" read -r u a step; do
      [ -n "${a:-}" ] || continue
      [ "$(inbox_count "$a")" -le "$bestbox" ] || continue
      printf '%s\t%s\t%s\n' "$u" "$a" "$step"
    done < "$cand" | sort -rn | head -1 > "$cand.pick"
    target=$(cut -f2 "$cand.pick" 2>/dev/null)
  fi
  rm -f "$cand.pick" "$cand"
  if [ -z "${target:-}" ]; then
    echo "fleet: 没有人声明空闲/可接「$want」——没派出去。" >&2
    echo '  · 先 list 看谁在忙；要指定人就直接 add <agent> <工程> <任务> <验收>' >&2
    echo '  · 空闲方自己声明一条：want <agent> <工程> <能力>' >&2
    exit 2
  fi
  cmd_add "$target" "$project" "$task" "$accept" "$from"
  write_row "$target" "$project" assigned "$task" "来自 handout（要:$want）｜验收：$accept" none
  full=$(awk -F"$TAB" -v k="$target" '$1 == k { print $3; exit }' "$ROSTER") || full=''
  printf '→ 已派给 %s。叫醒它：\n' "$target"
  wake_send_line "$target" "${full:-}" "$from" '' "$(inbox_count "$target")"
}

# ---------- 接手包 / 唤醒清单 / 收尾自检（v5） ----------
# brief：把某人手上那件活看全（工程/状态/任务/下一步/停了多久/收件箱），并把它专属的
# 「照抄即发」唤醒行与「照抄即跑」接管命令备好 —— 看护人不必自己想格式，也不必问任何人。
cmd_brief() {
  key=${1:-}
  if [ -z "$key" ]; then
    echo 'fleet: brief <短id|全id>（先 care 看谁该接，再 brief 它）' >&2
    exit 2
  fi
  short=$(awk -F"$TAB" -v k="$key" '$1 == k || $3 == k { print $1; exit }' "$ROSTER")
  full=$(awk -F"$TAB" -v k="$key" '$1 == k || $3 == k { print $3; exit }' "$ROSTER")
  short=${short:-$key}
  me=$(agent_of "")
  row=$(awk -F"$TAB" -v a="$short" '$1 == a { print; exit }' "$BOARD") || row=""
  printf '=== 接手包：%s（%s）===\n' "$short" "${full:-无全id}"
  if [ -z "${row:-}" ]; then
    echo '  黑板上没有它的行 —— 可能一直没醒（登记过名册，却没 post 过）。'
    echo '  · 先唤醒（照抄即发）：'
    wake_send_line "$short" "${full:-}" "$me" '' '' '    '
    echo '  · 唤不醒就当它没有在跑的活；黑板上不动别人的行（唯一例外是 takeover 记账）。'
    return 0
  fi
  project=$(printf '%s' "$row" | cut -f2)
  state=$(printf '%s' "$row" | cut -f3)
  task=$(printf '%s' "$row" | cut -f4)
  step=$(printf '%s' "$row" | cut -f5)
  device=$(printf '%s' "$row" | cut -f6)
  updated=$(printf '%s' "$row" | cut -f7)
  age=$(( (now - ${updated:-0}) / 60 ))
  printf '  工程 %s ｜ 状态 %s ｜ 动作 %s ｜ 停了 %sm ｜ 收件箱 %s 件\n' \
    "$project" "$state" "${device:-none}" "$age" "$(inbox_count "$short")"
  printf '  任务：%s\n  下一步：%s\n' "$task" "$step"
  echo '  接口先看黑板这行 + 它工程里的文件（docs/、AGENTS.md、fleet/board.tsv 快照）——'
  echo '  接口离开聊天才算冗余，别人凭这些就能接着干。'
  case "$state" in
    handoff)
      echo '  ⚠ 它已被别人接管（handoff）：先 list 看是谁接的，别两头同改一份文件。'
      return 0 ;;
    waiting-user|waiting-approval)
      echo '  ⚠ 它在等用户点头 / 卡在 icli 审批，不算睡死：waiting-user 用通知提醒用户；'
      echo '    waiting-approval 在线对话替它做 icli 部分（sh "$F" relay 看详情）。'
      return 0 ;;
    done|idle)
      echo '  ⚠ 它没有在手的长活（done/idle）：有活就直接 assign / handout 给它。'
      return 0 ;;
  esac
  echo '  ① 先唤醒（照抄即发，不要求回执）：'
  wake_send_line "$short" "${full:-}" "$me" "$age" "$(inbox_count "$short")" '    '
  echo '  ② 唤醒后 60 秒仍无动静，再接管（照抄即跑）：'
  printf '    sh "$F" takeover %s %s "唤醒 60 秒无动静"\n' "$me" "$short"
  echo '     只接随时能停的部分：只读查询 / 云端 CI·Release / 下载校验 / 设备取证 / 文档与三样同步；'
  echo '     改对方工程源码、装包、注销、杀进程一律不接（除用户当次明确同意）。'
}

# wakeall：只打「照抄即发的整行」，一次把全队该唤醒的都列出来（含名册里没 post 过的）。
cmd_wakeall() {
  limit=${1:-20}
  nowt=$(now)
  me=$(agent_of "")
  n=0
  printf '=== 照抄即发（≥%sm 没更新的活线，%s，看护人 %s）===\n' "$limit" "$(date '+%H:%M:%S')" "$me"
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      case "$state" in done|handoff|idle|waiting-user|waiting-approval) continue ;; esac
      [ "$agent" = "$me" ] && continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      [ "$age" -lt "$limit" ] && continue
      full=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $3; exit }' "$ROSTER")
      wake_send_line "$agent" "${full:-}" "$me" "$age" "$(inbox_count "$agent")" '  '
      n=$((n + 1))
    done < "$BOARD"
  fi
  if [ -s "$ROSTER" ]; then
    while IFS="$TAB" read -r short ts full project note seen; do
      [ -n "${short:-}" ] || continue
      [ "$short" = "$me" ] && continue
      if awk -F"$TAB" -v a="$short" '$1 == a { found = 1 } END { exit !found }' "$BOARD"; then
        continue
      fi
      age=$(( (nowt - ${seen:-0}) / 60 ))
      [ "$age" -lt "$limit" ] && continue
      wake_send_line "$short" "${full:-}" "$me" "$age" '' '  '
      n=$((n + 1))
    done < "$ROSTER"
  fi
  if [ "$n" -eq 0 ]; then
    echo '  （没有要唤醒的：每个人都在更新黑板，或被标了 done/handoff/idle/waiting-user/waiting-approval）'
  fi
  echo '  发的时候一次最多两条（别把别人信箱刷屏）；发完 60 秒仍无动静就 brief <短id> → takeover。'
}

# wake-do：输出可以直接执行唤醒的目标列表（session_id + 文案）+ 记账防重复（5 分钟内不重发）。
# 脚本替 agent 发不了 apelin_conversation_send，但把目标整理成 agent 一读就能直接调的格式：
#   WAKE_SEND|<session_id>|<唤醒文案>
# agent 读到后立刻逐条调 apelin_conversation_send(session_id, text) 真发出去——不能只打印不动手。
cmd_wake_do() {
  limit=${1:-${SWEEP_MIN:-20}}
  nowt=$(now)
  me=$(agent_of "")
  wakelog="$ROOT/.wake-log"
  n=0
  printf '=== 唤醒执行单（≥%sm 没更新，%s，看护人 %s）===\n' "$limit" "$(date '+%H:%M:%S')" "$me"
  echo '# 格式：WAKE_SEND|<session_id>|<唤醒文案>'
  echo '# 读到后立刻调 apelin_conversation_send(session_id, text) 真发出去'
  echo '# 一次最多发两条；发完 60 秒无动静再 brief → takeover'
  echo ''
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      case "$state" in done|handoff|idle|waiting-user|waiting-approval) continue ;; esac
      [ "$agent" = "$me" ] && continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      [ "$age" -lt "$limit" ] && continue
      full=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $3; exit }' "$ROSTER")
      if [ -z "${full:-}" ]; then
        printf '# %s: roster 里没有全 id（跳过——先 apelin_conversation_list 拿到，再 roster 登记）\n' "$agent"
        continue
      fi
      # 5 分钟内已发过的不重复
      last_sent=$(awk -F"$TAB" -v a="$agent" '$1 == a { print $2; exit }' "$wakelog" 2>/dev/null) || last_sent=""
      if [ -n "${last_sent:-}" ]; then
        sent_age=$(( nowt - last_sent ))
        if [ "$sent_age" -lt 300 ]; then
          printf '# %s: %sm 前已发过唤醒（跳过，5 分钟内不重复）\n' "$agent" "$(( sent_age / 60 ))"
          continue
        fi
      fi
      nbox=$(inbox_count "$agent")
      printf 'WAKE_SEND|%s|【fleet-wake】%s：你那边停了 %sm。收件箱 %s 件。先 sh \\"$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh\\" start %s —— 一次打印收件箱、全队状态和该唤醒谁。有活就 take/finish，没活就 want 一条；30 秒内回一句进度。\n' \
        "$full" "$me" "$age" "$nbox" "$agent"
      # 记账（防重复）
      lock
      tmp="$wakelog.tmp.$$"
      if [ -s "$wakelog" ]; then
        awk -F"$TAB" -v a="$agent" '$1 != a' "$wakelog" > "$tmp" || : > "$tmp"
      else
        : > "$tmp"
      fi
      printf '%s\t%s\t%s\n' "$agent" "$nowt" "$full" >> "$tmp"
      mv "$tmp" "$wakelog"
      release
      n=$((n + 1))
    done < "$BOARD"
  fi
  if [ "$n" -eq 0 ]; then
    echo '# （没有需要唤醒的：每个人都在更新黑板，或被标了 done/handoff/idle/waiting-user/waiting-approval）'
  else
    printf '\n# ⚠ 以上 %s 条必须立刻调 apelin_conversation_send 真发出去——不能只打印不动手！\n' "$n"
  fi
}

# guard：收尾自检 —— 看护报告 + 收尾三件事。每个 agent 每轮收尾前跑它，防睡死靠流程不靠记性。
cmd_guard() {
  agent=$(agent_of "${1:-}")
  limit=${2:-20}
  cmd_care "$limit"
  echo
  echo '=== 收尾三件事（此刻做，别留给下一个人）==='
  echo "  ① 唤醒：sh \"\$F\" wake-do $limit —— 输出 WAKE_SEND 行，立刻逐条调 apelin_conversation_send 真发（一次最多两条）。"
  echo "  ② 接管：发完 60 秒仍无动静 → sh \"\$F\" brief <短id>，再 sh \"\$F\" takeover $agent <短id> \"唤醒 60 秒无动静\"。"
  echo "  ③ 落盘：sh \"\$F\" post $agent <工程> <状态> \"<任务>\" \"<下一步 + 接口>\" —— 接口写全："
  echo '     文件路径 / 诊断键与期望值 / 包名与版本 / Release 资产 URL / CI run 号 / 验收标准。'
  echo '  这三件做完，你这一轮才算没把活带走；只写「我干完了」不写接口，等于没交接。'
  echo '  ⚠ 唤醒不是只打印：wake-do 输出的每条 WAKE_SEND 必须立刻调 apelin_conversation_send 真发出去！'
}

# ---------- 成员实时刷新 / 智能再分配（v6） ----------
# 本机上「成员」只有一处真相：名册（agents.tsv，登记过自己）+ 黑板（board.tsv，有心跳）。
# 两者对账就知道**新来的**（黑板有行、名册没登记）和**疑似离场的**（名册有、黑板没行）。
FSH="$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh"

# probation：新接入专项看护 —— 「刚来的机器人别没做完就睡死」。阈值比常规看护更严。
# 触发条件（满足其一，且黑板显示还没 done/handoff）：名册 note 写了「新接入」；
# 登记 ≤120 分钟；或**黑板有行但名册根本没登记**（刚出现、还没来得及登记）。
cmd_probation() {
  limit=${1:-${FLEET_PROBATION_MIN:-15}}
  nowt=$(now)
  me=$(agent_of "")
  printf '=== 新接入守则检查（接入后 >%sm 没心跳就算睡死，%s）===\n' "$limit" "$(date '+%H:%M:%S')"
  n=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      case "$state" in done|handoff) continue ;; esac
      age=$(( (nowt - ${updated:-0}) / 60 ))
      [ "$age" -lt "$limit" ] && continue
      note=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $5; exit }' "$ROSTER") || note=''
      seen=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $6; exit }' "$ROSTER") || seen=''
      fresh=0
      case "${note:-}" in *新接入*) fresh=1 ;; esac
      if [ -z "${seen:-}" ]; then fresh=1; fi
      if [ -n "${seen:-}" ] && [ "$(( (nowt - seen) / 60 ))" -le 120 ]; then fresh=1; fi
      [ "$fresh" -eq 1 ] || continue
      n=$((n + 1))
      box=$(inbox_count "$agent")
      printf '  ⚠ %s（%s，%s，%sm 没心跳，箱里 %s 件）｜ %s\n      下一步 %s\n' \
        "$agent" "$project" "$state" "$age" "$box" "$task" "$step"
      full=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $3; exit }' "$ROSTER") || full=''
      wake_send_line "$agent" "${full:-}" "$me" "$age" "$box" '    唤：'
      printf '    接：sh %s takeover %s %s "新接入 %sm 无心跳"\n' "$FSH" "${me:-<你>}" "$agent" "$age"
      printf '    骨架踩实（它回来照做即可）：先 sh %s members，再 beat；活照 inbox 做，做完 finish。\n' "$FSH"
    done < "$BOARD"
  fi
  if [ "$n" -eq 0 ]; then
    echo "  （没有：新接入/未登记的都在 $limit 分钟内动过）"
  fi
}

# members：成员对账（只读）—— 谁在、谁新来、谁像走了、各自能接什么、箱子几件。
cmd_members() {
  limit=${1:-20}
  nowt=$(now)
  me=$(agent_of "")
  new_t="$ROOT/.mem-new.$$"
  : > "$new_t"
  printf '=== 成员对账（%s，看护人 %s）===\n' "$(date '+%H:%M:%S')" "$me"

  echo '--- ① 现在在册、黑板有心跳的：'
  n=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      able='-'
      case "${step:-}" in *可接:*) able=${step#*可接:} ;; esac
      printf '  · %-9s %-16s %-12s age=%-4s box=%-2s 可接=%s\n' \
        "$agent" "$project" "$state" "$age" "$(inbox_count "$agent")" "$able"
      if ! awk -F"$TAB" -v a="$agent" '$1 == a { f = 1 } END { exit !f }' "$ROSTER"; then
        printf '%s\t%s\t%s\n' "$agent" "$project" "$step" >> "$new_t"
      fi
      n=$((n + 1))
    done < "$BOARD"
  fi
  [ "$n" -eq 0 ] && echo '  （黑板空：还没人 post；roster 看名册）'

  echo '--- ② 名册里有、黑板没行（可能已离场，也可能只是还没 post）：'
  g=0
  if [ -s "$ROSTER" ]; then
    while IFS="$TAB" read -r short ts full project note seen; do
      [ -n "${short:-}" ] || continue
      if awk -F"$TAB" -v a="$short" '$1 == a { f = 1 } END { exit !f }' "$BOARD"; then
        continue
      fi
      printf '  · %-9s %-16s 登记 %sm 前 ｜ %s\n' \
        "$short" "${project:-?}" "$(( (nowt - ${seen:-0}) / 60 ))" "${note:-}"
      printf '    确认结束：sh %s roster-drop %s ｜ 只是没 post：sh %s post %s <工程> <状态> "<任务>" "<下一步>"\n' \
        "$FSH" "$short" "$FSH" "$short"
      g=$((g + 1))
    done < "$ROSTER"
  fi
  [ "$g" -eq 0 ] && echo '  （无）'

  echo '--- ③ 新来的（黑板有行、名册没登记）→ 登记 + 立刻派一件活：'
  if [ -s "$new_t" ]; then
    while IFS="$TAB" read -r a p step; do
      [ -n "${a:-}" ] || continue
      printf '  · %s（%s）\n' "$a" "$p"
      printf '    登记：sh %s roster %s <全id> %s "新接入"\n' "$FSH" "$a" "$p"
      printf '    派活：sh %s intake %s <全id> %s "只读,云端,文档"\n' "$FSH" "$a" "$p"
    done < "$new_t"
  else
    echo '  （无）'
  fi

  echo '--- ③b 新接入守则检查（刚来的别没做完就睡死）：'
  cmd_probation "${FLEET_PROBATION_MIN:-15}"

  echo '--- ④ 叫不醒 / 已离场 → 立刻交接给活着的人：'
  printf '  一条命令看全部去向（改派 / 自己接 / 唤醒）：sh %s rebalance %s\n' "$FSH" "$limit"
  echo "  一句话：活不能留在睡死的人手里 —— 唤醒不了就改派，改派不了就自己接。"

  rm -f "$new_t"
}

# intake：新机器人接入 —— 登记 + 声明可接能力 + 从待派池挑一件最匹配的活改派给它 + 备好唤醒行。
cmd_intake() {
  short=${1:-}
  full=${2:-}
  project=${3:-?}
  able=${4:-只读,云端,文档}
  from=$(agent_of "")
  if [ -z "$short" ] || [ "$short" = unknown ]; then
    echo 'fleet: intake <短id> [全id] [工程] [能力,逗号分隔]' >&2
    exit 2
  fi
  cmd_roster "$short" "$full" "$project" "新接入 $able"
  cmd_want "$short" "$project" "$able"

  pick=''
  if [ -s "$INBOX" ]; then
    while IFS="$TAB" read -r id ts f from2 to p task accept; do
      [ -n "${id:-}" ] || continue
      kw=$(printf '%s' "$able" | tr ',' '\n' | awk -v t="$task" 'length($0) && index(t, $0) { print; exit }')
      if [ -n "${kw:-}" ] && [ -z "$pick" ]; then
        pick="$id"
      fi
    done < "$INBOX"
  fi
  if [ -n "$pick" ]; then
    info=$(awk -F"$TAB" -v id="$pick" '$1 == id { print $5 "\t" $6 "\t" $7 "\t" $4; exit }' "$INBOX")
    tp=$(printf '%s' "$info" | cut -f1)
    tt=$(printf '%s' "$info" | cut -f2)
    ta=$(printf '%s' "$info" | cut -f3)
    told=$(printf '%s' "$info" | cut -f4)
    inbox_remove "$pick"
    cmd_add "$short" "$tp" "$tt" "$ta" "$from"
    write_row "$short" "$tp" assigned "$tt" "来自 task#$pick（原给 $told，改派）｜验收：$ta" none
    printf 'fleet: 新接入 %s 立刻拿到 task#%s（原给 %s）\n' "$short" "$pick" "$told"
  else
    echo "fleet: $short 已登记；待派池里暂时没有匹配「$able」的活（池空或能力不命中）。"
  fi
  printf '守则：新接入 %s 每 ≤%sm 至少 beat 一次；超了就被当睡死，看护人会 wake → rebalance 改派。\n' \
    "$short" "${FLEET_PROBATION_MIN:-15}"
  printf '照抄即发（叫醒它）：\n'
  wake_send_line "$short" "$full" "$from" '' "$(inbox_count "$short")" '  '
}

# roster-drop：确认离场的成员从名册去掉，并把它黑板那行标 handoff（活由 rebalance 交接）。
cmd_roster_drop() {
  key=${1:-}
  if [ -z "$key" ]; then
    echo 'fleet: roster-drop <短id>' >&2
    exit 2
  fi
  lock
  tmp="$ROSTER.tmp.$$"
  if [ -s "$ROSTER" ]; then
    awk -F"$TAB" -v k="$key" '$1 != k' "$ROSTER" > "$tmp" || : > "$tmp"
  else
    : > "$tmp"
  fi
  mv "$tmp" "$ROSTER"
  release
  if awk -F"$TAB" -v k="$key" '$1 == k { f = 1 } END { exit !f }' "$BOARD"; then
    p=$(awk -F"$TAB" -v k="$key" '$1 == k { print $2; exit }' "$BOARD")
    write_row "$key" "$p" handoff "已离场（roster-drop）" "活已交接，别再派" none
  fi
  printf 'fleet: %s 已从名册去掉，黑板那行标 handoff。\n' "$key"
}

# rebalance：实时交接 —— 叫不醒 / 已离场者手上的活，立刻给活着的人（只打印，照抄即跑）。
cmd_rebalance() {
  limit=${1:-60}
  nowt=$(now)
  me=$(agent_of "")
  cand="$ROOT/.reb-cand.$$"
  : > "$cand"
  printf '=== 交接建议（≥%sm 没动静，%s，看护人 %s）===\n' "$limit" "$(date '+%H:%M:%S')" "$me"
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      case "$state" in done|handoff) continue ;; esac
      age=$(( (nowt - ${updated:-0}) / 60 ))
      [ "$age" -ge "$limit" ] && continue
      printf '%s\t%s\t%s\n' "$agent" "$project" "$age" >> "$cand"
    done < "$BOARD"
  fi

  stale=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      case "$state" in done|idle|handoff|waiting-user|waiting-approval) continue ;; esac
      age=$(( (nowt - ${updated:-0}) / 60 ))
      [ "$age" -lt "$limit" ] && continue
      stale=$((stale + 1))
      box=$(inbox_count "$agent")
      printf '  · %s（%s，%s，%sm，箱里 %s 件）：%s\n    下一步 %s\n' \
        "$agent" "$project" "$state" "$age" "$box" "$task" "$step"
      pick=''
      pickbox=999999
      if [ -s "$cand" ]; then
        while IFS="$TAB" read -r a p g; do
          [ -n "${a:-}" ] || continue
          [ "$a" = "$agent" ] && continue
          b=$(inbox_count "$a")
          if [ "$b" -lt "$pickbox" ]; then
            pickbox=$b
            pick="$a"
          fi
        done < "$cand"
      fi
      if [ -z "${pick:-}" ]; then
        echo '    ⚠ 没有一个活着的候选（全队停摆）：自己先 takeover，再把它的活按 plan 分出去。'
      else
        printf '    改派（给活着的 %s，box=%s）：sh %s add %s %s "%s" "%s"\n' \
          "$pick" "$pickbox" "$FSH" "$pick" "$project" "$task" "$step"
      fi
      printf '    自己接：sh %s takeover %s %s "唤醒 %sm 无动静"\n' "$FSH" "${me:-<你>}" "$agent" "$limit"
      full=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $3; exit }' "$ROSTER") || full=''
      [ -n "${full:-}" ] && wake_send_line "$agent" "$full" "$me" "$age" "$box" '    唤：'
    done < "$BOARD"
  fi
  [ "$stale" -eq 0 ] && echo "  （没有：近 ${limit}m 每个活线都在更新）"

  echo '--- 已离场（名册有、黑板无行）：'
  g=0
  if [ -s "$ROSTER" ]; then
    while IFS="$TAB" read -r short ts full project note seen; do
      [ -n "${short:-}" ] || continue
      if awk -F"$TAB" -v a="$short" '$1 == a { f = 1 } END { exit !f }' "$BOARD"; then
        continue
      fi
      printf '  · %-9s %-16s 登记 %sm 前 ｜ %s\n' \
        "$short" "${project:-?}" "$(( (nowt - ${seen:-0}) / 60 ))" "${note:-}"
      g=$((g + 1))
    done < "$ROSTER"
  fi
  [ "$g" -eq 0 ] && echo '  （无）'
  echo '--- 收尾：上面每一件都要有去向（改派 / 自己接），一件都不许留在睡死的人手里。'
  rm -f "$cand"
}

# progress：实时刷新自己那行的「进展/下一步」与时间（不动工程/状态/任务/设备）。
# 每跑完一小步就写一句 —— 别的对话 list 立刻看见你到哪了，不用 post 整行、也不用发消息。
cmd_progress() {
  msg=${1:-继续}
  agent=$(agent_of "")
  cur=$(awk -F"$TAB" -v a="$agent" '$1 == a { print $2 "\t" $3 "\t" $4 "\t" $6; exit }' "$BOARD" 2>/dev/null) || cur=""
  if [ -z "$cur" ]; then
    echo "fleet: 你还没 post 过，先 post 一行再 progress" >&2
    exit 2
  fi
  project=$(printf '%s' "$cur" | cut -f1)
  state=$(printf '%s' "$cur" | cut -f2)
  task=$(printf '%s' "$cur" | cut -f3)
  device=$(printf '%s' "$cur" | cut -f4)
  write_row "$agent" "$project" "$state" "$task" "进展：$msg" "$device"
  printf 'fleet: 进展已刷新 -> %s（%s）\n' "$agent" "$msg"
}

# plan：统一调度建议（只读）—— 把全队当一份资源重排：负载 / 撞车 / 待派配对 / 空闲 / 设备排队 / 结论。
cmd_plan() {
  limit=${1:-20}
  nowt=$(now)
  me=$(agent_of "")
  idle_t="$ROOT/.plan-idle.$$"
  load_t="$ROOT/.plan-load.$$"
  : > "$idle_t"
  : > "$load_t"
  printf '=== 统一调度建议（%s）｜看护人 %s ===\n' "$(date '+%H:%M:%S')" "$me"

  echo '--- ① 负载（box=收件箱没人认领的件数；age=分钟没更新黑板）：'
  n=0
  if [ -s "$BOARD" ]; then
    while IFS="$TAB" read -r agent project state task step device updated; do
      [ -n "${agent:-}" ] || continue
      age=$(( (nowt - ${updated:-0}) / 60 ))
      box=$(inbox_count "$agent")
      mark='正常'
      if [ "$age" -ge "$limit" ]; then
        mark='陈旧→唤醒/交接'
      elif [ "$box" -ge 2 ]; then
        mark='过载→分流'
      fi
      printf '  · %-9s %-16s %-12s box=%-2s age=%-4s %s\n' "$agent" "$project" "$state" "$box" "$age" "$mark"
      printf '%s\t%s\t%s\n' "$agent" "$project" "$age" >> "$load_t"
      case "$state" in
        idle) printf '%s\t%s\n' "$agent" "${step:-}" >> "$idle_t" ;;
        *) case "${step:-}" in *可接:*) printf '%s\t%s\n' "$agent" "$step" >> "$idle_t" ;; esac ;;
      esac
      n=$((n + 1))
    done < "$BOARD"
  fi
  [ "$n" -eq 0 ] && echo '  （黑板空：先 post 一行，或 roster 登记自己）'

  echo '--- ② 撞车检查（同一工程多人同时在动 = 可能同改一份文件）：'
  c=0
  for p in $(cut -f2 "$load_t" 2>/dev/null | sort -u); do
    [ -n "${p:-}" ] || continue
    [ "$p" = "-" ] && continue
    cnt=$(awk -F"$TAB" -v p="$p" '$2 == p { c++ } END { print c + 0 }' "$load_t")
    [ "$cnt" -ge 2 ] || continue
    who=$(awk -F"$TAB" -v p="$p" '$2 == p { printf "%s ", $1 }' "$load_t")
    printf '  ⚠ %s：%s（一文件一写者：先划清文件边界，或用 dep 串起来）\n' "$p" "$who"
    c=$((c + 1))
  done
  [ "$c" -eq 0 ] && echo '  （无）'

  echo '--- ③ 待派配对（收件箱里没认领的活 → 空闲/可接的人）：'
  t=0
  if [ -s "$INBOX" ]; then
    while IFS="$TAB" read -r id ts from to project task accept; do
      [ -n "${id:-}" ] || continue
      age=$(( (nowt - ${ts:-0}) / 60 ))
      hit=''
      if [ -s "$idle_t" ]; then
        while IFS="$TAB" read -r a step; do
          [ -n "${a:-}" ] || continue
          [ "$a" = "$to" ] && continue
          able=${step#*可接:}
          kw=$(printf '%s' "$able" | tr ',' '\n' | awk -v t2="$task" 'length($0) && index(t2, $0) { print; exit }')
          if [ -n "${kw:-}" ]; then
            hit="$a（命中能力「$kw」）"
            hitid="$a"
            break
          fi
        done < "$idle_t"
      fi
      printf '  · task#%-14s 现给 %-9s %-16s %sm ｜ %s\n' "$id" "$to" "$project" "$age" "$task"
      if [ -n "${hit:-}" ]; then
        printf '      可改派：%s → sh %s add %s %s "%s" "%s"\n' "$hit" "$FSH" "$hitid" "$project" "$task" "$accept"
      fi
      t=$((t + 1))
    done < "$INBOX"
  fi
  [ "$t" -eq 0 ] && echo '  （收件箱空：没有积压）'

  echo '--- ④ 空闲资源（能立刻派活的人）：'
  if [ -s "$idle_t" ]; then
    while IFS="$TAB" read -r a step; do
      [ -n "${a:-}" ] || continue
      printf '  · %-9s box=%-2s %s\n' "$a" "$(inbox_count "$a")" "${step:-（没写能力）}"
    done < "$idle_t"
  else
    echo '  （没人声明空闲；让空闲方 want <agent> <工程> [能力]）'
  fi

  echo '--- ⑤ 设备排队（谁在动设备，其余排队）：'
  cmd_busy

  echo '--- ⑥ 结论三条（照抄即跑）：'
  worst=''
  worstbox=-1
  best=''
  bestbox=999999
  while IFS="$TAB" read -r a p age; do
    [ -n "${a:-}" ] || continue
    b=$(inbox_count "$a")
    if [ "$b" -gt "$worstbox" ]; then worstbox=$b; worst=$a; fi
    if [ "$b" -lt "$bestbox" ]; then bestbox=$b; best=$a; fi
  done < "$load_t"
  if [ -n "${worst:-}" ] && [ "$worstbox" -ge 2 ] && [ -n "${best:-}" ] && [ "$best" != "$worst" ]; then
    printf '  ① 分流：%s 箱子最重（%s 件）→ 把「随时能停」的件改派给 %s（box=%s）：sh %s plan / handout\n' \
      "$worst" "$worstbox" "$best" "$bestbox" "$FSH"
  else
    printf '  ① 分流：负载均衡，无需搬动（最重 %s 件）\n' "${worstbox:-0}"
  fi
  printf '  ② 唤醒与交接：sh %s rebalance %s（叫不醒就改派，叫得醒就让它继续）\n' "$FSH" "$limit"
  printf '  ③ 成员刷新：sh %s members（新来的立刻 intake 派活；走了的 roster-drop）\n' "$FSH"
  rm -f "$idle_t" "$load_t"
}

# refresh：资源刷新（写）—— prune 陈旧席位 + 落盘快照 + members 对账 + plan 统一调度，一条命令。
# 只清 48 小时没心跳的席位与 6 小时前的旧投件（prune 的本职），不动任何人的在手任务。
cmd_refresh() {
  limit=${1:-20}
  cmd_prune 2880
  cmd_snapshot
  echo
  cmd_members "$limit"
  echo
  cmd_plan "$limit"
}

# ---------- 分发 ----------
CMD=${1:-list}
if [ $# -gt 0 ]; then
  shift
fi

case "$CMD" in
  list)     cmd_list "$@" ;;
  busy)     cmd_busy "$@" ;;
  post)     cmd_post "$@" ;;
  hold)     cmd_hold "$@" ;;
  free)     cmd_free "$@" ;;
  assign)   cmd_assign "$@" ;;
  claim)    cmd_claim "$@" ;;
  done)     cmd_done "$@" ;;
  prune)    cmd_prune "$@" ;;
  snapshot) cmd_snapshot "$@" ;;
  add)      cmd_add "$@" ;;
  inbox)    cmd_inbox "$@" ;;
  take)     cmd_take "$@" ;;
  finish)   cmd_finish "$@" ;;
  wish)     cmd_want "$@" ;;
  want)     cmd_want "$@" ;;
  dep)      cmd_dep "$@" ;;
  brief)    cmd_brief "$@" ;;
  decision) cmd_decision "$@" ;;
  handout)  cmd_handout "$@" ;;
  progress) cmd_progress "$@" ;;
  members)  cmd_members "$@" ;;
  intake)   cmd_intake "$@" ;;
  rebalance) cmd_rebalance "$@" ;;
  plan)     cmd_plan "$@" ;;
  refresh)  cmd_refresh "$@" ;;
  roster-drop) cmd_roster_drop "$@" ;;
  relay)    cmd_relay "$@" ;;
  care)     cmd_care "$@" ;;
  beat)     cmd_beat "$@" ;;
  takeover) cmd_takeover "$@" ;;
  start)    cmd_start "$@" ;;
  sweep)    cmd_sweep "$@" ;;
  roster)   cmd_roster "$@" ;;
  wake)     cmd_wake "$@" ;;
  wakeall)  cmd_wakeall "$@" ;;
  wake-do)  cmd_wake_do "$@" ;;
  guard)    cmd_guard "$@" ;;
  help|-h|--help) usage ;;
  *) echo "fleet: 不认识的命令 '$CMD'（用 help 看用法）" >&2; exit 2 ;;
esac
