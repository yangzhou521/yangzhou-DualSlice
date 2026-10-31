---
name: respring-hub-merge-dispatch
description: After a respring or any restart, the user returns to the hub conversation (f8fbdbd5); that conversation merges all running lines' status, dedups, reconciles, and issues the unified work plan. Every other line only executes and reports to it, never coordinates peer-to-peer. Read this when work resumes after a device restart or when you need to hand off consolidated status.
---

# 注销后统一调度（hub 合并排程）

用户 2026-10-31 定的**永久规矩**（所有对话、所有工程）：注销（或任何离线/重启）回来后，
用户会回到**统一调度台**对话 `f8fbdbd5-7f8c-402e-820f-73b6872c394b`（标题「继续操作」），
由它做**全员信息的合并、整合、统一工作安排**。

## 1. 角色分工
- **统一调度台（f8fbdbd5）** = 唯一汇总点：注销回来后各在跑对话把进度/结论/卡点汇报给它，
  它去重、对账（谁在跑/谁出事/谁要注销）、给出统一下一步，并负责再次注销前的全员通知
  （见技能 `respring-cross-team-notify`）。
- **各在跑对话（18b20213/3e983c10/6c78afa4/157b2985/5781b4c7 …）** = 只执行本线任务并
  向调度台汇报，不互相等待、不两两协调、不重复发全员通知。

## 2. 回来后的收口流程（调度台做）
1. 用 `apelin_conversation_list` 看哪些 `state=open`，用 `apelin_conversation_read`
   （`wait_seconds` 等收尾）收各线最新进度；ended 的用 `icli url open` 重开再读（见记忆
   「跨对话同步」）。
2. 去重：同一结论/同一文件改动只保留一处；用 `git fetch` + 云端 compare 核对版本锁与 HEAD
   （见技能 `verify-cloud-release`），别按记忆里的旧 sha 判断。
3. 整合：按「谁要注销/谁改了什么文件/谁卡住」出一张统一清单，给出下一轮统一排程。
4. 若需要再注销：严格走 `respring-cross-team-notify` 四步（先全员通知→正文知情→弹窗→
   用户当轮点头才 `--confirm`），**用户没在当轮明确说注销/确定，绝不动**。

## 3. 工具
- 读各线：`apelin_conversation_read`（`after_seq` 增量读，`wait_seconds` 等收尾）。
- 唤醒 ended：`icli url open apelin://conversation/<sid>`（批量后记得切回自己）。
- 对账：`sh scripts/fleet-live.sh <分钟>`（状态/alerts/ping）。
- 全权限查状态：`icli` / `irisin-cli` / GitHub API 自己查（见 `icli-status-self-check`），不推回用户。

## 4. 沉淀
本调度规则本身已入库（技能 `tweak-skill-capture-standard` 是库管理标准）；任何从「合并/对账/
收口」提炼的新做法按硬规矩写进本地技能包并同步云端。
