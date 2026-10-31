---
name: tweak-skill-capture-standard
description: 工作区技能库与记忆的管理规范：成功结果要沉淀成技能并上传云端；写之前先读同类，凡一样的问题/内容/规定一律合并精简压缩到已有条目（技能补进同类、记忆更新已有记录、AGENTS.md 并入对应章节），减少占用，不留重复。所有对话、所有工程适用。
---

# 技能沉淀规范（工作区长期技能库的标准）

用户 2026-10-31 定的**永久规矩**（所有对话、所有工程）：**全工作区和全员的成功技能都必须写进本地技能包并上传云端**，形成长期技能库与记忆，既是以后修同类问题的参考，也是别的问题排查/修复/优化技能的**参考规范**。只改代码、只回结论不沉淀 = 没做完。

## 0. 铁律：合并精简，不留重复（2026-10-31 15:58 加）

用户原话：「凡是一样的问题和内容和规定合并精简压缩到一起减少占用 也写进本地技能、记忆以及硬性规定同时上传到云端」。

**凡是一样的/同类的问题、内容、规定，一律合并精简压缩到已有条目，不另起新条目、不留重复。**
- **技能**：先 `apelin_skill_list` + `apelin_skill_read` 看有没有同类，有就**补进那一个**（`replace: true` 更新），不另起新技能；只有真正是新的「一类事」才新建。
- **记忆**：先 `apelin_memory_list` 找同类，有就**更新那一条**（带 revision），不新增记录；记忆满 64 条/32768 字节时**先合并过时项再写**，绝不盲重试。
- **硬性规定（AGENTS.md）**：同类条文**并入已有章节**（往那一条下面加子项），不新开重复段落；措辞尽量精简、只留「何时用+怎么做」，砍掉重复的解释。
- 目的：减少记忆库/技能库/AGENTS.md 的占用，别让同一条规矩在多处各写一份、越滚越大。

## 1. 什么结果值得写成技能
以下任一**成功后**就该沉淀（不局限于一次性修好）：
- tweak 业务 bug 修复（如角标双层、布局不保存、Sileo 搜索框死区）；
- 诊断 / 定位方法（如「磁盘新版但诊断旧版先查进程启动时间」「分轮取证定位触摸死区」）；
- 云编译 / CI 纪律（如「报 CI 状态前重查」「用 compare API 证 Release 纯度」）；
- 跨对话协调 / 注销 / 装包安全规矩（如「注销四步」「ended 对话用 url open 重开」）；
- 反复踩的环境坑（如 roothide jbroot 前缀会变、隐根上 rootless deb 闪退修法）。
判断标准：**这件事下次还会遇到、且值得别人照着做** → 写技能；纯一次性操作不写。

## 2. 怎么写一个好技能
- **先读后写，不复读、不另起**：动手前 `apelin_skill_list` + `apelin_skill_read` 看有没有同类，有就补、不另起（见 §0）。
- **描述即入口**：`apelin_skill_save` 的 description 一句话说清「何时用它」，让以后每个对话的 `apelin_skill_list` 一眼命中；要含关键词（tweak / 注销 / 云编译 / 排查 …）。
- **SKILL.md 结构固定**：① 背景（用户原话/场景）② 触发条件（什么时候读它）③ 做法（步骤+命令+路径，路径只写相对/运行时解析，见技能 `a11-roothide-ondevice`）④ 验收/证据（怎么算做对了）⑤ 与其他技能的关系（去重、引用）。
- **一个技能一件事**，别把不相关的修法捆一起。

## 3. 库的物理布局（三样一致）
| 内容 | 本机（Apelin 读） | 云端（仓库） |
| --- | --- | --- |
| 技能包 | `~/Documents/wiki.qaq.apelin/skills/<name>/SKILL.md` | 仓库 `skills/<name>/SKILL.md` |
| 记忆（用户偏好/跨工程事实） | `~/Documents/wiki.qaq.apelin/memories.json` | 仓库 `memory/memories.json` |
| 硬性规定 | 工程 `AGENTS.md` | 仓库根 `AGENTS.md` |
| 专项案例复盘 | — | 仓库 `docs/cases/<name>.md` |

**同步一把**：`sh scripts/sync-all.sh`（或 `sync-skills.sh`/`sync-memory.sh`）→ `git_commit(all:true)` → `git_push` 到 `main`，**不留本机新、云端旧**的半截状态。

## 4. 技能 vs 记忆的分工
- **技能** = 方法/流程/怎么做的（可被以后对话照做）；描述让 `apelin_skill_list` 命中。
- **记忆** = 用户持久偏好、跨工程事实、当前设备/版本状态（global 或 project 作用域）；`apelin_memory_list` 读、`apelin_memory_save` 写，满 64 条先合并过时项再写。

## 5. 现有库（示范）
本规范就是库的管理标准；已沉淀的示范：`verify-cloud-release`（CI 纪律）、`respring-cross-team-notify`（注销四步）、`sileo-searchbar-deadzone-fix`（触摸死区定位）、`icli-status-self-check`（状态自己查）、`injected-tweak-restart-app`（注入不必注销）。每个新技能都应是这类「可复用方法」，而不是流水账。
