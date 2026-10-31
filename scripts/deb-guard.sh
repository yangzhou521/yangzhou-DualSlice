#!/bin/sh
#
# deb-guard.sh —— 本工程唯一的装包 / 注销入口（版本锁 + 归属锁）。
#
# 为什么要它（2026-10-31 两次安全模式事故）：0.9.21 崩了之后本线回滚到 0.9.19，
# 别的对话又自己把 0.9.21 装回去，SpringBoard 连崩 5 次再次进安全模式。
# 从那时起：**改代码、云编译、装包、注销、回滚，全部只归 `scripts/version-lock.txt` 里
# 的 owner 一条线**。别的线要装/要滚/要注销 —— 先在这条对话里申请，不许自己动手。
#
# 用法：
#   sh scripts/deb-guard.sh check                      # 打印锁 + 机上实况，只读
#   GUARD_SID=<你的 sid> sh scripts/deb-guard.sh install /rootfs/var/mobile/Documents/xxx.deb
#   GUARD_SID=<你的 sid> sh scripts/deb-guard.sh respring [秒] [标签]
#   sh scripts/deb-guard.sh whoami                     # 锁里写的是谁
#
# 退出码：
#   0 通过   6 不是本线（拒绝）   7 版本与锁不符（拒绝）   8 锁文件缺失/损坏
#
# 它拦得住「照着文档做却做错」和「顺手回滚」，拦不住有人硬敲 irisin-cli 绕过 ——
# 那种情况由 `sh scripts/safemode-check.sh` 侦测：机上版本/dylib 指纹与锁不符就报 exit 2。

set -u

ROOTFS="${ROOTFS:-/rootfs}"
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PROJ="${APELIN_PROJECT_ROOT:-$(cd "$HERE/.." 2>/dev/null && pwd)}"
LOCK="$PROJ/scripts/version-lock.txt"

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit "${2:-1}"; }

lock_get() {
  [ -r "$LOCK" ] || die "✖ 锁文件不存在：scripts/version-lock.txt" 8
  sed -n "s/^$1=//p" "$LOCK" | head -1
}

# roothide 上 dpkg 与 TweakInject 都在**引导根**里（shell 看到的 `/`），
# 崩溃日志与用户数据在**真根**里（shell 看到的 `$ROOTFS`）。两边都试，谁先读到用谁。
dpkg_status() {
  for p in /var/lib/dpkg/status "$ROOTFS/var/lib/dpkg/status"; do
    [ -r "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

dylib_path() {
  for p in /usr/lib/TweakInject/ThemeCorePlus.dylib \
           "$ROOTFS/usr/lib/TweakInject/ThemeCorePlus.dylib"; do
    [ -r "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

installed_version() {
  st=$(dpkg_status) || return 0
  awk '/^Package: com.yangzhou.themecoreplus$/{f=1} f&&/^Version:/{sub(/^Version: */,"");print;exit}' \
    "$st" 2>/dev/null
}

installed_sha() {
  f=$(dylib_path) || return 0
  sha256sum "$f" 2>/dev/null | awk '{print $1}'
}

check_owner() {
  want=$(lock_get owner)
  got="${GUARD_SID:-}"
  [ -n "$want" ] || die "✖ 锁里没写 owner" 8
  if [ -z "$got" ]; then
    die "✖ 没有 GUARD_SID。装包/注销只归一条线：
    owner = $want
  别的对话要装/要滚/要注销：在这条对话里申请，不要自己动手。" 6
  fi
  [ "$got" = "$want" ] || die "✖ 你不是本线，拒绝执行。
    你        = $got
    唯一修复线 = $want
  停手；要装/要滚/要注销请找它（apelin_conversation_send）。" 6
}

cmd="${1:-}"

case "$cmd" in
  whoami)
    say "owner = $(lock_get owner)"
    say "version = $(lock_get version)"
    say "updated = $(lock_get updated)"
    say "note = $(lock_get note)"
    ;;
  check)
    lv=$(lock_get version); lsha=$(lock_get dylib_sha256)
    iv=$(installed_version);  isha=$(installed_sha)
    say "锁      : version=$lv  dylib_sha256=${lsha:-未记}"
    say "机上    : version=${iv:-读不到}  dylib_sha256=${isha:-读不到}"
    rc=0
    [ "$lv" = "$iv" ] || { say "⚠️ 版本与锁不符 —— 有人装了别的版本或回滚过"; rc=2; }
    if [ -n "$lsha" ] && [ -n "$isha" ] && [ "$lsha" != "$isha" ]; then
      say "⚠️ dylib 指纹与锁不符 —— 同一个版本号也可能被改过二进制"; rc=2
    fi
    [ "$rc" = 0 ] && say "✅ 与锁一致"
    exit "$rc"
    ;;
  install)
    deb="${2:-}"
    [ -n "$deb" ] || die "用法：GUARD_SID=<sid> sh scripts/deb-guard.sh install <deb 绝对路径>" 1
    check_owner
    [ -r "$deb" ] || die "✖ 找不到 deb：$deb" 1
    lv=$(lock_get version)
    case "$(basename "$deb")" in
      *_${lv}_*|*_${lv}.deb) ;;
      *) die "✖ 版本不符：锁里只允许 $lv，你要装 $(basename "$deb")
  版本号只由 owner 改；出过崩溃的版本号永不复用。" 7 ;;
    esac
    want_deb=$(lock_get deb_sha256)
    if [ -n "$want_deb" ]; then
      got_deb=$(sha256sum "$deb" 2>/dev/null | awk '{print $1}')
      [ "$got_deb" = "$want_deb" ] || die "✖ deb 指纹不符：锁=$want_deb 你=$got_deb" 7
    fi
    say "✅ 允许装：$(basename "$deb")（version=$lv, owner=$(lock_get owner)）"
    say "   真命令（须 root）：irisin-cli install --yes --json $deb"
    say "   装完立刻：sh scripts/safemode-check.sh"
    ;;
  respring)
    shift
    check_owner
    say "✅ 是本线；交给 respring-guard.sh（仍要用户点头 + --confirm）"
    exec sh "$PROJ/scripts/respring-guard.sh" "$@"
    ;;
  *)
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
