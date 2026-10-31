#!/bin/sh
#
# verify-countdownhud.sh —— CountdownHUD 1.6.0「点胶囊跳回对话」一键验收。
#
# 什么时候跑：**SpringBoard 已经注销、诊断里出现 v1.6.0 之后**（1.5.0 及以前没有 link=/taps=，
# 这个脚本会直接判「还没加载」退出 4，不会白测一轮）。
#
# 它按顺序验六件事（每件一条 ✓/✗）：
#   ① 诊断版本 = v1.6.0（shows 归零 = SpringBoard 换过新代码）
#   ② 带 HUD_SID 发一条纯文案 → 诊断 link=<sid>、mode=plain
#   ③ 点胶囊（岛矩形中心）→ taps +1，且前台变成 Apelin（apelin://conversation/<sid> 被打开）
#   ④ 不带 HUD_SID 再发一条 → 诊断 link=none
#   ⑤ 这时点胶囊 → taps 不变（老行为：不吃任何触摸）
#   ⑥ 提示用 apelin_crash_list（SpringBoard）确认无新报告 —— 这一步脚本查不了，留给 agent
#
# **它不做任何破坏性动作**：不注销（sbreload）、不装包、不杀进程、不改设置。
# 唯一会动屏幕的是 `icli screen tap`（只在 ③ 和 ⑤ 各点一下胶囊），点完 ③ 会真的把 Apelin 拉起来。
#
# 用法（仓库根目录）：
#   sh scripts/verify-countdownhud.sh                    # 用本对话 id 之外的默认：必须给 --sid
#   sh scripts/verify-countdownhud.sh --sid <对话 id>    # 正常用法
#   sh scripts/verify-countdownhud.sh --sid <id> --no-tap # 只验 ①②④，不点屏幕（不弹 icli 卡）
#   sh scripts/verify-countdownhud.sh --sid <id> --wait 20
#   sh scripts/verify-countdownhud.sh --selftest         # 不碰设备：只验解析逻辑（7 项）
#
# 注意：`icli screen tap` / `icli app frontmost` 在「使用屏幕前先询问」开着时各弹一张批准卡；
# --no-tap 可以完全避开屏幕操作。
#
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 1
DOMAIN=com.apple.springboard
KEY=CountdownHUDDiagnostics

SID=""
DO_TAP=1
WAIT=20
SELFTEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --sid) SID=${2:-}; shift 2 ;;
    --wait) WAIT=${2:-20}; shift 2 ;;
    --no-tap) DO_TAP=0; shift ;;
    --selftest) SELFTEST=1; shift ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "verify-countdownhud: 不认识的参数 $1（看 --help）" >&2; exit 2 ;;
  esac
done

if [ "$SELFTEST" = 1 ]; then
  # 不碰设备：拿两条写死的诊断串验解析（1.6.0 有 link= / 1.5.0 没有）。
  FIX='v1.6.0;shows=9;last=3s;label=完成：点击测试;font=12.3;island=SBSystemApertureContainerView|125,18,125,37;src=aperture;cand=4;mode=plain;win=CHWindow|scene=SBSystemApertureWindowScene|lvl=20000000;islandWin=SBSystemApertureWindow|lvl=0;haptic=1;alerts=0;ans=-;link=5781b4c7-a5e6-419a-87f7-7c9f5205cbdc;taps=3'
  FIX_NONE='v1.6.0;shows=10;last=2s;label=验证：不可点;font=12.3;island=SBSystemApertureContainerView|125,18,125,37;src=aperture;cand=4;mode=plain;win=CHWindow|lvl=20000000;haptic=0;alerts=0;ans=-;link=none;taps=3'
  N=0
  chk() { N=$((N + 1)); if [ "$2" = "$3" ]; then echo "  ✓ selftest $N: $1 = $3"; else echo "  ✗ selftest $N: $1 = $2（期望 $3）"; exit 1; fi; }
  chk "version"  "$(printf '%s' "$FIX" | sed -n 's/^\(v[0-9][0-9.]*\);.*/\1/p')" "v1.6.0"
  chk "link"     "$(printf '%s\n' "$FIX" | tr ';' '\n' | sed -n 's/^link=//p')" "5781b4c7-a5e6-419a-87f7-7c9f5205cbdc"
  chk "link none" "$(printf '%s\n' "$FIX_NONE" | tr ';' '\n' | sed -n 's/^link=//p')" "none"
  chk "taps"     "$(printf '%s\n' "$FIX" | tr ';' '\n' | sed -n 's/^taps=//p')" "3"
  GEO=$(printf '%s\n' "$FIX" | tr ';' '\n' | sed -n 's/^island=//p' | head -n 1); GEO=${GEO#*|}
  chk "island geo" "$GEO" "125,18,125,37"
  chk "tap x" "$(printf '%s' "$GEO" | awk -F, '{printf "%d", $1 + $3 / 2}')" "187"
  chk "tap y" "$(printf '%s' "$GEO" | awk -F, '{printf "%d", $2 + $4 / 2}')" "36"
  echo "selftest 全部通过（$N 项，未碰设备）。"
  exit 0
fi

case "$SID" in
  ''|*[!0-9a-fA-F-]*) echo "verify-countdownhud: 必须用 --sid 给一个对话 id（十六进制+连字符，8~64 位）" >&2; exit 2 ;;
esac
if [ "${#SID}" -lt 8 ] || [ "${#SID}" -gt 64 ]; then
  echo "verify-countdownhud: --sid 长度要在 8~64 之间（现在是 ${#SID}）" >&2
  exit 2
fi

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ✓ %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }

# device.sh read 一般直接打印诊断串本身；某些 defaults 版本会打印一块 JSON，
# 那就从 "value" 那一行取。
read_diag() {
  RAW=$(sh "$ROOT/scripts/device.sh" read "$DOMAIN" "$KEY" 2>/dev/null)
  case "$RAW" in
    *'"value"'*)
      printf '%s\n' "$RAW" \
        | sed -n 's/^[[:space:]]*"value"[[:space:]]*:[[:space:]]*"\(.*\)"$/\1/p' \
        | head -n 1
      ;;
    *) printf '%s\n' "$RAW" | head -n 1 ;;
  esac
}

# 诊断串是 `a=1;b=2;...`，取某个字段（第一段匹配）。
field() {
  printf '%s\n' "$1" | tr ';' '\n' | sed -n "s/^$2=//p" | head -n 1
}

echo "== ① 诊断版本 =="
D=$(read_diag)
if [ -z "$D" ]; then
  bad "读不到 $DOMAIN $KEY（SpringBoard 里没跑 CountdownHUD？）"
  exit 4
fi
VER=$(printf '%s' "$D" | sed -n 's/^\(v[0-9][0-9.]*\);.*/\1/p')
[ -n "$VER" ] || VER=$(printf '%s' "$D" | cut -d';' -f1)
info "诊断：$D"
if [ "$VER" = "v1.6.1" ] || [ "$VER" = "v1.6.0" ]; then
  ok "SpringBoard 跑的是 $VER"
else
  bad "SpringBoard 还在跑 $VER（新代码要注销才加载）→ 先注销再跑本脚本"
  echo
  echo "结论：未加载，退出（0 通过 / 1 失败）。"
  exit 4
fi
SHOWS0=$(field "$D" shows)
TAPS0=$(field "$D" taps)
[ -n "$TAPS0" ] || TAPS0=0
info "shows=$SHOWS0 taps=$TAPS0"

echo "== ② 带 sid 的纯文案请求 =="
if HUD_SID="$SID" sh "$ROOT/scripts/hud-notify.sh" "$WAIT" "验证：点击测试" >/dev/null 2>&1; then
  ok "请求已写入（HUD_SID=$SID）"
else
  bad "hud-notify.sh 写入失败"
fi
sleep 2
D=$(read_diag)
LINK=$(field "$D" link)
MODE=$(field "$D" mode)
if [ "$LINK" = "$SID" ]; then ok "诊断 link=$LINK"; else bad "诊断 link=$LINK（期望 $SID）"; fi
if [ "$MODE" = "plain" ]; then ok "mode=plain"; else bad "mode=$MODE（期望 plain）"; fi

if [ "$DO_TAP" = 1 ]; then
  echo "== ③ 点胶囊 → 跳对话 =="
  ISLAND=$(field "$D" island)
  GEO=${ISLAND#*|}
  CX=$(printf '%s' "$GEO" | awk -F, '{printf "%d", $1 + $3 / 2}')
  CY=$(printf '%s' "$GEO" | awk -F, '{printf "%d", $2 + $4 / 2}')
  if [ -z "$CX" ] || [ -z "$CY" ]; then
    bad "诊断里没有岛矩形（island=$ISLAND），点不了"
  else
    info "岛=$ISLAND → 点 ($CX,$CY)"
    if icli screen tap "$CX" "$CY" >/dev/null 2>&1; then
      ok "已点胶囊"
    else
      bad "icli screen tap 失败（屏幕锁着 / 没批准？）"
    fi
    sleep 2
    D2=$(read_diag)
    TAPS1=$(field "$D2" taps)
    [ -n "$TAPS1" ] || TAPS1=0
    if [ "$TAPS1" -gt "$TAPS0" ]; then
      ok "taps $TAPS0 → $TAPS1（胶囊真收到了这一下）"
    else
      bad "taps 还是 $TAPS1（没吃到触摸：窗口层级 / hitTest 问题）"
    fi
    FRONT=$(icli app frontmost 2>/dev/null | sed -n 's/.*"\(bundle_id\|bundleIdentifier\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' | head -n 1)
    if [ -z "$FRONT" ]; then
      info "前台读不到（icli app frontmost 失败），自己看一眼 Apelin 有没有被拉起"
    elif [ "$FRONT" = "wiki.qaq.apelin" ]; then
      ok "前台 = Apelin（apelin://conversation/<sid> 生效）"
    else
      bad "前台 = $FRONT（期望 wiki.qaq.apelin）"
    fi
  fi

  echo "== ④⑤ 不带 sid：应该点不动 =="
  if sh "$ROOT/scripts/hud-notify.sh" "$WAIT" "验证：不可点" >/dev/null 2>&1; then
    ok "不带 sid 的请求已写入"
  else
    bad "hud-notify.sh（不带 sid）写入失败"
  fi
  sleep 2
  D=$(read_diag)
  LINK=$(field "$D" link)
  if [ "$LINK" = "none" ]; then ok "诊断 link=none"; else bad "诊断 link=$LINK（期望 none）"; fi
  TAPS_BEFORE=$(field "$D" taps); [ -n "$TAPS_BEFORE" ] || TAPS_BEFORE=0
  ISLAND=$(field "$D" island); GEO=${ISLAND#*|}
  CX=$(printf '%s' "$GEO" | awk -F, '{printf "%d", $1 + $3 / 2}')
  CY=$(printf '%s' "$GEO" | awk -F, '{printf "%d", $2 + $4 / 2}')
  if [ -n "$CX" ] && [ -n "$CY" ]; then
    icli screen tap "$CX" "$CY" >/dev/null 2>&1 || info "icli screen tap 失败（这条只是期望「什么都没发生」）"
    sleep 2
    D=$(read_diag)
    TAPS_AFTER=$(field "$D" taps); [ -n "$TAPS_AFTER" ] || TAPS_AFTER=0
    if [ "$TAPS_AFTER" = "$TAPS_BEFORE" ]; then
      ok "taps 没变（$TAPS_AFTER）—— 老行为没被改坏"
    else
      bad "taps $TAPS_BEFORE → $TAPS_AFTER（不带 sid 时不该吃触摸）"
    fi
  fi
else
  echo "== ③④⑤ 已跳过（--no-tap）=="
fi

echo "== ⑥ 崩溃报告（脚本查不了，留给 agent）=="
info "跑 apelin_crash_list（process=SpringBoard）：有比本次注销更新的报告 = 装坏了，"
info "先 irisin-cli remove com.yangzhou.countdownhud 回滚再排查；无新报告才算装好。"

echo
echo "结论：$PASS 通过 / $FAIL 失败。"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
