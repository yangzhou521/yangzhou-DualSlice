---
name: notify-before-git-push
description: 向用户 GitHub 仓库 push 前先告诉用户开 VPN（GitHub 国内 DNS 污染，不能直连）；push 失败/不能访问仓库时，必须用通知（apelin_notification_send）或弹窗让用户知道。所有对话、所有工程适用。
---

# push 前先告诉用户开 VPN；push 失败要通知/弹窗

用户 2026-10-31 15:48 / 15:50 / 15:51 定，**所有对话、所有工程永久适用**（原话：「需要上传到我的 github 仓库时你跟我说一下！我开 VPN」「因为 GitHub 在国内访问、经常因为 DNS 污染不能直接访问！必须开 vpn 才行！」「不能访问我的仓库时给我说一声你来个通知或者弹窗让我知道这个！」）。

## 铁律

**每次要向用户的 GitHub 仓库 push（`git_push`），动手前必须先告诉用户，等用户开 VPN 并确认后再 push。**

**push 失败 / 不能访问仓库时，必须用通知（`apelin_notification_send`）或灵动岛弹窗让用户知道**——不能静默失败、不能连着重试十几次不吭声。

## 原因（写进硬性规定）

**GitHub 在国内被 DNS 污染，不能直连，必须开 VPN。** 本机实测（2026-10-31 15:4x）：
- github.com 普通 HTTPS（NSData / icli probe / apelin_web_fetch）有时能通，
- 但 Apelin 的 `git_push` 走另一条网络路径，不开 VPN 就反复报
  `failed to connect to github.com: Operation timed out` / `SecureTransport error OSStatus -9806`，
- 用户开 VPN 后立刻恢复。

## 做法（顺序固定）

1. **提交前**：本地改动先 `git_commit`（本地操作，不联网，随时可做）。
2. **push 前告诉用户**：正文写「现在要把 <内容> 推送到你 GitHub 仓库 <owner/repo>，GitHub 国内被 DNS 污染，请开 VPN，开好回我一声（或说 继续/推送）」。
3. **等用户确认**：用户回「开了 / 继续 / 推送」后再 `git_push`。
4. **push 失败 → 必须通知/弹窗**：报网络错误（failed to connect / Operation timed out / OSStatus -9806）时，
   - **正文说清**「push 失败了，像是 DNS 污染 / VPN 没生效」；
   - 用 `apelin_notification_send` 发一条通知（短标题 + 「push 失败，请检查 VPN」）；
   - 或写灵动岛胶囊 `sh scripts/hud-notify.sh 8 "!push 失败，请开 VPN"`；
   - **不能静默失败、不能空转重试**。等用户确认 VPN 就绪再重试。

## 边界

- `git_commit` 本地提交不受限（不联网）。
- `git_push` 到 GitHub 才需要先告知开 VPN；push 失败才需要通知/弹窗。
- 其它联网操作（apelin_web_fetch 读 GitHub、icli probe 下载 Release 资产）如果也超时，同样提示用户检查 VPN/DNS。

## 与其它技能的关系

- `subagent-change-review`：子机器人改动提交前先核实，本技能是「核实通过、commit 之后、push 之前」那一步。
- `load-all-skills-memory-repos`：三样同步后的 `git_push` 同样受本技能约束。
