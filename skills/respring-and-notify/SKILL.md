---
name: respring-and-notify
description: 注销（sbreload）、装包、请开 VPN 前怎么让用户真正知情并确认：屏幕弹窗 + 灵动岛胶囊 + 正文三通道，倒计时 5 秒，注销前先和别的对话同步、先查崩溃循环、装完 SpringBoard 插件必查 crash list；含「通知看不见」「胶囊不显示」「点了没注销」全部实测坑。任何工程、任何对话适用。
---

# 注销与知情：三个通道 + 五步 + 实测坑

**任何工程、任何对话适用。** 合并自原 `respring-confirm-via-island-popup`、`respring-cross-team-notify`、
`respring-hub-merge-dispatch`、`respring-notify-countdown` 四个技能。

用户反复强调过：「注销前用户确认点击的弹窗对话框为什么现在我没有收到实际落地」「安全模式了！注销又没通知我！多少次了！」

## 一、三个通道，各自能不能当「用户已知情」

| 通道 | 什么时候可见 | 能否当已知情 |
|---|---|---|
| **聊天回复正文** | 永远 | ✅ 必须写清「N 秒后注销 / 为什么 / 下一步」 |
| **灵动岛胶囊**（CountdownHUD） | 用户在看桌面或别的 App 时 | ✅ 唯一能跨 App 的通道 |
| **灵动岛弹窗**（`?` 请求） | 任何界面，层级压过一切 | ✅ 用户点了才动，最强的确认 |
| `apelin_notification_send` | 只在 Apelin **不在前台**时 | ❌ 发它这一下会把 Apelin 拉回前台，横幅被自己吞掉 |

**铁律：不靠通知当知情手段。** 用户盯着 Apelin 看你干活时，通知等于不存在。

## 二、五步，顺序不能变

**第 0 步：先和别的对话同步**（用户 2026-10-30 21:05 定）。
`apelin_project_list` + 对每个工程 `apelin_conversation_list`，把 `running` / `waitingForApproval` 挑出来；
逐个 `apelin_conversation_send` 说清「约 N 秒后注销，原因 X，请收尾」；`apelin_conversation_read`
（`wait_seconds: 60`）等它这一回合结束。**绝不 `apelin_conversation_stop`。** 超过 120 秒没结束就不硬注销，让用户决定。
细则见 `cross-chat-coordination`。

**第 1 步：前置检查崩溃**。`apelin_crash_list process=<目标进程>`；
`consecutiveCrashCount ≥ 2` 或这次启动就崩过 → **不许注销**，先停用插件救设备。

**第 2 步：发通知 + 正文写清「N 秒后做什么」**（≤3 条/回合，间隔 ≥30 秒）。

**第 3 步：弹窗问**。`sh scripts/respring-guard.sh --ask <秒> <标签>`。
屏幕上是 iOS 同款对话框（标题「⚠️ 即将注销」，按钮「取消」/「立即注销」）。
退出码：`0`=确认 / `4`=用户点了取消 / `5`=超时 / `6`=请求写不出去。
**取消或超时 = 什么都不做，不算拒绝**，下一轮继续提。

**第 4 步：5 秒倒计时后注销**。用户点头后走 `--confirm 5`。倒计时一律 5 秒，别擅自改。

**装包与注销已分家**（2026-11-05 22:57 用户定「装包不注销，装完弹窗由我决定」）：
`scripts/install-deb.sh` 只装；装完 `scripts/post-install-respring.sh` 单独弹窗问注销。

## 三、五种动作，两种规矩

**要让用户知情的**：装/升级 deb、注销、重启目标进程、请开 VPN。
**不需要的**：下载、云编译、读诊断、改源码、跑探针。

**先别注销的情况**：注入型插件装好后，App 类 `device.sh kill` + `launch` 就完成注入；
设置面板退出再进。**只有**插件注入 SpringBoard（桌面图标、HUD、控制中心）或改了过滤器 plist 才真注销。
细则见 `injected-tweak-restart-app`。

## 四、实测坑（都踩过）

**坑 1：通知看不见。** `apelin_notification_send` 返回 Sent 也没用 —— 发它这一下 0.35 秒内 Apelin 被拉回前台
（进程号不变，不是重启），自己的 `UNUserNotificationCenterDelegate` 把横幅吞掉。DynamicX 没有 App 黑白名单，
微信能上岛、Apelin 不能，不是设置问题。所以 CountdownHUD 这个自绘 HUD 才是可靠通道。

**坑 2：胶囊不显示（HUD v1.3.0 已修）。** 老代码量不到 windowScene 时退回 `[[UIWindow alloc] initWithFrame:]`，
iOS 13+ 里没有 scene 的窗口**完全不参与渲染**：窗口、子视图、`isHidden=NO`、`shows` 全正常，屏幕上一个像素都没有。
判活：`sh scripts/device.sh read com.apple.springboard CountdownHUDDiagnostics` —— `scene` 必须是 `UIWindowScene`；
`islandWin=…|lvl=…` 必须**小于**自己窗口的 `lvl`；`shows` 必须比上次大。

**坑 3：点了「立即注销」却没注销。** 老版本插件只写 `confirm` 文件，靠前台轮询的 shell 执行；
shell 一结束就没了。CountdownHUD 1.6.1 起插件自己 `posix_spawn` 注销（`dladdr` 取自己 dylib 路径推 jbroot，
**绝不写死路径**），诊断 `exec=spawned|skip-marker|term|fail|-`。
`.countdownhud-no-respring` 存在时只写答案不注销 —— `NO_RESPRING=1` 验法靠它转达，**忘了删 = 以后所有注销都不生效**。

**坑 4：注销后读到旧版本号 ≠ 没加载。** cfprefsd 缓存：新进程还没重写诊断键，读到的是上一进程的旧值。
判活要发一条探针请求看 `shows` 涨不涨。同理 `icli probe` 跑的是它自己的进程，里面查 `CHWindow` /
`SBIconController` 一律 `N`，**不是「插件没注入」的证据**。

**坑 5：`--ask` 的 shell 超时预算。** `--ask` 阻塞到用户答复（最多 `WAIT+5`），再走 `WAIT` 秒倒计时，
总耗时 ≈ `2*WAIT+5`。`shell_run` 的 `timeout_seconds` 必须大于这个数，否则被杀在倒计时中途，
用户点了却没注销。更稳：`--ask` 给短 WAIT（30~45 秒），点完另用 `--confirm 5`。

## 五、装完 SpringBoard 插件必查崩溃

```sh
apelin_crash_list process=SpringBoard
#  有比本次注销更新的报告 → 装坏了，先 irisin-cli remove 回滚
#  没有新报告 → 才算装好
```

**构造函数阶段铁律**：只准碰 Foundation，不准碰任何 UIKit API；`@try/@catch` 救不了
（`NSAssertionHandler` 走 `abort`）。案例：`docs/cases/countdownhud-safe-mode.md`、
`docs/cases/springboard-safemode-0.9.21.md`。

## 六、已经进了安全模式

安全模式 = 目标进程崩过，ellekit 起了不加载 tweak 的进程。**不要反复注销重试**，每试一次都是黑屏 + 一次崩溃。
顺序永远：读崩溃报告 → 定位 → 改代码 → 云编译 → 装 → 才注销。
安全模式下胶囊与弹窗都不显示 → 只走正文 + `apelin_notification_send`（真系统通知，实测可用），
装包用 `install-deb.sh`（打印 `SAFEMODE_DIRECT`，只装不注销）。**注销是退出安全模式的唯一办法。**

## 七、汇报要求

写清：通知了什么、正文有没有写「N 秒后」、倒计时了没有、查崩溃了没有、**注销后 crash list 有没有新报告**。
没做就明说没做。
