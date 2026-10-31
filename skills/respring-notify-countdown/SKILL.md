---
name: respring-notify-countdown
description: 注销、装 deb、重启目标进程前，必须先和本机其它工程/对话同步、别打断它们的工作（技能 cross-chat-coordination），再让用户真的看见「5 秒后执行」并倒计时；离开 Apelin 取证后必须自己回到 Apelin；注销前先查崩溃循环，避免把 SpringBoard 打进安全模式。任何工程、任何对话都适用；注销前必须先让用户在屏幕上真看见倒计时（回复正文 + 灵动岛胶囊；通知不算知情）。含「插件自己执行注销」的做法（CountdownHUD 1.6.1 起：确认后由插件 spawn sbreload，不再赌脚本还在前台等）、「注销后读到旧版本号 = cfprefsd 缓存 ≠ 没加载」的判活方法、以及 --ask 的 shell 超时预算。
---

# 通知 + 倒计时 5 秒，取证后回 Apelin

**任何工程、任何对话都适用。** 用户 2026-10-30 反复要求过（原话：「下次你安装插件注销的话！给我通知📢一下！」
「说好的倒计时五秒钟通知呢！给我一点准备也没有」「这个影响到我正常使用手机了！很严重！会丢失数据的！」
「安全模式了！注销又没通知我！多少次了！」）。

## 零、为什么会「通知了但用户没收到」（2026-10-30 11:05 事故，必读）

那一次我确实调了 `apelin_notification_send` 并返回 Sent，然后注销 —— 用户仍然什么都没看到，
而且注销把 SpringBoard 打进**安全模式**。三条硬事实：

1. **通知只在 Apelin 不在前台时可见。** 用户正盯着 Apelin 聊天看你干活时，通知等于不存在。
   → 所以「5 秒后注销」这句话**必须写进聊天回复正文**，那才是用户一定会看到的唯一位置。
2. 写过正文还不算，要**真的等**：`sh scripts/respring-guard.sh 5`（或 `sleep 5`），再执行。
3. 注销前不查崩溃循环，就会把设备反复打成安全模式（那次 `consecutiveCrashCount=7`）。
4. **（2026-10-30 11:36 实测，决定性）就在「发通知」这一下，Apelin 会被拉回前台**：
   `icli button home` 后前台是 `com.apple.springboard`，连测 6 次都稳定停在桌面；一调
   `apelin_notification_send`，0.35 秒内前台就变回 `wiki.qaq.apelin`，而进程号没变
   （前后都是 pid 56376，不是重启，是被拉到前台）。App 一在前台，它自己的
   `UNUserNotificationCenterDelegate` 就把横幅吞掉 —— 于是通知既不显示，也谈不上上岛。
   → **推论：不要指望通知能被用户看到。** 倒计时只能在聊天正文里，且必须真等；
     通知仍然照发（规矩不变、用户要求过），但把它当成「Apelin 不在前台时的一条补充」，
     绝不能当成「用户已经知道了」。

### 灵动岛（用户装的 DynamicX 1.5.1 + VisibleIsland）：Apelin 的通知不上岛

用户 2026-10-30 反复问「为什么微信能上岛、你的不行」。查过的事实：

- DynamicX hook 的是 SpringBoard 的横幅入口（`SBNotificationBannerDestination` /
  `BulletinDestinationBanner`），偏好里 `NotificationEnabled=true`、
  `NotificationSecondaryIslandEnabled=true`，**没有任何 App 白名单/黑名单**。
- 微信的通知正常上岛 → DynamicX 本身在这台机器上没问题。
- Apelin 的通知确实被系统投递（`/var/mobile/Library/UserNotifications/` 下会在发送时刻
  新建一条 section 记录），但它是**本地即时通知**，且发通知时 App 被拉回前台（见上面第 4 条），
  横幅根本没进 SpringBoard 的横幅通道 → DynamicX 没有东西可接。
- 结论：**这不是 DynamicX 的 bug，也不是能靠改设置修好的**。要让倒计时上岛，只有两条路：
  ① 自研一个 SpringBoard 侧的自绘倒计时 HUD（`scripts/respring-guard.sh` 发请求触发，
     5 秒胶囊在屏幕顶部，不依赖 Apelin 通知）—— **已实现，即 CountdownHUD**；② 反馈给 Apelin 修通知投递。

## 零、五、注销前先和别的对话同步（用户 2026-10-30 21:05 定的硬规矩）

原话：「你注销的话和另一个对话说一下！不要打断它的工作！把这个写进记忆和技能包内！并同步到云端！以后所有的
对话和工程在工作时想要注销的时候都要查看搜索另外一些工作区的对话是否在工作！注销前要和别的对话同步一下！」

- `apelin_project_list` + 对每个工程（含本工程）`apelin_conversation_list project: <folder>`，
  把 `running` / `waitingForApproval` / 最近几分钟内有活动的对话挑出来（本对话排除）。
- 对每一个用 `apelin_conversation_send` 说清「约 N 秒后注销，原因 X，请把当前这一步收尾、离开 Apelin 的先自己回来」，
  再用 `apelin_conversation_read`（`wait_seconds: 60`）等它这一回合结束。**绝不 `apelin_conversation_stop`。**
- 等超过约 120 秒仍没收尾：**不硬注销**，在回复正文说清「对话 A 还在做 X」让用户决定。
- 细则见技能 `cross-chat-coordination`。

## 零、六、先别注销：注入型插件把 App 划掉重开就生效（用户 2026-10-30 21:24 定的硬规矩）

原话：「这些注入型的插件在安装后 划掉后台重进软件和插件内就能实现功能完全注入！不必重新注销桌面！…
以后所有的对话和工程在工作时想要构建、修改、修复、编译插件的时候看看这个常识性的知识！」

- tweak 只在目标进程**启动时**加载，装包 / 改代码后**重启那个进程**就够了。
- App 类：`sh scripts/device.sh kill <bid>` + `launch <bid>`，或用户自己划掉再点开；设置面板退出再进。
- 只有插件本身注入 SpringBoard（桌面图标、HUD…）、或改了过滤器 plist / 包布局，才走注销的完整四步。
- 细则见技能 `injected-tweak-restart-app`。

## 零、七、注销前必须让用户**在屏幕上**真的看见（2026-10-30 23:42 事故的根因，必读）

用户 23:42 原话：「上次注销前用户还是不知情！这个根本性问题也是没解决！」

**「通知」不是知情通道，唯一可靠的知情通道是「用户的眼睛」。**

| 通道 | 什么时候可见 | 能不能当「用户已知情」 |
| --- | --- | --- |
| **聊天回复正文** | 永远 | ✅ 必须写清「N 秒后注销 / 为什么 / 下一步」 |
| **灵动岛胶囊**（CountdownHUD） | 用户在看桌面 / 别的 App 时 | ✅ 唯一能跨 App 的通道 |
| `apelin_notification_send` | 只在 Apelin **不在前台**时 | ❌ 发它这一下会把 Apelin 拉回前台，横幅被自己吞掉 |

**根因（HUD v1.3.0 已修）**：老代码量不到 windowScene 时退回 `[[UIWindow alloc] initWithFrame:]`，
而 iOS 13+ 里**没有 windowScene 的窗口完全不参与渲染**：窗口对象、子视图、`isHidden=NO`、`shows` 都正常，
屏幕上一个像素都没有 —— 「发了通知 + 写了正文 + 真等 5 秒」全做了，用户仍毫不知情。
v1.3.0 起拿不到 scene 就不显示、不消费请求（0.5 秒后重试）；窗口一律 `initWithWindowScene:`。

**动注销之前先确认胶囊真的显示了**：

```sh
sh scripts/respring-guard.sh 5 注销          # 只警告、不注销（退出码 3）
sh scripts/respring-guard.sh --confirm 5 注销  # 用户已明确答应后：倒计时 5 秒 + sbreload
sh scripts/device.sh read com.apple.springboard CountdownHUDDiagnostics
#   …;shows=N（必须比上一次大）;…;win=CHWindow|scene=UIWindowScene|lvl=20000000;islandWin=…|lvl=…
```

- `scene` 必须是 `UIWindowScene`；`-`/空 = 没挂上场景，屏幕上等于看不见。
- `islandWin=…|lvl=…` 必须**小于**自己窗口的 `lvl`，否则胶囊被岛盖住。
- `shows` 归零 = SpringBoard 刚载入新代码；不涨 = 这条请求没显示。
- v1.4.0 起倒计时胶囊出现前先震一下最弱触感（`haptic=` 计数），纯文案提醒不震。

## 零、八、装入 SpringBoard 的新插件，注销后必须查 crash list（2026-10-31 03:31 事故，必读）

实证（CountdownHUD 1.4.0）：插件在 dyld 构造函数里创建 `UISelectionFeedbackGenerator`，
启动约 0.67 秒后 `→ +[UIScreen mainScreen] → NSAssertionHandler → abort` → SIGABRT →
崩溃循环 → **安全模式**。崩溃列表里那份报告**就是唯一证据**，不查就等于没修。

```sh
apelin_crash_list process=SpringBoard
#  有比本次注销时间更新的报告 → 装坏了：先 irisin-cli remove 回滚
#  没有新报告 → 才算装好
sh scripts/device.sh read com.apple.springboard <Tweak>Diagnostics
```

**构造函数阶段的铁律**：只准碰 Foundation，不准碰任何 UIKit API；`@try/@catch` 救不了
（`NSAssertionHandler` 走 `abort`）；需要 UIKit 的一律延迟到拿到 windowScene 之后。
案例文档：仓库 `docs/cases/countdownhud-safe-mode.md`、`docs/cases/springboard-safemode-0.9.21.md`。

## 零、九、插件自己执行注销（CountdownHUD 1.6.1 起，2026-10-31 实测通过）

**病灶**（用户原话：「注销前用户确认点击的弹窗对话框为什么现在我没有收到实际落地」）：
点「立即注销」时插件只把 `confirm` 写进
`/var/mobile/Library/Preferences/.countdownhud-answer`，**插件自己从不注销**；真正 `sbreload`
要靠当时还在前台轮询 `wait_answer` 的 `respring-guard.sh --ask` —— 而那条 sh 跑在 agent 的
一次 `shell_run` 里，回合结束/超时/被中断它就没了。于是用户点了按钮，屏幕上什么都不发生。

**修法（1.6.1）**：

1. 写 `confirm` → 收起弹窗 → 写诊断 → **1 秒后**（留出落盘时间）由插件执行注销。
2. 怎么调：`dladdr` 取**自己 dylib 的真实路径**，截掉 `/usr/lib/TweakInject/` 得到 jbroot 根，
   依次试 `<jbroot>/usr/bin/sbreload`、`/usr/bin/sbreload`、`/var/jb/usr/bin/sbreload`，
   每个先 `isExecutableFileAtPath` 再 `posix_spawn`；全失败才 `kill(getpid(), SIGTERM)`
   （launchd 原样拉起，效果等同注销）。**路径绝不写死**（jbroot 前缀每次重越狱都会变）。
3. **安全开关**：`.countdownhud-no-respring` 存在时只写答案、不注销。插件看不到 shell 环境变量，
   所以 `RESPRING_GUARD_NO_RESPRING=1` 的「只倒计时」验法必须靠这个文件转达 ——
   `respring-guard.sh` 的 `--ask` 分支在 `NO_RESPRING=1` 时 `touch` 它，并用
   `trap 'rm -f "$NOMARK"' EXIT INT TERM HUP` 退出时删掉。**忘了删 = 以后所有注销都不生效。**
4. 诊断字段 `exec=spawned|skip-marker|term|fail|-`：`spawned`=真注销成功，`skip-marker`=见到标记文件，
   `term`=退化到 SIGTERM，`fail`=全失败（这时才真的没注销），`-`=还没点过。
5. 语义一字不许改：cancel→4、timeout→5、confirm 需用户点头。

**验收（实测）**：装 1.6.1 → 注销一次让新 dylib 进 SpringBoard → `--ask` 弹窗 → 用户亲手点
「立即注销」→ SpringBoard pid 更换、诊断 `v1.6.1;alerts=1;ans=confirm;exec=spawned`、crash list 无新报告。

### 踩过的坑一：注销后读到旧版本号 ≠ 没加载（cfprefsd 缓存）

注销后 `CountdownHUDDiagnostics` 仍报 `v1.6.0`，看着像新 dylib 没进进程 —— 我据此误判过一轮。
真因是 cfprefsd 缓存：新进程还没重写诊断键，读到的是上一进程的旧值（磁盘 plist 里甚至可能没这个键）。

**判活的正确做法**：

```sh
printf '%s|120|!探针：HUD活着吗|\n' "$(date +%s)" > \
  /rootfs/var/mobile/Library/Preferences/.countdownhud-request
sleep 3
sh scripts/device.sh read com.apple.springboard CountdownHUDDiagnostics | tail -1
# 变成 v1.6.1 / shows 递增 / label=探针… → 活着且是新代码
```

同理 `icli probe` 跑的是**它自己的进程**，不是目标进程：在里面查 `CHWindow` / `SBIconController`
一律 `N`，那不是「插件没注入」的证据，别拿它下结论。

### 踩过的坑二：`--ask` 的 shell 超时预算

`--ask` 前台阻塞到用户答复（最多 `WAIT+5` 秒），**再走 `WAIT` 秒倒计时**才 `sbreload`，
总耗时 ≈ `2*WAIT+5`。若跑在 `shell_run` 里，`timeout_seconds` 必须大于这个总数，否则会被杀在
倒计时中途 —— **用户点了「立即注销」却没注销**，看起来就像修复没生效。
实测：`--ask 90` 需 >185 秒（我用 150 秒，被杀）；`--ask 45` 用 115 秒刚好跑完。
更稳：`--ask` 也给 5 秒（2026-10-31 20:09 用户硬指令：注销倒计时一律 5 秒），点完的 5 秒倒计时另用 `--confirm 5` 走。

## 一、两种动作，两种规矩

### A. 会让屏幕黑一下 / 打断用户当前操作的动作 —— 必须通知 + 倒计时 5 秒

- 安装 / 升级 deb：`irisin-cli install --yes --json /rootfs/var/mobile/Documents/<name>.deb`（root）
- 注销：`sbreload`（不弹批准卡）。Apelin 的 `apelin_device_respring`、`apelin_package_confirm_loaded`
  （`respring: true`）同样算注销。本机**没有** `icli respring`（报 `Unexpected argument 'respring'`），
  只有 `icli sb respring`。
- 重启目标进程：`sh scripts/device.sh kill <bid>`（= `icli app kill` 免卡片）。

**固定五步，顺序不能变（第 0 步＝先和别的对话同步）：**

1. **前置检查**：`apelin_crash_list`（process 填目标进程）。`consecutiveCrashCount ≥ 2` 或这次启动
   就崩过 → **不许注销**，先停用插件再把设备救回来。
2. `apelin_notification_send` + **把「N 秒后做什么」写进回复正文**。
3. **先只警告**：`sh scripts/respring-guard.sh 5 <标签>`（胶囊 + 退出码 3，不注销）。
4. **用户明确回「注销/确定」之后**才 `sh scripts/respring-guard.sh --confirm 5 <标签>`。
5. 才执行安装 / 杀进程（装包这类接着做动作：`RESPRING_GUARD_NO_RESPRING=1 … --confirm 5 装包`）。

通知配额：每回合 ≤3 条、间隔 ≥30 秒；一次动作链第一条通知里就说清「装完会注销」。

### B. 只是耗时、不动屏幕的动作 —— 不发通知

下载、云编译、读诊断、改源码、跑 probe。

## 二、已经进了安全模式怎么办

- 安全模式 = 目标进程崩过，ellekit 的 MobileSafety 起了一份不加载 tweak 的进程。
  **不要反复注销重试**，每试一次都是一次黑屏 + 一次崩溃。
- 顺序永远：读崩溃报告 → 定位 → 改代码 → 云编译 → 装 → 才注销。
- **安全模式的判据**：诊断 `tick`/`shows` 是否还在涨、发探针请求看它接不接（见 §零·九），
  **别只看进程在不在、更别只读诊断键**。
- 汇报时把崩溃栈关键几帧抄给用户，并说清「这次注销后会不会再进安全模式」。

## 三、离开 Apelin 取证（桌面 / 插件设置内 / 别的 App），办完必须回到对话内

用户原话：「**去桌面上去桌面插件内去软件插件内回来 Apelin 对话内都写进硬性规定和技能包**」。
他在聊天里看不到屏幕，离开那段时间对他是黑箱。**三种去处一个都不例外。**

| 去哪儿 | 目的 | 目标 | 硬上限 |
| --- | --- | --- | --- |
| 桌面 | 看图标、看胶囊、截图 | 15~25 秒 | 60 秒 |
| 插件设置内 | 看面板、点开关、截图 | 25~40 秒 | 60 秒 |
| 别的 App | 定位现象、取日志 | 20~40 秒 | 60 秒 |

- **单次离开硬上限 60 秒**（到 `icli app frontmost` 报 `wiki.qaq.apelin` 为止）；到点没做完先回来，
  要更多证据就分多次外出，每次出发时人都在 Apelin 里。
- **出去前一句预告、回来一句交代，写进聊天正文**。
- 长步骤（云编译、下载、装包、扫盘、读诊断）**必须在回到 Apelin 之后才跑**。
- 去桌面 `icli button home`；回程 `icli app launch wiki.qaq.apelin`；回程写在 `trap EXIT/INT/TERM` 里。
- 现成脚本 `sh scripts/errand-in-app.sh <bid> [秒] [元素文字]…`；点元素用 `icli ui tap "<文字>"` 不用坐标。
- **汇报里写清外出多少秒，超了如实写。**

## 四、汇报要求

写清：通知了什么、正文里有没有写「N 秒后」、倒计时了没有、查崩溃了没有、**注销后 crash list
有没有新报告**、外出多少秒。没做就明说没做，别含糊。
