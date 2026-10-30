#!/bin/sh
#
# fleet.sh v2 —— 本机所有对话共用的「任务黑板 + 收件箱 + 唤醒器」。
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
#   唤醒（防睡死）：
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh start  [agent]      # 开工一条命令：收件箱+全队+唤醒清单
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh sweep  [分钟，默认 20]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh roster [短id] [全id] [工程] [备注]
#     sh $HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh wake   <短id|全id> [from]
#
# agent：对话 id 前 8 位（apelin_conversation_list 里能看到），或 FLEET_AGENT 环境变量。
# 状态：working | assigned | blocked | waiting-user | idle | done
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
mkdir -p "$ROOT"
[ -f "$BOARD" ] || : > "$BOARD"
[ -f "$INBOX" ] || : > "$INBOX"
[ -f "$ROSTER" ] || : > "$ROSTER"

usage() {
  cat <<'EOF'
fleet.sh —— 黑板 + 收件箱 + 唤醒器（本机所有对话共用）
  状态类  list | busy | post | hold | free | done | prune | snapshot
  派活类  assign | claim | add | inbox | take | finish | want
  唤醒类  start | sweep | roster | wake
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
    printf '  task#%-14s 来自 %-9s %-18s %s\n      验收：%s（%sm 前投递）\n' \
      "$id" "$from" "$project" "$task" "$accept" "$(( (nowt - ${ts:-0}) / 60 ))"
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
}

# 空闲声明：一行写清「我现在没活、能接什么」——别人不必再发消息问。
cmd_want() {
  agent=$(agent_of "${1:-}")
  write_row "$agent" "${2:-?}" idle "空闲待派" "可接:${3:-只读,云端,取证,文档}" none
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
      full=$(awk -F"$TAB" -v k="$agent" '$1 == k { print $2; exit }' "$ROSTER")
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
  echo '--- 等用户点头的：'
  case "$(awk -F"$TAB" '$3 == "waiting-user" { print $1 }' "$BOARD" 2>/dev/null)" in
    '') echo '  （无）' ;;
    *) awk -F"$TAB" '$3 == "waiting-user" { printf "  · %s：%s\n", $1, $4 }' "$BOARD" ;;
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
  short=$(awk -F"$TAB" -v k="$key" '$1 == k || $2 == k { print $1; exit }' "$ROSTER")
  full=$(awk -F"$TAB" -v k="$key" '$1 == k || $2 == k { print $2; exit }' "$ROSTER")
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
  cmd_sweep "${SWEEP_MIN:-20}"
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
  want)     cmd_want "$@" ;;
  start)    cmd_start "$@" ;;
  sweep)    cmd_sweep "$@" ;;
  roster)   cmd_roster "$@" ;;
  wake)     cmd_wake "$@" ;;
  help|-h|--help) usage ;;
  *) echo "fleet: 不认识的命令 '$CMD'（用 help 看用法）" >&2; exit 2 ;;
esac
