---
name: notify-before-git-push
description: 向用户 GitHub 仓库 push 前，必须用灵动岛弹窗让用户确定开 VPN（GitHub 国内 DNS 污染不能直连）；push 成功=VPN 通=只发胶囊；push 失败要胶囊提醒。所有对话、所有工程适用。
---

# push 前必须弹窗让用户确定开 VPN

用户 2026-10-31 15:48 / 15:50 / 15:51 / 15:53 / 15:56 / 16:00 / 16:02 定，**所有对话、所有工程永久适用**（原话：「需要上传到我的 github 仓库时你跟我说一下！我开 VPN」「因为 GitHub 在国内访问、经常因为 DNS 污染不能直接访问！必须开 vpn 才行！」「不能访问我的仓库时给我说一声你来个通知或者弹窗让我知道这个！」「无论任何界面都要给我一个通知或者弹窗」「你判断能上我的仓库时就说明 VPN 应该是通的就不要给我弹窗了只给一个灵动岛通知也行」「让我开vpn的话必须给我弹窗、让我确定这个！」）。

## 铁律

**GitHub 在国内被 DNS 污染，不能直连，必须开 VPN。** 本机实测（2026-10-31 15:4x）：github.com 普通 HTTPS（NSData / icli probe / apelin_web_fetch）有时能通，但 Apelin 的 `git_push` 走另一条网络路径，不开 VPN 就反复报 `failed to connect to github.com: Operation timed out` / `SecureTransport error OSStatus -9806`，开 VPN 后立刻恢复。

**判断 VPN 通没通唯一可靠办法 = 直接试 push**（普通 HTTPS 通不代表 push 通）。没有读系统 VPN 开关的工具。

## 做法（顺序固定）

1. **提交前**：本地改动先 `git_commit`（本地操作，不联网，随时可做）。
2. **push 前 → 必须弹窗让用户确定开 VPN（2026-10-31 16:02 加）**：
   - 写灵动岛**确认弹窗**（`?` 模式，让用户在屏幕上点确定）：
     ```sh
     printf '%s|120|?要推送 GitHub 请开 VPN|<sid>' "$(date +%s)" > /rootfs/var/mobile/Library/Preferences/.countdownhud-request
     ```
     或 `sh scripts/respring-guard.sh --ask 120 "要推送 GitHub 请开 VPN"`。
   - 同时正文写清「要推送了，请开 VPN」。
   - **必须弹窗让用户点确定**，不能只发纯文案胶囊或 `apelin_notification_send`（那些不让人「确定」）。
   - 用户点「确定」后（答案文件 `.countdownhud-answer` = confirm）再 push。
3. **push 后（2026-10-31 16:00 加）**：
   - **能连上仓库 / push 成功 = VPN 通 → 不必弹窗，只发一条灵动岛胶囊** `sh scripts/hud-notify.sh 8 "!已推送到 GitHub"` 知会即可，不再弹窗、不发通知。
4. **push 失败**（网络错误 failed to connect / Operation timed out / OSStatus -9806）：
   - 正文说清 + 胶囊 `sh scripts/hud-notify.sh 8 "!push 失败，请开 VPN"`；**不许静默失败、不许空转重试**。
   - 等用户确认 VPN 就绪再重试。

## 弹窗与胶囊的分工（别搞混）

| 场景 | 用什么 |
| --- | --- |
| **需要用户「确定/点头」**（开 VPN、注销、装包） | **灵动岛确认弹窗 `?` 模式**（respring-guard.sh --ask），用户点确定 |
| **只是知会进度/结果**（push 成功、任务完成） | 纯文案胶囊 `hud-notify.sh`（`!` 前缀） |

## 边界

- `git_commit` 本地提交不受限（不联网）。
- `git_push` 到 GitHub 前必须弹窗让用户确定开 VPN；push 成功只发胶囊；push 失败才提醒。
- 其它联网操作（apelin_web_fetch 读 GitHub、icli probe 下载 Release 资产）超时，同样提示用户检查 VPN/DNS。

## 与其它技能的关系

- `notify-any-screen`：灵动岛胶囊/弹窗跨任何界面；`apelin_notification_send` 只在 Apelin 退后台时显示、不能当唯一手段。
- `respring-confirm-via-island-popup`：`?` 弹窗的技术细节（请求文件、答案文件、CountdownHUD 1.6.1 spawn sbreload）。
- `subagent-change-review`：子机器人改动提交前先核实，本技能是「核实通过、commit 之后、push 前后」那一步。
