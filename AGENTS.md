# 本仓库怎么干活（AGENTS.md）

工作区工程 `yangzhouDualSlice`（Apelin 的 workspace，`buildSystem: external`，仓库
`https://github.com/yangzhou521/yangzhou-DualSlice`，分支 `main`）。

**这台设备编不了任何东西**：iPhone10,1（A11 / iOS 16.7.16 / roothide）缺 FEAT_LRCPC，
装不上 Command Line Tools，本机没有工具链，也不要在本机找。所有 .deb 一律走 GitHub Actions
云编译（macOS runner 上 clang 直编 arm64 + arm64e 两片 + lipo + ldid + dpkg-deb），装到本机
再验证。因此 `apelin-project.json` 里**没有**声明 `external.script`：声明了只会让
`apelin_project_build` 在本机必然失败。

## 仓库里有什么

| 路径 | 是什么 |
| --- | --- |
| `ThemeCorePlus/Sources/` | 插件本体（主题引擎）的源码 |
| `Prefs/ThemeCorePlusPrefs/` | 设置面板源码 + bundle 的 Info.plist / Root.plist |
| `Support/ThemeCorePlus.plist` | 插件注入清单（Filter/Bundles） |
| `Support/ThemeCorePlusPreferenceLoader.plist` | 设置里那一行的入口（bundle + 图标 + 控制器类） |
| `Support/ThemeCorePlusIcon@2x/@3x.png` | 面板图标（MarkTheme16 的 App 图标，180×180） |
| `scripts/build-themecoreplus.sh` | ThemeCorePlus 的构建脚本（**只在 CI 上跑**） |
| `scripts/respring-guard.sh` | **唯一注销入口**：先写 HUD 请求（装了 CountdownHUD 就出胶囊）再终端倒计时 5 秒，最后 `icli sb respring`（通知由会话先发） |
| `CountdownHUD/Sources/CountdownHUD.m` | 自绘倒计时胶囊（SpringBoard 顶层窗口，「N 秒后注销」），**不依赖通知** |
| `Support/CountdownHUD.plist` | HUD 的注入过滤器（只进 `com.apple.springboard`） |
| `scripts/build-countdownhud.sh` | HUD 的构建脚本（**只在 CI 上跑**，不链接 substrate） |
| `.github/workflows/countdownhud.yml` | HUD 的云编译 + 发 Release（tag `countdownhud-v1.1.0`） |
| `scripts/errand-in-app.sh` | 外出取证：进目标 App → 点元素 → 截图/界面树 → **trap 里强制回 Apelin** |
| `scripts/sync-skills.sh` | 本地技能目录 ↔ 仓库 `skills/` 双向同步（默认 push） |
| `skills/` | 技能包副本（`apelin_skill_read` 读的是 `~/Documents/wiki.qaq.apelin/skills/`，这里只是版本化并上 GitHub） |
| `.github/workflows/themecoreplus.yml` | ThemeCorePlus 的云编译 + 发 Release |
| `Sources/`、`Support/AxsDualSliceTweak.plist`、`scripts/build-dualslice.sh`、`.github/workflows/dual-slice.yml` | 原来的双切片模板（AxsDualSlice），**别动** |
| `Attachments/`、`probe1-3.js` | 素材与临时探针脚本 |

## 怎么出包

改完源码 push 到 `main`：只有 `ThemeCorePlus/**`、`Prefs/**`、`Support/ThemeCorePlus*`、
`scripts/build-themecoreplus.sh`、工作流自身变动才会触发（paths 过滤），以免白白重建已经验过的包。
同一次运行里发 Release（静态 tag `themecoreplus-v0.6.0`，每次运行都重建资产，sha256/体积会变）。
Release 资产地址：
`https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.6.0/com.yangzhou.themecoreplus_0.6.0_iphoneos-arm64e.deb`

可读的验证信息都写成 check-run annotation（`::notice/::error title=…`）：job 日志要登录才能看，
公开仓库的 annotations 匿名可读（`/repos/{owner}/{repo}/check-runs/{id}/annotations`）。
本机没有 curl/wget/python3，查状态用 `icli probe` + `NSData`/`NSURLForString` 调 GitHub API。

## 装到本机（本机只能这么验）

```sh
# 下载（放到真根 /rootfs 下的 Documents），然后：
irisin-cli install --yes --json /rootfs/var/mobile/Documents/<deb>     # 须 root:true
icli sb respring         # 注销（本机只有这个写法；icli respring 不存在）
```
依赖：`mobilesubstrate`（本机由 ellekit 提供）、`preferenceloader`（已装）。

验注入（诊断存在 = 插件在这条进程里活过）：
```sh
icli prefs read com.apple.springboard ThemeCorePlusDiagnostics
icli prefs read com.apple.springboard ThemeCorePlusCensus
```
设/回滚主题（也能从设置面板点）：
```sh
icli prefs write  com.yangzhou.themecoreplus ThemePath "/Library/ThemeCore/<主题目录>"
icli prefs write  com.yangzhou.themecoreplus ThemeName "液态玻璃"
icli prefs delete com.yangzhou.themecoreplus ThemePath     # 回滚 = 清 ThemePath/ThemeName
```
改完设置面板会广播 Darwin 通知 `com.yangzhou.themecoreplus.preferences-changed`，
SpringBoard 收到立刻重读快照并重排图标；shell 手写偏好不会触发，要自己 respring。

## CountdownHUD：屏幕上的倒计时（不靠通知）

通知这条路在本机废了（见下面硬规矩里的 11:36 实测）。所以倒计时改成自己画：

- 插件 `CountdownHUD.m` 注入 **SpringBoard**，起一个 0.5 秒的 `dispatch_source` 轮询
  `/var/mobile/Library/Preferences/.countdownhud-request`（系统原路径；SpringBoard 本来就在这个目录
  读写它自己的 `com.apple.springboard.plist`，权限没问题）。
- 文件内容 `<epoch>|<秒数>|<标签>`，例如 `1761794460|5|注销`；**内容变了才触发**，同名不重复触发；
  插件刚加载时已存在的旧内容只记下不触发。
- 触发后弹一个顶层窗口（`windowLevel = 10000000`，`hitTest` 返回 nil 不吃触摸），显示
  「5 秒后注销」，最后 3 秒橙色、最后 2 秒红色，到 0 显示「现在注销」再淡出。
- **胶囊的尺寸与位置 = 岛的尺寸与位置（v1.1.0 起）**：本机的岛是 DynamicX 用系统
  `SBSystemAperture*` 那套造的假岛，位置由 VisibleIsland 的 `yPos` 调。插件不写死尺寸，
  而是每秒（显示期间）在自己之外的窗口里找那只横向胶囊 —— 优先类名带 `Island`/`Aperture`
  的窗口（`src=aperture`），退而认类名带岛字样的视图（`src=classname`）；多个候选按
  「是否在 Aperture 窗口 / 类名像不像岛本体 / 尺寸离 126×37 有多远」打分取最高。找不到
  才退回写死的 190×44、安全区顶 +6（`src=none`）。选中项一并写进诊断（见下）。
- 从 shell 写这个文件必须加真根前缀：`/rootfs/var/mobile/Library/Preferences/.countdownhud-request`
  （脚本已包好，见 `scripts/respring-guard.sh`）。
- 验证：`icli prefs read com.apple.springboard CountdownHUDDiagnostics`
  → `v1.1.0;shows=N;last=5s;label=注销;island=<类名>|x,y,w,h;src=aperture;cand=N`；
  量到的候选清单：`icli prefs read com.apple.springboard CountdownHUDIslandCandidates`
  （最多 8 行 `A|<类名>|x,y,w,h`，前缀 A = 在 Aperture 窗口里）；
  日志 `icli log syslog --subsystem com.yangzhou.countdownhud`。
- 卸载：`irisin-cli remove com.yangzhou.countdownhud`；不装它时脚本照样终端倒计时，只是屏幕上没有胶囊。

**规矩：以后装包 / 注销 / 杀进程前，一律 `sh scripts/respring-guard.sh 5 <标签>`**（标签写清动作，
如「注销」「装包」），让屏幕和聊天正文同时有 5 秒。

## 硬规矩

- **装包 / 注销 / 重启目标进程之前，必须：① `apelin_notification_send` 通知 → ② 明说「5 秒后执行」并
  真等 5 秒（`sh scripts/respring-guard.sh 5`）→ ③ 才执行。** 用户 2026-10-30 三次要求过、仍然漏过，
  原因就是这条只写在记忆里 —— 现在同时写进本文件与技能 `respring-notify-countdown`。
  - 涉及的动作：`irisin-cli install`（装包）、**`icli sb respring`**（注销；本机**没有** `icli respring`，
    实测报 `Unexpected argument 'respring'`）、`apelin_device_respring`、
    `apelin_package_confirm_loaded(respring: true)`、`icli app kill <bid> --force`。
  - 通知正文：动了什么 + 为什么 + 下一步，一两句。Apelin 在前台时通知看不到，同一句话要写进回复。
  - 通知配额：每回合 ≤3 条、间隔 ≥30 秒；「装完随后注销」可在第一条通知里一并说明。
  - 只有「屏幕会黑一下 / 打断用户当前操作」才算；下载、云编译、读诊断、改源码不发通知。
  - **通知看不见是常态（2026-10-30 11:36 实测）**：调 `apelin_notification_send` 的瞬间，Apelin 会被
    拉回前台（实测：`icli button home` 后前台稳定是 springboard，一发送 0.35 秒内前台变回
    `wiki.qaq.apelin`，进程号不变 56376），它自己的通知代理随即把横幅吞掉。所以通知既不显示、
    也无法上灵动岛（微信能上岛，Apelin 这条进不了 SpringBoard 的横幅通道）。**倒计时永远以聊天正文
    为准**，通知只是补充，绝不当作「用户已经知道了」。
- **离开 Apelin（桌面 / 插件设置内 / 别的 App）必须按时自己回到对话内**——三种去处一个都不例外；
  用户 2026-10-30 两次要求，第二次原话：「去桌面上去桌面插件内去软件插件内回来 Apelin 对话内都写进硬性规定和技能包」
  （**所有工程、所有对话适用**）：
  - 三类去处：**桌面（主屏）**、**插件设置内（设置 ▸ 主题美化 + 面板）**、**别的 App 内（微信 / Safari / Filza…）**。
  - **单次离开 Apelin 前台的硬上限 = 60 秒**：从按下 Home / 拉起别的 App 算到 `icli app frontmost`
    报 `wiki.qaq.apelin` 为止。目标按 **15~30 秒**做（一次完整往返实测 14 秒），60 秒是天花板不是指标。
  - **到 60 秒无论做没做完，先回 Apelin**（`icli app launch wiki.qaq.apelin`）；要更多证据就分多次外出，
    每次出去前人都已在 Apelin 里。不许「走一步看一眼」，外出前把命令 / 要点的元素 / 要截的图准备好。
  - **出去前一句话预告**（去哪、看什么、预计几秒），**回来一句话交代**（看到什么、外出多少秒）——
    两句都写在聊天正文里，用户才不是对着黑箱。
  - **长活不占屏幕，而且必须在回来之后才跑**：`find` 扫盘、`icli prefs read` 读诊断、云编译、下载、改源码。
    实测（2026-10-30 12:12）：去主屏截图往返 ≈15 秒；那个 47 秒的 `find` 是**回 Apelin 之后**才跑的，
    顺序对了，屏幕就一直在 Apelin。
  - 回程写在 `trap EXIT/INT/TERM`（报错、超时、Ctrl-C 都会回），末尾 `icli app frontmost` 校验并打印
    「回到 Apelin: <bundle-id>（外出 N 秒）」；一次调用取齐证据用 `sh scripts/errand-in-app.sh`。
    **汇报里必须写清外出多少秒，超了也照写。** 绝不要求用户手动切回，也不把验证推回给用户。
- **不许 `-undefined dynamic_lookup` / `-undefined suppress`。** 缺符号就逐个写
  `-Wl,-U,_符号名`（面板的 `PSListController`/`PSSpecifier` 就是这么处理的）。
- **不许给私有类写消息发送。** 代码里出现 `[SBIconController sharedInstance]` 就会多出一个
  SDK 里没有的类符号、链接直接挂。私有类一律 `objc_getClass()` + `objc_msgSend`/IMP，
  `@interface` 只用于给类型。
- **路径分两种**（见 apelin-bootstrap-paths）：主题素材在**引导根**里（`/Library/ThemeCore`、
  `/Library/Themes`），必须走 `ApelinBootstrapPath()`；`/var/mobile/…`、容器路径是系统路径，
  原样写。绝不把解析出来的 jbroot 写进任何文件。
- 站点写法：只在类**自己声明**了该方法时才挂（`class_copyMethodList` 判定），
  每个 (类, 选择器) 各有一个静态原 IMP 槽，原实现用函数指针直接调、绝不在包装函数里查表。
- 诊断写进**目标进程自己的**偏好域（`kCFPreferencesCurrentApplication`），所以 SpringBoard 的在
  `com.apple.springboard` 域；日志用 `os_log`，subsystem 是包名，格式化符带 `%{public}`。
  `TCP_VERSION` 是 NSString 字面量，格式化只能用 `%@`。
- 面板 bundle **自带一份共享源码**（`SHARED_SRCS` = Paths/Config/Preferences/Store），
  所以它不依赖 dylib 的符号（自己扫盘、自己读写偏好）。代价：设置进程里同一批类名被注册两次，
  日志里会出现 "Class TCPThemeStore is implemented in both …" 的**预期告警**，功能无碍；
  两个镜像各用各的实例，别试图让面板和 dylib 共享单例。

## 当前状态

- ThemeCorePlus 0.6.0 **已装机验证（2026-10-30）**：面板「主题美化 +」原先推入后空白（0 段 0 行）已修，
  用户在屏幕上确认能正常进入。复核脚本 `probe-prefs-check.js`（在 icli 进程里 load 面板 bundle、
  走真实生命周期）：`view()+viewWillAppear:` → **5 段 8 行 / 13 个单元**，重复进入与连续 reload 稳定。
- 装机用的包：Release `themecoreplus-v0.6.0` 资产（GitHub Actions run 40983356266 编译），
  100720 B，sha256 `beba61e58738a7b268e46f1482ac604d1a048dce7c6df15fe7662d55d61f98b7`，
  装机副本 `/rootfs/var/mobile/Documents/themecoreplus-f351970.deb`。二进制里核对过新代码标记
  `_tcpApplyingSpecifiers`（旧包没有）。**装包不会 reload 已跑的 SpringBoard**，改 dylib 必须重启进程才算数。
- dylib 在 SpringBoard 里活着：`icli prefs read com.apple.springboard ThemeCorePlusDiagnostics`
  = `v0.6.0;active=0;theme=-;gen=7;…;sites=10[-SBIcon:iconImageWithInfo:,…];roots=[…]`，
  `ThemeCorePlusCensus` 里 SBIconBadgeView / SBIconImageView / SBFolderIconImageView 都有。
- 未做（阶段二）：管理器 App（导入/解包 .deb、预编译不可变成品、revision 切换与回滚）、
  作者素材 `图标蒙板AnemoneEffects.zip`、只有 `IconBundles/icon.png` 的角标主题。

### 面板空白：成因与修法（已修，2026-10-30）

`PSListController` 的**段落缓存只在父类入口** `-[self setSpecifiers:]` 里重建；`-reloadSpecifiers`
内部先把 `_specifiers` 置 nil 再走 `setSpecifiers:`，而面板之前在自己的 `reloadSpecifiers` 包装里
直接动过 `_specifiers`/ivar，缓存就没重建 → 0 段 0 行（`-specifiers` 有值、KVC 也能看到 13 个单元，
但表格没段没行）。**修法：specifier 数组只经 `setSpecifiers:` 落地，不再碰 ivar。**

本机实测要点（`probe-prefs-check.js`）：
- 探针跑在 **icli 自己进程**里，必须先 `NSBundle load` 面板 bundle，否则 `No ObjC class named TCRootListController`。
- 只 `view()` 仍是 0 段（`viewDidLoad` 不是缓存重建点）；`view()+viewWillAppear:` 才是 5 段 8 行。
- `reloadSpecifiers` 连调两次、`viewWillAppear:` 重入都稳定，不递归。

取证坑（都踩过）：
- `icli ui tree` 刚 push 完新页面时会**继续报上一页（根列表）的元素**，别据此断定 push 没成功；
  以用户屏幕看到的为准，或去读该页自己写下的偏好副作用。
- `icli screen shot --output` 收的是**真实路径**（`/var/mobile/Documents/x.jpg`），shell 侧要看它得用
  `/rootfs/var/mobile/…`；两套命名空间写错时命令**静默成功、文件没落地**。
- 列表里的目标行要「先滚到底 → 再用 `icli ui tap "<文字>"` 逐步回滚重试」，一次滚过头就找不到了。

## 外出取证：桌面 / 插件设置内 / 别的 App，办完必须回到 Apelin 对话内

用户在聊天里看不到屏幕：离开 Apelin 前台那段时间对他就是黑箱 —— 既看不到你在干什么，也没法随时
回来看。用户 2026-10-30 先要求「不要再让我手动回来」，随后两次要求把时限写死，第二次原话：
「**去桌面上去桌面插件内去软件插件内回来 Apelin 对话内都写进硬性规定和技能包**」。
**三种去处一个都不例外，所有工程、所有对话适用。**

| 去哪儿 | 典型目的 | 目标时长 | 硬上限 |
| --- | --- | --- | --- |
| 桌面（主屏 / SpringBoard） | 看桌面图标、看 HUD 胶囊、截图 | 15~25 秒 | 60 秒 |
| 插件设置内（设置 ▸ 主题美化 + 面板） | 看面板是否正常、点开关、截图 | 25~40 秒 | 60 秒 |
| 别的 App 内（微信 / Safari / Filza…） | 定位现象、取日志、取证据 | 20~40 秒 | 60 秒 |

- **时间从哪儿算到哪儿**：从**最后一次 Apelin 在前台**（按下 Home / 拉起别的 App 那一刻）算到
  `icli app frontmost` 报 `wiki.qaq.apelin` 为止。一次完整往返实测 14 秒就够；60 秒是天花板，不是指标。
- **出去前一句预告、回来一句交代，都写在聊天正文里**：出去前说「我去桌面看 X，目标 20 秒」，
  回来后说「回到 Apelin：看到了 Y，外出 N 秒」。这两句话是用户在那段时间里唯一的把手。
- **到 60 秒无论做没做完，先回 Apelin**（`icli app launch wiki.qaq.apelin`）；要更多证据就分多次外出，
  每次出发时人都在 Apelin 里。不许「走一步看一眼」，出发前把命令 / 要点的元素 / 要截的图一次备齐。
- **长步骤不占屏幕，而且要在回来之后才跑**：云编译、下载、装包、`find` 扫盘、读诊断、改源码 ——
  先在屏幕这一侧回 Apelin，再跑它们。（实测 2026-10-30 12:12：去主屏截图往返 ≈15 秒，
  随后那个 47 秒的 `find` 是在 Apelin 已经回到前台之后跑的。）
- 去桌面走 `icli button home`（Apelin 在前台时界面类工具会被拒，报 "UI actions may not reach wiki.qaq.apelin"），
  回程 `icli app launch wiki.qaq.apelin`。
- 不要停在设置里汇报，也不要把验证推回给用户；**汇报里写清这次外出了多少秒，超了如实写**。

机制：`sh scripts/errand-in-app.sh <bundle-id> [秒] [要点的元素文字]` —— **一次调用就把证据带回来**：
进目标 App → `icli ui tap "<文字>"` 按 label 点元素 → 截图 → `icli ui tree` 界面元素树 → 回程。
回程写在 `trap EXIT/INT/TERM` 里（报错、超时、Ctrl-C 都会回），末尾用 `icli app frontmost` 校验并打印
`回到 Apelin: <前景 bundle-id>（外出 N 秒）`。本机实测（2026-10-30）：完整往返 14 秒，
回程后前台 = `wiki.qaq.apelin`。

读界面结构：`icli ui tree [--human] [--clickable-only]`（本机 `icli screen describe` /
`icli screen ocr` 恒返回 `screen capture failed`）；Apelin 的 `apelin_screen_read_tree` 只在
前台就是目标 App 时才有意义。`icli screen shot` 可用，要给用户看时 `cp` 进工程再 `file_show`。
点元素别用坐标（`icli screen tap x y` 在列表里跑偏过），用 `icli ui tap "<文字>"`。

