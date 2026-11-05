#!/bin/sh
# post-install-respring.sh —— 装完包之后，**单独**问用户要不要注销。
#
# 用户 2026-11-05 22:57 原话：「你可以装包不注销的以后都这样 装包后直接给我弹窗
# 我来决定注销不注销！」。所以装包与注销彻底分家：
#   装包 → install-deb.sh（只放行，不注销）
#   装完 → 本脚本弹窗 → 用户点「立即注销」才输出 REVIVE_CONFIRMED
#
# 用法： sh scripts/post-install-respring.sh [标签] [超时秒数]
# 输出：
#   REVIVE_CONFIRMED   用户点了「立即注销」→ 调用方做 5 秒倒计时 + sbreload
#   NO_RESPRING        用户点了「稍后」/ 弹窗超时 → 什么都不做，绝不自动注销
#   SAFEMODE_QUIET     安全模式（弹窗显示不出来）→ 只靠正文 + 系统通知告知
#
# 规矩：本脚本**只问不注销**，sbreload 由调用方在用户点头后自己做。

set -u
LABEL="${1:-装包完成}"
ASK_SECS="${2:-120}"

HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PROJ="${APELIN_PROJECT_ROOT:-$(cd "$HERE/.." 2>/dev/null && pwd)}"

# 安全模式：CountdownHUD 不注入，弹窗与胶囊都出不来 —— 问了也没人看得见。
if [ -f "$PROJ/scripts/safemode-check.sh" ]; then
    sh "$PROJ/scripts/safemode-check.sh" >/dev/null 2>&1
    case "$?" in
        1|3)
            echo "post-install-respring: 安全模式，弹窗不可用 → 只走正文告知"
            echo "SAFEMODE_QUIET"
            exit 0
            ;;
    esac
fi

if [ ! -f "$PROJ/scripts/respring-guard.sh" ]; then
    echo "post-install-respring: 缺少 respring-guard.sh" >&2
    echo "NO_RESPRING"
    exit 0
fi

echo "post-install-respring: 弹窗询问是否现在注销（$ASK_SECS 秒）"
sh "$PROJ/scripts/respring-guard.sh" --ask "$ASK_SECS" "$LABEL"
rc=$?
case "$rc" in
    0) echo "REVIVE_CONFIRMED" ;;
    *) echo "NO_RESPRING" ;;
esac
exit 0
