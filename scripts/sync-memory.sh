#!/bin/sh
#
# sync-memory.sh —— 本地记忆 ↔ 仓库 memory/ 双向同步。
#
# 本地（Apelin 真正读的那份）：$HOME/Documents/wiki.qaq.apelin/memories.json
# 仓库（版本化、上 GitHub 的备份）：<工程根>/memory/memories.json
#
# 用法：
#   sh scripts/sync-memory.sh         # 本地 → 仓库（默认；之后自己 git commit/push）
#   sh scripts/sync-memory.sh push    # 同上
#   sh scripts/sync-memory.sh pull    # 仓库 → 本地（换机 / 别的会话改过仓库时用，
#                                     #  会覆盖本机记忆，先看 diff！）
#   sh scripts/sync-memory.sh diff    # 只比差异，不动文件
#
# 只复制这一个文件，不碰别的；memory/ 里可以另放说明（README.md）。
#
set -eu

SRC="${HOME:?}/Documents/wiki.qaq.apelin/memories.json"
DST="${APELIN_PROJECT_ROOT:?}/memory/memories.json"
MODE=${1:-push}

case "$MODE" in
  push)
    [ -f "$SRC" ] || { echo "sync-memory: 缺本地记忆文件 $SRC" >&2; exit 1; }
    mkdir -p "$(dirname "$DST")"
    cp "$SRC" "$DST"
    echo "sync-memory: 本地 → 仓库 ($DST  $(wc -c <"$DST" | tr -d ' ') 字节)"
    ;;
  pull)
    [ -f "$DST" ] || { echo "sync-memory: 仓库里没有 memory/memories.json" >&2; exit 1; }
    echo "sync-memory: 即将用仓库那份覆盖本机记忆 —— 先确认 diff 是你想要的"
    diff "$SRC" "$DST" || true
    cp "$DST" "$SRC"
    echo "sync-memory: 仓库 → 本地 ($SRC)"
    ;;
  diff)
    [ -f "$SRC" ] && [ -f "$DST" ] || { echo "sync-memory: 两边不齐（$SRC / $DST）" >&2; exit 1; }
    if diff "$SRC" "$DST"; then
      echo "sync-memory: 一致"
    else
      echo "sync-memory: 有差异（左=本机，右=仓库）" >&2
      exit 1
    fi
    ;;
  *)
    echo "sync-memory: 用法 sh scripts/sync-memory.sh [push|pull|diff]" >&2
    exit 2
    ;;
esac
