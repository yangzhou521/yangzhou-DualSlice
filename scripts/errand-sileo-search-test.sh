#!/bin/sh
# 外出取证：Sileo 源内「搜索软件包」输入框实测（点得进 / 键盘出得来 / 打得进字）
# 单条脚本内完成全部 UI 操作，trap 保证无论如何回到 Apelin；实测一趟 20~25 秒。
# 用法：sh scripts/errand-sileo-search-test.sh
set -u
SILEO=org.coolstar.SileoStore
APELIN=wiki.qaq.apelin
# SileoFix 把日志写在 jbroot 命名空间的 /var/mobile/Library/Caches/；
# shell（mobile）的 / 就是 jbroot，别加 /rootfs 前缀，加了会指向真实数据卷的另一处而读不到。
LOG=/var/mobile/Library/Caches/sileofix.log
START=$(date +%s)

back() {
  icli app launch "$APELIN" >/dev/null 2>&1
  sleep 2
  F=$(icli app frontmost --human 2>&1 | head -2)
  END=$(date +%s)
  echo "—— 回到 Apelin: $F （外出 $((END - START)) 秒）"
}
trap back EXIT INT TERM

show() { # show <标签> <grep 正则>
  echo "---- $1 ----"
  icli ui tree --human 2>&1 | grep -n -E "$2" | head -25
}

echo "== 1. 拉起 Sileo =="
icli app launch "$SILEO" >/dev/null 2>&1
sleep 4
echo "frontmost: $(icli app frontmost --human 2>&1 | head -2)"

echo "== 2. 进「软件源」 -> 打开第一个源 =="
icli ui tap "软件源" >/dev/null 2>&1
sleep 2
icli ui tap "季伯之家" --index 0 --human 2>&1 | head -2
sleep 3
show "源内页有没有搜索框" "搜索|Search|取消|Cancel"

echo "== 3. 点搜索框 =="
icli ui tap "搜索" --index 0 --human 2>&1 | head -2
sleep 2
show "点完之后：键盘 / 焦点 / 输入框值" "搜索|field=|value=|空格|Space|换行|Return|删除|删除键|Delete|拼|拼音|Shift|shift|A-Z"

echo "== 4. 打字 abcd =="
icli input type "abcd" --human 2>&1 | head -3
sleep 2
show "打字之后：输入框的值 / 键盘" "abcd|搜索|空格|Space|换行|Return"

echo "== 5. 插件日志尾部 =="
tail -n 12 "$LOG" 2>/dev/null || echo "(读不到 $LOG)"
