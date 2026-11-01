#!/bin/sh
# resume.sh —— 交接块：对话死了 / 换新对话 / 换人时，一条命令重建上下文（**只读，不动设备**）。
#
# 用法：
#   sh scripts/resume.sh            # 人读的交接块（任务链 + pending + 本机现状）
#   sh scripts/resume.sh --prompt   # 只输出可直接粘进新对话的接手提示词
#
# 为什么要有它：对话会死、会被压缩、会换人，而进度只写在对话历史里就等于没写。
# 权威状态在 scripts/WORK-STATE.json；本脚本把它 + 本机装机现状拼成一段能直接交给下一个 AI 的文字。
# 它不做任何判断、不装包、不注销、不发通知 —— 判断留给接手的人。
set -u

HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
PROJ="${APELIN_PROJECT_ROOT:-$(cd "$HERE/.." 2>/dev/null && pwd)}"
WS="$PROJ/scripts/WORK-STATE.json"
ROOTFS="${ROOTFS:-/rootfs}"

jget() { # jget <key> —— 取文件里第一处 `"key": "值"`（值里不许有引号）
  [ -r "$WS" ] || return 0
  sed -n "s/.*\"$1\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$WS" | head -1
}

TASK=$(jget task); STEP=$(jget step); NEXT=$(jget next)
STATUS=$(jget status); UP=$(jget updated); WHY=$(jget why); GUARD=$(jget guard)

if [ "${1:-}" = "--prompt" ]; then
  cat <<EOF
你是接手这条线的对话，**不要凭对话历史猜进度**（历史会死、会被压缩、会换人）。开工三步：

1. 读本工程（yangzhouDualSlice）的 scripts/WORK-STATE.json 与 AGENTS.md 顶部的「开工第 0 步（交接协议）」；
2. 跑 \`sh scripts/resume.sh\` 和 \`sh scripts/safemode-check.sh\`，把任务链、当前步、未清 pending **原样报一句给用户**，再动手；
3. 清账：pending 里每一项要么做完并验证、要么问用户取消，**不许无声消失**；需要用户点头的事（装包/注销/开 VPN/删东西）当轮就弹窗问。

任务：$TASK
当前步：$STEP
下一步：$NEXT
未清项：见 WORK-STATE.json 的 pending 数组（resume.sh 会一起打印）
边界：$GUARD
说明：$WHY
本机不编译（无工具链），改完 push 到 main 由 GitHub Actions 云编译，再下载 → 让用户点头装包 → 注销 → 读诊断验证。
EOF
  exit 0
fi

if [ ! -r "$WS" ]; then
  echo "resume: 读不到 $WS" >&2
  exit 2
fi

echo "════════ 交接块 $(date '+%Y-%m-%d %H:%M:%S %z') ════════"
echo "工程   : $PROJ"
echo "任务   : ${TASK:-?}"
echo "状态   : ${STATUS:-?}   更新: ${UP:-?}"
echo "当前步 : ${STEP:-?}"
echo "下一步 : ${NEXT:-?}"
[ -n "${GUARD:-}" ] && echo "边界   : $GUARD"
echo
echo "──── 未清项（pending，逐条要么做完要么问用户取消）────"
if [ -r "$WS" ]; then
  awk '/^[[:space:]]*"pending"/{p=1;next} p&&/^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/{exit} p{print}' "$WS" |
    sed -e 's/^[[:space:]]*//' -e 's/[{}\"]//g' -e 's/,$//'
fi
echo
echo "──── 本机现状（只读）────"
st=""
for p in /var/lib/dpkg/status "$ROOTFS/var/lib/dpkg/status"; do [ -r "$p" ] && { st="$p"; break; }; done
if [ -n "$st" ]; then
  echo "ThemeCorePlus 装机版本 : $(awk '/^Package: com.yangzhou.themecoreplus$/{f=1} f&&/^Version:/{sub(/^Version: */,"");print;exit}' "$st" 2>/dev/null)"
else
  echo "ThemeCorePlus 装机版本 : 读不到 dpkg status"
fi
dfile=""
for p in /usr/lib/TweakInject/ThemeCorePlus.dylib "$ROOTFS/usr/lib/TweakInject/ThemeCorePlus.dylib"; do
  [ -r "$p" ] && { dfile="$p"; break; }
done
[ -n "$dfile" ] && echo "磁盘 dylib            : $(sha256sum "$dfile" 2>/dev/null | cut -c1-16)…  $(wc -c <"$dfile" | tr -d ' ') 字节"
echo "待装 deb              : $(ls -t "$ROOTFS/var/mobile/Documents"/*.deb 2>/dev/null | head -3 | tr '\n' ' ')"
echo "探针文件              : $(ls -1 "$ROOTFS/var/mobile/Library/Preferences"/TCP*Probe.txt 2>/dev/null | tr '\n' ' ')"
latest=$(ls -t "$ROOTFS"/var/mobile/Library/Logs/CrashReporter/SpringBoard-*.ips 2>/dev/null | head -1)
echo "最新 SpringBoard 崩溃 : ${latest##*/}"
cc=$(grep -o '"consecutiveCrashCount":[0-9]*' "$latest" 2>/dev/null | head -1 | cut -d: -f2)
[ -n "${cc:-}" ] && echo "连崩计数              : $cc"
echo
echo "⚠️ 安全模式/崩溃循环判定请跑： sh scripts/safemode-check.sh（约 80 秒，只读）"
echo "   安全模式下胶囊与弹窗都不显示（tweak 全不注入）→ 用 install-deb.sh（会自动跳过弹窗直装）+ sbreload 退出安全模式。"
echo
echo "──── 接手提示词（可直接粘给新对话）────"
sh "$0" --prompt
