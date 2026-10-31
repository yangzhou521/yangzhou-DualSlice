#!/bin/sh
#
# sync-all.sh —— 一把把「硬性规定 + 技能包 + 记忆」三样同步到云端（仓库）之前的镜像步骤。
#
# 三样东西各自的位置：
#   硬性规定 = 本工程 AGENTS.md（就是仓库根那份，push 即上云端；技能里的硬规矩副本在 skills/）
#   技能包   = $HOME/Documents/wiki.qaq.apelin/skills  ↔  仓库 skills/
#   记忆     = $HOME/Documents/wiki.qaq.apelin/memories.json  ↔  仓库 memory/memories.json
#
# 用法：
#   sh scripts/sync-all.sh          # 本地 → 仓库（默认），完了打印 git status 让你 commit/push
#   sh scripts/sync-all.sh diff     # 只比差异，不动文件
#
# 本机那份是 Apelin 真正读的；仓库那份是版本化与云端备份，两边必须一致。
# 提交与推送用 Apelin 的 git 工具（git_commit / git_push），本脚本不动 git。
#
set -eu

ROOT="${APELIN_PROJECT_ROOT:?}"
MODE=${1:-push}
RC=0

echo "== 硬性规定 =="
if [ -f "$ROOT/AGENTS.md" ]; then
  echo "   AGENTS.md 在仓库根（$(wc -c <"$ROOT/AGENTS.md" | tr -d ' ') 字节）—— push 即上云端"
  grep -n '^## ' "$ROOT/AGENTS.md" | sed 's/^/   /'
else
  echo "   缺 AGENTS.md" >&2; RC=1
fi

echo "== 技能包 =="
if [ "$MODE" = diff ]; then
  # 临时文件只写项目内（本机 /tmp 常写不进，见 AGENTS.md 硬规矩）
  TMPD="$ROOT/.tmp"; mkdir -p "$TMPD"
  if diff -r "$HOME/Documents/wiki.qaq.apelin/skills" "$ROOT/skills" >"$TMPD/sync-all-skills.diff" 2>&1; then
    echo "   本机与仓库一致"
  else
    echo "   有差异（本机 vs 仓库）：" >&2; sed 's/^/   /' "$TMPD/sync-all-skills.diff" >&2; RC=1
  fi
else
  sh "$ROOT/scripts/sync-skills.sh" push
fi

echo "== 记忆 =="
if [ "$MODE" = diff ]; then
  sh "$ROOT/scripts/sync-memory.sh" diff || RC=1
else
  sh "$ROOT/scripts/sync-memory.sh" push
fi

echo "== 接下来 =="
if [ "$MODE" = diff ]; then
  echo "   只是检查，没动文件"
else
  echo "   用 Apelin 的 git 工具看状态并提交推送："
  echo "     git_status → git_commit(all: true) → git_push"
fi
exit $RC
