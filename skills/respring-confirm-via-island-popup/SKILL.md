---
name: respring-confirm-via-island-popup
description: 注销、装包、重启注入进程等会让屏幕黑一下或打断用户的动作，一律用灵动岛弹窗（CountdownHUD ? 模式 / respring-guard.sh --ask）把选择权交给用户，由用户在屏幕上点「立即注销」或「取消」，不在对话里等文字回复。所有对话、所有工程适用。
---

# 需用户确认的设备动作，一律上灵动岛弹窗让用户选

用户 2026-10-31 14:05 定的**永久硬规矩**（所有对话、所有工程）：

> 「凡是以后需要用户确认的注销事件全部以灵动岛和弹窗的形式告知用户让用户做出选择」

## 铁律

**任何需要用户点头的动作，都不许只在对话里等文字回复——必须在屏幕上弹出来让用户点。**

覆盖范围：
- 注销 / respring / `sbreload`
- 装 deb / 升级包（`irisin-cli install`）
- 重启注入目标进程（`icli app kill --force` + `launch`，会让 App 闪一下）
- 任何会让屏幕黑一下、打断用户操作的动作

## 怎么做（唯一正确姿势）

### 1. 写弹窗请求

```sh
printf '%s|120|?<标签>|<sid>' "$(date +%s)" > /rootfs/var/mobile/Library/Preferences/.countdownhud-request
```

- **`?` 前缀 = 确认弹窗**（`!` 是纯文案、不带 `?` 是倒计时）
- `120` 是等待用户回答的秒数
- `<sid>` 带上自己的会话 id，用户点完能跳回本对话
- **shell 写文件必须加 `/rootfs` 前缀**（roothide 真根），否则写到 jbroot 里 HUD 读不到

等价命令：`sh scripts/respring-guard.sh --ask 120 <标签>`

### 2. 用户点完，答案在

`/rootfs/var/mobile/Library/Preferences/.countdownhud-answer`

内容形如 `<epoch>|confirm`、`<epoch>|cancel`、`<epoch>|timeout`。

CountdownHUD 1.6.1 起用户点「立即注销」后**由插件自己 spawn `sbreload`**（诊断 `exec=spawned`），
不再依赖脚本还在前台等。取消 → `exec=-` 或 `skip-marker`，不注销。

### 3. 正文同时写清（弹窗不能替代）

在本对话正文写「为什么 / N 秒后执行 / 下一步」。发 `apelin_notification_send` 会把 Apelin 拉回前台、
横幅被自己的通知代理吞掉，**通知不是知情通道**。

## 不许做的事

- 不许在对话里问一句「要注销吗」就等文字回复 —— **必须有屏幕弹窗**
- 不许 agent 自己判断「该注销了」就静默执行
- 不许因为「用户已经在对话里说过注销」就跳过弹窗 —— 每轮都要弹，选择权每轮都是用户的
- 不许用 `apelin_notification_send` 代替弹窗

## 边界：注入型插件本来不必注销

先判断要不要注销（见技能 `injected-tweak-restart-app`）：

- App 内的注入型 tweak → `scripts/device.sh kill <bid>` + `launch <bid>` 就生效，**不走注销流程**
- 只有注入 **SpringBoard**（桌面图标 / HUD / 控制中心）、改了**过滤器 plist**、改了**包布局**，才需要注销

但**重启注入进程（kill + launch）同样会闪屏**，也照本规矩弹窗。

## 注销后必查

`apelin_crash_list process=SpringBoard` 无新报告才算装好。有更新的报告 = 装坏了，先
`irisin-cli remove` 回滚。

## 与其它技能的关系

- `respring-cross-team-notify`（四步硬规矩）—— 本文是它第 3 步的具体化与扩展（原来只要求注销弹窗，现在装包/杀进程也要）
- `respring-notify-countdown` —— 弹窗技术细节、`exec=` 四取值、cfprefsd 旧值判活
- `injected-tweak-restart-app` —— 先判断到底要不要注销
- `cross-chat-coordination` —— 弹窗前先同步其它在跑的对话
