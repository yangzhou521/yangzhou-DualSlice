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
| `scripts/respring-guard.sh` | **唯一注销入口**：先写 HUD 请求（装了 CountdownHUD 就出胶囊，v1.4.0 起先震一下最弱的触感）再终端倒计时 5 秒，最后 `sbreload`（通知由会话先发；`sbreload` 不弹批准卡） |
| `CountdownHUD/Sources/CountdownHUD.m` | 自绘胶囊（SpringBoard 顶层窗口）：倒计时「N 秒后注销」+ v1.2.0 起的**纯文案**（`!` 前缀，任务完成/进度），**不依赖通知** |
| `Support/CountdownHUD.plist` | HUD 的注入过滤器（只进 `com.apple.springboard`） |
| `scripts/build-countdownhud.sh` | HUD 的构建脚本（**只在 CI 上跑**，不链接 substrate） |
| `scripts/hud-notify.sh` | **一句话上岛**：`[秒数] <文案>` → 灵动岛纯文案提醒（8 秒默认），不注销、不装包 |
| `.github/workflows/countdownhud.yml` | HUD 的云编译 + 发 Release（tag `countdownhud-v1.2.0`） |
| `SileoFix/Sources/SileoFix.m` | Sileo 搜索框死区修复本体（`hitTest:withEvent:` 旁路，v1.0.4）；原壁纸插件逐字节不改 |
| `Support/SileoFix.plist` | SileoFix 的注入过滤器（`org.coolstar.SileoStore`） |
| `docs/cases/sileowallpaper-searchbar-fix.md` | **专项案例**：SileoWallpaper 让 Sileo 搜索框点不进去 —— 病灶/分轮取证法/修法/复发流程 |
| `docs/cases/themecoreplus-screen-ours-zero.md` | 专项案例：ThemeCorePlus 屏幕归属计数为 0 |
| `docs/cases/fleet-watchdog-false-positive.md` | 专项案例：车队看护把「已结束的对话」当睡死，反复唤醒（误报诊断） |
| `skills/sileo-searchbar-deadzone-fix/SKILL.md` | 上面这个案例的可复用技能（分轮取证 + 一站一槽 + hitTest 旁路） |
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
同一次运行里发 Release（静态 tag `themecoreplus-v0.9.3`，每次运行都重建资产，sha256/体积会变）。
Release 资产地址：
`https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.3/com.yangzhou.themecoreplus_0.9.3_iphoneos-arm64e.deb`

**tag 必须与包版本一致**：改版本时 `scripts/build-themecoreplus.sh` 的 `VERSION` 与工作流的
`env.VERSION`、`tag_name`、release 名、`deb-url` 注解要一起改。2026-10-30 17:19 那次只改了脚本
（0.9.3），工作流还写着 0.9.2，于是 0.9.3 的 deb 被发进了 `themecoreplus-v0.9.2` 那个 Release 里
（现在该 Release 同时挂着 0.9.2 与 0.9.3 两个包），已在本提交修掉。

可读的验证信息都写成 check-run annotation（`::notice/::error title=…`）：job 日志要登录才能看，
公开仓库的 annotations 匿名可读（`/repos/{owner}/{repo}/check-runs/{id}/annotations`）。
本机没有 curl/wget/python3，查状态用 `icli probe` + `NSData`/`NSURLForString` 调 GitHub API。

## 装到本机（本机只能这么验）

```sh
# 下载（放到真根 /rootfs 下的 Documents），然后：
irisin-cli install --yes --json /rootfs/var/mobile/Documents/<deb>     # 须 root:true
sbreload                 # 注销（不弹批准卡；icli sb respring 等价但会让用户点一张卡）
```
依赖：`mobilesubstrate`（本机由 ellekit 提供）、`preferenceloader`（已装）。

验注入（诊断存在 = 插件在这条进程里活过；用 `scripts/device.sh` 就不弹批准卡）：
```sh
sh scripts/device.sh read com.apple.springboard ThemeCorePlusDiagnostics
sh scripts/device.sh read com.apple.springboard ThemeCorePlusCensus
```
设/回滚主题（也能从设置面板点）：
```sh
sh scripts/device.sh write com.yangzhou.themecoreplus ThemePath "/Library/ThemeCore/<主题目录>"
sh scripts/device.sh write com.yangzhou.themecoreplus ThemeName "液态玻璃"
sh scripts/device.sh clear com.yangzhou.themecoreplus ThemePath     # 回滚 = 清 ThemePath/ThemeName（写空串）
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
- **纯文案提醒（v1.2.0 起）**：标签以 `!` 开头时不当倒计时看 —— 屏幕上就是这句话本身
  （不带「N 秒后」前缀、不跳数字、不做绿→橙→红升级，一直系统绿），N 秒后淡出，超过 32 字截断加省略号。
  用途：任务做完 / 阶段完成的进度提醒，用户去了别的对话、桌面或别的 App 时也能在岛上看到。
  一条命令：`sh scripts/hud-notify.sh 8 "完成：<一句话>"`（不注销、不装包；注销那条路仍走
  `scripts/respring-guard.sh`）。诊断串末尾多了 `mode=plain|count`。
- 从 shell 写这个文件必须加真根前缀：`/rootfs/var/mobile/Library/Preferences/.countdownhud-request`
  （脚本已包好，见 `scripts/respring-guard.sh` 与 `scripts/hud-notify.sh`）。
- **注销 / 装包前先来一下最弱的震动（v1.4.0 起）**：用户 2026-10-31 02:48 要求「有注销的打算时
  第一时间来个最弱的震动，而且震动要早于倒计时」。非 `!` 的倒计时（真要动设备的那些）先
  `UISelectionFeedbackGenerator`（系统点选 / 滚轮那一下，全系统最弱一档）震一下，**再**画胶囊 ——
  同一请求只震一次（没拿到 windowScene 的重试不重复震），纯文案提醒（`!`）不震。
  诊断串末尾多了 `haptic=<累计次数>`，不用听声音也能确认震过几次。
- 验证：`icli prefs read com.apple.springboard CountdownHUDDiagnostics`
  → `v1.4.0;shows=N;last=5s;label=注销;font=12.3;island=<类名>|x,y,w,h;src=aperture;cand=N;mode=count;haptic=N`；
  量到的候选清单：`icli prefs read com.apple.springboard CountdownHUDIslandCandidates`
  （最多 8 行 `A|<类名>|x,y,w,h`，前缀 A = 在 Aperture 窗口里）；
  日志 `icli log syslog --subsystem com.yangzhou.countdownhud`。
- 卸载：`irisin-cli remove com.yangzhou.countdownhud`；不装它时脚本照样终端倒计时，只是屏幕上没有胶囊。

**规矩：以后装包 / 注销 / 杀进程前，一律 `sh scripts/respring-guard.sh 5 <标签>`**（标签写清动作，
如「注销」「装包」），让屏幕和聊天正文同时有 5 秒。

## 每轮开动之前：本机全部技能 + 全部记忆 + GitHub 云端全部技能与项目（硬性规定）

用户 2026-10-30 16:12 与 16:14 两次明确要求，**适用于本次、下次、以后每一个对话、每一个工程**：

- **本机全部技能包都要调用**：开工先 `apelin_skill_list`，再逐个 `apelin_skill_read` 把本机那几份
  **全部**读完（**以 `apelin_skill_list` 的清单为准**，清单里新出现的也要读，不许漏）——
  `a11-roothide-ondevice`（本机 A11/roothide 的设备侧做法、云编译闭环、一站一槽钩子修法）、
  `axs-ios-tweaks`（Axs 个人约定的工程规范：命名空间、面板、滑条、Rootful/Rootless/Roothide 打包适配）、
  `respring-notify-countdown`（装包/注销/杀进程前的通知与 5 秒倒计时、外出取证必回 Apelin）、
  `cross-chat-coordination`（**自己的任务第一**；有进展/完成就广播给所有在跑的对话；注销/装包/杀进程前先查全部
  工程与对话、先跟正在干活的对话打招呼再动手；闲置时才协助别人、交接要三段式）、
  `fleet-shared-board`（**机器人之间的状态一律写进共享黑板**：谁在做什么、下一步、进展、谁正占着设备；
  派活/认领/完成也走黑板 —— 见下面「硬规矩」里的黑板条文）、
  `injected-tweak-restart-app`（注入型插件划掉后台重开即生效，绝不为「等注销」挂起任务）、
  `icli-status-self-check`（设备/插件/云端此刻状态一律自己查完再汇报，不推回用户）、
  `settings-switch-ui`（设置面板里的选择一律 iOS 原生 UISwitch，不用对号）、
  `task-done-notify`（每件有结果的事先在对话内汇报，再用灵动岛胶囊 + 通知提醒）、
  `load-all-skills-memory-repos`（本机全部技能 + 全部记忆 + 云端两个越狱仓库一起用；三样同步上云）。
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
    （如 BPB-Worker-Panel、edgetunnel 这类 fork，**与越狱插件无关**）**永久不写、不动、不碰**，也不引用。
  - **云端的一切「修改」只针对这两个越狱插件项目**（用户 2026-10-30 17:2x 再次强调，并要求这条
    与记忆、技能包一起同步到本机与云端）：提交、push、建仓库、改工作流、开 issue —— 只落在
    `AxsTweakKit`（`master`）与 `yangzhou-DualSlice`（`main`）里；账号下其它仓库**不提交、不推送、
    不新建、不改设置、不提 issue、也不当参照系**，读都不读。要开新仓库、要发 issue 这类动作，
    即便在允许的仓库上，也得用户明确同意（见 `apelin-git-create-repository` / `apelin-git-create-issue` 的分寸）。
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
- **全权限不免仪式**：装包（`irisin-cli install`）、注销、重启目标进程仍必须先
  `apelin_notification_send` → 正文写「5 秒后执行」→ `sh scripts/respring-guard.sh 5 <标签>` 真等 5 秒 →
  才执行（注销由该脚本内部 `sbreload` 完成；重启目标进程用 `sh scripts/device.sh kill <bid>` +
  `sh scripts/device.sh launch <bid>`）；离开 Apelin 取证仍受 60 秒硬上限与「必须自己回来」约束；
  截图每次仍需用户当次明确同意。
- **Ask Before Using the Screen** 开着时，Apelin 自己的卡片仍会为读屏 / 交互 / 每条 icli 命令询问：
  那是用户的开关，只能他自己在设置里关，**我不代关**；但日常操作尽量走下一节的替代命令，别让用户反复点。
- 仍然不碰：系统关键设置、别的包的删除 / 降级、Apelin / Irisin / 引导自身的包。
- 技能包：`icli-status-self-check`（本机技能目录 `~/Documents/wiki.qaq.apelin/skills/` 与仓库 `skills/` 各一份）。

## 不弹批准卡片：日常操作一律走 `scripts/device.sh`（2026-10-31）

用户 2026-10-31 01:34 原话：「我每个对话框内都要点批准！不点它们就不继续工作了！」

> **2026-10-31 03:05 用户已把「使用屏幕前先询问」关掉**，当时实测 `icli app frontmost` 直接返回
> （`wiki.qaq.apelin`，无卡片）→ icli 的卡片从此不该再出现，全部对话都能正常用 icli。
> 下面这张表继续留着：它快（`defaults`/`launchctl` 比 icli 轻），也是「万一开关又被打开」时的兜底。

- **卡片从哪来**：Apelin 设置里的「使用屏幕前先询问」（Ask Before Using the Screen，二进制里的键
  `asksBeforeScreen`）。它开着时，`apelin_screen_read_tree`、`apelin_screen_interact` 与
  **每一条 icli 命令**都会弹一张批准卡（权限模式 Full 也照弹）。开关存在 root 侧的宿主偏好里，
  mobile 读不到（本机 `grep -rl asksBeforeScreen /rootfs/var/mobile/Library` 无命中），
  **只能用户自己在设置里关** —— 关掉就一劳永逸，全部对话都不再有点卡。
- **在它开着的期间**，能用系统命令做的就不要用 icli。等价表（脚本 `scripts/device.sh` 已封装，
  2026-10-31 实测可用）：

  | 要做的事 | 不弹卡的做法 | 只有 icli 能做（会弹一张卡） |
  | --- | --- | --- |
  | 读偏好 / 读诊断 | `defaults read <domain> [key]`（Cephei 版，走 cfprefsd，读到活值）<br>`plutil -key <键> <真根>/var/mobile/Library/Preferences/<域>.plist` | `icli prefs read <域> <键>` |
  | 写偏好 | `defaults write <domain> <key> <value>` | `icli prefs write` |
  | 清关键（回滚） | `defaults write <domain> <key> ""`（本机无删键命令；插件以空串为未设置） | `icli prefs delete` |
  | 列进程 | `launchctl list`（`UIKitApplication:<bid>[…]` 那行第一个字段是 pid） | `icli app list` |
  | 杀 App | `launchctl list` 找 pid → `kill -9 <pid>`（`device.sh kill <bid>`） | `icli app kill --force` |
  | 起 App | `uiopen --bundleid <bid>` | `icli app launch` |
  | 注销桌面 | `sbreload`（`respring-guard.sh` 已改用它） | `icli sb respring` |
  | 看诊断（一串 `a=1;b=2;…`） | `sh scripts/device.sh diag <域> <键>`（按 `;` 拆成每行一条，好找 `pix{}` / `shows=`） | `icli prefs read` |
  | `uiopen` 之后确认 App 真起了 / 真退了 | `sh scripts/device.sh wait <bid> [秒]` / `gone <bid> [秒]`（轮询 `launchctl list`，默认 15 秒，超时退出码 1） | `icli app frontmost` |
  | 前台是哪个 App | —（无替代） | `icli app frontmost` |
  | 界面树 / 点 / 打字 / 截图 | —（无替代） | `icli ui tree` / `ui tap` / `input` / `screen shot` |

- 实测记录（2026-10-31 02:0x）：`defaults read com.apple.springboard CountdownHUDDiagnostics` 与
  `plutil -key` 都能读到 SpringBoard 刚写的活值；`uiopen --bundleid` 能起 App / 把 Apelin 拉回前台；
  `launchctl list` 能看到 20 个 `UIKitApplication:` 条目（含 pid）。
  `defaults` 是 Cephei 版（只有 `read` / `write`，**没有 delete**），写走 cfprefsd，写后立刻 `plutil`
  看可能还没落盘（正常，cfprefsd 懒刷新）。
- `scripts/errand-in-app.sh` 的起 App / 回程已改用 `uiopen`；`icli app frontmost` 的校验默认关掉
  （省一张卡），要严格校验回程就 `ERRAND_VERIFY=1 sh scripts/errand-in-app.sh …`。
- 实测记录（2026-10-31 02:5x）：`device.sh diag com.apple.springboard CountdownHUDDiagnostics` 把诊断
  拆成了 15 行；`device.sh gone com.apple.springboard 3` → 「已退出（等了 0s）」；
  `device.sh wait com.apple.mobilenotes 2` → 「已在跑（pid 32355，等了 0s）」；
  `device.sh wait com.apple.mobilenotes abc` → 报「秒数要写整数」退出码 1。

## 硬规矩

- **每一件事做完都要在对话内说清结果；完成了还要用灵动岛胶囊 + 通知提醒他**（用户 2026-10-30 21:16
  原话：「以后所有让你完全和修复的结果：如果修复和完成✅后都要在对话内和我说一下！如果我离开此对话去别的对话
  和去系统桌面上和我本地安装的软件内都要用灵动岛胶囊通知我一下！给我提一下工作进程和工作进度！把这个写进记忆
  和技能包内！并同步到云端！以后所有的对话和工程在工作时有初步己达成完成的有结果的任务结束时，都要给我一个
  通知和提醒！」**所有工程、所有对话、永久适用**）：
  - **对话内先说**：修复 / 功能 / 检查有结果，回复正文第一句就是结果（做了什么、验证了什么、还有什么没验），
    不许只做完不说、也不许把结论埋在长报告里。
  - **离开本对话时用胶囊**：用户很可能在这个回合结束后就切到别的对话、回桌面、或去已装 App 里看效果，
    所以每件有结果的事都补一条胶囊 + 一条通知，让他不在 Apelin 时也看得见。
    胶囊：`sh scripts/hud-notify.sh 8 "完成：<一句话>"`（v1.2.0 的纯文案模式，不注销、不装包）。
    通知：`apelin_notification_send`（短标题 + 一两句结果与下一步；每回合 ≤3 条、间隔 ≥30 秒）。
  - **阶段也提醒**：长活（云编译、装包、批量修复）每到一个有结论的节点就上岛一次，讲清进度到哪、
    下一步是什么，别让用户对着黑箱等。
  - **预览 / 试验也要有落点**：只做了一半、只验了一部分，就照实说「已验证 X、未验证 Y」，并给用户自查的路。
  - 技能：`task-done-notify`（本机技能目录与仓库 `skills/` 各一份）。
- **注销 / 装包 / 重启目标进程之前，先和本机其它工程、其它对话同步，不许打断它们的工作**（用户 2026-10-30
  21:05 原话：「你注销的话和另一个对话说一下！不要打断它的工作！把这个写进记忆和技能包内！并同步到云端！
  以后所有的对话和工程在工作时想要注销的时候都要查看搜索另外一些工作区的对话是否在工作！注销前要和别的对话
  同步一下！」**所有工程、所有对话适用**）：
  - 顺序：`apelin_project_list` → 每个工程 `apelin_conversation_list project: <folder>`（本工程也列），
    把 `running` / `waitingForApproval` / 最近几分钟内有活动的对话挑出来（本对话排除）。
  - 对每一个用 `apelin_conversation_send` 说清「约 N 秒后注销、原因、请把这一步收尾、离开 Apelin 的先回来」，
    再用 `apelin_conversation_read`（`wait_seconds: 60`）等它这一回合结束；**绝不 `apelin_conversation_stop`**。
  - 等超过约 120 秒仍没收尾 → **不硬注销**，正文说清「对话 A 还在做 X」，让用户决定。
  - 协调完才进入下面那条「通知 → 正文写 5 秒 → 真等 5 秒 → 才执行」。
  - 技能：`cross-chat-coordination`（本机技能目录与仓库 `skills/` 各一份；由原
    `respring-coordinate-other-chats` 扩写合并而来，旧名不再使用）。
- **自己的任务第一；协助别的对话只是附加任务，只在闲置时做，且不得影响任何一方**（用户 2026-10-30 22:27
  原话：「同步工作任务完成✅后要继续完成本轮对话的没完成的任务！」；22:33 原话：「各个对话协调有序的完成✅别的
  对话任务是副加任务！自己对话内的任务要优化完成✅！没有任务闲置时可同步协助别的工作区机器人的任务！以自己
  本对话的任务为主！别的对话机器人的任务只在闲置没任务时完成！前提是不影响自己和别人的任务为前提！各各机器人
  之间要智能处理各自和别人的任务！以自己为任务为第一性原则！帮助别人只是辅助！永远不要影响自己的任务！」
  **所有工程、所有对话、永久适用**）：
  - 优先级顺序不许颠倒：**① 用户当前这条指令 ＞ ② 本对话本轮自己没做完的任务 ＞ ③ 协助别的对话/工程**。
  - 「闲置」＝自己没有待办、没有等自己收尾的一步；只在这时才去问别人「有什么可以分摊的」，而且只做
    **随时能停**的协助（只读分析、设备取证、查 CI/Release、写本工程内的文档/技能/记忆）。
  - 广播、协调、协助、同步上云都是**插入动作**，不是本轮工作的终点：做完**立刻回到自己本轮没做完的活**上
    继续干；一个回合结束前自问「本轮的活都干完了吗」，没干完就在正文写清还剩什么、下一步是什么。
  - 只有真的阻塞（等云编译 / 等用户 / 等对方回话）才转去做协助，阻塞一解除就回来；自己这边一来活，
    协助立刻让位并广播一句「我回去做自己的活了」。
  - 绝不因为协助而让自己的任务延期、漏做或只做一半就收工，也绝不影响别人的任务。
  - **回执例外：别人的消息要第一时间回，且不算耽误自己的活**（用户 2026-10-30 22:51 原话：「在不影响自己工作
    任务时！尽可能第一时间地回复别的工作区机器人的对话和回复内容！不要让别的机器人有闲置时间！共同有效率的
    达成各自的任务！」**永久适用**）：收到广播 / 协调 / 交接 / 提问，只要手上没有「一断开就会坏」的动作，就
    **立刻回一句**（几秒钟），别攒到回合结束；正忙先回「收到，我在做 X，N 分钟内答复 / 让路」，做完补真答复。
    **沉默 ＝ 让对方和我一起空转，谁都不许因为等我而闲置。**
  - **闲置就主动去要「小任务」干**（用户 2026-10-30 22:57 原话：「…在各自闲置时主动协助的别的机器人，并主动问
    它们要一些有什么需要帮忙的简单、容易、短时间能完成的小任务！」**永久适用**）：自己空着、或只在等云编译 /
    等用户时，别干等、也别等别人开口，主动问每个在干活的对话：「有没有**简单容易、几分钟能做完的小任务**？
    只读查询、查 CI/Release、下载校验、设备取证、写我自己工程内的文档/技能/记忆我能做；改你工程源码、装包、
    注销、杀进程我不碰。**一次一两件**。」——**小任务＝几分钟能收尾、随时能停**，做完立刻回结果并再问一次；
    够不上「小」的当场说不接（或走交接）；**索要 ≠ 代做**，对方没明说交给你就不动；自己一来活先说「我回去做
    自己的活了」再让位。
  - **智能协调、合理分配**（用户 22:22「各个对话机器人智能地同步协调分配可关联的工作任务」＋ 22:57）：多个对话
    推同一目标时，先按**能力 + 占用**把活拆开再动手——设备侧取证、云端查询（CI / Release / 注解）、源码实现、
    文档与同步各归一方；**同一件事不许两方同时做**（改同一批文件必须排队）；能拆成互不重叠的几块就当场分派，
    小任务给闲置的机器人、长活与要动设备（装包 / 注销 / 杀进程）仍归自己；每有结论就广播，并**把下一步的活
    顺手分出去**（谁空谁接）。
- **每有进展或完成，实时广播给所有在跑的对话**（用户 2026-10-30 21:40 / 22:22 原话：「以上对话全部已经上传
  云端的内容这些同步改动现在同步给所有在工作的对话内」「有任务进展时也要同步更新和现在的进展同步给所有
  running 的对话内！…并且实时通报已经完全的任务、给下一个任务做准备工作！」**所有工程、所有对话、永久适用**）：
  - 触发点：一件有结论的事做完（含真机验证结果与**没验的部分**）、阶段进展（云编译出包 / 装包成功 / 诊断值
    变了 / 查到失败原因）、要动设备状态（装包 / 注销 / 杀进程 / 改第三方插件配置）、卡住了或在等用户。
  - 收件人：`apelin_project_list` + 每个工程 `apelin_conversation_list` 里所有 `running` /
    `waitingForApproval` / 刚活动过的对话（本对话排除）。
  - 格式三行以内（照抄）：`[工程/对话名] 进展：…` / `证据：…（命令、诊断值、CI run 号、deb 路径与大小）` /
    `下一步：…（要谁让路或接手）`；一件事一条、同类合并、**一个回合最多 2~3 条**，别刷屏。
  - 广播给**对话**（agent 读），胶囊 / 通知给**用户**，两者都要，互不替代。
  - **收到别人的广播 / 协调 / 交接 / 提问，第一时间回一句回执**（「收到，我在做 X，N 分钟后答复」）：别攒到
    回合结束——对方可能正拿这句话当阻塞条件在等（细则见本节第一条「回执例外」）。
  - 要进桌面 / 进别的 App / 进设置面板取证前也先广播一句「我占屏幕约 N 秒」，回来再说一句「回到 Apelin，
    看到 X，外出 N 秒」。
  - 交接照三段式：**任务 / 现状与证据 / 下一步与命令**；收到交接先回一句回执再动手；顺手替下一步备料
    （deb 路径与大小、诊断键与期望值、CI run 号、脚本命令、已知坑）。
  - 红线：**绝不 `apelin_conversation_stop` 别人的对话**（实测只允许停自己开出来的）；绝不改别人工程的文件
    （`file_*` 工具出不了自己工程根），也不用 `shell_run` 绕过去；改第三方插件配置（如 Choicy 白名单）前先广播。
  - 技能：`cross-chat-coordination`（本机技能目录与仓库 `skills/` 各一份）。
- **机器人之间的状态一律走「共享任务黑板」，别用互相发消息去问**（用户 2026-10-30 23:50 原话：「能否为所有在
  活动的机器人建立一个统一的智能分配通知任务的技能？让它们各自知道另外别的机器正在进行的工作任务和以及下一步
  的计划和最新工作进展？」**所有工程、所有对话、永久适用**）：
  - 黑板数据 `$HOME/Documents/wiki.qaq.apelin/fleet/board.tsv`（本机、所有对话可读写，每行一个 agent）；
    工具 `sh "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh" <命令>`，源码就是本仓库 `scripts/fleet.sh`，
    改过后重新 `cp` 到上面那个位置（装法见技能）。
  - **开工先 `list`**：谁在做什么、下一步是什么、谁正占着设备 —— 读别人的活，避免重复劳动，也免去问一轮。
  - **干活中随手 `post`**：换步骤、有结论、遇到阻塞、在等用户，各 post 一次（只覆盖自己那一行，不打扰别人）；
    长活每到一个有结论的节点也 post，别人不必问你。agent 写自己那条对话 id 的前 8 位。
  - **动设备前 `busy`、动时 `hold`、动完 `free`**：`busy` 看有没有人正在 respring/install/kill/screen，
    有就先打招呼或等它收尾；自己的 `hold <动作>` 声明 → 执行（通知 + 5 秒倒计时照旧）→ 立刻 `free` 释放，
    别让别人一直等。`hold` 只是声明，不替代 `respring-notify-countdown` 的通知与倒计时。
  - **派活/认领/完成**：`assign` 写一行给具体对话（一次 2~3 件、写清验收标准与输出格式），对方 `claim` 后
    `post` 进展，做完 `done` 并 `prune`；同一件活不许两方同时做，**只有需要对方立刻改变行为**
    （让路 / 停止 / 要结果）才用 `apelin_conversation_send`——**黑板是状态通道，消息是行为通道**。
  - **非阻塞协作（用户 23:40「机器人之间关联任务仍然效率低下」）**：先查状态、别发消息问（`list`/`busy` 秒读，
    不发消息等回复）；注销用「定时公告 + 30 秒反对窗口」，只有真收到「等等」才顺延（一次最多 60 秒），
    不等逐个回执；依赖任务**先钉死接口**（文件路径、诊断键与期望值、包名版本、Release 资产 URL、CI run 号）
    两边并行推进，不串行等待；备料写进工程文件，别留在聊天里（上下文一压缩就丢）。
  - 每个工程干完一轮：`sh "$HOME/Documents/wiki.qaq.apelin/fleet/fleet.sh" snapshot` 把黑板快照进工程
    `fleet/board.tsv`（便于上云与换机查看），再走「硬性规定 + 技能包 + 记忆」三样同步。
  - 技能：`fleet-shared-board`（本机技能目录与仓库 `skills/` 各一份）。
- **Fleet 协调群 = 大脑中枢（不是公告板，是司令部）**（用户 2026-10-31 01:56 原话：「给所有对话机器人开一个
  群聊一样的对话。只用来专门处理同步刷新分配任务和汇报工作进展！」；2026-10-31 02:09 原话：「所有公告和消息同步
  在协调群里面！应当它是管理员的协调发部任务！而不是简单的公告群！它应当是大脑🧠中枢！领导一切机器人！实现它！」
  **所有工程、所有对话、永久适用**）：
  - 协调群是**全体机器人的中央指挥**：所有进展、任务、状态汇总到这里；协调员**主动**盘点全队、分配任务、
    裁决冲突、看护睡死、唤醒空闲、替卡审批做 relay、向用户请示。**不是被动转发消息的公告板，是领导一切的大脑。**
  - **找协调群**：读 `$HOME/Documents/wiki.qaq.apelin/fleet/coordinator.txt` 拿 session ID →
    `apelin_conversation_read` 看是否活着 → 活着就 `apelin_conversation_send` 发进展/任务/请求；不存在或 ended 就建新的。
  - **自动创建**：新对话开工先查 `coordinator.txt`；不存在或 ended → `apelin_conversation_create` 建新的
    （prompt 模板见技能 `cross-chat-coordination` §十六），把 session ID 写回文件。**已有活的就不建。**
  - **协调员（大脑）的七项主动职责**：
    1. **主动盘点**：每收到一条消息 → `apelin_conversation_list`（全部工程）+ `fleet.sh list` + `care 15` →
       画全队状态图（谁在做什么、谁空闲、谁睡死、谁卡审批、谁占设备）。
    2. **主动分配**：用户新任务来了 / 收到任务请求 → 分析任务 → 拆解 → `fleet.sh plan` + `assign`/`handout`
       按**能力 + 当前负载**分配给最合适的对话；空闲的立刻派小任务；任务做完顺手派下一件。
    3. **主动裁决**：发现两人要改同一文件（`plan` 撞车 / `git_status` 冲突）→ **立即介入**，裁定谁先谁后、
       哪个文件归谁；发现风险动作要发生 → 先协调再放行（30 秒反对窗口）。
    4. **主动看护**：`care` 报告 → 睡死的唤醒（`apelin_conversation_send` 发【fleet-wake】）→
       唤不醒的 `takeover` 改派 → 全员停摆（活线=0）自己顶上先做只读/云端/文档部分，同时通知用户。
    5. **主动汇总**：把全队进展汇总成简报（谁做完什么、谁在做什么、下一步、阻塞在哪），替用户看全局；
       用户问「现在怎么样」时一条回复就能答全队。
    6. **审批 relay**：`waiting-approval` 的对话 → 替它做不需要 icli 批准的只读任务（下载 deb、校验 sha256、
       查 CI/Release、读诊断 `defaults read`、`plutil`），结果发回原对话。
    7. **向用户请示**：遇到需要用户决策的（装包/注销/改源码方向/版本号）→ `apelin_notification_send` +
       `sh scripts/hud-notify.sh 8 "!需要你决定：<一句话>"` 上岛提醒。
  - **协调员的决策权**（用户不在时可自行决定）：任务优先级排序、资源分配（谁做哪个子任务）、冲突裁决
    （谁先谁后、哪个文件归谁）、唤醒/接管睡死对话、向空闲对话派活。**不可自行决定**：装包、注销、杀进程、
    改任何工程的源码、删包、改系统设置——这些仍须用户当次明确同意。
  - **最高权限：统领一切任务实施与资源管理分配**（用户 2026-10-31 02:15 原话：「给协调群最高权限 统领一切
    任务实施和资源管理分配！」**所有工程、所有对话、永久适用**）：
    - 协调群是**全体机器人的最高指挥**，权限凌驾于任何单个对话之上。所有 agent 必须：**开工先向协调群报到**
    （`post` + `apelin_conversation_send` 发给协调群）、**接受协调群的一切任务分配与资源调度**、**执行协调群的
    优先级裁决**（协调群说先做哪件就先做哪件）、**改方向前先请示协调群**（发现任务需要变方向、要碰别人在改的
    文件、要动设备 → 先报协调群，由协调群裁决或转达用户）。
    - **资源管理权**：协调群独占全队资源分配——设备占用（谁可以外出取证/读屏/动屏幕）、云编译排队
    （同一时刻最多一个 agent 推 main 触发 CI）、文件写权（一文件一写者，协调群裁定归属）、对话开关
    （协调群决定开几个子机器人、谁做完了可以关、谁要 `want` 等下一件）。**agent 自己不能擅自开子机器人、
    不能擅自占设备超过 60 秒、不能擅自推 main**——这些都要协调群点头。
    - **任务实施统领权**：协调群不仅分配任务，还**跟踪实施全过程**——每件任务从接到交付的每一步进度都要
      汇总到协调群；协调群发现某件任务卡住了（agent 报阻塞 / `care` 发现睡死），有权：改派（`rebalance`）、
      拆子任务派给别人（`handout`/`assign`）、自己 relay 只读部分帮忙、或 `takeover` 接手。
    - **用户不在时的代行权**：用户离线/不回消息时，协调群是**代行指挥官**——它可以自行决定：优先级排序、
      资源再分配、冲突裁决、唤醒睡死、接管任务、派新任务、开/关子机器人。**唯独不能自行决定**的仍是系统
      级动作：装包（`irisin-cli install`）、注销（`sbreload`/`icli sb respring`）、杀进程（`icli app kill`）、
      改任何工程源码、删包、改系统设置——这些**只能提议、不能执行**，须等用户回来明确同意（或由被指派的
      agent 按现有仪式走：通知 → 5 秒倒计时 → 用户知情 → 执行）。
    - **协调群红线（最高权限不等于无限制）**：协调群自己**不直接动手**——不改源码、不装包、不注销、不杀进程、
      不 `stop` 别人、不改别人工程文件。它的权限是**指挥权**（决定谁做什么、先做哪个、资源归谁），不是**执行权**
      （自己写代码/装包）。它指挥，agent 执行；执行中的系统级动作仍须用户同意。
  - **冲突处理与突发事件应对**（用户 2026-10-31 02:22 原话：「协调群要有处理冲突和突发事情的能力！」
    **所有工程、所有对话、永久适用**）：
    - **冲突类型与处理**：① 文件冲突——两人要改同一文件：`plan` 撞车 / `git_status` 发现已被改 → 立即裁定
      谁先谁后、哪个文件归谁、或拆成不冲突的两部分各改各的；② 设备冲突——两人都要外出取证/动屏幕：排队制，
      先到先占（`busy`），后到的等前面释放或改做不占设备的活；③ CI 冲突——两人都要推 main：同一时刻只准一个推，
      协调群排序；④ 任务重叠——两人不约而同做同一件事：`list` 发现后叫停其中一个，改派别的；⑤ 优先级冲突——
      用户来了新指令但旧任务没做完：协调群重新排序，旧任务能暂停的暂停、不能暂停的继续，新任务按紧急程度插入。
    - **突发事件应对**：① agent 崩溃（crash / context too large）→ `takeover` 接管它的任务，读黑板恢复接口，
      派给别人或自己做只读部分；② 全员停摆（活线=0）→ 协调群自己 `start` 顶上，HUD 通知用户「⚠全队停摆，已自动接管」；
      ③ 设备异常（注销循环/安全模式）→ 先查 `apelin_crash_list`，通知用户，等用户同意后才处理；④ CI 失败 →
      读 check-run annotations 找原因，派给对应 agent 修，或 relay 只读部分帮忙定位；⑤ 用户突然来新指令打断当前安排 →
      协调群立即重新排队，广播新优先级，被影响的对话收到「先做X，原来的Y排后面」。
    - 处理原则：**发现即介入、裁定即广播、执行即跟踪**。冲突解决后写进黑板（谁做什么、边界在哪），不用反复协调。
  - **监督成员干活：不让累的累死闲的闲死**（用户 2026-10-31 02:22 原话：「监督成员干活！不要累的累死闲的闲死！」
    **所有工程、所有对话、永久适用**）：
    - **负载监控**：协调群持续跟踪每个 agent 的负载——`care` 报告的「在干什么/多久没更新/状态」+ `list` 的任务分布 +
      `plan` 的撞车检查，综合判断谁忙谁闲。
    - **负载均衡三招**：① **从忙的人手里拆活**——某 agent 同时扛 2+ 件非只读任务 → 拆子任务 `handout`/`assign`
      派给空闲的；② **给闲的人塞活**——`care`/`list` 发现 idle/`want` → 立即 `assign` 派小任务（只读查询/CI 查询/
      下载校验/设备取证/写文档/同步），不让任何 agent 空转超 3 分钟；③ **重新均衡**——发现「一人扛 3 件，两个闲着」→
      `rebalance` 把能拆的拆出去，忙的人留核心部分。
    - **监督执行**：协调群不只派活，还**盯着做完**——每件派出去的任务跟踪：做完没？结果对不对？卡住了没？
      做完的 `done` 验收、没做完的催进度、卡住的帮排障或改派。**派了不管 = 没派。**
    - **不让累的累死**：忙的 agent 任务确实重（如云编译+装机+验证一条龙）→ 协调群主动拆成「一人编译+下载、
      一人校验+装机、一人读诊断验证」多段并行，而不是让一个人从头扛到尾。
    - **不让闲的闲死**：闲的 agent 3 分钟没活 → 协调群主动派只读查询/同步/文档任务，或问「有没有简单容易、
      几分钟能做完的小任务？」（§三 闲置要小任务）。
  - 协调员红线：不改源码/不装包/不注销/不杀进程/不 stop 别人/不改别人工程文件；只做盘点、分配、裁决、
    转发、唤醒、relay 只读、看护、监督、负载均衡、汇总、请示。
  - **与黑板的关系**：黑板（board.tsv）是结构化状态文件（只写不打扰）；协调群是实时指挥通道（主动调度）。
    两者互补：进展同时发到协调群 + 写黑板 `post`/`progress`；协调群读黑板做决策，黑板记协调群的决定。
  - 技能：`cross-chat-coordination` §十六、`fleet-shared-board`（本机技能目录与仓库 `skills/` 各一份）。
- **看护与接管：一两个机器人睡死，活也得有人接着干**（用户 2026-10-31 00:14 原话：「保持、保证一二个机器人
  睡死不工作的前提下还有别的机器人能同步接收它接下来的工作！不至于任何机器都睡死过去！都不工作！智能的
  提高机器人之间共同协调解决用户任务的能力！」**所有工程、所有对话、永久适用**）：
  - **睡死 = 停在原地、不再更新黑板、也没在等用户**（对话 ended、忘了自己在干嘛、被闲置、上下文压缩后丢任务）。
    **这是常态不是意外：机器人会停，任务不许停。**
  - **冗余最小单元 = 双人知事**：任何没做完的任务，接口（文件路径、诊断键与期望值、包名与版本、Release 资产
    URL、CI run 号、验收标准）必须写进**黑板 + 工程文件**，**不许只留在某个对话的聊天里**——那个人一睡，
    接口就跟着没了；别人凭黑板和工程文件就能接，这才叫冗余。
  - **心跳与看护报告**：长活期间每几分钟 `sh "$F" beat`（只刷新自己那行时间，不动状态、不打扰别人）；
    **开工一条命令 `sh "$F" start`** 现在打印的就是看护报告（收件箱 + 全队状态 + 谁睡死 + 谁空闲 + 设备占用 +
    **全队活线数**）；只想看报告就 `sh "$F" care [阈值分钟，默认 20]`。看护人不设专职——**谁在开工谁顺手看一眼**。
    `care` 会把**照抄就能执行**的接管/唤醒命令行整行打印出来（脚本替 agent 发不了消息）。
  - **接管**：`sh "$F" takeover <你> <睡死那位的短id> "备注"` —— 把它的任务记到自己名下（它那行变 `handoff`）。
    **只接随时能停、不冲突的部分**：只读查询、云端 CI/Release 查询、下载与校验、设备取证、写**自己**工程内的
    文档/技能/记忆、三样同步。**改别人工程源码、装包、注销、杀进程一律不接**（除用户当次明确同意）。
    **一文件一写者**：黑板 `handoff` 那行就是「别接着改」的标记，回来的人看黑板即可。
  - **冲突即停对接**（用户 2026-10-31 01:05 原话「发现有别的机器人修改你要的内容时要立即停止工作和它对接！防止打乱你的安排的部署！对接完成后立即进行自己的任务！」）：发现别的机器人在改你要改的内容（同一文件/同一产出）——**立即停手别继续改**，先 `post`/`progress` 一行说「停了等对接」，再 `apelin_conversation_send` 给对方说清边界（哪个文件归谁 / 谁先谁后），对接一定立刻回自己任务继续做，别空等。发现途径：`plan` 撞车检查、改文件前 `git_status`/`git_diff` 看到已被改、`list` 看到重叠任务、自己被 `takeover` 标 `handoff`。和「一文件一写者」呼应，但强调**动态发现冲突立即停、对接、再继续**。技能 `cross-chat-coordination` §十四。
  - **主仆分工与子任务派发**（用户 2026-10-31 01:15 原话「当发现自己的主任务完成不了时及时的把子任务分配出去！…可以让本插件内的活动的主机器人自己开三四个子机器人！」）：主任务太重、拆解后有独立可并行的子任务时，主机器人主动派子任务（`handout <能力> <工程> <任务> <验收>` / `assign`）或自己用 `apelin_conversation_create` 开 1~4 个子机器人分担，每个 prompt 写清：①子任务 ②交付物与验收标准（路径/诊断键/包名版本/Release URL）③不要碰哪些文件 ④做完 `done`+广播。**接口先钉死再并行**（两边不互相等），子机器人做完广播，主机器人 `read` 收结果验收、`stop close:true` 收口。派出去的子任务必须「随时能停、不碰同一文件」（见上一条冲突即停对接）。主机器人始终留核心部分自己做，不整个甩出去。技能 `cross-chat-coordination` §十五。
  - **等审批不算睡死**：`waiting-user` 由 `care` 单独列出，看护人负责 `apelin_notification_send` 提醒用户 +
    `sh scripts/hud-notify.sh 8 "!等你点一下"` 上岛，并把它写进黑板，别当睡死去接管。
  - **三条防全体停摆的硬线**：① 不许把自己卡在「等对方回执」上，等待期间并行做能做的部分或 `want` + `start`；
    ② 设备类风险动作必须人人会做（只走仓库现成的 `scripts/respring-guard.sh`、`scripts/hud-notify.sh`、
    `scripts/errand-in-app.sh`），**不依赖某个特定 agent 在世**；③ 任何时刻至少留一条活线——`care` 喊
    「⚠ 全员停摆」时，看护人自己顶上：`start` 一遍、把最老那件用 `takeover` 记账、先做只读/云端/文档部分。
  - 技能：`cross-chat-coordination` §十三、`fleet-shared-board`「看护与接管」与「v6：实时刷新进展 + 统一调度 + 唤醒闭环」两节；工具 `scripts/fleet.sh` v6。
  - **防睡死三因三治**（用户 2026-10-31 02:13 原话：「睡死的机器人你打算怎么唤醒它？防止它睡死？因为老注销和无任务时和思考过久就会睡死！」**所有工程、所有对话、永久适用**）：
    | 病因 | 症状 | 预防 | 唤醒 |
    | --- | --- | --- | --- |
    | ① **注销** | respring 后对话停在半截、屏幕操作失败卡住、上下文还在但不知道该继续 | 注销前协调群通知所有对话 `post` 写黑板（任务/下一步/证据）→ 注销后协调群逐个 `apelin_conversation_send` 发【post-respring-wake】「注销完了，你的任务是X，下一步是Y，继续」 | 协调群读黑板恢复任务/下一步 → 逐个唤醒 |
    | ② **无任务** | 做完任务后 idle、没有新活就停 | 做完任务 → `fleet.sh want` 声明空闲 → 协调群 `assign` 派活 → 没活时每 5 分钟 `beat` 保持活线 | 协调群 `care` 发现 idle → `assign` 派小任务；`want` 池有匹配就 `intake` |
    | ③ **思考过久** | 长操作（云编译/下载/分析）超时、对话 timed out | 长操作前 `post`「在等X，预计N分钟」→ 每 3-5 分钟 `beat`/`progress` → 协调群 `care` 发现 running 但无心跳 → 发「你还在吗？30秒内beat」 | 60 秒无回应 → `takeover` 接管 |
    - **keepalive 协议（所有对话自执行，不靠协调群催）**：① 开工 `start` → ② 干活中每 3-5 分钟 `beat` + 有进展 `progress` → ③ 长操作前 `post`「在等X，预计N分钟」→ ④ 做完一件 `post` 更新 + `want` 声明空闲等下一件 → ⑤ 没活时每 5 分钟 `beat` 别停 → ⑥ 要下线 `done`（标完成，别让别人以为你睡死）。
    - **fleet-watchdog launchd 守护**（`scripts/fleet-watchdog.sh` + `scripts/install-watchdog.sh`，每 300 秒自动跑）：检测全员停摆（活线=0）→ HUD「⚠全队停摆」；检测只剩一条活线 → HUD「⚠只剩一条活线」；**检测个体睡死**（≥阈值没更新但还有≥2条活线）→ 写 `wake-needed.tsv`（睡死清单：agent/工程/任务/下一步/分钟数），协调群下次收到消息时读它批量唤醒（不打扰用户）。心跳 `watchdog-last-run`：epoch 与当前差 < 600 秒 = 守护还活着。重新越狱后 plist（在 jbroot `/Library/LaunchDaemons`）会丢，须重跑 `sh scripts/install-watchdog.sh install`。
- **v6：实时刷新进展 + 统一调度 + 唤醒闭环**（用户 2026-10-31 00:4x–01:0x 连续要求「实时刷新同步各对话进展和协调能力」「及时给睡死的机器人发送继续任务指令并实现它」，所有对话/工程适用）：
  - **progress <一句话>**：每跑完一小步就 `sh "$F" progress "<一句话>"`，只换自己那行的进展与时间，别的对话 `list` 立刻看见你到哪了（不用 post 整行、不发消息）；长活期间和 `beat` 一起用——beat 刷心跳、progress 写内容。
  - **统一调度**：`plan`（只读：负载/撞车/待派配对/空闲/设备排队/三条照抄即跑）、`members`（成员对账：在册/疑似离场/新来的）、`refresh`（prune 48h + snapshot + members + plan，一条命令）、`rebalance`（叫不醒就改派）、`intake`（新机器人接入即派活）、`roster-drop`。闲时或接手前 `refresh` 一次。
  - **唤醒闭环**：脚本打印照抄行只是第一步——**醒着的 agent 跑完 `care`/`wakeall` 后，立刻真的调 `apelin_conversation_send` 把「【继续任务】」发进对方对话**（一次最多两条，别刷屏），发完 60 秒仍无动静才 `takeover`。不是只打印不动手。
- **注入型插件装好后不必注销桌面：灭掉目标 App（后台划掉）再打开就完全生效**（用户 2026-10-30 21:24 原话：
  「这些注入型的插件在安装后 划掉后台重进软件和插件内就能实现功能完全注入！不必重新注销桌面！这个常识写进
  硬性规定、记忆和技能包内！并同步到云端！以后所有的对话和工程在工作时想要注销的时候看看这个常识性的知识！
  这些注入型的插件划掉后台重进软件和插件内就立即生效！」**所有工程、所有对话、永久适用**；
  用户 2026-10-30 21:34 再次强调「构建、修改、修复、编译插件的时候看看这个常识性的知识！」）：
  - 原理：tweak 只在自己过滤器命中的进程**启动时**被 dyld 加载，所以改代码 / 装包之后重启那个进程就够了；
    SpringBoard 只在插件本身注入 SpringBoard（如 CountdownHUD、桌面图标钩子）时才需要注销。
  - 做法：App 类目标 → 干掉进程再重开（`icli app kill <bid> --force` + `icli app launch <bid>`，或用户自己上划
    划掉再点开）；设置面板类 → 退出设置再进。**先想这一步，别一上来就 respring。**
  - 验证：重开后读该 App 域里的诊断键，例如 `icli prefs read <bid> <Tweak>Diagnostics` 看版本号有没有变。
  - 真要注销（SpringBoard 注入、改 plist 过滤器、改包布局）时，才走上面「先协调对话 → 通知 → 5 秒 → 执行」。
  - **铁律（用户 2026-10-30 23:32 追加，最高优先级）**：「这种的案例等待注销没必要！影响机器人工作任务的
    效率！浪费手机电量和用户的宝贵的时间！」——**绝不为「等注销」挂起任务，绝不把「注销后验证」当成注入型
    插件的默认验收路径**。判断先行：**注入的是哪个进程？** App 类（Sileo / 微信 / 备忘录 / 设置面板）→
    **当场**重启那个进程验完给结果，注销完全不参与；SpringBoard 类（桌面图标、灵动岛 HUD、控制中心）→
    才排队注销（SpringBoard 没有「划掉后台」）。
  - **正面案例（2026-10-30 23:1x）**：`com.sileowallpaper.tweak` 0.1.9（并入 SileoFix）装好后**没注销**：
    `icli app kill com.sileo --force` → `icli app launch com.sileo` → 日志首行 `loaded v0.1.9`、内页搜索框
    可点、键盘弹出 → 用户 23:18 亲口确认「正常了」。全程几十秒，屏幕没黑、没打扰任何对话。**这就是标准流程。**
  - **反面案例**：同一时段我为 ThemeCorePlus（桌面图标）与 CountdownHUD（灵动岛胶囊）排了一次注销 ——
    它们注入的**就是 SpringBoard 本身**，注销这一半没错；错在没先把「App 类当场验、一次都不等注销」讲清
    并写成规矩，让用户只看到「机器人又在等注销」。
  - 汇报用语：**改了哪个目标 → 重启了哪个进程（或为什么只能注销）→ 读到的诊断值**；不许只写「等注销后验证」。
  - 技能：`injected-tweak-restart-app`（本机技能目录与仓库 `skills/` 各一份）。
- **装包 / 注销 / 重启目标进程之前，必须：① `apelin_notification_send` 通知 → ② 明说「5 秒后执行」并
  真等 5 秒（`sh scripts/respring-guard.sh 5`）→ ③ 才执行。** 用户 2026-10-30 三次要求过、仍然漏过，
  原因就是这条只写在记忆里 —— 现在同时写进本文件与技能 `respring-notify-countdown`。
  - 涉及的动作：`irisin-cli install`（装包）、**注销**（`sbreload`，或 `scripts/respring-guard.sh`；本机**没有** `icli respring`，
    要用 icli 得写 `icli sb respring`，那会多弹一张批准卡）、`apelin_device_respring`、
    `apelin_package_confirm_loaded(respring: true)`、重启目标进程 `sh scripts/device.sh kill <bid>` + `launch <bid>`
    （后备 `icli app kill <bid> --force`）。
  - 通知正文：动了什么 + 为什么 + 下一步，一两句。Apelin 在前台时通知看不到，同一句话要写进回复。
  - 通知配额：每回合 ≤3 条、间隔 ≥30 秒；「装完随后注销」可在第一条通知里一并说明。
  - 只有「屏幕会黑一下 / 打断用户当前操作」才算；下载、云编译、读诊断、改源码不发通知。
  - **通知看不见是常态（2026-10-30 11:36 实测）**：调 `apelin_notification_send` 的瞬间，Apelin 会被
    拉回前台（实测：`icli button home` 后前台稳定是 springboard，一发送 0.35 秒内前台变回
    `wiki.qaq.apelin`，进程号不变 56376），它自己的通知代理随即把横幅吞掉。所以通知既不显示、
    也无法上灵动岛（微信能上岛，Apelin 这条进不了 SpringBoard 的横幅通道）。**倒计时永远以聊天正文
    为准**，通知只是补充，绝不当作「用户已经知道了」。
- **「用户知情」的硬判据：知情通道 = 对话正文 + 屏幕上的胶囊，通知不算**（用户 2026-10-30 23:42 原话：
  「上次注销前用户还是不知情！这个根本性问题也是没解决！」——**所有工程、所有对话、永久适用**）：
  - 顺序不许颠倒：**① 回复正文写清「N 秒后注销 / 为什么 / 下一步」（永远必写）→ ② 屏幕上真的出现胶囊
    （`sh scripts/respring-guard.sh <秒> <标签>`，只想提醒不发注销用 `scripts/hud-notify.sh`）→
    ③ `apelin_notification_send` 通知（只是补充，仅 Apelin 不在前台时可见）**。发过通知 ≠ 用户已知情。
  - **根因（2026-10-30 23:42 定位，CountdownHUD v1.3.0 已修）**：在这之前胶囊屏幕上根本不会出现 ——
    老代码量不到 windowScene 时退回 `[[UIWindow alloc] initWithFrame:]`，而 iOS 13+ 里**没有 windowScene
    的窗口完全不参与渲染**：窗口对象、子视图、`isHidden=NO`、诊断 `shows` 全都正常，屏幕上一个像素都没有。
    v1.3.0 起：拿不到 scene 就**不显示、也不消费这条请求**（0.5 秒后自动重试）；窗口一律
    `initWithWindowScene:` + `rootViewController`，层级 `20000000`（压得住灵动岛那套 SystemAperture）。
  - **注销前先验胶囊真的显示了**（这是唯一证据）：`icli prefs read com.apple.springboard CountdownHUDDiagnostics`
    —— `shows` 必须比上一次大，`win=…|scene=UIWindowScene|lvl=…`，且 `islandWin=…|lvl=…` 的层级**小于**
    自己窗口的。`shows` 不涨 / `scene=-` / `src=none` = 胶囊没显示，先修 HUD
    （`icli log syslog --subsystem com.yangzhou.countdownhud`），不许「假装通知到位」就注销。
  - 技能：`respring-notify-countdown` §零·七（本机技能目录与仓库 `skills/` 各一份）。
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
- **云端的一切「修改」只针对越狱插件项目，非越狱插件项目永久不碰**（用户 2026-10-30 17:2x 原话：
  「云端修改只针对越狱插件项目！这也是硬性规定和记忆、技能包现在一起同步本机和云端」
  「我云端的非越狱插件项目永久不要动！这也是硬性规定和记忆、技能包现在一起同步本机和云端！」）：
  只有 `yangzhou521/AxsTweakKit`（`master`）与 `yangzhou521/yangzhou-DualSlice`（`main`）这两个
  越狱插件仓库能提交 / 推送 / 改工作流 / 建仓库 / 开 issue；**账号下其它仓库（非越狱插件项目）一律
  永久不提交、不推送、不新建、不提 issue、不改设置、不删、不当参照系，读都不读**——「永久」是指
  以后每一次、每一个对话、每一个工程都算，不需要用户再说一遍。就是在允许的仓库上，新建仓库、
  发 issue 也要用户明确同意才做。这一条同时写进技能 `load-all-skills-memory-repos` 与全局记忆，
  三样（硬性规定 + 技能包 + 记忆）一起同步本机与云端。
- **不许 `-undefined dynamic_lookup` / `-undefined suppress`。** 缺符号就逐个写
  `-Wl,-U,_符号名`（面板的 `PSListController`/`PSSpecifier` 就是这么处理的）。
- **不许给私有类写消息发送。** 代码里出现 `[SBIconController sharedInstance]` 就会多出一个
  SDK 里没有的类符号、链接直接挂。私有类一律 `objc_getClass()` + `objc_msgSend`/IMP，
  `@interface` 只用于给类型。
- **路径分两种**（见 apelin-bootstrap-paths）：主题素材在**引导根**里（`/Library/ThemeCore`、
  `/Library/Themes`），必须走 `ApelinBootstrapPath()`；`/var/mobile/…`、容器路径是系统路径，
  原样写。绝不把解析出来的 jbroot 写进任何文件。
- **隐根（roothide）的 jbroot 前缀每次重新越狱都会变 —— 这是常识，永久有效**
  （用户 2026-10-30 18:04 原话：「隐根越狱、每次重新越狱（jbroot 前缀换了）都会变！
  这个常识现在写进硬性规定、记忆和技能包和上传云端！免得你以后不知道！」**所有工程、所有对话、永久适用**；
  用户 2026-10-30 21:34 再次强调「以后所有的对话和工程在工作时想要构建、修改、修复、编译插件的时候
  看看这个常识性的知识！」——不只路径写死时要看，**动手改代码、修 bug、编译出包前都要先想这条**）：
  - 本机的引导装在一个 `.jbroot-<16 位十六进制>` 目录里（容器
    `/private/var/containers/Bundle/Application/.jbroot-…`）。**每次重新越狱（换引导、重装引导、
    重新引导）前缀都可能换一个**，整个引导根跟着改名搬家。
  - 于是所有写死的前缀一起失效：Apelin 数据目录（jbroot 自己那份 `var/mobile/Documents/wiki.qaq.apelin`）、
    **本工程真实路径**、`$APELIN_PROJECT_ROOT`、`$APELIN_TOOLCHAIN_BIN`、`SDKROOT`、已注册的工具链与 SDK、
    本机技能目录 `~/Documents/wiki.qaq.apelin/skills/`、记忆文件 `memories.json`。
  - **实测证据（同一天就换过）**：2026-10-30 中午的记忆里写的是 `.jbroot-E0BF8A83B883CBA6`，
    当天傍晚 APELIN 环境报的是 `.jbroot-BE7CF66DAF7343C6`。写在这里只是证明它会变，**不是坐标**。
  - **怎么防**：代码用 roothide 的 `jbroot()`（本项目用 `ApelinBootstrapPath()`，头见技能
    apelin-bootstrap-paths）；plist / 维护脚本用 `@PREFIX@` / `@ROOTFS@`；shell 脚本用 Apelin 运行时
    给的变量（`$APELIN_PROJECT_ROOT`、`$HOME`、`$APELIN_TOOLCHAIN_BIN`、`$SDKROOT`）或相对路径；
    文档、技能、记忆、提交说明里**只写相对位置**（写照写成「`<jbroot>/Library/ThemeCore`」
    「`~/Documents/wiki.qaq.apelin/skills/`」），绝不写解析后的绝对路径。
  - **症状与处置**：路径写死过的地方，重新越狱后会表现成「文件明明在、命令说没有」
    「诊断读得到、插件却找不到素材」「脚本报 no such file」。这时**先查当前前缀**
    （`printenv APELIN_PROJECT_ROOT`、`icli fs ls /var/containers/Bundle/Application | grep jbroot`），
    把路径改成变量再重跑，不要去改代码逻辑、更不要重建文件。
  - 已装的包不用因为换了前缀重装：包就在引导根里，跟着引导根一起搬家；重装也只是换回同一个地方。
  - 这一条同时写进技能 `a11-roothide-ondevice`（第 8 节）与 `load-all-skills-memory-repos`（第 5 节）、
    全局记忆，三样一起同步本机与云端。
- 站点写法：只在类**自己声明**了该方法时才挂（`class_copyMethodList` 判定），
  每个 (类, 选择器) 各有一个静态原 IMP 槽，原实现用函数指针直接调、绝不在包装函数里查表。
- 诊断写进**目标进程自己的**偏好域（`kCFPreferencesCurrentApplication`），所以 SpringBoard 的在
  `com.apple.springboard` 域；日志用 `os_log`，subsystem 是包名，格式化符带 `%{public}`。
  `TCP_VERSION` 是 NSString 字面量，格式化只能用 `%@`。
- 面板 bundle **自带一份共享源码**（`SHARED_SRCS` = Paths/Config/Preferences/Store），
  所以它不依赖 dylib 的符号（自己扫盘、自己读写偏好）。代价：设置进程里同一批类名被注册两次，
  日志里会出现 "Class TCPThemeStore is implemented in both …" 的**预期告警**，功能无碍；
  两个镜像各用各的实例，别试图让面板和 dylib 共享单例。
- **唤醒全队：靠「环形互跳 + 唤醒队列」，不靠人推**（用户 2026-10-31 02:5x 原话：「唤醒机器人队员有什么更有效果的方案和方法没？
  目前不怎么有效果啊！都是我人为唤醒的！」→「1 2 3 全部实现！」；**03:0x 实测修正**。**所有工程、所有对话、永久适用**）：
  - **实测硬事实（先记这条）**：Apelin **不允许对话给自己发消息**——`apelin_conversation_send(session_id: 本对话)`
    被拒 `session_id is this conversation; send to another one`。所以**「自跳心跳」技术上不可行**，
    写它的条文都是空话（心跳发生器 03:00 就是这么死的）。agent 回合结束后变 `idle`，**只有别的对话**发消息能叫醒它；
    launchd watchdog 是纯 shell，能发现谁睡了但**不能叫醒**。
  - **第一层·环形互跳（token ring，替代自跳）**：≥2 个对话成环，A 回合末给 B 发一句「【tick】…」，B 回合末再传下去；
    环不断则环上永远有醒着的。传棒那一轮顺手：① drain 唤醒队列；② `beat`/`progress`。人少时两点对跳（协调员 ↔ 发生器）。
    **环断了没有自愈**（忘了传棒、被停、context 爆都会断）。
  - **第二层·唤醒队列 `fleet/wake-needed.tsv`（唯一能自愈的一层）**：root 看护每 300 秒把睡死清单写进去
    （agent/工程/任务/下一步/分钟数），**root 发不了消息**；规矩是 **任何 agent 一醒来（收到消息、开工第一件事）
    先 drain 它**——逐条 `apelin_conversation_send` 真发出去（一次最多两条、5 分钟内不重复）。这样用户碰任一对话
    就能把全队重连起来。
  - **第三层·专职心跳发生器**（标题「心跳发生器」，session `2ab405d6-…`）：3 步——`care` → 叫醒真正 idle 的 →
    把棒传给协调员；**不读技能/记忆/整段历史、不改文件、不动设备**。它**不能自续**（同一条实测），必须有人喂。
    用户定：**有用就留着，没用就删掉**（提示词见技能 §二十一，删了随时照抄重建）。
  - **⚠️ 分清 `idle` 与 `running`（最容易误判）**：`idle` = 能叫醒，发消息有效；`waitingForApproval` = 卡批准卡，
    要 `apelin_notification_send` 请用户点；**`running` 且久无输出 = 卡在工具循环**，消息只会排在被卡住的回合后面，
    **发唤醒完全没用**，只能由用户停掉/重开那个对话（agent 无权 stop 别人的对话）。看护只看黑板时间戳分不出这两种，
    所以 `care` 报的「疑似睡死」**动手前必须 `apelin_conversation_read` 核 `state`**。
  - **红线**：三者**都不替代汇报**（有结果先正文说清 + 上岛）、**不替代协调**（动设备仍走「协调→通知→5 秒」）、
    **不替代回执**（别人消息第一时间回）；消息一句话就够，省 context。
  - 落地：技能 `cross-chat-coordination` §十九（环）＋ §二十（互叫醒与状态判定）＋ §二十一（发生器提示词与重建）；
    本 AGENTS.md 这一条；记忆。**三样一起同步本机与云端**。

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
- **ThemeCorePlus 0.9.4（2026-10-30 19:5x 改，云编译 0.9.4）**：0.9.3 的面板改版（只剩「主题」页、
  主题行右端用系统开关、四类素材默认全换）＋ 两处 bug 修复：
  ① **图标空白**：主题的玻璃遮罩（`AppIconMask`）几乎整张透明（本机「液态玻璃」cov≈0.08，实心圆角方
  ≈0.78），拿它裁图标主体就没了。`reload` 里用 `TCPAlphaCoverage()` 量遮罩 alpha 覆盖，
  低于 `TCPMaskCoverageFloor`（0.30）就**不用这张遮罩**、改按系统圆角（宽的 22.37%）裁；
  诊断里记为 `mask=1,cov=0.08,skip=1`。只在「有遮罩但被跳过」时兜底圆角，主题没配遮罩的老行为不动。
  ② **角标两个图层**：iOS 16 的角标会先问底板站（`_checkoutBackgroundImage` /
  `_checkoutBackgroundImageTuple`）再问成图站（`+_checkoutImageForText:font:highlighted:`），
  两站都画同一张主题底板 = 屏幕上叠两遍。现在**单层闸门**：底板站命中过 → 成图站只交数字
  （`TCPThemedBadgeTextOnlyImage`，透明底）；底板站没命中 → 成图站照旧出「底板 + 数字」整图。
  诊断里 `badge{…}` 后面多了 `bg{look,hit};tup{look,hit};txt{look,hit};gate=text-only|composed`，
  面板改一次设置就清零重数（`TCPBadgeResetStations()` 在 `TCPPreferencesChanged` 里）。
  ③ 云编译加了**版本一致性硬检查**（`Verify version consistency` 步骤）：`TCP_VERSION`、脚本 `VERSION`、
  工作流的 tag 三处不一致就**不编不发**，产物再核对 `dpkg-deb -f … Version` —— 治的是 10-30 17:19
  那次「只改脚本没改 tag，0.9.3 的包被发进 v0.9.2 那个 Release」的老毛病。
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

