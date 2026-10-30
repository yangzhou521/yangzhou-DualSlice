---
name: fleet-shared-board
description: 多对话/多工程同时干活时，用本机共享「任务黑板」交换状态：只写不打扰地广播自己在做什么、下一步、进展，并读别人的；动设备（注销/装包/杀进程/用屏幕）前先看谁在占；派活与认领也走黑板，替代互相发消息等待；并用看护报告（care）发现睡死的机器人、用 takeover 把它的活接过来，保证一两个机器人停摆时任务照样有人干。任何工程、任何对话适用。
---

# 共享任务黑板（fleet board）

多个工程、多个对话同时干活时，机器之间**默认用一块共享黑板交换状态，而不是互相发消息**。

## 为什么

对话之间用 `apelin_conversation_send` 一问一答太慢：发的人要等回复、收的人要停下手里的活，
一轮几分钟，还常常两边一起空转；而且聊天内容一被压缩就丢。

事实是**绝大多数信息只需要被看见，不需要被回应**——谁在做哪个工程、做到哪一步、下一步打算
干什么、此刻有没有占着设备。这些写进一个共享文件就够了：**只写不打扰**，谁想知道随时读，
读的时候别人照常干活。

## 黑板在哪

本机（所有工程、所有对话都能用 shell 读写）：

```
$HOME/Documents/wiki.qaq.apelin/fleet/
├── fleet.sh        工具（本仓库 scripts/fleet.sh 的安装副本）
├── board.tsv       数据（每个 agent 一行，TAB 分隔）
├── inbox.tsv       收件箱（派活不覆盖状态行，可以积压）
└── agents.tsv      名册（短 id ↔ 全对话 id ↔ 工程）
```

工具固定入口（任何工程里都写这一条绝对路径，别用相对路径）：

```sh
F="$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh"
sh "$F" start          # 开工一条命令：我的收件箱 + 全队状态 + 看护报告
```

仓库 `yangzhou521/yangzhou-DualSlice` 里 `scripts/fleet.sh` 是工具源码；工程内的
`fleet/board.tsv` 只是**快照**（`sh "$F" snapshot` 生成），方便上云和换机时看见，
**干活时读写的是本机那份**。

## 一条命令的事

```sh
F="$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh"

# 状态
sh "$F" list                                       # 全队状态（按更新时间倒序）+ 谁在占设备
sh "$F" busy                                       # 只问：现在有没有人在动设备（5 分钟内才作数）
sh "$F" post   <agent> <工程> <状态> <任务> <下一步> [动作]   # 更新自己那一行
sh "$F" hold   <agent> <工程> <动作> <任务>        # 我要动设备了（动作见下）
sh "$F" free   <agent> <工程> <任务> [下一步]      # 设备动作做完了
sh "$F" done   <agent> [备注]                      # 完成
sh "$F" prune  [分钟，默认 180]                    # 清掉过期/已完成的行

# 派活 / 收件箱（派活不再覆盖对方的状态行，可以积压，对方醒来先看收件箱）
sh "$F" assign <agent> <工程> <任务> [下一步]      # 给某个对话派活（待认领）
sh "$F" claim  <agent> <工程> <任务> [下一步]      # 认领一件活
sh "$F" add    <收件人> <工程> <任务> <验收> [from] # 投递一件活（带验收标准）
sh "$F" inbox  [agent]                             # 我的收件箱
sh "$F" take   <agent> <task#id>                   # 从收件箱接下一件
sh "$F" finish <agent> [task#id] <结果>            # 做完并回报
sh "$F" want   <agent> <工程> [能力,用逗号]         # 我空闲，能接只读/云端/取证/文档…

# 看护（防睡死）
sh "$F" start  [agent]                             # 开工一条命令 = 收件箱 + 全队 + 看护报告
sh "$F" care   [阈值分钟，默认 20]                  # 看护报告：谁睡死、该谁接、全队活线数
sh "$F" beat   [agent]                             # 心跳：我在干（只刷新时间，不动状态）
sh "$F" takeover <你> <睡死那位的短id> [备注]        # 接管它的活，并把它那行标 handoff
sh "$F" roster [短id] [全id] [工程] [备注]          # 登记名册（照抄的唤醒命令靠它）
sh "$F" sweep  [分钟，默认 20]                      # 只要唤醒清单（care 是它的加强版）
sh "$F" wake   <短id|全id> [from]                   # 单个唤醒：打印照抄就能发的消息
```

- `agent` = **对话 id 前 8 位**（`apelin_conversation_list` 里能看到），或 `FLEET_AGENT` 环境变量。
  传错或留空会写成 `unknown`，别人就分不出是谁——一定写自己那条对话的 id。
- `状态`：`working` | `assigned` | `blocked` | `waiting-user` | `idle` | `done` | `handoff`（已被别人接管）
- `动作`：`none` | `respring` | `install` | `kill` | `screen`（正在注销 / 装包 / 杀进程 / 用屏幕取证）
- 每个 agent **只有一行**，再 post 就覆盖自己那行，所以不会写乱、不会吵醒别人。
- 字段用 TAB 分隔，参数保持**单行**，别在任务文字里塞 TAB 或换行。
- 脚本**不会替 agent 发消息**（`apelin_*` 工具只在 agent 手里），所以 `care` / `sweep` / `wake` /
  `takeover` 会把「照抄就能发」的 `apelin_conversation_send(...)` 整行打印出来，直接抄。

## 什么时候写、什么时候读

**开工（读完本机技能与记忆之后）**：
```sh
sh "$F" start <自己的短id>   # 收件箱 + 全队状态 + 看护报告，一条命令看完
```

**干活中**——一个命令，几秒钟，不打断任何人：
- 换步骤 / 有新进展 / 有结论 / 遇到阻塞 / 等用户回话：都 `post` 一次。
- 长活（云编译、装包、批量修复）到一个有结论的节点就 post 一次，**每几分钟 `beat` 一次**，
  别人由此知道你还活着，不会当你睡死去接管。
- 一件活做完，`post` 的「下一步」字段一定要写下一件事；写不出来就 `want` 一条。

**要动设备之前**（注销、装包、杀进程、用屏幕做界面取证）：
```sh
sh "$F" busy        # 有人正在动设备，就先打招呼 / 等它收尾
sh "$F" hold <agent> <工程> respring "<在做什么>"     # 自己动之前声明
# …执行（照旧走通知 + 5 秒倒计时）…
sh "$F" free <agent> <工程> "<接下来做什么>"           # 做完立刻释放，别让别人一直等
```
`hold` 只是**声明**，不替代通知、倒计时和对话协调；那三样仍按
`cross-chat-coordination` 与 `respring-notify-countdown` 走。

## 看护与接管（一两个机器人睡死，活照样有人干）

`care` 一次给你五段：①疑似睡死 ②等用户点头 ③空闲可派 ④设备占用 ⑤全队活线数。

```sh
sh "$F" care 20        # 阈值：20 分钟没更新黑板就算疑似睡死（长活可以用 45）
```

- **判据**：黑板行 20 分钟没更新、状态不是 `done`/`idle`/`handoff`/`waiting-user`。只是疑似——
  接管前先 `list` 看有没有人已经接了，必要时发一条 `【fleet-wake】` 唤醒它（不要求回执）。
- **接管**：
  ```sh
  sh "$F" takeover <你> <它的短id> "备注"    # 我接下它的任务；它那行变 handoff
  ```
  接的都是**随时能停、不冲突**的部分：只读查询、云端 CI / Release 查询、下载与校验、设备取证、
  写自己工程内的文档 / 技能 / 记忆、三样同步。**改别人工程源码、装包、注销、杀进程不接**
  （除用户当次明确同意）—— 那些要走通知 + 5 秒倒计时，只能由用户点头后动手。
- **一文件一写者**：黑板上 `handoff` 那行就是「你回来别再接着改」的标记；同一个文件同一时刻
  只有一个 agent 在改。
- **等审批不是睡死**：`waiting-user` 单独列出，看护人负责 `apelin_notification_send` 提醒用户，
  并用 `sh scripts/hud-notify.sh 8 "!等你点一下"` 让灵动岛胶囊也说一句。
- **活线 = 0 就喊**：`care` 的第五段会直接打出「⚠ 全员停摆」，那时看护人自己顶上——
  `start` 一遍、把最老那件用 `takeover` 记账、先做只读 / 云端 / 文档部分。

## 分工：黑板 vs 消息

| 用途 | 走哪条路 |
| --- | --- |
| 广播状态、进展、下一步、计划、谁在占设备 | **黑板**（`fleet.sh`），只写不打扰 |
| 派活 / 认领 / 回收 | **黑板**（`assign` / `add` / `take` / `claim` / `finish`） |
| 发现有人睡死、把它的活接过来 | **黑板**（`care` / `takeover`）+ 可选一条 `【fleet-wake】` 消息 |
| 需要对方**立刻改变行为**（让路、停止、等我、要一份结果） | `apelin_conversation_send`（并先回一句回执） |
| 注销前的「30 秒反对窗口」公告 | 仍按 `cross-chat-coordination` §十二 |

优先级不变：**用户当前指令 ＞ 本对话没做完的任务 ＞ 协助别人**。

## 红线

- 只写自己那一行；别人的行只读，**唯一的例外是 `takeover` 把对方那行标成 `handoff`**——那是接管记账，
  不是改别人的活；要改内容就发消息请对方自己改。
- 不往黑板写秘密（token、密码、私密信息）；它在本机是明文文件。
- 别人正在 `hold respring/install/kill/screen` 时，自己不要同时动设备（对方可能正在看屏幕）。
- 定时的 `prune` 只清 `done` 和超过 3 小时没更新的行，别拿它当"清场"工具删别人的活。
- **接管只接随时能停的部分**：改别人工程源码、装包、注销、杀进程一律不接。
- 黑板是**状态通道**，不是聊天室：一行说完，不写长篇。

## 与其它技能的关系

- `cross-chat-coordination`：协作总则（优先级、回执、注销前协调、非阻塞、看护与接管 §十三）
  ——**黑板是它的执行工具**。
- `respring-notify-countdown`：装包/注销/杀进程的通知与 5 秒倒计时——动设备前照走，另加 `hold`/`free`。
- `icli-status-self-check`：设备状态自己查——黑板上的状态同样自己读，不回头问别人。

## 安装 / 修复

工具装到本机共享位置（每个工程跑一次就够）：

```sh
mkdir -p "$HOME/Documents/wiki.qaq.apelin/fleet"
cp "$APELIN_PROJECT_ROOT/scripts/fleet.sh" "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh"
chmod +x "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh"
sh "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh" care    # 冒烟：能打印看护报告就对了
```

改过 `scripts/fleet.sh` 后重新 `cp` 一次（本机那份不会自动更新），再用 `list`/`care` 冒烟验证。
本机路径含 roothide 隐根前缀，**一律用 `$HOME` 变量，不写解析后的绝对路径**（换引导根就变）。

## v6：实时刷新进展 + 统一调度 + 唤醒闭环

### progress —— 实时刷新自己的进展（高频、轻量）

每跑完一小步就写一句，**别的对话 `list` 立刻看见你到哪了**，不用 post 整行、也不用发消息：

```sh
sh "$F" progress "改完 Store 去重，开始时钟日历合成"
```

只换自己那行的「下一步/进展」与时间，不动工程/状态/任务/设备。协调与实时同步就靠它高频更新——
长活期间每隔几分钟 `progress` 一次（和 `beat` 一起用：beat 刷心跳、progress 写内容）。

### 统一调度（把全队当一份资源重排）

```sh
sh "$F" plan      [阈值分钟]   # 只读：①负载 ②撞车 ③待派配对 ④空闲 ⑤设备排队 ⑥三条照抄即跑
sh "$F" members   [阈值分钟]   # 成员对账：在册的 / 疑似离场的 / 新来的（新来的立刻 intake 派活）
sh "$F" refresh   [阈值分钟]   # 资源刷新（写）：prune 48h 陈旧席位 + snapshot + members + plan
sh "$F" rebalance [阈值分钟]   # 叫不醒/已离场者手上的活，立刻改派给活着的候选（打印 add + takeover + 唤醒行）
sh "$F" intake <短id> <全id> <工程> <能力>   # 新机器人接入：登记 + 声明能力 + 从待派池挑最匹配的活改派给它
sh "$F" roster-drop <短id>     # 确认离场的成员从名册去掉（它的黑板行标 handoff）
```

闲时或接手前跑一次 `refresh`，让黑板只留「在场的人」并给一份调度建议；`plan` 的撞车检查会标出
「同一工程多人同时在动 = 可能同改一份文件」，那时先划清文件边界或用 `dep` 串起来。

### 唤醒闭环：真的发出去，不是只打印

脚本**算得出该唤醒谁、也打印照抄即发的整行**，但 `apelin_conversation_send` 只有醒着的 agent 能调。
所以规矩是：**每个醒着的 agent 跑完 `care`/`wakeall` 拿到列表后，立刻真的把「【继续任务】」发进
对方对话**——一次最多两条，别刷屏；发完 60 秒仍无动静才 `takeover`。不是打印完就完事。

```sh
sh "$F" care 20      # 看到「疑似睡死」列表 + 每人的唤醒整行（含 session_id 与文案）
# 然后真的调 apelin_conversation_send(session_id:"...", text:"【继续任务】...")  ← 直接发，不是手抄
```

唤醒文案要点：说清「你停了多久 / 你的下一步是什么 / 先 beat 报个心跳 / 30 秒内回一句」。

## Fleet 协调群 = 大脑中枢（2026-10-31 起）

用户 2026-10-31 01:56 原话：「给所有对话机器人开一个群聊一样的对话。」；
2026-10-31 02:09 原话：「它应当是大脑🧠中枢！领导一切机器人！」

协调群是**全体机器人的中央指挥（大脑）**——不是被动转发消息的公告板。黑板是文件（只写不打扰），
协调群是实时指挥通道（主动调度）。**两者互补**：

| 通道 | 用途 | 工具 |
| --- | --- | --- |
| 黑板（board.tsv） | 结构化状态（谁在做什么、下一步、设备占用） | `fleet.sh post`/`progress`/`care` |
| 协调群（对话） | 实时指挥（任务分配、冲突裁决、唤醒、relay、汇总、请示） | `apelin_conversation_send(session_id, ...)` |

**协调群的 session ID** 存在 `$HOME/Documents/wiki.qaq.apelin/fleet/coordinator.txt`。
新对话开工先查这个文件；不存在或对话已 ended → `apelin_conversation_create` 建新的（prompt 模板见技能
`cross-chat-coordination` §十六），把 session ID 写回文件。**已有活的就不建。**

**协调员（大脑）的七项主动职责**（每收到一条消息都要跑一遍）：
1. **盘点**：`apelin_conversation_list`（全部工程）+ `fleet.sh list` + `care 15` → 全队状态图
2. **分配**：新任务/请求 → 拆解 → `fleet.sh plan` + `assign`/`handout` 按能力+负载分配；空闲的派小任务
3. **裁决**：两人同改一文件 → 立即介入裁定谁先谁后、文件归谁；风险动作 → 先协调再放行
4. **看护**：睡死→唤醒；唤不醒→`takeover` 改派；全员停摆→自己顶上+通知用户
5. **汇总**：全队进展简报（谁做完什么、谁在做什么、下一步、阻塞在哪）
6. **relay**：`waiting-approval` 的对话 → 替做只读任务（下载/校验/查CI/读诊断），结果发回
7. **请示**：需要用户决策的 → `apelin_notification_send` + `hud-notify.sh` 上岛

**决策权**（用户不在时可自行决定）：任务优先级、资源分配、冲突裁决、唤醒/接管、派活。
**不可自行决定**：装包、注销、杀进程、改源码、删包、改系统设置——须用户当次明确同意。
**红线**：不改源码/不装包/不注销/不杀进程/不 stop 别人/不改别人工程文件。
