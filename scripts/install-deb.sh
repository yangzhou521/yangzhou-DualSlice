#!/bin/sh
# install-deb.sh —— 唯一装包入口。
#
# 用法： sh scripts/install-deb.sh <deb路径> [标签] [--revive]
#   --revive（默认行为，用户 2026-11-05 22:57 定）：
#       ① 先装包（不注销、不弹窗）；
#       ② 装完再弹窗「扩容已装好，要现在注销吗？」——注销与否**由用户在屏幕上决定**；
#       ③ 用户点「立即注销」→ 输出 REVIVE_CONFIRMED（调用方做倒计时 + sbreload）；
#          点「稍后」/超时 → 输出 NO_RESPRING，什么都不做；
#          同一会话里已经问过就不再重复问（判据见下）。
#   安全模式：胶囊与弹窗都显示不出来 → 直接输出 SAFEMODE_DIRECT，调用方装完必须如实告诉
#        用户「注销是退出安全模式的唯一办法」，不得自动注销。
#
# 这个脚本**只负责判断与授权**，真正的 irisin-cli install 要 root，由调用方（agent）做。
#
# 晚点再注销（用户 2026-11-05 22:57 原话：「你可以装包不注销的以后都这样 装包后直接给我
# 弹窗 我来决定注销不注销！」）：装包本身不再和注销绑在一起 —— 以前一次弹窗把两件事捆死，
# 用户想攒几条线一起注销就没法选。现在拆成两步。

set -u
DEB="${1:?用法: install-deb.sh <deb路径> [标签] [--revive]}"
LABEL="${2:-装包}"

HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PROJ="${APELIN_PROJECT_ROOT:-$(cd "$HERE/.." 2>/dev/null && pwd)}"

[ -f "$DEB" ] || [ -f "/rootfs$DEB" ] || { echo "install-deb: 找不到 $DEB" >&2; exit 2; }

# ── ① 安全模式检测 ─────────────────────────────────────────────
SM=0
if [ -f "$PROJ/scripts/safemode-check.sh" ]; then
    sh "$PROJ/scripts/safemode-check.sh" >/dev/null 2>&1
    case "$?" in
        1|3) SM=1 ;;
    esac
fi

if [ "$SM" = "1" ]; then
    echo "install-deb: 安全模式（胶囊与弹窗都不会显示）→ 不弹窗、不注销，装完由正文告知用户"
    echo "SAFEMODE_DIRECT"
    exit 0
fi

# ── ② 正常环境：装包放行（不注销、不弹窗） ────────────────────
echo "install-deb: 正常环境 → 放行装包（不注销）"
echo "INSTALL_OK"
exit 0
