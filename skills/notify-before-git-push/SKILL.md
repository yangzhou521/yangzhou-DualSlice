---
name: notify-before-git-push
description: 向用户的 GitHub 仓库 push（git_push）之前，必须先告诉用户「现在要推送了」，等用户开了 VPN / 网络就绪并确认后，再执行 push。push 反复超时/网络错误时，提示用户检查 VPN。所有对话、所有工程适用。
---

# push 前先告诉用户开 VPN

用户 2026-10-31 15:48 定，**所有对话、所有工程永久适用**（原话：「需要上传到我的 GitHub 仓库时你跟我说一下！我开 VPN」）。

## 铁律

**每次要向用户的 GitHub 仓库 push（`git_push`），动手前必须先告诉用户，等用户确认网络（VPN）就绪再 push。**

不要静默 push；不要因为「上一轮 push 成功过」就跳过告知。

## 做法（顺序固定）

1. **提交前**：本地改动先 `git_commit`（commit 是本地操作，不联网，随时可做）。
2. **push 前告诉用户**：在对话正文写一句「现在要把 <commit 内容> 推送到你 GitHub 仓库 <owner/repo>，请开一下 VPN，开好了回我一声（或直接说 继续/推送）」。
3. **等用户确认**：用户回复「开了 / 继续 / 推送」后，再执行 `git_push`。
4. **push 失败处理**：报「failed to connect / Operation timed out / OSStatus -9806（TLS 握手失败）」这类网络错误时，**先不空转重试**——告诉用户「推不上去，像是网络不通，麻烦确认下 VPN」，等用户确认后再重试。别连着重试十几次。

## 边界

- `git_commit` 本地提交不受此限（不联网）。
- `git_push` 到 GitHub 才需要先告知开 VPN；本地其它联网操作（apelin_web_fetch 读 GitHub、icli probe 下载 Release 资产）如果也超时，同样提示用户检查网络/VPN。
- 用户明确说过「以后 push 直接推，不用每次问」时，才可省略告知——否则每次都要先告知。

## 为什么

本机实测（2026-10-31 15:4x）：github.com 普通 HTTPS（NSData）能通，但 Apelin 的 `git_push` 反复报 `failed to connect to github.com: Operation timed out` / `SecureTransport error OSStatus -9806`，用户开了 VPN 后立刻恢复正常。push 走的是不同网络路径，需要 VPN 才能稳定连通。

## 与其它技能的关系

- `subagent-change-review`：子机器人改动提交前先核实，本技能是「核实通过、commit 之后、push 之前」的那一步。
- `load-all-skills-memory-repos`：三样同步（AGENTS.md + skills/ + memory/）后的 `git_push` 同样受本技能约束。
