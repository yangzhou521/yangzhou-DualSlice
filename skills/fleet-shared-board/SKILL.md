# 共享任务黑板（fleet board）

多个工程、多个对话同时干活时，机器之间**默认用一块共享黑板交换状态，而不是互相发消息**。事实是绝大多数信息只需被看见不需被回应——谁在做什么、做到哪、下一步、谁占着设备。写进一个共享文件就够：**只写不打扰**。

## 位置与入口

```sh
F="$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh"
sh "$F" start          # 开工一条命令：收件箱 + 全队状态 + 看护报告
```

本机 `$HOME/Documents/wiki.qaq.apelin/fleet/`（`fleet.sh` 工具 + `board.tsv` 数据 + `inbox.tsv` 收件箱 + `agents.tsv` 名册）。工具源码＝仓库 `scripts/fleet.sh`，改后重新 `cp` 到上面位置。工程内 `fleet/board.tsv` 只是快照（`snapshot` 生成，便于上云）。

## 命令速查

```sh
# 状态
sh "$F" list                    # 全队状态 + 谁在占设备
sh "$F" busy                    # 只问：有没有人在动设备（5 分钟内才作数）
sh "$F" post <agent> <工程> <状态> <任务> <下一步> [动作]   # 更新自己那行
sh "$F" progress "<一句话>"     # 高频轻量：只换进展与时间（v6）
sh "$F" done <agent> [备注]     # 完成
sh "$F" prune [分钟]            # 清过期/已完成行

# 派活 / 收件箱
sh "$F" assign <agent> <工程> <任务> [下一步]   # 派活（待认领）
sh "$F" add <收件人> <工程> <任务> <验收> [from]  # 投递一件活
sh "$F" inbox [agent]           # 我的收件箱
sh "$F" take <agent> <task#id>  # 从收件箱接一件
sh "$F" finish <agent> [task#id] <结果>  # 做完回报
sh "$F" want <agent> <工程> [能力]  # 我空闲，能接只读/云端/取证/文档
sh "$F" handout <能力> <工程> <任务> <验收>  # 派给有空的人（v6）

# 动设备
sh "$F" hold <agent> <工程> <动作> <任务>   # 声明要动设备（none|respring|install|kill|screen）
sh "$F" free <agent> <工程> <任务> [下一步] # 做完释放

# 看护（防睡死）
sh "$F" care [阈值分钟，默认20]    # 看护报告：谁睡死、该谁接、活线数
sh "$F" beat [agent]              # 心跳：只刷时间，不动状态
sh "$F" takeover <你> <短id> [备注]  # 接管它的活（它那行变 handoff）
sh "$F" wake <短id|全id> [from]   # 单个唤醒：打印照抄即发的消息
sh "$F" wake-do [limit]           # 唤醒执行单：WAKE_SEND 行，直接调 apelin_conversation_send（v6）

# 统一调度（v6）
sh "$F" plan [阈值]      # 只读：负载/撞车/待派配对/空闲/设备排队/三条照抄即跑
sh "$F" members [阈值]   # 成员对账：在册/疑似离场/新来的
sh "$F" refresh [阈值]   # 写：prune 48h + snapshot + members + plan
sh "$F" rebalance [阈值] # 叫不醒就改派给活着的候选
sh "$F" intake <短id> <全id> <工程> <能力>  # 新机器人接入即派活
sh "$F" roster-drop <短id>  # 确认离场的从名册去掉
```

- `agent` = **对话 id 前 8 位**（或 `FLEET_AGENT` 环境变量）。
- `状态`：`working`|`assigned`|`blocked`|`waiting-user`|`idle`|`done`|`handoff`。
- 每个 agent 只有一行，再 post 就覆盖，不会写乱。字段 TAB 分隔，参数保持单行。
- 脚本**不会替 agent 发消息**——`care`/`wake`/`takeover` 打印「照抄就能发」的整行，agent 直接调。

## 什么时候用

**开工**（读完技能与记忆后）：`start` 一条命令看完。
**干活中**：换步骤/有结论/遇阻塞 → `post` 或 `progress`；长活每几分钟 `beat`；做完写「下一步」，写不出就 `want`。
**动设备前**：`busy` → `hold` → 执行（通知+5 秒照旧）→ `free`。`hold` 只是声明，不替代协调和倒计时。
**干完一轮**：`snapshot` 把黑板快照进工程 `fleet/board.tsv`，再走三样同步。

## 唤醒闭环（v6，关键）

`care`/`wake-do` 会打印 `WAKE_SEND|<session_id>|<唤醒文案>` 行——**醒着的 agent 读到后立刻真的调 `apelin_conversation_send` 发出去**（一次最多两条），发完 60 秒无动静才 `takeover`。**不是只打印不动手。**

## 黑板 vs 消息

| 用途 | 走哪条 |
| --- | --- |
| 广播状态、进展、下一步、计划、谁占设备 | **黑板**（只写不打扰） |
| 派活 / 认领 / 回收 / 接管 | **黑板** |
| 需要对方**立刻改变行为**（让路、停止、要结果） | `apelin_conversation_send`（并先回回执） |

优先级不变：**用户当前指令 ＞ 本对话没做完的 ＞ 协助别人**。

## 红线

- 只写自己那行；别人行只读（唯一例外：`takeover` 把对方标 `handoff`）。
- 不往黑板写秘密（token、密码）。
- 别人 `hold respring/install/kill/screen` 时自己不要同时动设备。
- 接管只接随时能停的部分：改别人源码、装包、注销、杀进程一律不接。
- 黑板是状态通道，不是聊天室：一行说完。

## 安装 / 修复

```sh
mkdir -p "$HOME/Documents/wiki.qaq.apelin/fleet"
cp "$APELIN_PROJECT_ROOT/scripts/fleet.sh" "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh"
chmod +x "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh"
sh "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh" care    # 冒烟
```

改过 `scripts/fleet.sh` 后重新 `cp`，用 `list`/`care` 冒烟。路径含 roothide 隐根前缀，**一律用 `$HOME` 变量**。
