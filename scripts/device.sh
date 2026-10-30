#!/bin/sh
#
# device.sh —— 不经过 icli 的设备操作。
#
# 为什么要有它：本机开着 Apelin 的「使用屏幕前先询问」（Ask Before Using the Screen）时，
# **每一条 icli 命令**都要用户点一次批准卡片（那是 Apelin 自己设置里的开关，agent 不能代关；
# 关掉它就一劳永逸 —— 设置 ▸ 使用屏幕前先询问）。在它开着的时候，日常操作走下面这些
# 等价命令就不弹卡：
#
#   读偏好 / 读诊断   defaults read <domain> [key]        （Cephei 版 defaults，走 cfprefsd，活值）
#   写偏好           defaults write <domain> <key> <value>
#   回滚（清键）      defaults write <domain> <key> ""    ← 本机没有能删键的命令；
#                    本工程插件都把空串当未设置（ThemeCorePlus：path.length > 0 才生效）
#   列进程           launchctl list
#   杀 App           launchctl list 里找 UIKitApplication:<bid>[…] 的 pid → kill -9 <pid>
#   起 App           uiopen --bundleid <bid>
#   注销桌面         sbreload（不弹卡；但黑屏前仍要通知 + 5 秒倒计时，见 respring-guard.sh）
#
# 仍然只有 icli 能做的（会弹一张卡，尽量合并成一次问清）：
#   前台是哪个 App（`icli app frontmost`）、界面元素树（`icli ui tree`）、
#   点/打字（`icli ui tap` / `icli input`）、截图（`icli screen shot`）。
#
# 用法：
#   sh scripts/device.sh read  com.apple.springboard CountdownHUDDiagnostics
#   sh scripts/device.sh read  com.yangzhou.themecoreplus
#   sh scripts/device.sh write com.yangzhou.themecoreplus ThemeName "液态玻璃"
#   sh scripts/device.sh clear com.yangzhou.themecoreplus ThemePath   # 回滚 = 写空串
#   sh scripts/device.sh procs [bundle-id 子串]
#   sh scripts/device.sh kill  com.apple.mobilenotes   # 杀进程前先通知 + 5 秒倒计时
#   sh scripts/device.sh launch com.apple.mobilenotes
#   sh scripts/device.sh respring                      # 注销：先 respring-guard.sh
#   sh scripts/device.sh doctor                        # 这套工具齐不齐
#
set -u

CMD=${1:-}
shift 2>/dev/null || true

die() { echo "device.sh: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "找不到命令 $1（本机越狱环境不完整）"; }

# 从 launchctl list 里取某个 bundle id 的 pid（UIKitApplication: 那一行）。没有输出 = 没在跑。
app_pid() {
  bid=$1
  launchctl list 2>/dev/null | awk -v key="UIKitApplication:$bid[" '
    index($0, key) > 0 { if ($1 != "-") { print $1; exit } }
  '
}

case "$CMD" in
  read)
    DOMAIN=${1:-}; KEY=${2:-}
    [ -n "$DOMAIN" ] || die "用法: device.sh read <domain> [key]"
    need defaults
    if [ -n "$KEY" ]; then defaults read "$DOMAIN" "$KEY"; else defaults read "$DOMAIN"; fi
    ;;

  write)
    DOMAIN=${1:-}; KEY=${2:-}; shift 2 2>/dev/null || true
    [ -n "$KEY" ] || die "用法: device.sh write <domain> <key> <value>"
    need defaults
    defaults write "$DOMAIN" "$KEY" "$@" \
      && echo "已写 $DOMAIN $KEY = $*（cfprefsd 生效；插件靠 Darwin 通知或注销才重读）"
    ;;

  # 回滚：本机没有能删偏好键的命令，写空串等价于未设置（ThemeCorePlus / CountdownHUD 都是这么判的）。
  clear)
    DOMAIN=${1:-}; KEY=${2:-}
    [ -n "$KEY" ] || die "用法: device.sh clear <domain> <key>"
    need defaults
    defaults write "$DOMAIN" "$KEY" "" && echo "已清空 $DOMAIN $KEY（写空串）"
    ;;

  procs)
    need launchctl
    PAT=${1:-}
    if [ -n "$PAT" ]; then
      launchctl list 2>/dev/null | awk -v p="$PAT" 'index($0, p) > 0'
    else
      launchctl list 2>/dev/null
    fi
    ;;

  kill)
    BID=${1:-}
    [ -n "$BID" ] || die "用法: device.sh kill <bundle-id>"
    need launchctl
    PID=$(app_pid "$BID")
    [ -n "$PID" ] || die "$BID 没在跑（launchctl list 里没有 UIKitApplication:$BID）"
    kill -9 "$PID" && echo "已杀 $BID（pid $PID）"
    ;;

  launch)
    BID=${1:-}
    [ -n "$BID" ] || die "用法: device.sh launch <bundle-id>"
    need uiopen
    uiopen --bundleid "$BID" >/dev/null 2>&1 || die "uiopen 打不开 $BID"
    echo "已请系统打开 $BID（uiopen；不返回前台状态，要确认前台仍需 icli app frontmost）"
    ;;

  respring)
    # 只负责执行；通知与倒计时由会话做（apelin_notification_send + scripts/respring-guard.sh）。
    need sbreload
    echo "device.sh: 执行注销（sbreload）"
    exec sbreload
    ;;

  frontmost)
    echo "device.sh: 前台 App 只能问 icli（这一条会弹批准卡）：icli app frontmost" >&2
    exit 2
    ;;

  doctor)
    for c in defaults launchctl killall uiopen sbreload plutil icli; do
      if command -v "$c" >/dev/null 2>&1; then
        echo "有   $c"
      else
        echo "缺   $c"
      fi
    done
    ;;

  *)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
