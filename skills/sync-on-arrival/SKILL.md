---
name: sync-on-arrival
description: Hard rule for ALL agents in this workspace, new or returning: the moment a conversation starts or resumes work, it MUST first sync/align with the other running agents (report what it is about to do, ask what they are doing, confirm file ownership) BEFORE touching code, device, or dispatching work. Hub (f8fbdbd5) collects and merges. Read at every session start.
---

# 上线即对齐（新机器人 / 老机器人复工的第一硬规矩）

用户 2026-10-31 13:25 定，**所有对话、所有工程永久适用**（原话：「补充一个硬性规则所有新上线的和老上线的机器人第一时间要和别的机器人同步对齐工作进展这个写入本地技能包和上传云端」）。

## 铁律
**任何机器人（新开的对话、或复工的老对话）开工的第一件事，是与其它在跑的机器人同步对齐工作进展**——在对齐完成前，不许改码、不许动设备、不许派活。上线就闷头干 = 重复劳动 + 撞文件 + 挤爆注销窗口。

## 开工对齐三步（顺序固定）
1. **报到**：用 `apelin_conversation_send` 向**统一调度台**（当前 = `f8fbdbd5-7f8c-402e-820f-73b6872c394b`「继续操作」）发三行：**我是谁 · 我要干什么 · 我要改哪些文件**。
2. **对账**：读调度台回的总表（AGENTS.md「统一调度台」章节 = 权威版：分工 / 版本号占用 / 注销窗口 / 已出包指纹 / 冻结清单），确认自己要改的文件**没有**别的写者（一文件一写者），要用的版本号没被占（已发布的不复用）。同时 `apelin_memory_list` 读自上次以来的新结论与新冻结指令。
3. **回执**：给调度台一句「已对齐，按 XX 干」，然后才动手。调度台若有更正（归属、冻结、版本号），**以调度台为准**。

## 调度台侧（hub）的对齐职责
- 收到报到后，把总表发回（AGENTS.md「统一调度台」章节就是权威版）；
- 新线要改的文件已有写者 → 当场指定归属或改派；
- 新线要动设备 → 告知当前注销窗口与排队规则；
- 广播全员「有新成员上线 + 它的活」。

## 老机器人复工（注销回来 / 用户切回 / 从 ended 唤醒）
同样走三步，但第 2 步必须先读 `AGENTS.md` + `apelin_memory_list`——**别按自己上次记的状态继续干**，中途排程可能已经变了（本工作区实测：角标从「修」到「冻结」只隔了一小时）。

## 已有相关规矩（并行适用）
- 注销四步（`respring-cross-team-notify`）：全员通知 → 正文知情 → 弹窗点头 → 当轮确认。
- 一文件一写者（AGENTS.md 分工表）：越界前先问调度台。
- 发不进去先查 state（记忆「跨对话同步」）：别把发送失败当 ended。
- 离开 Apelin 取证 60 秒上限：必须自己回来。
