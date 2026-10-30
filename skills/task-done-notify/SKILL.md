---
name: task-done-notify
description: 修复/功能/检查有结果时：先在对话内说清结果，再用灵动岛胶囊（scripts/hud-notify.sh，CountdownHUD 1.2.0 纯文案）加 apelin_notification_send 提醒用户——他要切到别的对话、回桌面或去已装 App 里看效果时也能看见；长活每到一个有结论的节点也上岛一次。完成、汇报、提醒都要做，任何工程、任何对话适用。
---

# 任务完成：对话内说清 + 灵动岛上提醒（所有对话、所有工程）

用户 2026-10-30 21:16 原话：

> 以后所有让你完全和修复的结果：如果修复和完成✅后都要在对话内和我说一下！如果我离开此对话去别的对话和去系统桌面上和我本地安装的软件内都要用灵动岛胶囊通知我一下！给我提一下工作进程和工作进度！把这个写进记忆和技能包内！并同步到云端！以后所有的对话和工程在工作时有初步己达成完成的有结果的任务结束时，都要给我一个通知和提醒！

这是一条**永久规则**，与本技能配套的还有 `respring-notify-countdown`（注销/装包/杀进程前的通知 + 5 秒）
和 `respring-coordinate-other-chats`（注销前先跟别的对话同步）。三件事互不替代。

## 一、顺序：先说，再上岛

1. **对话内先给结论**：只要一个修复、一个功能、一次检查有了结果，回复正文第一句就写结果
   （做了什么、**在本机实际验证了什么**、还有什么没验）。不允许「做完了不说」。
2. **再提醒一次**：用户很可能在这个回合结束后就切到别的对话、回桌面、或进已装 App 里看效果，
   所以每件有结果的事都补：
   - **灵动岛胶囊**（主）：`sh scripts/hud-notify.sh 8 "完成：<一句话>"`，默认 8 秒；
     想留久点给个秒数（3~60），如 `sh scripts/hud-notify.sh 15 "完成：ThemeControl 设置面板已装"`。
   - **通知**（辅）：`apelin_notification_send`，短标题 + 一两句「修好了什么 / 下一步 / 要他做什么」。
     每回合 ≤3 条、间隔 ≥30 秒；能一条说完就别拆两条。
3. **阶段也算**：长活（云编译、装包、批处理、多文件重构）每到一个**有结论的节点**就上岛一次，
   讲清「进度到哪、下一步是什么」，别让用户对着黑箱等；不需要每跑一条命令就报。

## 二、胶囊怎么工作（CountdownHUD 1.2.0 起）

- 请求文件（系统原路径，SpringBoard 里的插件每 0.5 秒轮询一次，内容变了才触发）：
  `/var/mobile/Library/Preferences/.countdownhud-request`
  - 从 shell 写必须加真根前缀 `/rootfs`；`scripts/hud-notify.sh` 已经包好，直接用它。
  - 内容 `<epoch>|<秒数>|!<文案>`：**`!` 前缀＝纯文案**——屏幕上就是这句话本身，
    没有「N 秒后」前缀、不跳数字、不做绿→橙→红升级，N 秒后淡出，超过 32 字截断。
  - 不带 `!` 的老格式仍是倒计时（`5 秒后注销`），那是 `scripts/respring-guard.sh` 用的。
- 文案要短、要具体：`完成：注销前同步已写进技能`、`进度：CI 编译中 2/3`、`完成：胶囊纯文案版已装`。
  单行显示、宽度跟着岛走，太长会被缩到看不清。
- **不注销、不装包、不杀进程**：`hud-notify.sh` 只提醒。真要重启 SpringBoard 或装包，
  仍旧走 `respring-coordinate-other-chats` → `respring-notify-countdown` 的两道闸门 + `scripts/respring-guard.sh`。
- 用户就在 Apelin 里（前台）时胶囊看不见——那很正常，正文那句结论才是主体，胶囊是给「人不在」准备的。

## 三、验证与排错

- 装的是不是 1.2.0（有纯文案）：`icli prefs read com.apple.springboard CountdownHUDDiagnostics`
  → `v1.2.0;shows=N;...;mode=plain|count`。旧版（`v1.1.x`）会把 `!文案` 显示成「N 秒后!文案」，
  这时只能等 1.2.0 装上，别硬发看起来怪的话。
- 发完看诊断第二段：`shows` 加一、`label=` 是刚发的那句、`mode=plain` → 插件真收到了。
- 读不到诊断 = SpringBoard 里没这个插件（没装 / 装了没重启 SpringBoard）；胶囊没有回执，
  只写日志：`icli log syslog --subsystem com.yangzhou.countdownhud`。
- 本机的胶囊位置/字号来自系统 Aperture 那只岛（DynamicX 造的假岛），岛一动它跟着动，
  不用为位置单独调。

## 四、别踩的坑

- 别用 `apelin_notification_send` 代替正文汇报，也别用它报「正在跑的命令」。
- 别为了提醒就顺手 respring；提醒不需要重启任何东西。
- 别把用户当已读：通知会把 Apelin 拉回前台、横幅被它自己吞掉，所以正文永远是主渠道。
- 文案里不写 token、路径里的 jbroot 哈希、设备标识；写相对位置或功能名。

## 五、一条最小流程

```
# 1. 对话内先写好结论（回复正文）
# 2. 上岛
sh scripts/hud-notify.sh 8 "完成：<一句话结果>"
# 3. 通知（有需要时，本回合算上这条不超过 3 条）
#    apelin_notification_send：「<标题>」「<一两句结果与下一步>」
```
