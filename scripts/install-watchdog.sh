#!/bin/sh
# install-watchdog.sh — 安装/卸载 fleet-watchdog launchd 守护进程
#
# 用法（须 root）：
#   sh scripts/install-watchdog.sh install [fleet]   # 安装；fleet=同时同步 fleet.sh
#   sh scripts/install-watchdog.sh uninstall          # 卸载
#   sh scripts/install-watchdog.sh status             # 查状态（不需 root）
#
# 重新越狱后 jbroot 前缀变了，plist（在 jbroot /Library/LaunchDaemons 里）会丢失，
# 需要重跑 install。

set -u

ACTION=${1:-status}
LABEL="com.yangzhou.fleet-watchdog"

# fleet 目录（用 glob 查找：root 下 $HOME=/var/root，不能用）
PROJ="${APELIN_PROJECT_ROOT:-$(pwd)}"
FLEET_DIR=""
for _d in /private/var/containers/Bundle/Application/.jbroot-*/var/mobile/Documents/wiki.qaq.apelin/fleet; do
  [ -d "$_d" ] && FLEET_DIR="$_d" && break
done
[ -z "$FLEET_DIR" ] && FLEET_DIR="$HOME/Documents/wiki.qaq.apelin/fleet"  # fallback
SCRIPT_SRC="$PROJ/scripts/fleet-watchdog.sh"
SCRIPT_DST="$FLEET_DIR/fleet-watchdog.sh"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"

case "$ACTION" in
  install)
    if ! [ -d "$FLEET_DIR" ]; then
      echo "fleet: 找不到 fleet 目录 $FLEET_DIR —— 先在 Apelin 里跑过 fleet.sh start" >&2
      exit 1
    fi
    # 1. 复制 watchdog 脚本到 fleet 目录
    cp "$SCRIPT_SRC" "$SCRIPT_DST"
    chmod +x "$SCRIPT_DST"
    echo "  watchdog 脚本 → $SCRIPT_DST"
    # 2. 可选：同步 fleet.sh
    if [ "${2:-}" = "fleet" ]; then
      cp "$PROJ/scripts/fleet.sh" "$FLEET_DIR/fleet.sh"
      chmod +x "$FLEET_DIR/fleet.sh"
      echo "  fleet.sh 已同步到 fleet 目录"
    fi
    # 3. 生成 plist（脚本路径用 fleet 目录里的那份，launchd 按绝对路径调）
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>${SCRIPT_DST}</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${FLEET_DIR}/watchdog-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${FLEET_DIR}/watchdog-stderr.log</string>
</dict>
</plist>
EOF
    echo "  plist → $PLIST"
    # 4. 加载（先卸再装，幂等）
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "✅ fleet-watchdog 已安装：每 300 秒检查 board.tsv，全员停摆时写 HUD 提醒"
    echo "   日志：$FLEET_DIR/watchdog.log"
    ;;
  uninstall)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "✅ fleet-watchdog 已卸载（plist 已删；fleet-watchdog.sh 仍在 fleet 目录）"
    ;;
  status)
    if launchctl list 2>/dev/null | grep -q "$LABEL"; then
      echo "fleet-watchdog: 已加载"
      launchctl list 2>/dev/null | grep "$LABEL" || true
    else
      echo "fleet-watchdog: 未加载"
    fi
    if [ -f "$FLEET_DIR/watchdog.log" ]; then
      echo "--- 最近 5 条日志 ---"
      tail -5 "$FLEET_DIR/watchdog.log"
    else
      echo "（无日志：还没跑过或没检测到停摆）"
    fi
    ;;
  *)
    echo "用法: $0 install [fleet] | uninstall | status" >&2
    exit 2
    ;;
esac
