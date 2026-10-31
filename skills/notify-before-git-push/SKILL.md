---
name: notify-before-git-push
description: 向用户 GitHub 仓库 push 前后用灵动岛胶囊告知；GitHub 国内 DNS 污染必须开 VPN。判断「能连上仓库（push 成功/能访问 GitHub）」就说明 VPN 通，此时不必弹窗，只发一条灵动岛胶囊即可。所有对话、所有工程适用。
---

# push 前后用灵动岛胶囊告知；VPN 通了就不必弹窗

用户 2026-10-31 15:48 / 15:50 / 15:51 / 15:53 / 15:56 / 16:00 定，**所有对话、所有工程永久适用**（原话：「需要上传到我的 github 仓库时你跟我说一下！我开 VPN」「因为 GitHub 在国内访问、经常因为 DNS 污染不能直接访问！必须开 vpn 才行！」「不能访问我的仓库时给我说一声你来个通知或者弹窗让我知道这个！」「通知和弹窗都行让我知道啊」「无论任何界面都要给我一个通知或者弹窗」「你判断能上我的仓库时就说明 VPN 应该是通的就不要给我弹窗了只给一个灵动岛通知也行」）。

## 铁律

**GitHub 在国内被 DNS 污染，不能直连，必须开 VPN。** 本机实测（2026-10-31 15:4x）：github.com 普通 HTTPS（NSData / icli probe / apelin_web_fetch）有时能通，但 Apelin 的 `git_push` 走另一条网络路径，不开 VPN 就反复报 `failed to connect to github.com: Operation timed out` / `SecureTransport error OSStatus -9806`，开 VPN 后立刻恢复。

**判断 VPN 通没通的唯一可靠办法 = 直接试 push**（普通 HTTPS 能通不代表 push 通，两条路径不同）。没有读系统 VPN 开关的工具。

## 做法（顺序固定）

1. **提交前**：本地改动先 `git_commit`（本地操作，不联网，随时可做）。
2. **push 前**：发一条**灵动岛胶囊** `sh scripts/hud-notify.sh 8 "!要推送 GitHub 了，请开 VPN"` + 正文写清，等用户回「开了/继续/推送」再 push。
3. **push 后（关键，2026-10-31 16:00 加）**：
   - **能连上仓库 / push 成功 = VPN 是通的 → 不必弹窗，只发一条灵动岛胶囊** `sh scripts/hud-notify.sh 8 "!已推送到 GitHub"` 告知即可。
   - 不必再发 `apelin_notification_send`，更不必弹窗确认——VPN 通了就静默完成，只留一条胶囊知会。
4. **push 失败**（网络错误 failed to connect / Operation timed out / OSStatus -9806）：
   - 正文说清 + 胶囊 `sh scripts/hud-notify.sh 8 "!push 失败，请开 VPN"`；**不许静默失败、不许空转重试**。
   - 等用户确认 VPN 就绪再重试。

## 边界

- `git_commit` 本地提交不受限（不联网）。
- `git_push` 到 GitHub 才需要先发胶囊告知；push 成功只发胶囊、不弹窗；push 失败才需要提醒。
- 其它联网操作（apelin_web_fetch 读 GitHub、icli probe 下载 Release 资产）超时，同样提示用户检查 VPN/DNS。

## 与其它技能的关系

- `notify-any-screen`：灵动岛胶囊跨任何界面（Apelin 内/桌面/别的 App 都盖得住），`apelin_notification_send` 只在 Apelin 退后台时显示、不能当唯一手段。
- `subagent-change-review`：子机器人改动提交前先核实，本技能是「核实通过、commit 之后、push 前后」那一步。
- `load-all-skills-memory-repos`：三样同步后的 `git_push` 同样受本技能约束。
