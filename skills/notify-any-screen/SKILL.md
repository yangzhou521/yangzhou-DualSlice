---
name: notify-any-screen
description: 凡需要让用户知道的事（push 前后、任务完成、失败、阶段进度），无论用户在任何界面（Apelin 内/桌面/别的 App），一律用灵动岛胶囊（scripts/hud-notify.sh）告知——它是 SpringBoard 顶层窗口跨所有界面；apelin_notification_send 只在 Apelin 退到后台时才显示，不能当唯一手段。所有对话、所有工程适用。
---

# 任何界面都要用灵动岛胶囊告知用户

用户 2026-10-31 15:48 / 15:50 / 15:51 / 15:53 / 15:56 定，**所有对话、所有工程永久适用**（原话：「不能访问我的仓库时给我说一声你来个通知或者弹窗让我知道这个！」「通知和弹窗都行让我知道啊」「对了无论任何界面都要给我一个通知或者弹窗」）。

## 铁律

**凡需要让用户知道的事（push 前后、任务完成、失败、阶段进度、需要用户点头），无论用户此刻在任何界面（Apelin 内 / 桌面 / 别的 App），都必须让他真看见。**

## 两种手段的分工（关键，别搞混）

| 手段 | 什么时候用户看得到 | 用途 |
| --- | --- | --- |
| **灵动岛胶囊** `sh scripts/hud-notify.sh 8 "!文案"` | **任何界面都看得到** —— 它是 CountdownHUD 注入 SpringBoard 画的顶层窗口（`windowLevel` 最高、跨 Apelin/桌面/别的 App 盖得住） | **要「任何界面都让用户看见」时的唯一保底手段，优先用它** |
| `apelin_notification_send` | **只在 Apelin 不在前台时显示**；Apelin 在前台时横幅被它自己的通知代理吞掉，用户看不到 | 用户切去别的对话/桌面/别的 App 时的补充提醒 |

**所以「无论任何界面都要给通知或弹窗」= 必须写灵动岛胶囊**（`hud-notify.sh`），不能只发 `apelin_notification_send`——那条用户人在 Apelin 里时根本看不到。

## 做法（凡要告知用户，固定顺序）

1. **正文写清**（Apelin 前台时用户能看到正文，但正文不是唯一的知情通道）。
2. **写灵动岛胶囊**：`sh scripts/hud-notify.sh 8 "!<一句话>"`
   - `!` 前缀 = 纯文案（不倒数、不注销、不装包，绿色，最长 32 字）
   - 可带秒数：`sh scripts/hud-notify.sh 12 "!文案"`（3~60 秒，默认 8）
   - 可带对话 id 让胶囊可点：`HUD_SID=<sid> sh scripts/hud-notify.sh 8 "!文案"`（不指定会自动认发消息的对话）
   - 前置条件：本机已装 CountdownHUD（1.2.0 起支持纯文案）；胶囊在 SpringBoard 顶层窗口，任何 App 上方都盖得住
3. **可选再发 `apelin_notification_send`**：用户离开 Apelin 时的补充，不能替代胶囊。
4. 涉及 GitHub push 的场景，见 `notify-before-git-push` 的 push 前后告知。

## push 场景（配合 notify-before-git-push）

- **push 前**：胶囊 `sh scripts/hud-notify.sh 8 "!要推送 GitHub 了，请开 VPN"` + 通知，等用户确认 VPN 再 push。
- **push 失败**：胶囊 `sh scripts/hud-notify.sh 8 "!push 失败，请开 VPN"` + 通知。
- **push 成功**：胶囊 `sh scripts/hud-notify.sh 8 "!已推送到 GitHub"` + 通知。

## 边界

- 胶囊是「告知」用，不做破坏性动作（不注销、不装包、不杀进程）。要用户点头的设备动作（注销/装包）仍走灵动岛确认弹窗（`?` 模式 / respring-guard.sh --ask），见 `respring-confirm-via-island-popup`。
- `apelin_notification_send` 每回合 ≤3 条、间隔 ≥30 秒；胶囊不受此限但别刷屏。

## 与其它技能的关系

- `notify-before-git-push`：push 前后告知的具体场景。
- `task-done-notify`：任务完成/阶段进度的胶囊+通知。
- `respring-confirm-via-island-popup`：需要用户「点头」的动作走 `?` 确认弹窗，不是纯文案。
