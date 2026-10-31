---
name: notify-before-git-push
description: 访问 GitHub 仓库（push）时：先自己直接试 push，通了就直接做（只发胶囊知会）；不通才用弹窗/胶囊请用户开 VPN。绝不在 push 前就让用户先开 VPN。GitHub 国内 DNS 污染需 VPN。所有对话、所有工程适用。
---

# push 前先自己试，不通才请用户开 VPN

用户 2026-10-31 15:48 / 15:50 / 15:51 / 15:53 / 15:56 / 16:00 / 16:02 / 16:48 / 16:51 定，**所有对话、所有工程永久适用**（原话：「需要上传到我的 github 仓库时你跟我说一下！我开 VPN」「因为 GitHub 在国内访问、经常因为 DNS 污染不能直接访问！必须开 vpn 才行！」「不能访问我的仓库时给我说一声你来个通知或者弹窗让我知道这个！」「无论任何界面都要给我一个通知或者弹窗」「你判断能上我的仓库时就说明 VPN 应该是通的就不要给我弹窗了只给一个灵动岛通知也行」「让我开vpn的话必须给我弹窗、让我确定这个！」「你需要访问仓库时『检测 VPN』直接试 push 如果不通的话才要求我开弹窗接收或者看看灵动岛显示！不要不试直接让我开 VPN！」）。

## 铁律（顺序别颠倒）

**要 push 时，先自己直接试 push；试通了就直接干（只发胶囊知会），不通才请用户开 VPN。**

**绝不能在 push 前就让用户先开 VPN**（2026-10-31 16:51 用户明确纠正：不要不试直接让开）。

## 做法（顺序固定）

1. **提交前**：本地改动先 `git_commit`（本地，不联网）。
2. **直接试 push**（不要先让用户开 VPN）：
   - 直接 `git_push`，看结果。
3. **push 成功** = 网络通 = **只发一条纯文案胶囊** `sh scripts/hud-notify.sh 8 "!已推送到 GitHub"` 知会，不弹窗、不发通知、不请开 VPN。
4. **push 失败**（网络错误 `failed to connect` / `Operation timed out` / `SecureTransport OSStatus -9806`）：
   - 这时才请用户开 VPN：写灵动岛**确认弹窗**（`?` 模式）或纯文案胶囊 `sh scripts/hud-notify.sh 8 "!push 失败，请开 VPN"` + 正文说清；
   - **绝不用 `?` 注销弹窗来做「请开 VPN」**（`?` = 注销确认弹窗，按钮「立即注销」会真 spawn sbreload，2026-10-31 16:06 血的教训）；
   - 不许静默失败、不许空转重试；等用户确认 VPN 就绪再重试。

## 判断 VPN 通没通的唯一可靠办法

**直接试 push**。没有读系统 VPN 开关的工具（那是系统隐私，mobile 读不到）。普通 HTTPS（NSData/icli probe/web_fetch）能通**不代表** push 通（两条不同路径），所以别拿「能访问 github.com」当「VPN 开了」的证据——只有 push 结果算数。

## 弹窗/胶囊/注销的分工

| 需求 | 用什么 | 前缀 |
| --- | --- | --- |
| 知会（push 成功、任务完成） | 纯文案胶囊 `hud-notify.sh` | `!` |
| 需要用户点「立即注销」的设备动作（注销/装包） | 注销确认弹窗 `respring-guard.sh --ask` | `?` |
| 请用户开 VPN（push 失败后） | 纯文案胶囊 或 对话告知 | `!`（不是 `?`） |

## 与其它技能的关系

- `notify-any-screen`：胶囊跨任何界面；`apelin_notification_send` 只在 Apelin 退后台时显示。
- `respring-confirm-via-island-popup`：`?` 只用于真注销/装包，与「请开 VPN」无关。
- `subagent-change-review`：子机器人改动提交前先核实，本技能是「核实通过、commit 之后、push」那一步。
