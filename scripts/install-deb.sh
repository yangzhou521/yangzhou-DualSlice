#!/bin/sh
# install-deb.sh —— 唯一装包入口。自己判断环境，安全模式下**不再等弹窗**，直接装 + 注销。
#
# 为什么要有它（2026-11-01 15:5x 实测教训）：
#   进安全模式时 tweak 全不注入、CountdownHUD 也死，`respring-guard.sh --ask` 的弹窗
#   根本显示不出来。旧做法是「发了弹窗就一直等」，结果永远等不到、包也装不上。
#
# 用法： sh scripts/install-deb.sh /rootfs/var/mobile/Documents/xxx.deb "标签"
#
# 行为：
#   ① 先跑 safemode-check.sh
#      · 退出码 1（崩溃循环/疑似安全模式）或 3（插件没在跑）→ SAFE MODE 路径：
#         不需要用户点任何东西，直接打印「安全模式：跳过弹窗，直接安装」，退出码 0 交给调用方装。
#      · 其它 → 走弹窗 `respring-guard.sh --ask --install`，用户点「立即注销」才继续。
#   ② 本脚本**只负责判断与授权**，真正的 irisin-cli install 要 root，由调用方（agent）做。

set -u
DEB="${1:?用法: install-deb.sh <deb路径> [标签]}"
LABEL="${2:-装包}"

HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PROJ="${APELIN_PROJECT_ROOT:-$(cd "$HERE/.." 2>/dev/null && pwd)}"

[ -f "$DEB" ] || [ -f "/rootfs$DEB" ] || { echo "install-deb: 找不到 $DEB" >&2; exit 2; }

# ── ① 安全模式检测 ─────────────────────────────────────────────
SM=0
if [ -x "$PROJ/scripts/safemode-check.sh" ] || [ -f "$PROJ/scripts/safemode-check.sh" ]; then
    sh "$PROJ/scripts/safemode-check.sh" >/dev/null 2>&1
    rc=$?
    case "$rc" in
        1|3) SM=1 ;;
    esac
fi

if [ "$SM" = "1" ]; then
    echo "install-deb: 安全模式（弹窗与胶囊都不会显示）→ 跳过弹窗，直接安装"
    echo "SAFEMODE_DIRECT"
    exit 0
fi

# ── ② 正常环境：弹窗让用户点 ────────────────────────────────────
echo "install-deb: 正常环境，弹窗等用户确认"
sh "$PROJ/scripts/respring-guard.sh" --ask 300 --install "$DEB" "$LABEL"
rc=$?
case "$rc" in
    0) echo "CONFIRMED" ;;
    4) echo "CANCELLED"; exit 4 ;;
    *) echo "TIMEOUT"; exit 5 ;;
esac
