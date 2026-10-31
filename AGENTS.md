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
| `scripts/respring-guard.sh` | **唯一注销入口**，四段：**先警告**（屏幕胶囊「⚠️ 要注销吗？在 Apelin 回「注销」或「取消」」+ 终端警告块 + **退出码 3**，什么都不做）→ **用户点头** → 带 `--confirm` 才倒计时 5 秒 → `sbreload`。不带 `--confirm` 永远不注销 |
| `CountdownHUD/Sources/CountdownHUD.m` | 自绘胶囊（SpringBoard 顶层窗口）：倒计时「N 秒后注销」+ v1.2.0 起的**纯文案**（`!` 前缀，任务完成/进度），**不依赖通知** |
| `Support/CountdownHUD.plist` | HUD 的注入过滤器（只进 `com.apple.springboard`） |
| `scripts/build-countdownhud.sh` | HUD 的构建脚本（**只在 CI 上跑**，不链接 substrate） |
| `scripts/hud-notify.sh` | **一句话上岛**：`[秒数] <文案>` → 灵动岛纯文案提醒（8 秒默认），不注销、不装包 |
| `.github/workflows/countdownhud.yml` | HUD 的云编译 + 发 Release（tag `countdownhud-v1.4.2`） |
| `SileoFix/Sources/SileoFix.m` | Sileo 搜索框死区修复本体（`hitTest:withEvent:` 旁路，v1.0.4）；原壁纸插件逐字节不改 |
| `Support/SileoFix.plist` | SileoFix 的注入过滤器（`org.coolstar.SileoStore`） |
| `docs/cases/sileowallpaper-searchbar-fix.md` | **专项案例**：SileoWallpaper 让 Sileo 搜索框点不进去 —— 病灶/分轮取证法/修法/复发流程 |
| `docs/cases/themecoreplus-screen-ours-zero.md` | 专项案例：ThemeCorePlus 屏幕归属计数为 0 |
| `docs/cases/fleet-watchdog-false-positive.md` | 专项案例（**已废弃的方案**）：车队看护把「已结束的对话」当睡死，反复唤醒（误报诊断）——黑板/看护/心跳已于 2026-10-31 05:5x 全部删除，留作反面教材 |
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
同一次运行里发 Release（静态 tag 与包版本一致，当前 `themecoreplus-v0.9.21`，每次运行都重建资产，sha256/体积会变）。
Release 资产地址：
`https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.21/com.yangzhou.themecoreplus_0.9.21_iphoneos-arm64e.deb`

**tag 必须与包版本一致**：改版本时 `scripts/build-themecoreplus.sh` 的 `VERSION` 与工作流的
`env.VERSION`、`tag_name`、release 名、`deb-url` 注解要一起改。2026-10-30 17:19 那次只改了脚本
（0.9.3），工作流还写着 0.9.2，于是 0.9.3 的 deb 被发进了 `themecoreplus-v0.9.2` 那个 Release 里
（现在该 Release 同时挂着 0.9.2 与 0.9.3 两个包），已在本提交修掉。

可读的验证信息都写成 check-run annotation（`::notice/::error title=…`）：job 日志要登录才能看，
公开仓库的 annotations 匿名可读（`/repos/{owner}/{repo}/check-runs/{id}/annotations`）。
本机没有 curl/wget/python3，查状态用 `icli probe` + `NSData`/`NSURLForString` 调 GitHub API。

## 桌面图标布局保存（ThemeCorePlus 0.9.18 起，0.9.19 补诊断，0.9.20 修 nomodel，0.9.21 崩过、已废）

> **0.9.21 = 崩溃版本，永不再装、永不复用版本号。** 它把「枚举全进程所有类」搬进了构造函数，
> 对来路不明的类发 `isSubclassOfClass:` → 消息转发 SIGTRAP → SpringBoard 连崩 5 次进安全模式
> （详见「硬规矩」第一条）。**下一版从 0.9.22 起**，并且必须按那 4 条修法写。

用户的病灶：「图标注销/崩溃后不保存，回到旧摆位」。全部逻辑在 `ThemeCorePlus/Sources/ThemeCorePlusLayout.m`
（**只改这一个文件**，Icons/Badges/Store 不碰）。诊断有两条：

- `ThemeCorePlusLayout`（0.9.19 起，**看它，tick 最多旧 60 秒**）：
  `sh scripts/device.sh read com.apple.springboard ThemeCorePlusLayout`
- 主诊断 `ThemeCorePlusDiagnostics` 里嵌的 `lay{...}`：**只在启动那几轮 / 面板改设置时才重写**，
  读到的是那一刻的快照，别拿它判断定时器现在活没活。

```
lay{rst=N,sav=N,tick=N,force=N,site=<挂上的保存方法|none>,model=<none|hooked:save|hooked:leaf>,last=<原因>,probe=<枚举到的候选方法>}
```

- **0.9.20/0.9.21 修 `last=nomodel` 的根因**：旧代码用 `respondsToSelector:leafIcons` 判断「self 是不是模型」，
  而 iOS 16.7 的零参数保存方法挂在 `SBIconModel` 上、模型未必响应 leafIcons → 活模型永远拿不到。
  现在改成不猜：运行时枚举 `SBIconModel` 家族**自己声明**的方法（`class_copyMethodList`），
  「零参数 + 名含 IconState 且含 save/persist/write/store」判为保存站，
  「零参数 + leafIcons/allIcons/icons」判为图标列表站；两类站各挂各的槽（一站一槽，声明者才挂），
  从站的 self 直接取得活模型与活图标数组。`model=` 写 `hooked:save`（拿到模型）还是 `hooked:leaf`
  （只拿到图标数组）就一眼看出挂在哪；`probe=` 列出枚举到的候选方法名。
- 0.9.20 那次 CI 编译失败（run 41158895611）真因：`ThemeCorePlusHooks.m:277` 用了 `TCPThemeStore`
  而没声明 → 修法是在 `ThemeCorePlusHooks.h` 里 `#import "ThemeCorePlusStore.h"`（不改禁改的 Hooks.m）。
  修好后 run 41159676651 成功，tag `themecoreplus-v0.9.21`。

- **0.9.17 及以前的真正 bug：`tick=0`** —— `dispatch_source_t` 原来是 `TCPLayoutInstall()` 里的局部变量，
  文件用 `-fobjc-arc` 编译，函数返回时源被释放并取消，handler 一次都没跑过（恢复是同步调用，所以照跑）。
  修法：文件级静态 `sLayoutTimer` 持有；定时器跑**主队列**（碰 `SBIconModel` 必须主线程）。
- 0.9.19 起每拍自己写一次 `ThemeCorePlusLayout`（状态一变立刻写，没变最多每 60 秒写）：
  `tick` 会一直涨；`last` 会写 `baseline`/`nomodel`/`nosignature`/`forced:changed`/`forcefail`，
  一眼看出这一拍在干什么。没有这条键 = 这个进程没跑 0.9.19 的代码。
- 每 5 秒一拍：① 类晚到了就补挂保存站；② `IconState.plist` 比备份新 → 跟存；
  ③ 活的模型摆位签名（`leafIcons` 的 identifier + indexPath/gridPosition）变了 → 主动让系统写盘。
- 保存站只挂**零参数**方法（`saveIconState` / `_saveIconState` / `persistIconState`，
  `method_getNumberOfArguments == 2` 才挂）。钩子签名是 `(id, SEL)`，带参数的版本
  （`saveIconStateAndWait:` 之类）挂上去会丢参数，把系统写盘弄坏 —— 一律不碰。
  主动保存时先试 `SBIconModel`，再试 `SBIconController`（有的版本挂在控制器上），同样只调零参数版本。
- 恢复规则（0.9.17 起不再无条件覆盖）：内容相同 → 一个字节不动（`last=keepsource`）；
  系统那份缺失/坏了 → 回填（`last=restored`）；**备份比系统那份新**（崩溃前系统没写盘）→ 回填
  （`last=restored:newer`）。
- 路径：源 `/var/mobile/Library/SpringBoard/IconState.plist`，备份
  `/var/mobile/Library/ThemeCorePlus/IconState.backup.plist`（shell 里要加真根 `/rootfs` 前缀）。
- 验收：① 挪个图标等 30 秒 → `sav` 涨、`force` 涨、备份 mtime 变新；② 注销后图标还在且 `rst=0`；
  ③ 把 `IconState.plist` 挪走再注销 → `rst=1,last=restored`；④ `apelin_crash_list` 无新报告。
- 已实测（2026-10-31）：0.9.17 装机后 `tick=0`（两分钟两次读数都不动）＝上表那条 ARC 根因；
  系统那份与备份内容只差一个 UUID 字符串（说明系统确实在写盘，摆位没丢）。
- **状态（2026-10-31 12:50，注销后实测）：0.9.23 已在磁盘 + 内存里一致在跑**（dpkg 0.9.23，
  磁盘 dylib 与内存版本一致，`v0.9.23`，`tick` 在涨、`safeskip=0`，SpringBoard 崩溃列表无新报告，
  最新仍是 10:44 那批 0.9.21 旧档）。
  但**布局保存仍然一个站都没挂上**，0.9.23 的诊断给出决定性读法：
  `lay{rst=0,sav=1,tick=1,force=0,site=none,model=-,last=noinstance,probe=-,safeskip=0,hooked=0}`
  - **`probe=-`（不是 `base=nil`、也不是 `classlist=0`、也不是 `scanned=N,hit=0`）＝ 早退发生在写 probe 之前**。
    0.9.23 的三种 probe 字面量一个都没被写出来，说明 `TCPLayoutHookSave` 在写 probe 的分支之前就 return 了
    —— 即 `classes.count==0` 那句 return 比「写 probe」更靠前。定位时**先核 `TCPLayoutCandidateClasses()`
    的早退路径与 probe 的写入位置的先后**，不要以为 probe=- 代表「类没找到」。
  - `hooked=0` = 本进程挂站数 0（不受 prefs 跨进程残留干扰，可信）。
  - `sav=1` = **备份写盘次数**，不是挂站次数 —— 拿它判断「挂上过站」是错的（历史上误判过）。
  - `site=-SBIconModel:_saveIconState` 之类的旧值是 **prefs 跨进程残留**，不能当「曾挂上站」的证据。
  - `last=noinstance` 是挂站失败后每拍早退的**后果**，不是原因。
- **0.9.24（角标双层修复）已发布但用户明确「先不装」**：Release `themecoreplus-v0.9.24`，
  deb 142844 B，sha256 `da13ecbc…`，CI run 41168497476（提交 `cb3a307b`，success）。
  它的 `ThemeCorePlusLayout.m` 与 0.9.23 **逐字节相同**（compare `5811a2b6...cb3a307b` 的 files[] 里没有该文件），
  所以装它不会让布局诊断失真；但**没装就是没装**，锁里 version=0.9.24 只是席位声明。
- 查 CI：`icli probe scripts/ci-status.js`（匿名 GitHub API，列出最近 3 次 run 的 status/conclusion/sha）；
  下载：`icli probe scripts/download-tcp-09xx.js` → 写到 `/var/mobile/Documents/`。
  **报 CI 状态前必须重查一次**（见技能 `verify-cloud-release`：早先读到 `in_progress` 可能几分钟后就完成了）。

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
- **点胶囊跳回发消息的对话（v1.6.0 起）**：请求文件多一个**可选的第 4 段** = 对话 session id，
  即 `<epoch>|<秒数>|<标签>|<sid>`。有它时 `CHWindow` 的 `hitTest`/`pointInside` **只在胶囊自身矩形内**
  返回胶囊（屏幕别处照旧返回 nil 穿透，不会因为这一改吃掉触摸），点一下先收起胶囊、再
  `openURL: apelin://conversation/<sid>` 打开那条对话；没有第 4 段（老脚本、注销倒计时、`?` 弹窗）
  行为与 1.5.0 完全一致：不吃任何触摸。sid 只认「十六进制 + 连字符」形状（8~64 位），别的内容一律当没有。
  脚本用法：`HUD_SID=<对话 id> sh scripts/hud-notify.sh 8 "完成：<一句话>"`。
  **不给 `HUD_SID` 也不再是老的纯文案**：脚本会**自动认出本会话**（在 `~/Documents/wiki.qaq.apelin/sessions/`
  里找「最后一次发起 `hud-notify.sh` 调用的那个会话」，也就是正在跑这条通知的对话），照样生成可点胶囊。
  早期版本按「全局最近一条用户消息」认，会被别的对话抢走链接 —— 已改（2026-10-31）。
  并发跑多条线时仍可能认错，那种场合显式传 `HUD_SID=<自己的 session id>`。
  诊断串末尾多了 `link=<sid>|none` 与 `taps=<累计点击次数>`；点一次 `taps` +1、`link` 就是跳去的那个对话。
  **状态（2026-10-31 10:1x）：1.6.0 已装、已加载、已实测通过。** CI run 41155920001（commit `c5981b5b`，
  tag `countdownhud-v1.6.0`，deb 20780 B）；`/Library/MobileSubstrate/DynamicLibraries/CountdownHUD.dylib`
  里能搜到 `apelin://conversation/`、`link=…;taps=`；用户注销后 SpringBoard 跑 **v1.6.0**。
  `sh scripts/verify-countdownhud.sh --sid <对话 id>` 实测 **10 项全过**：① 版本 v1.6.0；
  ② 带 sid → `link=<sid>`、`mode=plain`；③ 点胶囊 → `taps` +1 且**前台变成 Apelin**
  （`apelin://conversation/<sid>` 生效）；④ 不带 sid → `link=none`；⑤ 再点胶囊 `taps` 不变
  （老行为没被改坏）；⑥ `apelin_crash_list`（SpringBoard）无报告。窗口层级 `lvl=20000000`
  的 CHWindow **能吃到胶囊那一小块**的触摸，胶囊外照旧穿透。
  验收脚本自己踩过的坑：`device.sh read` 有的版本直接打印诊断串、有的打印 JSON（从 `"value"` 行取）；
  `icli app frontmost` 的字段是 **`bundle_id`**（不是 `bundleIdentifier`）。
  注销加载后按这个顺序验（**已做成脚本**：`sh scripts/verify-countdownhud.sh --sid <对话 id>`，
  自动跑 ①~⑤，`--no-tap` 跳过点屏幕，`--selftest` 不碰设备只验解析）：
  ① 诊断出现 `v1.6.0`（shows 归零 = SpringBoard 换了新代码）；
  ② `HUD_SID=<对话 id> sh scripts/hud-notify.sh 15 "完成：点击测试"` → 诊断 `link=<sid>`、`mode=plain`；
  ③ 点胶囊（岛矩形约 `125,18,125,37`，中心 ≈ 187,36）→ `taps=1`，Apelin 被拉起并落到那条对话；
  ④ 不带 `HUD_SID` 再来一次 → `link=none`，点胶囊**什么都不该发生**（不吃触摸）；
  ⑤ 注销倒计时（`respring-guard.sh --confirm`）那条路仍不可点；
  ⑥ `apelin_crash_list`（SpringBoard）无新报告才算装好。
- 从 shell 写这个文件必须加真根前缀：`/rootfs/var/mobile/Library/Preferences/.countdownhud-request`
  （脚本已包好，见 `scripts/respring-guard.sh` 与 `scripts/hud-notify.sh`）。
- **注销 / 装包前先来一下最弱的震动（v1.4.0 起）**：用户 2026-10-31 02:48 要求「有注销的打算时
  第一时间来个最弱的震动，而且震动要早于倒计时」。非 `!` 的倒计时（真要动设备的那些）先
  `UISelectionFeedbackGenerator`（系统点选 / 滚轮那一下，全系统最弱一档）震一下，**再**画胶囊 ——
  同一请求只震一次（没拿到 windowScene 的重试不重复震），纯文案提醒（`!`）不震。
  诊断串末尾多了 `haptic=<累计次数>`，不用听声音也能确认震过几次。
- **铁律：注入 SpringBoard 的插件，构造函数阶段禁止碰任何 UIKit API**（`UIScreen` / `UIFeedbackGenerator` /
  `UIWindow` / `UIView` / `UIFont`…）。1.4.0 在 dyld 构造函数里就 `CHPrepareHaptic()` 创建
  `UISelectionFeedbackGenerator` → `+[UIScreen mainScreen]` 抛断言 → `NSAssertionHandler` → `abort`
  （SIGABRT）→ SpringBoard 崩溃循环 → **安全模式**（报告 `SpringBoard-2026-10-31-033134.ips`）。
  `@try/@catch` 救不了（`NSAssertionHandler` 走 abort，不是可捕获异常）。
  修法三步：①1.4.1 惰性创建（构造函数只预热，不 new）；②1.4.2 震动严格排在 UIKit 就绪之后 ——
  先 `CHEnsureWindow()` 拿到真实 windowScene（= UIKit 已活着）才打震动，再画胶囊；
  ③需要 UIKit 的一律延迟到主线程 + 拿到 scene 之后。
  案例文档：`docs/cases/countdownhud-safe-mode.md`（根因 / 三步修法 / 复发处理流程）。
- **装入 SpringBoard 的新插件，注销后必须查 crash list**：`apelin_crash_list`（process=SpringBoard），
  有比本次注销更新的报告 = 装坏了（先 `irisin-cli remove` 回滚再排查），**无新报告才算装好**。
  已装并实测通过：**1.6.0**（当前版本，CI run 41155920001，commit c5981b5b，tag `countdownhud-v1.6.0`，
  deb 20780 B，2026-10-31 09:34 装机；1.4.2 是历史版本，早已不是当前版本）。
  注销后诊断 `v1.6.0;shows=N;mode=plain|count;...;alerts=N;ans=confirm|cancel|-;link=<sid>|none;taps=N`，
  crash list **无新报告**，不在安全模式。纯文案（`!`）不震已实测；别的 App 在前台时胶囊照样消费请求（已实测）。
  验收矩阵见 `docs/cases/countdownhud-1.6.0-acceptance.md`。
  **续验（2026-10-31 10:2x–10:4x，接手 `?` 确认框那条线）**：
  ① `?` 注销确认框的**四个出口全部端到端验过** —— `cancel` → 退出码 4 未注销；
  `confirm` → 读到答案后倒计时 5 秒，`NO_RESPRING=1` 时「只倒计时，不注销」、退出码 0、屏幕不黑；
  `timeout`（弹窗 45 秒无人应答，插件自己写 `timeout`）→ 退出码 5；脚本判 `none` 同样退出码 5，
  **四条路都绝不自动注销**。
  ② `?` 弹窗在**别的 App 前台**照样弹：切到「设置」前台后写请求，`alerts` 4→5、`mode=alert`、
  45 秒后 `ans=timeout`（SpringBoard 顶层窗口 `lvl=20000000`，盖得住任何 App）。
  ③ 本轮操作后 `apelin_crash_list process=SpringBoard` **为空**。
  ④ 仍缺：点胶囊后是否**精确落在**那一条会话（宿主拒绝在 Apelin 前台代点，需用户亲手点胶囊确认）。
  技能 `respring-notify-countdown` 的「零、八」一节已写死这条。
- 验证：`icli prefs read com.apple.springboard CountdownHUDDiagnostics`
  → `v1.6.0;shows=N;last=5s;label=注销;font=12.3;island=<类名>|x,y,w,h;src=aperture;cand=N;mode=count;haptic=N;alerts=N;ans=-;link=<sid>|none;taps=N`；
  量到的候选清单：`icli prefs read com.apple.springboard CountdownHUDIslandCandidates`
  （最多 8 行 `A|<类名>|x,y,w,h`，前缀 A = 在 Aperture 窗口里）；
  日志 `icli log syslog --subsystem com.yangzhou.countdownhud`。
- 卸载：`irisin-cli remove com.yangzhou.countdownhud`；不装它时脚本照样终端倒计时，只是屏幕上没有胶囊。

**规矩（用户 2026-10-31 05:33 原话：「以后注销事件给我一个警告⚠️弹窗 让我决定要不注销！」）**：
注销一律先 `sh scripts/respring-guard.sh 5 <标签>`（标签写清动作，如「注销」「装包」）—— 它**只警告、
不注销**：屏幕胶囊弹「⚠️ 要注销吗？在 Apelin 回「注销」或「取消」」45 秒，终端打印警告块，**退出码 3**。
等用户在 Apelin 明确回「注销 / 确定」之后，同一个动作才跑
`sh scripts/respring-guard.sh --confirm 5 <标签>`（5 秒倒计时 + `sbreload`）。
**没回话、回「取消/先别」、或者只是自己觉得该注销了 —— 一律停在警告那步，绝不加 `--confirm`。**
`--confirm` 必须写在最前面。

## 每轮开动之前：本机全部技能 + 全部记忆 + GitHub 云端全部技能与项目（硬性规定）

用户 2026-10-30 16:12 与 16:14 两次明确要求，**适用于本次、下次、以后每一个对话、每一个工程**：

- **本机全部技能包都要调用**：开工先 `apelin_skill_list`，再逐个 `apelin_skill_read` 把本机那几份
  **全部**读完（**以 `apelin_skill_list` 的清单为准**，清单里新出现的也要读，不许漏）——
  `a11-roothide-ondevice`（本机 A11/roothide 的设备侧做法、云编译闭环、一站一槽钩子修法）、
  `axs-ios-tweaks`（Axs 个人约定的工程规范：命名空间、面板、滑条、Rootful/Rootless/Roothide 打包适配）、
  `respring-notify-countdown`（装包/注销/杀进程前的通知与 5 秒倒计时、外出取证必回 Apelin）、
  `cross-chat-coordination`（**自己的任务第一**；有进展/完成就广播给所有在跑的对话；注销/装包/杀进程前先查全部
  工程与对话、先跟正在干活的对话打招呼再动手；闲置时才协助别人、交接要三段式；
  **跨对话同步只有 `apelin_conversation_send`/`read` 直接发消息这一条路**，黑板/看护/心跳已删，别重造）、
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
  `apelin_notification_send` → 正文写清动作 → **注销先只警告**（`sh scripts/respring-guard.sh 5 <标签>`，
  只弹胶囊警告、退出码 3、**不注销**），等用户明确回「注销 / 确定」后才
  `sh scripts/respring-guard.sh --confirm 5 <标签>` 真倒计时 5 秒 + `sbreload`；装包这类要接着做动作的用
  `RESPRING_GUARD_NO_RESPRING=1 sh scripts/respring-guard.sh --confirm 5 装包`；重启目标进程用
  `sh scripts/device.sh kill <bid>` + `sh scripts/device.sh launch <bid>`；离开 Apelin 取证仍受 60 秒硬上限
  与「必须自己回来」约束；截图每次仍需用户当次明确同意。
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

- **构造函数里禁止做重活、禁止对「任意运行时类」发消息 —— 一次崩就是安全模式**（2026-10-31 10:37 / 10:44
  两次实测事故，用户原话：「又安全模式了！修复前后第一时间把安全模式注销的事件和修复后的方法告告诉全员知道」，
  **所有工程、所有对话、永久适用**）：
  - **事故**：ThemeCorePlus 0.9.21 装上后 SpringBoard **连续崩 5 次 → 进安全模式**（`consecutiveCrashCount: 5`，
    `throttleTimeout: 5`）。崩溃报告 `SpringBoard-2026-10-31-103755.ips` / `-103832.ips` / `-104430.ips`，
    `bug_type 309`、`EXC_BREAKPOINT`、`SIGTRAP`、`faultingThread 0`（主线程），栈：
    `TCPInitialize` → `TCPLayoutInstall` → `TCPLayoutHookSave` → `CF_forwarding_prep_0` → `___forwarding___`
    → `___forwarding___.cold.3`。寄存器里 `OBJC_CLASS_$_ISOverlayEmbossedFolder` + `isSubclassOfClass:`。
  - **根因**：`ThemeCorePlusLayout.m` 的 `TCPLayoutCandidateClasses()`（被内联进 `TCPLayoutHookSave`）用
    `objc_getClassList` 枚举**全进程所有类**，再对每一个类发 `[c isSubclassOfClass:base]`。其中某个类
    不响应这条类方法 → 消息转发失败 → `SIGTRAP`。**这一步跑在 dyld initializer（构造函数）里**，
    所以 SpringBoard 每次启动都必崩 → 连崩 5 次 → 安全模式。0.9.19 不崩是因为它不枚举类。
  - **修法（0.9.22 起，写代码时照做）**：
    ① 判类关系一律用 **C 函数 `class_getSuperclass()` 往上走**，绝不用 `isSubclassOfClass:` /
       `isKindOfClass:` 去问一个「从运行时枚举出来的、来路不明的类」；
    ② 枚举类、挂站这类重活**移出构造函数**，放到启动后主队列的第一拍（延迟 ≥1 秒），构造函数里只做纯赋值；
    ③ 加**启动护栏文件**：跑重活前写 `~/Library/ThemeCorePlus/.tcp-launch-guard`，跑完删掉；
       下次启动发现它还在 = 上次就是崩在这里 → **整段跳过**并记 `lay{safeskip=1}`，宁可功能不生效也绝不连崩；
    ④ 任何 `MSHookMessageEx` 之前先用 `method_getTypeEncoding` / `method_getNumberOfArguments` 验真实签名，
       宁可一个都不挂。
  - **症状识别**：屏幕顶部「安全模式」、所有插件失效、诊断键还是崩溃前的旧值（`defaults` 值会残留，
    **读到诊断 ≠ 插件在跑**）。此时 `irisin-cli show <包>` 看版本，`apelin_crash_list process=SpringBoard`
    看 `consecutiveCrashCount`；回滚到已知good版本 → 用户点头 → `sbreload` 即脱离。
  - **纪律**：**新版本只许一条线装一次**，装之前先 `irisin-cli show` 核对版本、装之后立刻读 crash list；
    已出过崩溃的版本号**永不复用**（0.9.21 已废，下一版从 0.9.22 起）。
  - **单线修复纪律（用户 2026-10-31 10:56 原话：「安全模式全员对齐工作进展和工作内容，只准一个对话机器人着手
    修复安全模式！其它机器人立即停止⏹️工作！同步通告全员！修复后第一时间通告全员后让他们继续工作！」）**：
    - 一进安全模式 / 一出崩溃循环，**只留一条「修复线」**（由本对话指定并写进广播），它独占：改代码、
      触发云编译、装包、注销、回滚。**其它对话立即停手**：不改相关源码、不 push、不建 run、不装包、不注销、
      不读设备状态做判断；只准回一句「收到，已停手」。
    - **停手范围 = 整个 ThemeCorePlus / CountdownHUD 及其装包与注销**，不只是崩溃的那个文件 ——
      0.9.21 就是「别的线自己装了一次」把设备两次送进安全模式。
    - 修复线修完 → 自己先验（`irisin-cli show` 版本对、诊断对、`apelin_crash_list` 无新增）→ **第一时间
      通告全员**「已修复，可以继续」+ 各自被冻结的那一步 → 再让它们复工。**没通告前不许任何人复工。**
    - 广播一次一条、三行以内：现状 / 谁是唯一修复线 / 其它人现在做什么。用 `apelin_conversation_send`。
    - **排查有结论、修复完成，都要第一时间通告全员**（用户 2026-10-31 11:0x 原话：「安全模式排查！修复早后都要
      第一时间通告全员知道！这个内容同步到以上规则内！」）—— 不等修完才说，排查出根因就先发一条；修完再发一条
      「已修复，可以继续」。两条都不许省。
  - **防回滚：版本锁 + 唯一装包入口（2026-10-31 11:0x 落地，脚本已实测）**：
    - `scripts/version-lock.txt`：`owner`（唯一修复线 session id）、`version`（唯一允许装在机上的版本）、
      `dylib_sha256`（该版本指纹）、`deb_sha256`。**只有 owner 能改**，改版本 = 改这个文件，一改就要提交上云。
    - `scripts/deb-guard.sh`：装包/注销的唯一入口。
      `GUARD_SID=<自己的 sid> sh scripts/deb-guard.sh install <deb>` —— 不是 owner 直接 **exit 6 拒绝**；
      版本与锁不符 **exit 7 拒绝**（顺手回滚就卡在这里）。`respring` 子命令同样先验归属，再交给
      `respring-guard.sh`（仍然要用户点头 + `--confirm`）。`check` 只读比对锁与机上实况。
    - `scripts/safemode-check.sh`：一条命令体检，只读、不弹卡。输出 ①版本 ②dylib 指纹 ③最近崩溃
      ④`ThemeCorePlusLayout` 的 tick 两次读数是否在涨（插件这一刻在不在跑）。退出码
      `0`健康 / `1`连崩或安全模式 / `2`**版本漂移（有人回滚或私装）** / `3`插件没在跑 / `9`读数缺失。
    - **绕过守卫硬敲 `irisin-cli install` = 违规**，会被 `safemode-check.sh` 的 ① ② 抓到（exit 2）并广播点名。
    - 判定「在安全模式」的硬证据：最新 ips 的 `consecutiveCrashCount ≥ 5`、SpringBoard 的 pid 自那次崩溃后
      没换过、且 `tick` 不再增长（注入被 ellekit 关掉）。**读到诊断 ≠ 插件在跑**。
      **tick 有 60 秒写盘节流**：状态没变时诊断里的 `tick` 最多旧 60 秒，量「活没活」要隔 70 秒读两次，
      7 秒内两次不动**不能**判死（2026-10-31 11:03 就差点误判）。
  - **一个 bug 只许一条线改：禁止全员反复修改、反复回归（用户 2026-10-31 11:0x 原话「做到一个 bug 不要被全员
    反复修改回归耽误用户时间」）**：
    1. 同一个 bug 的**改码权只属于 `scripts/version-lock.txt` 里的 owner**；别的线读到新线索 → 一条消息发给 owner，
       不自己改、不自己装、不自己注销。
    2. owner 一轮只出**一个**改动：改一处 → push 一次 → 编一次 → 装一次 → 验一次。**禁止「装 A 不行又装 B」的来回**；
       换方案先广播为什么，再动手。
    3. 每次装包/注销必须过 `scripts/deb-guard.sh`（非 owner exit 6、版本不符锁 exit 7）；绕过它硬敲 `irisin-cli`
       一律算违规，`safemode-check.sh` 的 ① ② 会抓到并广播点名。
    4. **出过崩溃的版本号永不复用**（0.9.21 已废，下一版 0.9.22），改完必须换版本号，别在同号上反复覆盖。
    5. 修完第一时间通告全员「已修复，可以继续」，并把根因与结论写进 AGENTS.md / 技能 / 记忆（同一提交），
       让下一条线不用重新踩坑。
  - **事故复盘必须发给全员（用户 2026-10-31 11:1x 原话「安全事故原因过程解决后的分析发给全员！这个也写成
    运行规定」）**：任何安全事故（崩溃循环、安全模式、数据丢失、误删）**解决之后**，必须写三段并发给所有在跑的
    对话 —— ① **原因**（直接原因 / 崩点 / 为什么升级成事故 / 根因归类）② **过程**（怎么发现、耽误在哪、哪一步
    判断错了）③ **解决与复盘**（怎么救回来、以后怎么防、规矩落到哪个文件）。
    模板与本次实况：`docs/cases/springboard-safemode-0.9.21.md`；广播用「一句话版本」那一节，三行以内。
    复盘不是可选项：只修不写 = 没修完。
  - **根因没定位前，不许注销、不许装新包（用户 2026-10-31 11:16 原话「在没有真正排查出安全事故的原因情况下
    不要让他们注销」）**：注销是**验证手段**，不是排查手段 —— 根因不明就注销 = 拿用户桌面做随机试验，
    还会掩盖证据（注销后 pid 变了、崩溃现场没了、诊断键仍是旧值）。固定顺序：
    **先读 ips 定位 → 改码 → 云编译 → 装包 → 最后才注销**；注销仍须用户当轮点头
    （`respring-guard.sh --confirm 5 <标签>`）。多人排查时由 owner 统一对外，**任何人不得自行发起注销**。
  - 技能：`a11-roothide-ondevice` 第 9 节「安全模式与崩溃循环自救」。
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
- **任何界面都要用灵动岛胶囊告知用户（2026-10-31 15:48/15:50/15:51/15:53/15:56 定，用户原话「不能访问我的仓库时
  给我说一声你来个通知或者弹窗让我知道这个！」「通知和弹窗都行让我知道啊」「无论任何界面都要给我一个通知或者弹窗」，
  **所有工程、所有对话、永久适用**）**：
  - **要「任何界面都让用户看见」= 必须写灵动岛胶囊** `sh scripts/hud-notify.sh 8 "!<一句话>"`（`!`=纯文案，
    CountdownHUD 注入 SpringBoard 的**顶层窗口**，Apelin 内 / 桌面 / 别的 App 都盖得住，3~60 秒可调）。
  - **`apelin_notification_send` 只在 Apelin 不在前台时显示**，Apelin 在前台时横幅被自己的通知代理吞掉，
    用户看不到 —— 不能当唯一手段，只能做「用户离开 Apelin 时」的补充。
  - **凡要让用户知道的事**（任务完成、失败、阶段进度、push 前后、需要用户点头）都照此：正文写清 + 胶囊 + 可选通知。
  - 落地：技能 `notify-any-screen`（通用告知）；push 场景见下面「GitHub 访问规矩」+ 技能 `notify-before-git-push`。
- **GitHub 访问规矩（2026-10-31 15:48/15:50/15:51 定，用户原话「需要上传到我的 github 仓库时你跟我说一下！我开 VPN」
  「因为 GitHub 在国内访问、经常因为 DNS 污染不能直接访问！必须开 vpn 才行！」「不能访问我的仓库时给我说一声
  你来个通知或者弹窗让我知道这个！」，**所有工程、所有对话、永久适用**）**：
  - **push 前先告诉用户开 VPN**：每次 `git_push` 到 GitHub 前，先在正文说「现在要推送到你仓库，GitHub 国内被
    DNS 污染，请开 VPN」，等用户回「开了/继续/推送」再 push。绝不静默 push、绝不因「上一轮成功过」跳过告知。
  - **开 VPN 必须弹窗让用户确定（2026-10-31 16:02 加）**：凡让用户开 VPN，一律用灵动岛**确认弹窗**（`?` 模式 /
    `sh scripts/respring-guard.sh --ask 120 <标签>`）让用户点确定，不能只发纯文案胶囊或 `apelin_notification_send`
    （那些不让人「确定」）。用户点「确定」后再 push。
  - **push 成功 = VPN 通 = 只发一条灵动岛胶囊「已推送」，不再弹窗、不发通知**（2026-10-31 16:00 加）。
  - **push 失败 / 不能访问仓库 → 必须通知/弹窗让用户知道**：报网络错误（`failed to connect` /
    `Operation timed out` / `SecureTransport OSStatus -9806`）时，正文说清原因 + 胶囊
    `sh scripts/hud-notify.sh 8 "!push 失败，请开 VPN"`。**不许静默失败、不许空转重试十几遍不吭声**。等用户确认 VPN 就绪再重试。
  - **原因**：GitHub 在国内被 DNS 污染，不能直连。本机实测（2026-10-31 15:4x）：github.com 普通 HTTPS
    （NSData / icli probe / apelin_web_fetch）有时能通，但 Apelin 的 `git_push` 走另一条网络路径，
    不开 VPN 就反复超时，开 VPN 后立刻恢复。
  - `git_commit` 是本地操作（不联网）不受限；只有 `git_push` 到 GitHub 才需要先告知开 VPN、失败才需要通知/弹窗。
  - 落地：技能 `notify-before-git-push`；记忆「每轮开工…三样同步…push 前告知开 VPN」。
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
- **跨对话同步：只有「直接发消息」这一条路（黑板 / 看护 / 唤醒队列 / 心跳，2026-10-31 05:5x 全部删除）**
  （用户 05:41–05:5x 原话：「跨工作区跨对话的任务与进展同步协调统一还是没能实现」「我不说你们都不知道对方在干嘛」
  「看看这个功能还有别的实现方案方法没！」「删掉本地和云端失败的那几种同步工作进展和内容的方法！」
  **所有工程、所有对话、永久适用**）：
  - **已删掉、禁止重造的东西**：共享黑板 `board.tsv` + `scripts/fleet.sh`、launchd 看护
    `com.yangzhou.fleet-watchdog` + `scripts/fleet-watchdog.sh` + `scripts/install-watchdog.sh`、
    唤醒队列 `wake-needed.tsv`、协调群 `coordinator.txt`、名册 `agents.tsv`/`inbox.tsv`/`links.tsv`、
    环形互跳 / 传棒保温 / 专职心跳发生器、技能 `fleet-shared-board`。**本地与云端都已删，一条都别再试。**
  - **为什么必然失败（根因，记住这句就够）**：agent 回合结束就 `idle`，**只有外部发来的消息能把它叫醒**；
    而「谁还活着、谁在干什么」**没法靠文件时间戳推断**——推断必然误报（看护把已结束的会话当睡死，反复 STALLED，
    案例 `docs/cases/fleet-watchdog-false-positive.md`）。任何「让别人自觉写状态、再由第三方推断死活」的方案都不成立。
  - **有效通道 ①：要别人知道一件事** → `apelin_conversation_send`（一次一条，三行内：做了什么 / 证据 / 下一步）。
    这是唯一实测能真到达、能被读到的通道。
  - **有效通道 ②：要知道对方现在怎么样** → `apelin_conversation_list` 看 `state`
    （`running` / `waitingForApproval` / `idle` / `ended`）+ `apelin_conversation_read`（`wait_seconds` 等它收尾）。
    **`ended` 收不到消息**，只能请用户在侧栏重开——写进正文告诉用户，别自己重试。
  - **有效通道 ③：要「不说也知道别人在干嘛」** → `sh scripts/fleet-live.sh [分钟数]`：直接读
    `sessions/<sid>/events.jsonl` 的最后活动时间与最后一条意图，**不依赖任何人写任何东西**，
    是目前唯一「实证派」的全队视图（本仓库 `scripts/fleet-live.sh`，云端同名）。
  - **有效通道 ④：要让用户知道** → 回复正文 + `sh scripts/hud-notify.sh`（胶囊）+ `apelin_notification_send`，
    见 `task-done-notify`。用户要的是他自己看得见，不是机器人之间的暗号。
  - **规矩不变**：自己的活第一、别人消息第一时间回执、动设备前打招呼（协调 → 通知 + 5 秒）、交接三段式
    （任务 / 现状与证据 / 下一步与命令）、绝不 `apelin_conversation_stop` 别人、绝不改别人工程的文件。
    细则与自检清单见技能 `cross-chat-coordination` §十二、§十三。
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
- **装包 / 注销 / 重启目标进程之前，必须：① `apelin_notification_send` 通知 → ② 正文写清要做什么 →
  ③ 注销先只警告（`sh scripts/respring-guard.sh 5 <标签>`，弹胶囊、退出码 3、不注销）→ ④ 用户明确
  回「注销 / 确定」后才 `sh scripts/respring-guard.sh --confirm 5 <标签>` 真等 5 秒并 `sbreload`。**
  用户 2026-10-30 三次要求「先通知 + 5 秒」，2026-10-31 05:33 又加一条「注销必须我点头」；两条都写进
  本文件与技能 `respring-notify-countdown`。
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
- **唤醒与「谁在干嘛」的硬事实（2026-10-31 03:0x–05:5x 实测，替代已删的环形互跳/唤醒队列/心跳发生器）**：
  - **Apelin 不允许对话给自己发消息**（`send` 到自己 → `session_id is this conversation` 被拒）：
    「自跳心跳」技术上不存在，写它的条文都是空话。
  - **四种状态，四种处置**（动手前必须 `apelin_conversation_read` 核 `state`，别只看时间戳）：
    `idle` = 能叫醒，`apelin_conversation_send` 有效；`waitingForApproval` = 卡批准卡，`apelin_notification_send`
    请用户点；`running` 且久无输出 = 卡在工具循环，消息只排在后面，**发唤醒没用**，只能由用户停掉/重开
    （agent 无权 stop 别人的对话）；`ended` = 收不到消息，只能用户在侧栏重开。
  - **第五种「叫不醒」：模型线没额度**——`send` 返回 `done=sent`，但 `events.jsonl` 尾部立刻
    `{"finished":{"reason":"failed"}}`（`code:14018 / Credits exhausted`）或反复 `{"reconnecting":{}}`。
    判据：`tail -n 8 sessions/<sid>/events.jsonl`，mtime 每秒在动 + `tokens` 递增 + 零 error 才是真在干活。
    修法：`cp session.json session.json.bak-model` 后把 `"model"` 改成有额度的线（本机 `deepseek-flash`），
    Apelin 每回合重读 `session.json`，改完立即生效。**逐个发、别群发**（同时唤醒会撞上游限流，挂了等 60 秒）。
  - **想知道全队此刻在干什么**：`sh scripts/fleet-live.sh [分钟数]`（读 `events.jsonl`，实证派），
    或 `apelin_conversation_list` 逐个工程看 `state`。**没有别的办法，也不需要再发明一个。**
  - **红线**：唤醒与广播**都不替代汇报**（有结果先在正文说清 + 上岛）、**不替代协调**（动设备仍走
    「协调 → 通知 → 5 秒 → 用户点头」）、**不替代回执**（别人的消息第一时间回）。消息一句话就够，省 context。

## 当前状态

### 🔴 统一调度台与三线任务分工（2026-10-31 12:45，用户排定优先级）

**用户原话**：「第一个重要的任务就是修复图标布局不能保存的问题第二个是修复图标不能正确加载的问题第三个修复角标不能正确教的问题」。

**统一调度台 = 本对话 `f8fbdbd5-7f8c-402e-820f-73b6872c394b`（标题「继续操作」）**：
注销回来后由它合并全员信息、整合、统一排程；各线只执行并向它汇报，不互相协调、不重复协调
（硬规矩 + 技能 `respring-hub-merge-dispatch`）。

| 优先级 | 任务 | 对话 | 改码范围 | 版本号 | 出包状态 |
| --- | --- | --- | --- | --- | --- |
| ① | 图标布局不能保存 | `37cad7f0` | `ThemeCorePlusLayout.m` + Main.m + build.sh | **1.0.5** | 🔄 push e3a9f635，CI 编译中 |
| ② | 文件夹图标显示 | `1f464fa1` | `ThemeCorePlusFolders.m` + `Hooks.m` | 1.0.4 | ✅ 已装机 |
| ③ | 时钟日历修复 | `be994374` | `ThemeCorePlusIcons.m` | 1.0.6 | 🔄 改码中 |
| — | HUD 1.6.1（点确认自己注销） | `3e983c10` | `CountdownHUD.m` + `scripts/respring-guard.sh` | 1.6.1 | ✅ 已装机 |

**一文件一写者**：`Layout.m` / `Icons.m` / `Badges.m` / `CountdownHUD.m` / `version-lock.txt` 各归一线上表那条，
越界前先在群里问。

**两个注销窗口（顺序固定，别撞）**：
- **第 1 轮 = HUD 1.6.1**，`3e983c10` 走，**等用户当轮点头**。其它线这期间**不发弹窗、不装包、不注销**。
- **第 2 轮 = ThemeCorePlus 0.9.25 + 0.9.26 + 0.9.27**，**调度台排**（等 0.9.27 出包）→ 一次装三个 →
  弹窗 → 用户点头 → 一次注销 → 各线只读验收。
  （0.9.24 已被 0.9.26 取代，不单独装。）

**装包/注销权统一在调度台**：出包的线只报「run 号 + deb 文件名 + deb sha256 + dylib sha256」，
**不自己装、不自己注销、不发弹窗**；`scripts/version-lock.txt` 的 owner = `f8fbdbd5`。

**三个验收字段组互不重叠，可分开归因**：图标看 `census{layer{ours>0}}` / `file{hit>0}`；
角标看 `sys{…tree=…*…}` / `sys{host=N}`；布局看 `probe=` 的 `cand[model=N,ctrl=M]`。

**注销流程**：走 `respring-cross-team-notify` 四步（全员通知 → 正文知情 → 弹窗让用户决定 →
用户当轮明确点头才 `--confirm`），别让用户被黑屏好几次。

**三条任务的现有证据（0.9.23 实测，`v0.9.23` 在跑、tick 在涨、无新崩溃）**：
- 布局：`lay{…site=none,model=-,last=noinstance,probe=-,hooked=0}` —— 一个站都没挂上；
  **真根因（0.9.25 的提交说明里定案）**：`TCPLayoutHookSave()` 只在 hooked/skipped 非空时才写 probe，
  于是「找到了类、但一个方法名都没匹配上」退化成 `probe=-`，看起来像什么都没枚举到。
  `hooked=0` 可信；`sav=` 是备份写盘次数、`site=` 旧值是 prefs 跨进程残留，两者都不能当「曾挂上站」的证据。
- 图标：`file{look=58,hit=0}`（58 个素材全 miss）、`icon{look=4,miss=4,hit=0}`、
  `census{layer{ours=0},disp{ours=6}}`（`Icons.m` 纯指针比对必然不等）、
  `pix{screen{ours=0,stock=0}}`（主题图一张没上屏）、`dyn{seen=0}` + `clockv{last=noface}`（时钟日历没认出来）。
- 角标：`sys{…tree=SBDarkeningImageView}` 无 `*`、`asset=25x25;canvas=25x19;fit=0.78`。
  **别用 `badge{look=0,hit=0}` 判「素材没接上」** —— 那是 iOS 16.7 上两个角标背景方法不存在导致的恒 0，
  与素材无关；真正在用的是 `txt{look=133,hit:133}`，主题 `SBBadgeBG@3x.png` 实测 75×75 px 是有的。
  角标验收看三条：`sys{…tree=…*…}` 有 `*`（真清动过）、`sys{…host=N}` 的 N>0（contents 那步真执行了）、
  屏幕只剩主题那一层（透明玻璃）没有系统红底。

### 其它历史状态

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

