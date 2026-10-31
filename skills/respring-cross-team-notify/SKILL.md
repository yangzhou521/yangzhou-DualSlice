---
name: respring-cross-team-notify
description: Before ANY respring (sbreload) on this device: tell all running conversations via apelin_conversation_send, write in your own chat body why + "N seconds" + next step, show a Dynamic-Island popup so the user decides (CountdownHUD ? mode or scripts/respring-guard.sh --ask), and only run --confirm after the user explicitly says 注销/确定 this round. Never respring silently; never on your own initiative.
---

# 注销四步硬规矩（跨对话同步 + 用户点头）

用户 2026-10-31 定的**永久规矩**（所有对话、所有工程）：任何一次注销（respring / `sbreload`）
都不许静默、不许 agent 自作主张，必须走满四步。

## 0. 先判断要不要注销
注入型插件（tweak）装完/改完**不必注销**——划掉后台重开（`scripts/device.sh kill <bid>` + `launch <bid>`）
就完成注入。只有以下情况才走本流程：
- 插件本身注入 **SpringBoard**（桌面图标、HUD、控制中心）；
- **改了过滤器 plist** 或**包布局**；
- 别的确实要让整个桌面重启的情形。
（详见技能 `injected-tweak-restart-app`：装完包先想这条，再决定要不要注销。）

## 1. 四步（顺序不可省）
1. **同步全员**：用 `apelin_conversation_send` 通知所有 `state=open` 的对话，说明
   「我要注销、原因、预计 N 秒、你们别误判我挂了/别在我注销时动设备」。等它们收讫/回复。
   已 ended 的对话用 `icli url open apelin://conversation/<sid>` 重开再发（实测有效，但批量唤醒后
   记得切回自己）。
2. **正文知情**：在本对话回复正文写清「为什么注销 / N 秒后执行 / 下一步」。
   **通知横幅不算知情**——发 `apelin_notification_send` 会把 Apelin 拉回前台，横幅被它自己的
   UNUserNotificationCenterDelegate 吞掉，用户看不到。正文必写。
3. **屏幕弹窗让用户决定**：走灵动岛弹窗，二选一：
   - CountdownHUD `?` 模式：写 `.countdownhud-request` 内容 `<epoch>|N|?<标签>`（shell 写加 `/rootfs` 前缀），
     弹窗点「立即注销」→ 答案文件 `<epoch>|confirm`；点「取消」→ `cancel`；超时 → `timeout`。
   - `sh scripts/respring-guard.sh --ask N <标签>`（等同弹窗路径）。
   默认（不带 `--ask`/`?`）只警告、退出码 3、不注销。
4. **当轮确认才执行**：只有用户**本轮明确回「注销 / 确定」**后，才跑
   `sh scripts/respring-guard.sh --confirm N <标签>` → 倒计时 N 秒 → `sbreload`。
   `--confirm` 必须写在最前面。用户没回、回「取消」、或 agent 自己觉得该注销了 ——
   **一律停在警告/弹窗那一步，不许往下走**。

## 2. 注销后必查
`apelin_crash_list process=SpringBoard` 无新报告才算装好；有更新报告＝装坏了（先 `irisin-cli remove` 回滚）。

## 3. 装包 / 杀进程照此通报
`irisin-cli install` 装包、`icli app kill --force` 重启进程同样要通知 + 正文知情 + 倒计时（见记忆
「装包/注销/重启进程前…」与技能 `respring-notify-countdown`），只是不必弹窗点头——
但用户要求「让用户知道」的场景，弹窗更稳妥。

## 4. 沉淀
任何从「注销踩坑 / 协调冲突」提炼出的新做法，按硬规矩写进本地技能包并同步云端（见记忆
「解决问题/化解逻辑冲突后必须沉淀成技能包并上传云端」与技能 `verify-cloud-release`）。
