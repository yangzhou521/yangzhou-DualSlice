#!/bin/sh
# 注销后验 ThemeCorePlus 桌面布局保存（只读，不弹批准卡、不注销、不装包）。
#
# 用法：sh scripts/verify-layout.sh
#
# 它只做三件事：① 隔 12 秒读两次轻量诊断 ThemeCorePlusLayout（看 tick 涨不涨、
# last 是什么）；② 读主诊断里嵌的 lay{}（那是启动快照，只能当参考）；
# ③ 列源文件/备份的大小与 mtime（真根前缀 /rootfs）。
#
# 判定口径见 AGENTS.md「桌面图标布局保存」一节：
#   · 没这条键 = 这个进程没跑 0.9.19 的代码；
#   · tick 不涨 = 定时器没跑（0.9.17 的 ARC bug 回归）；
#   · site=none = 保存站一个都没挂上（跟存备份和主动保存就只剩 mtime 那条路）；
#   · 挪图标 30 秒后 sav/force 不涨 = 主动保存没成功，看 last= 的原因。
set -u

DEVICE="sh scripts/device.sh"

echo "== 1/4 轻量诊断（第一次）"
$DEVICE read com.apple.springboard ThemeCorePlusLayout || true

echo
echo "== 2/4 等 12 秒再读一次（tick 必须更大）"
sleep 12
$DEVICE read com.apple.springboard ThemeCorePlusLayout || true

echo
echo "== 3/4 主诊断里的 lay{}（启动那几轮写的快照，只作参考）"
MAIN=$($DEVICE read com.apple.springboard ThemeCorePlusDiagnostics 2>/dev/null || true)
echo "$MAIN" | tr ';' '\n' | grep -E '^lay\{|^v[0-9]' || echo "（读不到主诊断）"

echo
echo "== 4/4 文件：源 / 备份"
ls -l /rootfs/var/mobile/Library/SpringBoard/IconState.plist \
      /rootfs/var/mobile/Library/ThemeCorePlus/IconState.backup.plist 2>&1

echo
echo "== 附：已装的包版本"
grep -A3 '^Package: com.yangzhou.themecoreplus$' /Library/dpkg/status 2>/dev/null | head -4
ls -l /Library/MobileSubstrate/DynamicLibraries/ThemeCorePlus.dylib 2>&1

echo
echo "== 完（只读，什么都没改）"
