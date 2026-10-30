#!/bin/sh
#
# sync-skills.sh —— 本地技能目录 ↔ 仓库 skills/ 双向同步。
#
# 本地（Apelin 读的那份）：$HOME/Documents/wiki.qaq.apelin/skills
# 仓库（版本化、可上 GitHub 的那份）：<工程根>/skills
#
# 用法：
#   sh scripts/sync-skills.sh         # 本地 → 仓库（默认；之后自己 git commit/push）
#   sh scripts/sync-skills.sh push    # 同上
#   sh scripts/sync-skills.sh pull    # 仓库 → 本地（换机/别的会话改过仓库时用）
#
# 只做复制，不删任何一边独有的文件，避免误删。想知道差异用 diff -r。
#
set -eu

SRC="${HOME:?}/Documents/wiki.qaq.apelin/skills"
DST="${APELIN_PROJECT_ROOT:?}/skills"
MODE=${1:-push}

[ -d "$SRC" ] || { echo "sync-skills: 缺本地技能目录 $SRC" >&2; exit 1; }

case "$MODE" in
  push)
    mkdir -p "$DST"
    cp -R "$SRC"/. "$DST"/
    echo "sync-skills: 本地 → 仓库 ($DST)"
    ;;
  pull)
    [ -d "$DST" ] || { echo "sync-skills: 仓库里没有 skills/" >&2; exit 1; }
    mkdir -p "$SRC"
    cp -R "$DST"/. "$SRC"/
    echo "sync-skills: 仓库 → 本地 ($SRC)"
    ;;
  *)
    echo "sync-skills: 用法 sh scripts/sync-skills.sh [push|pull]" >&2
    exit 2
    ;;
esac

find "$SRC" "$DST" -name SKILL.md | sed 's|/SKILL.md$||' | sed 's|.*/||' | sort -u | sed 's/^/  技能: /'
echo "sync-skills: 差异检查 —— diff -r \"\$HOME/Documents/wiki.qaq.apelin/skills\" \"$DST\""