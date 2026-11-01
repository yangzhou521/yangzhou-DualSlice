#!/bin/sh
# 断点续做：机读断点。用法：
#   sh scripts/work-state.sh get                    # 读当前断点
#   sh scripts/work-state.sh set '<json>'           # 整体写
#   sh scripts/work-state.sh field k v               # 改一个字段
# 只读写项目内 scripts/WORK-STATE.json，不碰任何系统路径。
set -e
D="${APELIN_PROJECT_ROOT:?}/scripts/WORK-STATE.json"
case "${1:-get}" in
  get) cat "$D" ;;
  set) printf '%s\n' "${2:?json}" > "$D"; cat "$D" ;;
  field)
    k="${2:?key}"; v="${3:-}"
    # 用 sed 替换 "k": "...." 的值（值里不许有引号）
    sed -e "s|\"$k\":[[:space:]]*\"[^\"]*\"|\"$k\": \"$v\"|" "$D" > "$D.new"
    mv "$D.new" "$D"; cat "$D" ;;
  *)
    echo "用法: get | set '<json>' | field <key> <value>" >&2; exit 2 ;;
esac
