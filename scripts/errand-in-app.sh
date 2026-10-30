#!/bin/sh
#
# errand-in-app.sh —— 「去别的 App 办事，必回 Apelin」
#
# 为什么要有这个脚本：进设置面板 / 别的 App 取证时，屏幕离开 Apelin，用户在聊天里
# 看不到任何过程。约定是**每次外出的时间有上限，并且结束时屏幕必须回到 Apelin**，
# 不管是正常办完、中途报错、还是脚本被 Ctrl-C 打断 —— 所以回程写在 trap 里，
# 而不是写在最后一行。
#
# 用法：
#   sh scripts/errand-in-app.sh <bundle-id> [最长时间秒，默认 60] [要点的元素文字]...
#   sh scripts/errand-in-app.sh com.apple.Preferences 60                    # 只看一眼
#   sh scripts/errand-in-app.sh com.apple.Preferences 60 "主题美化 +" "生效主题"  # 依次点两个
#
# 输出（一次调用就把证据带回来）：
#   - 目标 App 的截图路径（落在 /tmp，要给你看时再 cp 进工程用 file_show）
#   - `icli ui tree` 的界面元素树（这是本机唯一可用的读树手段：
#     `icli screen describe` 与 `icli screen ocr` 在这台机器上恒失败）
#   - 最后一行永远是回程结果：`回到 Apelin: <前台 bundle-id>（外出 N 秒）`
#
# 为什么点元素而不是点坐标：`icli ui tap "<文字>"` 按 label/identifier 匹配，
# 不受列表滚动位置影响（坐标点击已经跑偏过一次）。
#
# 2026-10-31：起 App 与回程改用 `uiopen --bundleid`（不弹批准卡片）。本机开着 Apelin 的
# 「使用屏幕前先询问」时，**每条 icli 都要用户点一次批准**，而读界面树/点元素/截图只有 icli
# 能做，所以那些留着；`icli app frontmost` 的校验改成可选：默认不查（省一张卡），
# 要严格校验回程就 `ERRAND_VERIFY=1 sh scripts/errand-in-app.sh …`。
# 设备操作一览见 scripts/device.sh。

set -u

TARGET=${1:-}
LIMIT=${2:-60}
shift 2 2>/dev/null || shift $#   # 余下参数都是要依次点击的元素文字
APELIN_BID=wiki.qaq.apelin
VERIFY=${ERRAND_VERIFY:-0}

if [ -z "$TARGET" ]; then
    echo "用法: sh scripts/errand-in-app.sh <bundle-id> [最长时间秒] [要点的元素文字]" >&2
    exit 2
fi

if ! command -v uiopen >/dev/null 2>&1; then
    echo "uiopen 不在 PATH 上，无法起 App（请确认设备越狱环境）" >&2
    exit 3
fi

STAMP=$(date +%Y%m%d-%H%M%S)
SHOT=${TMPDIR:-/tmp}/apelin-errand-$STAMP.jpg
START=$(date +%s)

# 起 App：uiopen --bundleid（不弹卡）。回程也一样。
open_app() {
    uiopen --bundleid "$1" >/dev/null 2>&1
}

# 前台 App 只有 icli 能问（会弹一张卡），所以默认不查；ERRAND_VERIFY=1 时才查。
frontmost_bid() {
    [ "$VERIFY" = "1" ] || { echo ""; return; }
    icli app frontmost 2>/dev/null \
        | sed -n 's/.*"bundle_id" *: *"\([^"]*\)".*/\1/p' \
        | head -1
}

# 回程：无论怎么退出都会跑（EXIT/INT/TERM）。launch 失败再试一次，
# 因为 launch 内部等前台是超时语义，偶发一次不生效。
back_to_apelin() {
    open_app "$APELIN_BID" || true
    if [ "$VERIFY" = "1" ]; then
        now=$(frontmost_bid)
        if [ "$now" != "$APELIN_BID" ]; then
            open_app "$APELIN_BID" || true
            now=$(frontmost_bid)
        fi
        echo "回到 Apelin: ${now:-未知}（外出 $(( $(date +%s) - START )) 秒）"
        if [ "${now:-}" != "$APELIN_BID" ]; then
            echo "警告: 前台不是 Apelin —— 用户看不到聊天，请手动切回" >&2
        fi
    else
        echo "已请系统打开 Apelin（外出 $(( $(date +%s) - START )) 秒；未用 icli 校验前台，要校验加 ERRAND_VERIFY=1）"
    fi
}
trap 'back_to_apelin' EXIT INT TERM

elapsed() { echo $(( $(date +%s) - START )); }
over_limit() { [ "$(elapsed)" -ge "$LIMIT" ]; }

echo "去 $TARGET 办事（上限 ${LIMIT}s，超时就回）"
open_app "$TARGET" || echo "uiopen $TARGET 返回非零，继续尝试取证"
sleep 3

if over_limit; then
    echo "时间已到，跳过取证直接回程"
    exit 0
fi

for LABEL in "$@"; do
    if over_limit; then
        echo "时间已到，跳过剩余点击（「$LABEL」及之后）"
        break
    fi
    if icli ui wait "$LABEL" --timeout 5 >/dev/null 2>&1 && \
       icli ui tap "$LABEL" >/dev/null 2>&1; then
        echo "已点击「$LABEL」"
        sleep 2
    else
        echo "点击「$LABEL」失败（元素没出现或不可点，不影响回程）"
    fi
done

if ! over_limit; then
    if icli screen shot --output "$SHOT" >/dev/null 2>&1 && [ -s "$SHOT" ]; then
        echo "截图: $SHOT"
    else
        echo "截图失败（不影响回程）"
    fi
fi

if ! over_limit; then
    echo "--- 界面元素树 ---"
    if ! icli ui tree --human --max-elements 120 2>&1 | sed -n '1,90p'; then
        :
    fi
    sleep 1
    echo "--- 界面元素树（第二次，防上一页残留） ---"
    icli ui tree --human --max-elements 120 2>&1 | sed -n '1,90p'
fi

exit 0
