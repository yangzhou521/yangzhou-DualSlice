#!/bin/sh
#
# errand-in-app.sh —— 「去别的 App 办事，必回 Apelin」
#
# 为什么要有这个脚本：进设置面板 / 别的 App 取证时，屏幕离开 Apelin，用户在聊天里
# 看不到任何过程。约定是**每次外出的时间有上限，并且结束时屏幕必须回到 Apelin**，
# 不管是正常办完、中途报错、还是脚本被 Ctrl-C 打断 —— 所以回程写在 trap 里，
# 而不是写在最后一行。
#
# 用法：
#   sh scripts/errand-in-app.sh <bundle-id> [最长时间秒，默认 60]
#   sh scripts/errand-in-app.sh com.apple.Preferences 45     # 进设置看一眼再回来
#
# 输出：
#   - 目标 App 的截图路径（默认落在 /tmp，需要给用户看时再 cp 进工程）
#   - 目标 App 的界面结构（icli screen describe）
#   - 最后一行永远是回程结果：`回到 Apelin: <前台 bundle-id>`
#
# 注意：本机 icli 在 PATH 上；Apelin 自身的界面**不能**被遥距点击（宿主一律拒绝），
# 所以本脚本只负责「进入目标 App」和「必定回程」，目标 App 里的具体点击用
# `icli screen tap <x> <y>` 自己补。

set -u

TARGET=${1:-}
LIMIT=${2:-60}
APELIN_BID=wiki.qaq.apelin

if [ -z "$TARGET" ]; then
    echo "用法: sh scripts/errand-in-app.sh <bundle-id> [最长时间秒]" >&2
    exit 2
fi

if ! command -v icli >/dev/null 2>&1; then
    echo "icli 不在 PATH 上，无法执行（请确认设备越狱环境）" >&2
    exit 3
fi

STAMP=$(date +%Y%m%d-%H%M%S)
SHOT=${TMPDIR:-/tmp}/apelin-errand-$STAMP.jpg
START=$(date +%s)

frontmost_bid() {
    icli app frontmost 2>/dev/null \
        | sed -n 's/.*"bundle_id" *: *"\([^"]*\)".*/\1/p' \
        | head -1
}

# 回程：无论怎么退出都会跑（EXIT/INT/TERM）。launch 失败再试一次，
# 因为 launch 内部等前台是超时语义，偶发一次不生效。
back_to_apelin() {
    icli app launch "$APELIN_BID" >/dev/null 2>&1 || true
    now=$(frontmost_bid)
    if [ "$now" != "$APELIN_BID" ]; then
        icli app launch "$APELIN_BID" >/dev/null 2>&1 || true
        now=$(frontmost_bid)
    fi
    echo "回到 Apelin: ${now:-未知}（外出 $(( $(date +%s) - START )) 秒）"
    if [ "${now:-}" != "$APELIN_BID" ]; then
        echo "警告: 前台不是 Apelin —— 用户可能看不到聊天，请手动切回" >&2
    fi
}
trap 'back_to_apelin' EXIT INT TERM

elapsed() { echo $(( $(date +%s) - START )); }
over_limit() { [ "$(elapsed)" -ge "$LIMIT" ]; }

echo "去 $TARGET 办事（上限 ${LIMIT}s，超时就回）"
icli app launch "$TARGET" >/dev/null 2>&1 || echo "launch $TARGET 返回非零，继续尝试取证"
sleep 3

if over_limit; then
    echo "时间已到，跳过取证直接回程"
    exit 0
fi

if icli screen shot --output "$SHOT" >/dev/null 2>&1 && [ -s "$SHOT" ]; then
    echo "截图: $SHOT"
else
    echo "截图失败（不影响回程）"
fi

if ! over_limit; then
    echo "--- 界面结构 ---"
    # 本机实测 icli screen describe 恒返回 "screen capture failed"（截图可用），
    # 所以它只是尽力而为：失败就提示改用 Apelin 的界面树工具，别让它挡住回程。
    TREE=$(icli screen describe --human 2>&1 | head -40)
    case "$TREE" in
        *error*|*failed*) echo "icli screen describe 在本机不可用；界面结构请用 apelin_screen_read_tree 读，或看上面那张截图" ;;
        *) printf '%s\n' "$TREE" ;;
    esac
fi

exit 0
