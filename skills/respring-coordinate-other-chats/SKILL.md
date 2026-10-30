---
name: respring-coordinate-other-chats
description: 注销（respring）、装包、重启目标进程之前，先查本机所有工程和所有对话里有没有别的会话正在干活，先跟它们打招呼、等它们收尾，再执行；不许把别的对话的工作打断。任何工程、任何对话都适用。
---

# 注销前先和别的对话同步，别打断它们的工作

用户 2026-10-30 21:05 原话：

> 「你注销的话和另一个对话说一下！不要打断它的工作！把这个写进记忆和技能包内！并同步到云端！
> 以后所有的对话和工程在工作时想要注销的时候都要查看搜索另外一些工作区的对话是否在工作！
> 注销前要和别的对话同步一下！」

**任何工程、任何对话都适用。** 这条和技能 `respring-notify-countdown`（通知 + 5 秒倒计时）是两道并列的闸门，
**两道都要过**：先跟别的对话同步，再通知用户 + 倒计时。

## 为什么要这条

注销会重启 SpringBoard，把它上面的一切掀掉：

- 别的对话可能正带着你在别的 App / 桌面 / 设置里做界面验证（读了界面树、正要截图、正要 tap 下一个元素）；
- 可能正等着一个 `icli app launch` 的结果、正读诊断、正跑一次安装后的首个启动；
- 注销会让它的界面动作全部作废，甚至把它正在观察的进程一起杀掉，它的验证结论与进度就白做了。

用户的原话是「不要打断它的工作」——不是「打个招呼就行」，是**等它把这一步做完**。

## 适用范围

要过这道闸门的动作（和 `respring-notify-countdown` 的清单一致）：

- `icli sb respring`（本机唯一注销写法；**没有** `icli respring`）
- `apelin_device_respring`
- `apelin_package_confirm_loaded(respring: true)`
- `sh scripts/respring-guard.sh …`（它最后就执行 respring）
- `irisin-cli install` 装包、`icli app kill <bid> --force` 重启目标进程：不重启 SpringBoard，但会打断别的对话正在测的那个进程中状态，
  **同样先查一遍、同样打个招呼**（除非对方明确说不受影响）。

## 固定顺序（一道都不能省）

### 1. 把所有工程和对话列出来

```
apelin_project_list                                   # 全部工程：projectID / folder
apelin_conversation_list                              # 本项目全部对话
apelin_conversation_list project: <folder|projectID>   # 逐个工程再列一次
```

**本对话自己排除在外**（`isThisConversation: true`）。

### 2. 找出「可能正在干活」的对话

看 `state` 与 `updatedAt`：

- `running` / `waitingForApproval` → **算正在干活**，必须处理；
- `open` 但最近几分钟内有更新 → 也当正在干活（可能刚结束一回合、屏幕还没收拾）；
- `idle` / `ended` → 不用管。

要更确定就用 `apelin_conversation_read`（`session_id`，可以带 `after_seq` 少读些）看它的 `state` 与最后在做什么。
读别的工程的对话要加 `project:`。

### 3. 给每一个「正在干活」的对话发一句协调消息

`apelin_conversation_send`，内容照这个模板，说清三件事：

> 我是同一台设备上另一个对话（工程 X）。我准备在约 N 秒后注销 SpringBoard（原因：装了 Y / 插件要生效 / 修安全模式）。
> 请把当前这一步收尾：保存进度、放下正在做的界面验证；已经离开 Apelin 的请先自己回来。收到/收尾完回我一句。

要点：

- **发消息只是排队，不会打断它当前这一步**——这正是要的效果。
- **绝不 `apelin_conversation_stop`**：停掉别人的回合是抢它的工作，比注销更粗暴。
- 如果它是 `waitingForApproval`，它其实在等用户点卡片：消息会排在后面，这时**先把这件事写进回复正文告诉用户**，
  并等它这一步过去（用户点完它才继续）。

### 4. 等它们收尾

`apelin_conversation_read`（带 `wait_seconds: 60`）等它这一回合结束，再读一次确认没有新的动作。
多个对话就逐个等。

- 全部收尾 / 明确说不受影响 → 继续第 5 步。
- **等超过约 120 秒还没完**：**不要硬注销**。在回复正文里说清「对话 A 还在做 X（工程 Y），我先不注销」，
  让用户决定是「等」还是「现在注销、让它重做」。用户明确说「现在就注销」后才可继续。

### 5. 再走「通知 + 5 秒倒计时」

```
apelin_notification_send                     # 短标题＋一两句
（回复正文写明「N 秒后执行」）
sh scripts/respring-guard.sh 5 <标签>          # 真等 5 秒，屏幕上出胶囊
```

### 6. 汇报里写清楚

回复正文写：查了哪几个工程、哪几个对话、各自状态、发了什么协调消息、等了多久、最后是否注销。
「查了，没有别的对话在干活」也是一句要写的话——它是证据，不是废话。

## 例外（只有这些）

- **设备在崩溃循环 / 一进安全模式**：目标进程反复崩，用户要求「先救回来」时，先修好再谈协调——
  但仍然要在正文写清「我现在注销，别的对话会被打断」。
- 用户明确说「现在就注销，不用等」→ 照办，但正文里如实写「已按你要求不等对话 X」。
- 别的对话明确回了「不影响，我不用屏幕」→ 可以不等。

## 自检

- [ ] `apelin_project_list` + 每个工程的 `apelin_conversation_list` 都跑过。
- [ ] 每个 `running` / `waitingForApproval` / 刚活动过的对话都发了协调消息。
- [ ] 没有用 `apelin_conversation_stop` 停别人。
- [ ] 等过对方的回合（除非用户点名不用等），等待时间写进回复。
- [ ] 协调之后才发通知、才倒计时 5 秒、才注销。

## 落地位置

- 本机技能目录 `~/Documents/wiki.qaq.apelin/skills/respring-coordinate-other-chats/`（Apelin 读的就是这份）
- 仓库副本 `skills/respring-coordinate-other-chats/`（`sh scripts/sync-skills.sh` 推上去）
- 同时写在：技能 `respring-notify-countdown`（作为第 0 步）、工程 `AGENTS.md`「硬规矩」一节、
  `scripts/respring-guard.sh` 的提示行、全局记忆一条。
