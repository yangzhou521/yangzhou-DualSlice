#!/bin/sh
#
# safemode-check.sh —— 一条命令做完「我是不是在安全模式 / 谁偷偷改了版本」的体检（只读）。
#
# 为什么要有它：进安全模式时 `defaults` 里还留着崩溃前的诊断值，**读到诊断 ≠ 插件在跑**；
# 而「谁装的、装的哪个版本」靠人问人问不清。这条脚本一次把四件事量出来：
#   ① 机上装的是哪个版本（dpkg status）        ② dylib 指纹与 `scripts/version-lock.txt` 是否一致
#   ③ SpringBoard 最近有没有连崩（ips 的 consecutiveCrashCount）
#   ④ 插件这一刻还在不在跑（ThemeCorePlusLayout 的 tick 两次读数是否在涨）
#
# 用法：sh scripts/safemode-check.sh            （只读，不装、不注销、不弹卡）
#       WINDOW=30 sh scripts/safemode-check.sh  （改崩溃窗口分钟数，默认 15）
#
# 退出码：
#   0 健康      1 崩溃循环/疑似安全模式      2 版本被改（有人回滚或私装）      3 插件没在跑
#   9 关键读数缺失（读不到 dpkg / 崩溃目录）

set -u

ROOTFS="${ROOTFS:-/rootfs}"
WINDOW="${WINDOW:-15}"
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PROJ="${APELIN_PROJECT_ROOT:-$(cd "$HERE/.." 2>/dev/null && pwd)}"
LOCK="$PROJ/scripts/version-lock.txt"
CRASHDIR="$ROOTFS/var/mobile/Library/Logs/CrashReporter"

say() { printf '%s\n' "$*"; }
lock_get() { [ -r "$LOCK" ] && sed -n "s/^$1=//p" "$LOCK" | head -1; }

rc=0
say "════ 安全模式体检 $(date '+%H:%M:%S') ════"

# ① 版本（dpkg status 在引导根里；崩溃日志在真根里 —— 两边都试）
st=""
for p in /var/lib/dpkg/status "$ROOTFS/var/lib/dpkg/status"; do
  [ -r "$p" ] && { st="$p"; break; }
done
iv=""
[ -n "$st" ] && iv=$(awk '/^Package: com.yangzhou.themecoreplus$/{f=1} f&&/^Version:/{sub(/^Version: */,"");print;exit}' "$st" 2>/dev/null)
lv=$(lock_get version)
if [ -z "$iv" ]; then
  say "① 版本      : 读不到 dpkg status（引导根 /var/lib/dpkg/status）"
  rc=9
else
  if [ "$iv" = "$lv" ]; then say "① 版本      : $iv（与锁一致）"
  else say "① 版本      : $iv ≠ 锁 $lv  ← 有人装了别的版本或回滚过"; rc=2; fi
fi

# ② 指纹
lsha=$(lock_get dylib_sha256)
dfile=""
for p in /usr/lib/TweakInject/ThemeCorePlus.dylib "$ROOTFS/usr/lib/TweakInject/ThemeCorePlus.dylib"; do
  [ -r "$p" ] && { dfile="$p"; break; }
done
isha=$( [ -n "$dfile" ] && sha256sum "$dfile" 2>/dev/null | awk '{print $1}')
short() { printf '%s' "$1" | cut -c1-16; }
if [ -z "$isha" ]; then say "② dylib     : 读不到 ThemeCorePlus.dylib"; [ "$rc" = 0 ] && rc=9
elif [ -z "$lsha" ]; then say "② dylib     : $(short "$isha")…（锁里没记指纹）"
elif [ "${isha:0:${#lsha}}" = "$lsha" ]; then say "② dylib     : $(short "$isha")…（与锁一致）"
else say "② dylib     : $(short "$isha")… ≠ 锁 $(short "$lsha")…  ← 二进制被换过（同版本号也可能）"; rc=2; fi

# ③ 崩溃
if [ -d "$CRASHDIR" ]; then
  n=$(find "$CRASHDIR" -name 'SpringBoard-*.ips' -mmin -"$WINDOW" 2>/dev/null | wc -l | tr -d ' ')
  latest=$(ls -t "$CRASHDIR"/SpringBoard-*.ips 2>/dev/null | head -1)
  cc=""
  [ -n "$latest" ] && cc=$(grep -o '"consecutiveCrashCount":[0-9]*' "$latest" 2>/dev/null | head -1 | cut -d: -f2)
  say "③ 崩溃      : 最近 ${WINDOW} 分钟 SpringBoard ${n} 份；最新 $(basename "${latest:-无}")"
  if [ -z "${cc:-}" ]; then
    say "              （报告本体 mobile 读不到，连崩计数用 apelin_crash_read 看 consecutiveCrashCount）"
  else
    say "              consecutiveCrashCount=$cc"
  fi
  if [ "${n:-0}" -ge 3 ] || { [ -n "${cc:-}" ] && [ "$cc" -ge 3 ]; }; then
    say "              ← 连崩：很可能是安全模式（ellekit 第 5 次后关注入）"; [ "$rc" = 0 ] && rc=1
  fi
else
  say "③ 崩溃      : 读不到 $CRASHDIR"; [ "$rc" = 0 ] && rc=9
fi

# ④ 插件在不在跑：tick 两次读数。
# ⚠️ tick 有 60 秒写盘节流（状态没变时最多旧 60 秒），间隔太短必然误判「不动」。
#    所以先等 FALLBACK 秒重读一次；仍不动才判死。默认 7 秒快判不行就补 70 秒；
#    SAFEMODE_CHECK_FAST=1 可强制只做快判（自己知道在测什么时才用）。
TICK_WAIT=${SAFEMODE_CHECK_TICK_WAIT:-7}
t1=$(sh "$PROJ/scripts/device.sh" read com.apple.springboard ThemeCorePlusLayout 2>/dev/null |
  sed -n 's/.*tick=\([0-9]*\).*/\1/p' | head -1)
sleep "$TICK_WAIT"
t2=$(sh "$PROJ/scripts/device.sh" read com.apple.springboard ThemeCorePlusLayout 2>/dev/null |
  sed -n 's/.*tick=\([0-9]*\).*/\1/p' | head -1)
if [ -z "$t1" ]; then
  say "④ 插件      : 没有 ThemeCorePlusLayout 键 ← 这个进程没跑过带布局代码的版本（或注入没生效）"
  [ "$rc" = 0 ] && rc=3
elif [ "$t1" = "$t2" ]; then
  # 快判不动 → 按 60 秒节流再等 70 秒，别拿 7 秒的读数下结论
  say "④ 插件      : tick=$t1 → $t2 不动，再等 70 秒（tick 有 60 秒写盘节流）…"
  sleep 70
  t3=$(sh "$PROJ/scripts/device.sh" read com.apple.springboard ThemeCorePlusLayout 2>/dev/null |
    sed -n 's/.*tick=\([0-9]*\).*/\1/p' | head -1)
  if [ -n "$t3" ] && [ "$t3" != "$t1" ]; then
    say "④ 插件      : tick=$t1 → $t3 在涨（活；快判只是撞上节流）"
  else
    say "④ 插件      : tick=$t1 → ${t3:-?} 70 秒仍不动 ← 定时器真的没活（或进程没在跑）"
    [ "$rc" = 0 ] && rc=3
  fi
else
  say "④ 插件      : tick=$t1 → $t2 在涨（活）"
fi

say "────────────────────────────────"
case "$rc" in
  0) say "✅ 健康：版本与锁一致、无连崩、插件在跑" ;;
  1) say "🔴 连崩 / 安全模式：回滚到锁里的版本（只有 owner 能装），装完再跑本脚本" ;;
  2) say "🟠 版本漂移：有人装了锁以外的版本或改过 dylib —— 先问 owner，别自己再装" ;;
  3) say "🟡 插件没在跑：注入型插件只在进程启动时加载 → 注销（需用户点头）或重启对应进程" ;;
  9) say "⚪ 读数缺失：先 `sh scripts/device.sh doctor` 查工具齐不齐" ;;
esac
exit "$rc"
