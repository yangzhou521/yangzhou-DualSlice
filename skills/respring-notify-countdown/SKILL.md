---
name: respring-notify-countdown
description: 注销、装 deb、重启目标进程前，必须先和本机其它工程/对话同步、别打断它们的工作（技能 cross-chat-coordination），再让用户真的看见「5 秒后执行」并倒计时；离开 Apelin 取证后必须自己回到 Apelin；注销前先查崩溃循环，避免把 SpringBoard 打进安全模式。任何工程、任何对话都适用；注销前必须先让用户在屏幕上真看见倒计时（回复正文 + 灵动岛胶囊；通知不算知情），并读 CountdownHUD 诊断确认胶囊真显示了；装入 SpringBoard 的新插件，注销后必须查 crash list，无新报告才算装好。 **注销必须用户点头**：`scripts/respring-guard.sh` 不带 `--confirm` 只警告、退出码 3、不注销，等用户明确回「注销/确定」才真注销。
---

---
name: respring-notify-countdown
description: 注销、装 deb、重启目标进程前，必须先和本机其它工程/对话同步、别打断它们的工作（技能 cross-chat-coordination），再让用户真的看见「5 秒后执行」并倒计时；离开 Apelin 取证后必须自己回到 Apelin；注销前先查崩溃循环，避免把 SpringBoard 打进安全模式。任何工程、任何对话都适用；注销前必须先让用户在屏幕上真看见倒计时（回复正文 + 灵动岛胶囊；通知不算知情），并读 CountdownHUD 诊断确认胶囊真显示了；装入 SpringBoard 的新插件，注销后必须查 crash list，无新报告才算装好。 **注销必须用户点头**：`scripts/respring-guard.sh` 不带 `--confirm` 只警告、退出码 3、不注销，等用户明确回「注销/确定」才真注销。
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
  ① 自研一个 SpringBoard 侧的自绘倒计时 HUD（由 `scripts/respring-guard.sh` 发 Darwin 通知触发，
     5 秒胶囊在屏幕顶部，不依赖 Apelin 通知）；② 反馈给 Apelin 修它的通知投递方式。
  在 ① 做出来之前，倒计时就老老实实写在聊天正文里。

## 零、五、注销前先和别的对话同步（用户 2026-10-30 21:05 定的硬规矩）

原话：「你注销的话和另一个对话说一下！不要打断它的工作！把这个写进记忆和技能包内！并同步到云端！以后所有的
对话和工程在工作时想要注销的时候都要查看搜索另外一些工作区的对话是否在工作！注销前要和别的对话同步一下！」

- `apelin_project_list` + 对每个工程（含本工程）`apelin_conversation_list project: <folder>`，
  把 `running` / `waitingForApproval` / 最近几分钟内有活动的对话挑出来（本对话排除）。
- 对每一个用 `apelin_conversation_send` 说清「约 N 秒后注销，原因 X，请把当前这一步收尾、离开 Apelin 的先自己回来」，
  再用 `apelin_conversation_read`（`wait_seconds: 60`）等它这一回合结束。**绝不 `apelin_conversation_stop`。**
- 等超过约 120 秒仍没收尾：**不硬注销**，在回复正文说清「对话 A 还在做 X」让用户决定。
- 协调完才进入下面的「通知 → 正文写 5 秒 → 真等 5 秒」三步。
- 细则见技能 `cross-chat-coordination`（不只注销前协调：有进展要广播，自己的活永远第一）。

## 零、六、先别注销：注入型插件把 App 划掉重开就生效（用户 2026-10-30 21:24 定的硬规矩）

原话：「这些注入型的插件在安装后 划掉后台重进软件和插件内就能实现功能完全注入！不必重新注销桌面！…
以后所有的对话和工程在工作时想要注销的时候都要看看这个常识性的知识！」

- tweak 只在目标进程**启动时**加载，所以装包 / 改代码后**重启那个进程**就够了，不需要注销整台 SpringBoard。
- App 类：`icli app kill <bid> --force` + `icli app launch <bid>`，或用户自己上划划掉再点开；
  设置面板类：退出「设置」再进。
- 验证用诊断键（`icli prefs read <bid> <Tweak>Diagnostics` 看版本号），不要用「屏幕黑没黑」当证据。
- 只有插件本身注入 SpringBoard（桌面图标、HUD…）、或改了过滤器 plist / 包布局，才走注销的完整四步。
- 细则见技能 `injected-tweak-restart-app`。

## 零、七、注销前必须让用户**在屏幕上**真的看见（2026-10-30 23:42 事故的根因，必读）

用户 23:42 原话：「上次注销前用户还是不知情！这个根本性问题也是没解决！」

**「通知」不是知情通道，唯一可靠的知情通道是「用户的眼睛」。** 三条通道的优先顺序不许颠倒：

| 通道 | 什么时候可见 | 能不能当「用户已知情」 |
| --- | --- | --- |
| **聊天回复正文** | 永远（用户正看 Apelin 时就是这里） | ✅ 必须写，且必须写清「N 秒后注销 / 为什么 / 下一步」 |
| **屏幕上的灵动岛胶囊**（CountdownHUD，v1.4.0 起还会先震一下最弱的触感） | 用户在看桌面 / 别的 App 时 | ✅ 唯一能跨 App 的通道 —— 注销前就靠它 |
| `apelin_notification_send` 通知 | 只在 Apelin **不在前台**时 | ❌ 发通知这一下会把 Apelin 拉回前台，横幅被自己吞掉（见 §零） |

**根因（2026-10-30 23:42 定位，HUD v1.3.0 已修）**：在这之前胶囊在屏幕上**根本不会出现** ——
老代码量不到 windowScene 时退回 `[[UIWindow alloc] initWithFrame:]`，而 iOS 13+ 里
**没有 windowScene 的窗口完全不参与渲染**：窗口对象、子视图、`isHidden=NO`、诊断计数 `shows` 全都正常，
屏幕上一个像素都没有。于是「发了通知 + 写了正文 + 真等了 5 秒」全做了，用户仍然毫不知情。
v1.3.0 起：拿不到 scene 就**不显示、也不消费这条请求**（0.5 秒后的下一拍重试）；窗口一律
`initWithWindowScene:` + `rootViewController`，层级 `20000000`（压得住灵动岛那套 SystemAperture）。

**动注销之前先确认胶囊真的显示了**（这是「用户已知情」的唯一证据）：

```sh
# 1) 发请求（respring-guard.sh 已包好；只想上岛提醒用 hud-notify.sh）
sh scripts/respring-guard.sh 5 注销        # 只警告、不注销（退出码 3）
sh scripts/respring-guard.sh --confirm 5 注销  # 用户已明确答应后：倒计时 5 秒 + sbreload
# 2) 读诊断：shows 必须比上一次大，win= 里必须有真实场景与层级
icli prefs read com.apple.springboard CountdownHUDDiagnostics
#   v1.3.0;shows=3;last=5s;label=注销;font=12.3;island=…|x,y,w,h;src=aperture;cand=4;
#          mode=count;win=CHWindow|scene=UIWindowScene|lvl=20000000|bounds=390x844;islandWin=…|lvl=…
# 3) shows 不涨 / scene 不是 UIWindowScene / src=none → 胶囊没显示，
#    先修 HUD（icli log syslog --subsystem com.yangzhou.countdownhud），别假装通知到位就注销。
```

- `win=…|scene=…` 里的 scene 必须是 `UIWindowScene`；是 `-` 或空 = 没挂上场景，屏幕上等于看不见。
- **v1.4.0 起胶囊出现前会先震一下最弱的触感**（用户 2026-10-31 02:48：「有注销的打算时第一时间来个
  最弱的震动」「震动要早于倒计时」）：非 `!` 的倒计时走 `UISelectionFeedbackGenerator`（全系统最弱一档），
  先震、再画胶囊；同一请求只震一次（拿不到 windowScene 的重试不重复震），纯文案提醒不震。
  诊断串末尾 `haptic=<累计次数>` —— 不用听声音也能确认震过几次。
  某个机型没有 Taptic Engine 时只是安静地什么都不发生，功能不受影响。
- `islandWin=…|lvl=…` 是岛那只窗口的层级 —— 它必须**小于**自己窗口的 `lvl`，否则胶囊被岛盖住。
- `shows` 归零 = SpringBoard 刚载入新代码；`shows` 不涨 = 这一条请求没显示（没有 scene 时插件会自动重试）。

## 零、八、装入 SpringBoard 的新插件，注销后必须查 crash list（2026-10-31 03:31 事故，必读）

**新装的 SpringBoard 插件第一次注销之后，「装好了」这句话不许凭感觉说 —— 必须查崩溃报告。**

实证（CountdownHUD 1.4.0，2026-10-31 03:31）：插件在 SpringBoard 的 **dyld 构造函数**里就创建
`UISelectionFeedbackGenerator`，启动约 0.67 秒后走
`CHInitialize → -[UIFeedbackGenerator init] → +[UIFeedbackGenerator _defaultCoordinateSpace]
→ +[UIScreen mainScreen] → NSAssertionHandler → abort` → SIGABRT → 崩溃循环 → **安全模式**。
设备的 SpringBoard 报告 `SpringBoard-2026-10-31-033134.ips`。

**为什么必须查**：崩溃是循环的，第一份报告出现时设备已经进了安全模式，用户看到的是「手机自己坏了」。
崩溃列表里那份报告**就是唯一的证据**，不查就等于没修。

**固定做法（装完 SpringBoard 插件、注销之后立刻做）**：

```sh
# 1) 查最新崩溃报告：进程填 SpringBoard
apelin_crash_list process=SpringBoard        # 或 scripts/device.sh 读报告目录
# 2) 判读：
#    - 有比「本次注销时间」更新的报告 → 装坏了：先卸包回滚（irisin-cli remove <pkg>），再进安全模式排查
#    - 没有新报告 → 才算装好
# 3) 再看 SpringBoard 活着、诊断键能读：
sh scripts/device.sh read com.apple.springboard <Tweak>Diagnostics
```

**出崩溃了怎么办（不要反复注销重试）**：

1. **先卸包回滚**：`irisin-cli remove <package-id>`（root）—— 让设备恢复可用，这比继续试更重要。
2. 再注销一次（走完整四步：查崩溃 → 通知 → 正文写 5 秒 → 真等 5 秒）把坏插件带走。
3. 读崩溃报告定位，用 `apelin_crash_symbolicate` 对着本次构建的 dSYM 看符号。
4. 改代码 → 云编译 → 装 → 注销 → **再查一次 crash list**，闭环。
5. 汇报时写清：哪一步崩的、根因几帧、这次注销后会不会再进安全模式。

**构造函数阶段的铁律（注入 SpringBoard 的插件尤其致命）**：

- **构造函数里只准碰 Foundation，不准碰任何 UIKit API**（`UIScreen` / `UIFeedbackGenerator` /
  `UIWindow` / `UIView` / `UIFont` …）。UIKit 那时还没初始化完，`+[UIScreen mainScreen]` 会抛断言。
- `@try/@catch` **救不了**：`NSAssertionHandler` 走的是 `abort`，不是可捕获的 ObjC 异常。
- 需要 UIKit 的东西一律**延迟**：拿真实 `windowScene`（= UIKit 已经活着）之后再碰，
  或在主线程上、UIKit 就绪后再惰性创建。
- 案例文档：仓库 `docs/cases/countdownhud-safe-mode.md`（根因 / 三步修法 / 复发处理流程）。

## 一、两种动作，两种规矩

### A. 会让屏幕黑一下 / 打断用户当前操作的动作 —— 必须通知 + 倒计时 5 秒

- 安装 / 升级 deb：`irisin-cli install --yes --json /rootfs/var/mobile/Documents/<name>.deb`（root）
- 注销：`icli sb respring`
  **本机没有 `icli respring`**（2026-10-30 实测报 `Unexpected argument 'respring'`），只有 `icli sb respring`。
  Apelin 的 `apelin_device_respring`、`apelin_package_confirm_loaded`（`respring: true`）同样算注销。
- 重启目标进程：`icli app kill <bundle-id> --force`

**固定五步，顺序不能变（第 0 步＝先和别的对话同步，见上一节）：**

1. **前置检查（新增，最重要）**：`apelin_crash_list`（process 填目标进程，如 SpringBoard），
   读最新报告的 `consecutiveCrashCount` 与崩溃栈。
   - ≥2，或这次启动就崩过 → **不许注销**。先把插件停用（关功能 / 把 dylib 改名 / 卸载），
     确认新进程不会再崩，再按下面三步走。
   - 刚装上的包还没验证过不崩 → 先别注销；要注销就在通知里写明「可能再进安全模式」。
2. `apelin_notification_send`：标题 ≤40 字，正文一两句说清「动了什么 + 为什么 + 下一步」，
   并**同时把「5 秒后注销」写进回复正文**（通知在 Apelin 前台时看不见）。
3. **注销先只警告**：`sh scripts/respring-guard.sh 5 <标签>` —— 只弹胶囊警告、终端打印、**退出码 3、不注销**（用户 2026-10-31 05:33 原话：「以后注销事件给我一个警告⚠️弹窗 让我决定要不注销！」）。
4. **用户明确回「注销 / 确定」之后**，同一个动作才 `sh scripts/respring-guard.sh --confirm 5 <标签>` 真等 5 秒并 `sbreload`；没回话、回「取消」、或只是自己觉得该注销了 → 一律停在③，绝不加 `--confirm`。
5. 才执行安装 / 杀进程（装包这类要接着做动作：`RESPRING_GUARD_NO_RESPRING=1 sh scripts/respring-guard.sh --confirm 5 装包`）。

通知配额：每回合最多 3 条、间隔 ≥30 秒。一次动作链（装包 → 随后注销）第一条通知里就说清
「装完会注销」，注销前若已过 30 秒，再发第二条。

### B. 只是耗时、不动屏幕的动作 —— 不发通知

下载、云编译（GitHub Actions）、读诊断、改源码、跑 probe。发了只会变成噪音。

## 二、已经进了安全模式怎么办

- 安全模式 = 目标进程崩过，ellekit 的 MobileSafety 起了一份不加载 tweak 的进程。
  此时**不要反复注销重试**，每试一次都是一次黑屏 + 一次崩溃。
- 顺序永远是：读崩溃报告（`apelin_crash_*` 或 `/var/mobile/Library/Logs/CrashReporter`）→ 定位 → 改代码
  → 云编译 → 装 → 才注销。
- 需要立刻让用户手机恢复可用：把插件 dylib 临时改名（root），注销一次；修好后再改回。
- 汇报时把崩溃栈的关键几帧抄给用户看，并说清「这次注销后会不会再进安全模式」。

## 三、离开 Apelin 取证（桌面 / 插件设置内 / 别的 App），办完必须回到对话内

用户 2026-10-30 先要求「不要再让我手动回来」，随后两次要求把时限也写死，第二次原话：
「**去桌面上去桌面插件内去软件插件内回来 Apelin 对话内都写进硬性规定和技能包**」。
原因：他在聊天里看不到屏幕，离开 Apelin 前台那段时间对他就是黑箱 —— 既看不到你在干什么，
也没法随时回来看。**三种去处一个都不例外；任何工程、任何对话都适用。**

| 去哪儿 | 典型目的 | 目标时长 | 硬上限 |
| --- | --- | --- | --- |
| 桌面（主屏 / SpringBoard） | 看桌面图标、看 HUD 胶囊、截图 | 15~25 秒 | 60 秒 |
| 插件设置内（设置 ▸ 目标插件面板） | 看面板是否正常、点开关、截图 | 25~40 秒 | 60 秒 |
| 别的 App 内（微信 / Safari / Filza…） | 定位现象、取日志、取证据 | 20~40 秒 | 60 秒 |

### 时间预算（硬性）

- **单次离开 Apelin 前台的硬上限 = 60 秒**：从「按下 Home / 拉起别的 App」算到
  `icli app frontmost` 报 `wiki.qaq.apelin` 为止。
- 目标按上表做：一次「进目标 App → 点元素 → 截图 → 回程」实测 14 秒，够用了。
  60 秒是天花板，不是指标。
- **出去前一句预告、回来一句交代，都写在聊天正文里**：出去前「我去桌面看 X，目标 20 秒」，
  回来「回到 Apelin：看到了 Y，外出 N 秒」。这两句是用户在那段时间里唯一的把手。
- **到 60 秒无论做没做完，先回 Apelin**（`icli app launch wiki.qaq.apelin`），再决定要不要第二次外出。
  需要更多证据就**分多次外出**，每次出发时人都在 Apelin 里。
- **长步骤不占屏幕，而且必须在回来之后才跑**：云编译、下载、装包、`find` 扫盘、`icli prefs read`
  读诊断、改源码 —— 先在屏幕这一侧回 Apelin，再跑它们。
  2026-10-30 12:12 实测：去主屏截图往返 ≈15 秒；随后那个 47 秒的 `find` 是在 Apelin 已经回到前台
  之后才跑的 —— 顺序对了，屏幕就一直在 Apelin。
- **不许「走一步看一眼」**：外出前把命令、要点的元素、要截的图一次备齐，
  一次调用跑完（`scripts/errand-in-app.sh` 就是为这个写的）。
- 去桌面走 `icli button home`（Apelin 在前台时界面类工具会被拒，报
  "UI actions may not reach wiki.qaq.apelin"）；回程 `icli app launch wiki.qaq.apelin`。

### 回程怎么做

- 回程写在 `trap EXIT/INT/TERM` 里，报错、超时、Ctrl-C 都会回。
- 末尾 `icli app frontmost` 校验并打印「回到 Apelin: <bundle-id>（外出 N 秒）」。
- 现成脚本：`sh scripts/errand-in-app.sh <bundle-id> [秒] [要点的元素文字]…`
- 点元素用 `icli ui tap "<文字>"`，不要用坐标（列表里跑偏过）。
- **汇报里写清这次外出多少秒；超了 60 秒如实写超了。**

## 四、汇报要求

在回复里写清：通知了什么、正文里有没有写「5 秒后」，倒计时了没有，查崩溃了没有，**注销后查了
crash list 没有、有没有新报告**，外出多少秒。没做就明说没做，别含糊。
