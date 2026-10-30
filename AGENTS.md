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
| `.github/workflows/countdownhud.yml` | HUD 的云编译 + 发 Release（tag `countdownhud-v1.1.1`） |
| `scripts/errand-in-app.sh` | 外出取证：进目标 App → 点元素 → 截图/界面树 → **trap 里强制回 Apelin** |
| `scripts/sync-skills.sh` | 本地技能目录 ↔ 仓库 `skills/` 双向同步（默认 push） |
| `scripts/sync-memory.sh` | 本地记忆 ↔ 仓库 `memory/memories.json` 双向同步（默认 push；`pull` 会覆盖本机，先看 diff） |
| `scripts/sync-all.sh` | **一把同步三样**：硬性规定（AGENTS.md）+ 技能包 + 记忆；`diff` 只比差异 |
| `skills/` | 技能包副本（`apelin_skill_read` 读的是 `~/Documents/wiki.qaq.apelin/skills/`，这里只是版本化并上 GitHub） |
| `memory/memories.json` | 记忆副本（Apelin 真正读的是 `~/Documents/wiki.qaq.apelin/memories.json`） |
| `.github/workflows/themecoreplus.yml` | ThemeCorePlus 的云编译 + 发 Release |
| `Sources/`、`Support/AxsDualSliceTweak.plist`、`scripts/build-dualslice.sh`、`.github/workflows/dual-slice.yml` | 原来的双切片模板（AxsDualSlice），**别动** |
| `Attachments/`、`probe1-3.js` | 素材与临时探针脚本 |

## 怎么出包

改完源码 push 到 `main`：只有 `ThemeCorePlus/**`、`Prefs/**`、`Support/ThemeCorePlus*`、
`scripts/build-themecoreplus.sh`、工作流自身变动才会触发（paths 过滤），以免白白重建已经验过的包。
同一次运行里发 Release（静态 tag `themecoreplus-v0.9.2`，每次运行都重建资产，sha256/体积会变）。
Release 资产地址：
`https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.2/com.yangzhou.themecoreplus_0.9.2_iphoneos-arm64e.deb`

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
  「5 秒后注销」：常规字色 **系统绿 `#34C759`**（v1.1.1 起，原为白 `#FFFFFF`），
  最后 3 秒橙 `rgb(255,158,10)`、最后 2 秒红 `rgb(255,69,59)`，到 0 显示「现在注销」再淡出
  （那一帧也是同一支红，代码里写了两处：`CHPaint()` 与倒计时结束的 block，改红要一起改）。
- **胶囊的尺寸与位置 = 岛的尺寸与位置（v1.1.0 起）**：本机的岛是 DynamicX 用系统
  `SBSystemAperture*` 那套造的假岛，位置由 VisibleIsland 的 `yPos` 调。插件不写死尺寸，
  而是每秒（显示期间）在自己之外的窗口里找那只横向胶囊 —— 优先类名带 `Island`/`Aperture`
  的窗口（`src=aperture`），退而认类名带岛字样的视图（`src=classname`）；多个候选按
  「是否在 Aperture 窗口 / 类名像不像岛本体 / 尺寸离 126×37 有多远」打分取最高。找不到
  才退回写死的 190×44、安全区顶 +6（`src=none`）。选中项一并写进诊断（见下）。
- **文字尺寸 = 胶囊高度 ÷ 3（v1.1.1 起）**：原来取高度的一半（本机岛上 18.5pt），用户
  2026-10-30 15:38 反馈「字体太大、不够精致」，压到 2/3（= 高度 ÷ 3，同一只岛 12.3pt），
  字重 Semibold → Medium，数字用 `monospacedDigitSystemFontOfSize:` 让每秒跳动不左右抖。
  再要调就改 `CHApplyPillRect()` 里那一个系数（÷3 = 原来的 ×0.5 的 2/3），夹取范围 9~16pt。
  实际用的字号写进诊断 `font=`。
- 从 shell 写这个文件必须加真根前缀：`/rootfs/var/mobile/Library/Preferences/.countdownhud-request`
  （脚本已包好，见 `scripts/respring-guard.sh`）。
- 验证：`icli prefs read com.apple.springboard CountdownHUDDiagnostics`
  → `v1.1.1;shows=N;last=5s;label=注销;font=12.3;island=<类名>|x,y,w,h;src=aperture;cand=N`；
  量到的候选清单：`icli prefs read com.apple.springboard CountdownHUDIslandCandidates`
  （最多 8 行 `A|<类名>|x,y,w,h`，前缀 A = 在 Aperture 窗口里）；
  日志 `icli log syslog --subsystem com.yangzhou.countdownhud`。
- 卸载：`irisin-cli remove com.yangzhou.countdownhud`；不装它时脚本照样终端倒计时，只是屏幕上没有胶囊。

**规矩：以后装包 / 注销 / 杀进程前，一律 `sh scripts/respring-guard.sh 5 <标签>`**（标签写清动作，
如「注销」「装包」），让屏幕和聊天正文同时有 5 秒。

## 每轮开动之前：本机全部技能 + 全部记忆 + GitHub 云端全部技能与项目（硬性规定）

用户 2026-10-30 16:12 与 16:14 两次明确要求，**适用于本次、下次、以后每一个对话、每一个工程**：

- **本机全部技能包都要调用**：开工先 `apelin_skill_list`，再逐个 `apelin_skill_read` 把本机那几份
  **全部**读完 ——
  `a11-roothide-ondevice`（本机 A11/roothide 的设备侧做法、云编译闭环、一站一槽钩子修法）、
  `axs-ios-tweaks`（Axs 个人约定的工程规范：命名空间、面板、滑条、Rootful/Rootless/Roothide 打包适配）、
  `respring-notify-countdown`（装包/注销/杀进程前的通知与 5 秒倒计时、外出取证必回 Apelin）。
  不许只挑一份读，也不许拿「我记得内容」代替真读；Apelin 内置技能照旧按任务需要读。
- **全部记忆一起读**：`apelin_memory_list`（加 `all_projects: true` 就是全部工程、全部对话的记忆），
  给别的工程干活时用 `apelin_memory_list project: <folder|projectID>`；动手前先看记忆里已有的结论与坑，
  有新结论就 `apelin_memory_save` 写回（用户级偏好用 `scope: global`，工程事实用默认 project）。
  记忆与用户当前原话冲突时，以用户当前原话为准。
- **GitHub 云端的全部技能与项目一起用**（账号 `yangzhou521`，**只认越狱插件相关的两个仓库**）：
  - 云端技能 = 本仓库 `skills/`（本机技能目录的版本化副本，两边用 `scripts/sync-skills.sh` 保持一致）
    ＋ `AxsTweakKit` 里的模板、生成/自检脚本、CI 工作流模板。本机与云端不一致时，先同步再动手。
  - `yangzhou521/AxsTweakKit`（`master`）= Axs 的越狱工程工具箱：工程模板 `Templates/AxsDualSlice`、
    生成/自检脚本、CI 工作流模板、命名空间与面板写法约定。**新插件、新工程优先复用它的形状。**
  - `yangzhou521/yangzhou-DualSlice`（`main`，**就是本工程**）= 实际产品与脚本：ThemeCorePlus
    （主题引擎 + 设置面板）、CountdownHUD（倒计时胶囊）、`scripts/*.sh`、`skills/` 副本、各条 CI 工作流。
  - **只认这两个越狱插件相关的仓库**：`AxsTweakKit` 与 `yangzhou-DualSlice`。账号下别的仓库
    （如 BPB-Worker-Panel、edgetunnel 这类 fork）**不写、不动、不碰**，也不引用。
  动手写新的东西之前先看仓库里已有的同类实现，不另起一套。
  本机没有 curl/wget/python3，读云端用 `apelin_web_fetch`，或 `icli probe` + `NSData`
  （`raw.githubusercontent.com` / `api.github.com`）。
- **云端同步（硬性规定 + 技能包 + 记忆，三样一起）** —— 用户 2026-10-30 17:19 原话：
  「本机上硬性规定、技能包和记忆以后同步上传云端 以后同步修改」。**所有工程、所有对话适用。**
  改完任何一样就 `sh scripts/sync-all.sh`（＝ AGENTS.md 核对 + 技能 push + 记忆 push），
  然后用 Apelin 的 git 工具 `git_commit(all: true)` → `git_push` 到 `main`，**一次提交里三样一起走**，
  不留「本机改了、云端还是旧版」的半截状态。三样各自的位置：

  | 什么 | 本机（Apelin 真正读的） | 云端（仓库里） | 同步 |
  | --- | --- | --- | --- |
  | 硬性规定 | 本工程 `AGENTS.md`（技能里的同类条文在 `skills/*/SKILL.md`） | 仓库根 `AGENTS.md` | 就是仓库文件，push 即上传 |
  | 技能包 | `~/Documents/wiki.qaq.apelin/skills/` | `skills/` | `sh scripts/sync-skills.sh [push\|pull]` |
  | 记忆 | `~/Documents/wiki.qaq.apelin/memories.json` | `memory/memories.json` | `sh scripts/sync-memory.sh [push\|pull\|diff]` |

  本机那份是 Apelin 真正读的，仓库那份是版本化与云端备份，**两边必须一致**；换机或别的会话改过仓库时
  才用 `pull`（`sync-memory.sh pull` 会覆盖本机记忆，先看它打印的 diff 再确认）。

## 设备状态自己查（全权限）

用户 2026-10-30 16:30 原话：「icli状态以后你自己查 给你全权限」。**所有工程、所有对话适用。**

- 凡是要设备 / 插件 / 云端**此刻状态**才能决定下一步的事，一律自己查完再汇报：`icli prefs read` 读诊断、
  `icli app frontmost/list`、`irisin-cli list/show`、读 `/var/lib/dpkg/status`、`icli probe`+NSData
  下载并校验（大小 / sha256 / `cmp`）、列目录 / 读 plist / `grep -a` 抽二进制、`icli ui tree` /
  `apelin_screen_read_tree`、GitHub API 读 run 与 Release 状态。**不把查询推回用户、不让他截图或读屏替我、
  不来回确认**；查不到就换一条路（换命令 / 换域 / 换探针），不是回头问。
- **全权限不免仪式**：装包（`irisin-cli install`）、注销（`icli sb respring`）、重启目标进程
  （`icli app kill --force`）仍必须先 `apelin_notification_send` → 正文写「5 秒后执行」 →
  `sh scripts/respring-guard.sh 5 <标签>` 真等 5 秒 → 才执行；离开 Apelin 取证仍受 60 秒硬上限与
  「必须自己回来」约束；截图每次仍需用户当次明确同意。
- **Ask Before Using the Screen** 开着时，Apelin 自己的卡片仍会为读屏 / 交互 / 每条 icli 命令询问：
  那是用户的开关，只能他自己在设置里关，**我不代关**，卡来了正常走、不因此反复解释。
- 仍然不碰：系统关键设置、别的包的删除 / 降级、Apelin / Irisin / 引导自身的包。
- 技能包：`icli-status-self-check`（本机技能目录 `~/Documents/wiki.qaq.apelin/skills/` 与仓库 `skills/` 各一份）。

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
- **面板里凡是有「选择」的地方，一律用设置里那种系统开关（`UISwitch`），不许用对号 / 勾选标记。**
  用户 2026-10-30 17:09 / 17:11 原话：「插件面板的选择开关的按钮形状和 iOS 设置内的按钮保持一致！像启用插件开关一样！
  以后凡是应用到系统设置的插件，全部插件的开关都是按钮开关！不要用对号！」「不要用这个不好看不好用！」
  ——**所有工程、所有对话适用**，已写进技能包 `settings-switch-ui`、全局记忆与本文件：
  - 判据：插件只要挂在系统设置里（PreferenceLoader 面板，含二级页），功能开关、多选、单选，
    右端都是 `UISwitch` —— `PSSpecifier` 用 `PSSwitchCell`；纯 UIKit 页把 `UISwitch` 放进
    `cell.accessoryView`（与「启用插件」那颗同一个控件、同一套观感）。
  - 明确不用：`UITableViewCellAccessoryCheckmark`、自己画的对号 / 勾选图、
    `UITableViewCellAccessoryDetailButton` 之类冒充选择态的配件。
  - 多选列表照样用开关：**打开的顺序就是生效顺序**，关掉 = 取消这一项；点整行应与拨开关等价。
  - 本工程落点：`Prefs/ThemeCorePlusPrefs/TCRootListController.m` 里的 `TCPThemeSwitchCell`（0.9.3 起）。
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

- **CountdownHUD 1.1.0 已装机（2026-10-30 12:2x）**：CI run 41002300177（提交 `27363e43`）编译，
  `com.yangzhou.countdownhud_1.1.0_iphoneos-arm64e.deb` 14032 B，装机副本
  `/rootfs/var/mobile/Documents/countdownhud-1.1.0.deb`；注销后新代码生效。
  本机量岛实测：`island=SBSystemApertureContainerView|125,18,125,37;src=aperture;cand=4`
  （候选清单还有 `UIView|125,18,125,37`、`_SBSystemApertureGainMapView|125,18,125,37`、
  `UIView|115,17,145,47`）—— 也就是说 DynamicX 的岛本体就是 **125×37、居中、y=18**，
  胶囊现在按这个矩形画。**用户 2026-10-30 14:07 目视确认「基本可以」，之后先观察一段时间**。
  验证法（本机唯一可行）：写 8 秒倒计时请求 → `icli button home` → 5.5 秒后 `icli screen shot`，
  这时胶囊是橙色（最后 3 秒橙、最后 2 秒红），彩色块＝本插件画的、黑块＝岛/底衬，用户比对边界。
  **本机 `icli screen describe` 与 `icli screen ocr` 都报 `screen capture failed`**（同一环境
  `icli screen shot` 正常），所以「把屏幕读成文字」这条路在本机不可用，屏上观感只能靠用户看；
  agent 自己也看不了图（读图工具回「模型不支持图像」）。截屏只用于这次比对，用完即删。
- **CountdownHUD 1.1.1 已装机并生效（2026-10-30 15:50 装、16:40 别人那次注销带进去）**：
  deb 14084 B ← `/rootfs/var/mobile/Documents/countdownhud-1.1.1.deb`（CI 提交 `e500d545`，
  tag `countdownhud-v1.1.1`）。装前把已装 dylib 与包内解出来的做 `cmp`（**必须做**，本机有
  CDN 返回旧构建的坑），一致才继续。生效后诊断 =
  `v1.1.1;shows=1;last=3s;label=自检;font=12.2;island=SBSystemApertureContainerView|92,18,191,36;src=aperture;cand=11`
  —— `shows` 归零可当「SpringBoard 真载入了新代码」的判据（1.1.0 时同域是 `shows=3`）。
- **岛宽会变，别写死**：同一天先量到 `125,18,125,37`，注销后又量到 `92,18,191,36`（候选 11 项）。
  插件按量到的矩形画就对了；用户改 VisibleIsland 宽度或岛处于展开态都会变。
- **颜色不靠截图也能量**：`icli probe` 里 `[UIColor systemGreenColor]` 是动态色，
  直接 `.CIColor()` 会抛 `-CIColor not defined for … need to first convert colorspace`；
  先 `resolvedColorWithTraitCollection:[UITraitCollection currentTraitCollection]`，再读它的
  `.description()` 就有分量：本机 systemGreen = `kCGColorSpaceModelRGB 0.141176 0.541176 0.239216 1`
  （RGB 36,138,61），橙 (201,52,0)、红 (215,0,21)。现成探针 `probe-color.js`。
- ThemeCorePlus **0.6.1 已装机（2026-10-30 12:05 起）**，SpringBoard 稳定、脱离安全模式：
  `icli prefs read com.apple.springboard ThemeCorePlusDiagnostics` =
  `v0.6.1;active=1;…;disp{look=125,hit=111};icon{look=12,skip=0,miss=8,hit=4}`（图标站在真干活）。
  0.6.0 的崩溃根因写在提交 `ef781ae1`：`TCPIconImageInfo` 多写 `reserved[5]` 把 4 个 double 的 HFA
  撑成 8 个 → 编译器改成从 x2 取结构体指针，而系统调用方不设 x2 → `tcpIconHook6+0x20` 崩；
  现在结构体与系统一致，并加了 `_Static_assert(sizeof(...)==32)`。
- **ThemeCorePlus 0.9.3 待装（2026-10-30 17:0x~17:2x 改）**：面板只剩「主题」——「素材开关」四行删干净、
  「系统原生外观」那行删掉、主题行副标题带素材清单；四类素材一律全换（默认开启，没素材就不换也不加载）；
  「选择主题」页每一行右端是**系统开关**（`UISwitch`，与设置里「启用插件」那颗同款），不用对号，
  而且**整页只有主题行**：段落标题与页脚说明都删了。
- 装机用的 0.6.0 包：Release `themecoreplus-v0.6.0` 资产（run 40983356266 编译），
  100720 B，sha256 `beba61e58738a7b268e46f1482ac604d1a048dce7c6df15fe7662d55d61f98b7`。
  **装包不会 reload 已跑的 SpringBoard**，改 dylib 必须重启进程才算数。
- 未做（阶段二）：管理器 App（导入/解包 .deb、预编译不可变成品、revision 切换与回滚）、
  作者素材 `图标蒙板AnemoneEffects.zip`、只有 `IconBundles/icon.png` 的角标主题。

### 多主题叠加：规则与写法（0.7.0）

用户 2026-10-30 12:25 要的「通用多选」：主题不再是单选，可以叠。「图标包 ＋ 角标包」这种各管一块的
组合同时生效，重叠的部分后勾的说了算。

- **偏好键 `ThemePaths`**（有序数组，**靠后的覆盖靠前的** ＝ 靠后的是上层）。旧的 `ThemePath` /
  `ThemeName` 仍然读得懂（单主题时老写法照常工作）；面板一旦勾选就只写 `ThemePaths`，
  并且会把那两个旧键**删掉** —— 两个键共存规则就说不清，所以不共存。
- **实现要点**：`-[TCPThemeStore resolveThemePathsWithValues:]` 把数组去重、去空、只留确实存在的
  目录、上限 8 层，然后 `reload` **从最后一层往前扫**。各索引表（`iconMap`/`namedMap`/
  `globalFileMap`/`bundleFileMap`）都是「先到先得」（`if (!entry[key])`），所以倒着扫 = 靠后的优先；
  作者素材（蒙板/底图/overlay/文件夹底板）也按层补缺（表里有就不再动）。单个主题内部的行为
  与只支持单主题时一字不差。
- **面板**：`TCPThemeChooserController` 用「一行一颗系统开关」，开着的顺序即叠加顺序，副标题写「叠加第 N 层 ·
  根目录名」，关掉开关 ＝ 取消这一层（点这一行同样），「系统原生外观」那行已删（关光所有开关就是它）；
  拨完**不自动 pop**，右上角有「完成」，Preferences 的返回键也能回去。改完立刻 `TCPPostPreferencesChanged()`。
- **诊断**：`ThemeCorePlusDiagnostics` 里多了 `layers=N[层1|层2|…]`（从左到右 = 从下到上；
  末尾那个 `themes=` 是「扫到几个主题」的普查，两回事），`theme=` 是「层1 + 层2」的合并名，
  `mask/base/overlay/folder` 是最终选中的四样素材。
- **路径容错**：存的路径每层都过 `TCPReResolveThemePath()`（Paths.h）：原样能用就用；不行就把
  `/Library/…` 之后的部分重新贴到**本进程**解析出的同名根上（治隐根换名）；再不行按目录名在根里找
  同名主题。**shell 手写 `ThemePath` / `ThemePaths` 时可以直接写 `/Library/ThemeCore/液态玻璃.theme`**
  ——以前不行，因为系统进程里 plain 策略看不见（诊断 `try=[…,plain:0]`）。
- shell 手写叠加链（写数组要用 `--type json`，`--notify` 能让 SpringBoard 立刻重读，不用注销）：
  `icli prefs write com.yangzhou.themecoreplus ThemePaths '["/Library/ThemeCore/角标：透明玻璃","/Library/ThemeCore/液态玻璃.theme"]' --type json --notify com.yangzhou.themecoreplus.preferences-changed`；
  清空用 `icli prefs delete com.yangzhou.themecoreplus ThemePaths`。

### 面板版式与「选择主题」页（用户 2026-10-30 14:37 → 17:03 的定稿）

根页三组（照 ThemeCore 0.5.1 的样子，**不写功能说明**）：

| 组 | 内容 |
| --- | --- |
| 通用 | `启用插件`（`TCPKeyEnabled`，默认开） |
| 主题 | `选择主题`（右侧灰字写当前状态：`系统原生外观` 或 `主题名（N 层）`）＋ `刷新图标` |
| 底部 | 作者行：`作者：yangzhou · v<版本>` ＋ 一行状态；其下 `运行日志`（`TCP_PANEL_LOG_ENTRY`＝0 时整段消失） |

**「选择主题」页（`TCPThemeChooserController`，纯 UIKit 的 UITableViewController，只有一段）**：

- **这一页只有主题行，别的什么都没有**（用户 2026-10-30 17:1x 原话：「选择主题 里面只有主题项目，
  用来开关选择主题素材包！别的不要有！别的功能默认开启！它们没素材既不生效也不加载！」）：
  段落标题（原来是「主题（N 个）」）与整段页脚说明都已删，页面就是一张光列表 —— 每一行一个主题，
  右端一颗开关。别的功能（图标 / 文件夹 / 角标 / 系统界面图）一律**默认开启**、面板上不给开关；
  主题里没有那类素材，就既不生效也不去加载（`TCPThemeStore` 里 flags 恒为四类全开）。
- 一行一个：标题＝主题名，副标题＝`第 N 层 · 图标 84 · 角标 3 · 界面图 7`
  （没勾时副标题开头写主题所在的根目录名；一类素材都没有就写「里面没有可用素材」）。
- **右端是系统开关**（`TCPThemeSwitchCell`）：`UISwitch` 作 `accessoryView`，与设置里「启用插件」那颗
  同一个控件、同一套观感 —— **不用对号**（用户 2026-10-30 17:09 起的硬规矩，见下节）。开关被拨 =
  唯一写入口 `-tcpToggleThemeAtIndex:`；**点这一行同样拨这颗开关**（保留原来单击选上的手感），
  越界行把开关停用，单元复用时先 `removeTarget:` 免得串行。
- **开关 = 叠加**：打开顺序就是叠加顺序，靠后的盖住靠前的（同一张素材谁在上层用谁的）；
  关掉开关取消这一层；到 `TCPMaxThemeLayers`（8）弹窗明说并把那颗开关拨回原位，不静默丢选择。
  （这套语义原先写在页脚，17:1x 起页脚也删了 —— 页面上除了主题行不留任何文字。）
- **`系统原生外观` 那行已删**（用户 17:03）：全部关掉就是系统原生外观，回滚不再占一行，
  面板里也没有单独的「清空 / 恢复」按钮（`-tcpRestoreNativeAppearance` 只留给别的入口用）。
- **分类素材开关（`素材开关` 一段四行）已整组删掉**（用户 16:59 / 17:00）：四类素材一律全换；
  `IconsEnabled / FoldersEnabled / BadgesEnabled / FilesEnabled` 四个键不再读、不再写
  （`TCPThemeStore` 里 flags 直接全开），老偏好里留着什么都不理会。
- 历史包袱别踩：这一页原先用 `PSListController` + `PSLinkCell`，进页面就崩（Preferences 给
  specifier 备元数据那步）；现在是纯 UIKit，并且把 Preferences 塞进来的
  `specifier / parentController / rootController` 全部实现成空操作。

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

