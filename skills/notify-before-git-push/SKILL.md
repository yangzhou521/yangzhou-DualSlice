---
name: notify-before-git-push
description: 向用户 GitHub 仓库 push 前，用通知或灵动岛弹窗告诉用户开 VPN（GitHub 国内 DNS 污染不能直连），等确认后再 push；push 失败也要通知/弹窗。所有对话、所有工程适用。
---

# push 前用通知/弹窗告诉用户开 VPN；失败也要通知

用户 2026-10-31 15:48 / 15:50 / 15:51 / 15:53 定，**所有对话、所有工程永久适用**（原话：「需要上传到我的 github 仓库时你跟我说一下！我开 VPN」「因为 GitHub 在国内访问、经常因为 DNS 污染不能直接访问！必须开 vpn 才行！」「不能访问我的仓库时给我说一声你来个通知或者弹窗让我知道这个！」「通知和弹窗都行让我知道啊」）。

## 铁律

**每次要向用户的 GitHub 仓库 push（`git_push`），动手前必须用通知或灵动岛弹窗让用户知道「要推送了，请开 VPN」，等用户确认后再 push。**

**push 失败 / 不能访问仓库时，同样必须用通知或弹窗让用户知道。**

通知和弹窗二选一即可，但**不能只写在对话正文**——正文只在 Apelin 前台时可见，用户切去别的对话/桌面/别的 App 就看不到。通知（`apelin_notification_send`）和灵动岛胶囊（`scripts/hud-notify.sh`）能在他离开 Apelin 时也让他看见。

## 原因（写进硬性规定）

**GitHub 在国内被 DNS 污染，不能直连，必须开 VPN。** 本机实测（2026-10-31 15:4x）：
- github.com 普通 HTTPS（NSData / icli probe / apelin_web_fetch）有时能通，
- 但 Apelin 的 `git_push` 走另一条网络路径，不开 VPN 就反复报
  `failed to connect to github.com: Operation timed out` / `SecureTransport error OSStatus -9806`，
- 用户开 VPN 后立刻恢复。

## 做法（顺序固定）

1. **提交前**：本地改动先 `git_commit`（本地操作，不联网，随时可做）。
2. **push 前通知/弹窗**：
   - 正文写清「现在要推送 <内容> 到 <owner/repo>，GitHub 国内被 DNS 污染，请开 VPN」；
   - 同时 `apelin_notification_send`（短标题「要推送了」+ 「请开 VPN，开好回我一声」）；
   - 或写灵动岛胶囊 `sh scripts/hud-notify.sh 8 "!要推送 GitHub 了，请开 VPN"`。
   - 通知和弹窗至少发一个，别只靠正文。
3. **等用户确认**：用户回「开了 / 继续 / 推送」后再 `git_push`。
4. **push 失败 → 再通知/弹窗**：报网络错误时，正文说清 + 通知/胶囊「push 失败，请检查 VPN」；
   **不许静默失败、不许空转重试**。等用户确认 VPN 就绪再重试。
5. **push 成功 → 也可发一条通知**告知已上云端（可选，但用户 15:53 表示「让我知道」，建议做）。

## 边界

- `git_commit` 本地提交不受限（不联网）。
- `git_push` 到 GitHub 才需要先通知/弹窗告知开 VPN。
- 其它联网操作（apelin_web_fetch 读 GitHub、icli probe 下载 Release 资产）如果也超时，同样提示用户检查 VPN/DNS。

## 与其它技能的关系

- `subagent-change-review`：子机器人改动提交前先核实，本技能是「核实通过、commit 之后、push 之前」那一步。
- `load-all-skills-memory-repos`：三样同步后的 `git_push` 同样受本技能约束。
