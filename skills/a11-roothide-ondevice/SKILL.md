---
name: a11-roothide-ondevice
description: 在这台 iPhone10,1（A11 / iOS 16.7.16 / roothide）上做越狱 deb 的现实做法：本机没有可用工具链，所以写完源码走 GitHub Actions 双切片云编译（arm64 + arm64e），再用 irisin-cli 装到本机、重启目标进程读诊断验证；含「一站一槽 / Per-Site Original Slot」钩子修复法、隐根路径、过滤器、日志窗口与故障速查。
---

# A11 / roothide 设备侧工作方式（含云编译闭环）

本文件只写**在这台设备上真正成立**的做法：iPhone10,1（iPhone 8，A11，iOS 16.7.16，roothide 隐根）。
插件本身怎么写、字段怎么填，读 Apelin 的内置技能（apelin-tweak-development、apelin-project-description、apelin-bootstrap-paths、apelin-package-dependencies…），这里不复制。

## 0. 一句话闭环

本机没有编译器 → 源码 push 到 GitHub → GitHub Actions 用 clang 直编出 **arm64 + arm64e 双切片**的 deb 并发布成 Release → 用 `irisin-cli` 装到本机（真根路径）→ **重启目标进程** → 读插件自己写的诊断 / 崩溃报告 → 界面行为最后单独确认。
这套叫「A11 双切片云编译闭环」，是这台机器上唯一能走通的交付路径（已在 com.unknown.notesreadonly 上完整跑过两轮）。

## 1. 本机没有编译器，也不要去装

- A11 缺 `FEAT_LRCPC`：Apple 目录里每个 Command Line Tools 都被 `apelin_toolchain_list` 标成 `requires CPU features this device lacks`，`installed` 永远为空。SDK（iphoneos16.4/16.5）已注册也**不是**编译器。
- 不要写、也不要承诺「本机直编闭环」「本机自测通过」；不要反复试装工具链，不要改 flags 绕。工具链状态每次都读 `apelin_toolchain_list` 的实时结果。
- `apelin_project_build` 在这台机器上必然失败（没有匹配的工具链），带编译需求的模板新建时就会被拒，只有 workspace/empty 这类空工程能建。所以「产出 deb」这件事只发生在 CI。

## 2. 云编译的形状（已验证）

- CI 里检出 `roothide/theos`（私有头在 `$THEOS/vendor/include`，预编的 `CydiaSubstrate.framework` 在 `$THEOS/vendor/lib`），SDK 用 `theos/sdks` 的 headerless `iPhoneOS16.5.sdk`，再 `brew install ldid dpkg`。
- **不用 Theos 的构建系统**：一个 `sh scripts/build-xxx.sh` 里 clang 逐 arch 编译、`lipo -create` 合成、`ldid -S` 签名、`dpkg-deb -b --root-owner-group` 打包。
- 一个产品一个 workflow 文件，`push` 触发 + `paths` 过滤（只列这个产品的源码、构建脚本和该 workflow 自身）。**没有 paths 过滤时，改一次文档也会重建并覆盖 Release 资产**，把已经在设备上验证过的那份 deb 换掉。
- Release 资产**每次运行都重建**：源码没变也会得到不同的体积与 sha256。记录验证结果时写清楚「哪一次 run（head 提交）产的」，不要拿旧 sha256 当"这一份"。
- job 日志要登录才能看，所以把要读的验证信息写成 check-run annotation（`::notice title=…::`），公开仓库的 annotations 匿名可读。
- 构建脚本自己核对：切片是否 arm64 **和** arm64e 都在、substrate 依赖是否为 `.jbroot` 相对形式；缺一片就 exit 非 0，别把坏包发出去。

- **默认只编 roothide，但 rootless 的编译能力必须留着**（用户 2026-11-01 11:14 明确要求）：
  本机是 roothide 隐根，**默认只编译、只发布 roothide 包**（arm64 + arm64e 双切片，装本机的那一份）。
  `scripts/build-xxx.sh` 的第二个参数 `rootless` **能力保留、代码不许删** —— 什么时候要编 rootless
  无根包由用户明说（「要编 rootless deb」），那时才跑那条腿。
  推论：**不要**为了「省 CI 配额」把 rootless 那条腿从脚本里删掉或注释掉；省配额靠少触发、
  钉死工具版本、合并 job，不是砍能力。工作流里现在**只有一个 build job（roothide）**，
  第二个 job 是 release（只发资产、不编译）；rootless 从来没在这个工作流里编过。
- **CI 省配额的常规做法（用户 2026-11-01 11:16 认可，之后都这么写）**：
  ① **钉死 Xcode 版本**——`setup-xcode` 用具体版本（如 macos-15 镜像的 `16.2`），不要 `latest-stable`：
     后者每次可能切换大版本并重建索引，是 macOS runner 上最慢的一步（2–5 分钟）。
  ② **发布合并进 build job**——原来 build(macos-15) + release(ubuntu-latest) 两个 job，
     产物要 artifact 上传/下载再发布；合并成一个 job 后产物直接在 `packages/`，
     省一次 runner 启动与一次上传传输，发布失败仍有匿名托管兜底步骤。
  合并后工作流只有 `jobs.build`（runs-on: macos-15），发布步骤用 `softprops/action-gh-release`
  + `token: ${{ github.token }}`，`files: packages/*.deb`；顶层 `permissions: contents: write` 继承即可。
- **云编译过程「静默折叠」，出问题才汇报**（用户 2026-11-01 11:28 明确要求，所有工程、所有对话永久适用）：
  触发 CI / 等编译 / 查 run 状态 / 下载 / 装包 / 读诊断这类**过程性动作，只做不说**，不要在对话里
  一条条播报「push 了」「CI in_progress」「sleep 等结果」「下载成功」。
  只有**结果或真出问题**（编译失败、Release 没发布、装机报错、诊断异常）才开口，一次说清：什么挂了 + 证据 + 下一步。
  配合省额度原则：过程性工具输出也不往上下文里贴，自己消化后只留结论。
- **补充（用户 2026-11-01 11:57）**：过程里的小差错（下载脚本版本号写错、重下、改参数、重推、换文件名等）
  **能自己解决就自己解决，不播报、不写进三样上云**；只有**卡住无法自行解决**的才告诉用户。
- **修完问题不要直接云编译，等用户确认后才编译**（用户 2026-11-01 12:10 明确要求，所有工程、所有对话永久适用）：
  改完源码/工作流后，**先停下来把「改了什么、怎么改的」告诉用户，等用户点头（确认/编译/继续）才 commit+push 触发云编译**；
  绝不改完就顺手 push 触发 CI。commit/push 是「等确认后才做」的动作，不是改完自动做的动作。
- **刷新兜底与布局覆盖（用户 2026-11-01 12:20 认可沉淀）**：
  ① 进程内热刷新（面板「刷新图标」、`device.sh kill`+`launch`）**优先**，不注销、不黑屏；热刷新做不到 100%
  （比如某类视图没被热刷新覆盖到）时，**重启式刷新（`sbreload`）是最终兜底**——它重启整个 SpringBoard，
  所有注入重载、视图重建、缓存清空，图标/角标/主题/桌面布局保证全部生效；但必须走注销弹窗确认，不是自动动作。
  ② roothide 下 `cp`/`chown` 系统路径（如 `/var/mobile/Library/SpringBoard/IconState.plist`）**必须加真根
  前缀 `/rootfs`**，否则写进隐根容器里的假路径、系统读不到。shell 里判断：`ls /rootfs/var/mobile/...`。
  ③ 覆盖布局文件**先停 SpringBoard（或先注销）→ 再覆盖 → 再起**；SpringBoard 还活着时直接 `cp` 覆盖，
  它会把内存里的旧布局写回磁盘，白覆盖。`sbreload` 本身就重启 SpringBoard，别再叠加 `killall SpringBoard`。
  ④ ThemeCorePlus 已内置布局自动备份/恢复（`/rootfs/var/mobile/Library/ThemeCorePlus/IconState.backup.plist`），
  手工 `cp` 那一套插件内部已经做了；要恢复就用这个机制，不自己硬 cp。
- **云编译开始后每 3 分钟查一次状态**（用户 2026-11-01 12:56 明确要求，所有工程、所有对话永久适用）：
  push 触发云编译后，**每隔约 3 分钟用 `icli probe scripts/ci-status.js` 查一次 run 状态**（success/failure/in_progress），
  查到 success 就下载、装、验；查到 failure 就停下定位报错、等用户。中间过程照旧静默不播报，只报「结果/出问题」。
- **补充（用户 2026-11-01 12:57）**：云编译每 3 分钟查状态**自主自动做，不用等用户催**；
  查 GitHub API 失败（网络不通、访问不了 github）时，**立即弹窗告诉用户**（`sh scripts/vpn-guard.sh`，
  标签写「查编译失败，访问不了 GitHub」），等用户开 VPN/处理后重查。
- **更正（用户 2026-11-01 13:05）**：云编译查询频率**从每 3 分钟改为每 1 分钟**（`icli probe scripts/ci-status.js`），
  自主自动做、不等用户催；查 GitHub API 失败（网络不通）立即弹窗（`vpn-guard.sh`）。
- **安全模式下绕过弹窗直接装 + 注销**（用户 2026-11-01 13:09 认可，救急用）：
  安全模式（MobileSafety）里**所有 tweak 都不注入，CountdownHUD 也死了** → `respring-guard.sh --ask`、
  `vpn-guard.sh` 写的 `?` 弹窗**根本不会显示**，走弹窗流程会卡死（超时/没反应）。
  此时救急做法：**直接用 `irisin-cli install --yes --json <deb>`（root）装，再 `sbreload` 注销**，
  绕过弹窗。前提与理由：用户已经在安全模式、什么都跑不起来，没有「打断别人工作」的顾虑，
  装包+注销是唯一能让系统恢复正常的动作。判断是否安全模式：诊断/弹窗全无反应、tweak 全不生效、
  桌面出现「安全模式」横幅。
- **装包注销进桌面后立即自动体检**（用户 2026-11-01 13:37，所有工程、所有对话永久适用）：
  每次装包 → sbreload → 桌面起来后（等约 10-12 秒），**立刻自动做一次体检，不等用户催、不播报过程**：
  ① 读诊断键确认版本号已变（v1.0.x = 新包在跑）；② `apelin_crash_list process=SpringBoard` 查有无新崩溃；
  ③ 读运行日志尾部确认启动行（「启动 v@ pid=」）；④ 读关键功能诊断（sites/grid/dyn/clockv 等）确认站点挂上。
  全部正常 → 只报一句「✅ 1.0.x 已装已验：版本 ✓ 无崩溃 ✓ 站点 ✓」；有异常（崩溃/版本没变/站点没挂）
  → 立即带着证据开口定位。
## 3. 双切片是这台设备的硬要求

| 事实 | 数值 |
|---|---|
| 用户态进程架构 | arm64（SpringBoard 是 `Mach-O 64-bit arm64`） |
| 已装 tweak dylib | 52 fat、6 仅 arm64、**0 仅 arm64e** |
| 包标签 | roothide 写 `Architecture: iphoneos-arm64e`（与 dylib 的真实 slice 无关） |

- 被注入的 dylib **必须含 arm64**；只含 arm64e 的在这个设备上注入不进任何进程，症状是「装上后完全没反应、没有日志」（1.0.7 的包就是这样一直没生效）。
- 包标签保持 `iphoneos-arm64e`，不要改成 `iphoneos-arm64`（那是 rootless 的标签）。
- 看切片：`file <dylib>`；本机没有 `lipo`/`otool`/`nm`/`size`/`python3`，别写依赖它们的排查步骤。

## 4. 链接坑（headerless SDK + vendor 头）

- substrate：`-F$THEOS/vendor/lib -framework CydiaSubstrate`（`-lsubstrate` 解析不了）。
- 该 SDK 的 `UIKit.tbd` **不 reexport CoreGraphics**（Foundation 仍 reexport CoreFoundation）。凡用到 `CGRectZero` / `CGRectGetWidth` 之类，必须显式 `-framework CoreGraphics`。别为了"修"链接把它去掉。
- install_name 与 substrate 依赖都用 `.jbroot` 相对形式（`@loader_path/.jbroot/usr/lib/…`）；构建后 `otool -L` 核对，必要时 `install_name_tool -change` 兜底。
- dylib 不签名不加载：`ldid -S`。

## 5. 装：只有一条路

- 把 deb 弄到本机：`icli probe` 里用 `NSData`/`NSURL` 下载并写文件（本机没有 curl/wget/python3）；`sha256sum` 只有 jbroot 那份可用，路径要加 `/rootfs` 前缀。
- 安装（须 root）：`irisin-cli install --yes --json /rootfs/var/mobile/Documents/<deb>`。**必须真根 `/rootfs` 前缀**，jbroot 拼写找不到文件。
- 不要用 `apt`/`dpkg`；不要拿 `irisin-cli` 去装 Apelin 自己构建出来的包（那是 `apelin_package_install` 的事）。

## 6. 验：顺序不能错

1. **先重启目标进程**：`icli app kill <bundle> --force` → `icli app launch <bundle>`。没重启 dylib 就没被映射，诊断也不会出现——**「装完看起来没生效」几乎总是这个原因**。
2. 读插件加载时写的诊断：`icli prefs read <目标域> <key>`（key 是位置参数，`--key` 会被拒）。第二通道是目标 App 自己容器里的 `Documents/<X>Diagnostics.txt`；第三是 os_log——统一日志在 iOS 上**没有历史**，`apelin_log_read` 只从调用那刻起听最多 10 秒。
3. 崩溃：`apelin_crash_list` → `apelin_crash_read`。本机没有本机构建，`apelin_crash_symbolicate` 用不上；靠报告里的镜像名 + 偏移 + 自己代码里的宏/函数名定位。
4. 界面：`apelin_screen_read_tree` / `capture` / `interact`。**Apelin 在前台时动作会被拒**（"UI actions may not reach wiki.qaq.apelin"），而用户切回 Apelin 看进度就会打断——所以界面验证要设计成一次做完，不要跨多轮；做不到的部分如实写「未测」。
5. 只读/禁用类行为的旁证：`icli input type` 打不进被禁用的文本视图（键盘不出现）——这本身就是"限制生效"的证据。

## 7. 钩子结构：一站一槽（Per-Site Original Slot）

这套命名用来描述这类修复，写文档、写提交信息时照用：

- **R1 一站一槽**：每个 (类, 选择器) 站点各有**自己的静态原 IMP 槽**和自己的包装函数；装钩时把原指针存进这一站，运行时**绝不按 `self` 的类去查一张总表**。
- **R2 声明者才挂**（Declared-Owner Install）：只在类**自己声明**了该方法时才挂站；继承来的不挂，`super` 链路自然落到被钩的父类。

违反 R1 的典型崩溃：`-[子类 setEditable:]` 里 `[super setEditable:]` 进到父类那一站的钩子，而 `self` 仍是子类实例，按 `self` 的类查总表又取回子类那份「原 IMP」→ 钩子→原IMP→super→钩子 无限递归，几帧撑爆栈。

自检方式：诊断里记 hooks 数与装了哪些类。因为 R2，站点数会**少于** `类数 × 方法数`，这是对的，不要当成缺钩。

## 8. 过滤器、隐根、面板

- 在 Apelin 工程里只写 `package.tweakFilter`，别自己 ship 一份 Filter plist；过滤器只列真正要注入的进程。
- 隐根：`@ROOTFS@` 是 `/rootfs`、`@PREFIX@` 为空、不存在 `/var/jb`、jbroot 名每次越狱都变，绝不写死；代码要打开 bootstrap 里的文件用 `ApelinBootstrapPath()`（头要从 apelin-bootstrap-paths 技能拷进 `Sources/`）。
- **jbroot 前缀每次重新越狱都会变 —— 本机常识，永久记住**（用户 2026-10-30 18:04 原话：
  「隐根越狱、每次重新越狱（jbroot 前缀换了）都会变！这个常识现在写进硬性规定、记忆和技能包和上传云端！
  免得你以后不知道！」；2026-10-30 21:34 再次强调「以后所有的对话和工程在工作时想要构建、修改、
  修复、编译插件的时候看看这个常识性的知识！」——**改代码、修 bug、编译出包之前都先想这条**）：
  - 引导根 = 容器 `/private/var/containers/Bundle/Application/.jbroot-<16 位十六进制>`。重新越狱
    （换引导 / 重装引导 / 重新引导）时**这个哈希会换**，整个引导根跟着改名搬家。
  - 跟着一起变的东西（都别记死）：Apelin 数据目录 `var/mobile/Documents/wiki.qaq.apelin`（在 jbroot 里）、
    工程真实路径、`$APELIN_PROJECT_ROOT`、`$APELIN_TOOLCHAIN_BIN`、`$SDKROOT`、注册的工具链与 SDK 路径、
    本机技能目录、`memories.json`。
  - 实测：2026-10-30 中午记忆里是 `.jbroot-E0BF8A83B883CBA6`，傍晚环境报 `.jbroot-BE7CF66DAF7343C6`
    —— 同一天就换过，**这不是可以背下来的值**。
  - 写法：代码 `jbroot()` / `ApelinBootstrapPath()`；plist 与维护脚本 `@PREFIX@` / `@ROOTFS@`；
    shell 用运行时变量（`$APELIN_PROJECT_ROOT`、`$HOME`、`$APELIN_TOOLCHAIN_BIN`、`$SDKROOT`）或相对路径；
    文档与记忆只写相对位置，不写解析结果。
  - 症状：写死过路径的地方，换前缀后会「文件明明在、命令说没有」「诊断读得到、插件找不到素材」
    「脚本 no such file」。**先查当前前缀**（`printenv APELIN_PROJECT_ROOT`、
    `icli fs ls /var/containers/Bundle/Application | grep jbroot`），改成变量重跑；
    别改代码逻辑、别重建文件。已装的包跟着引导根搬家，不用因为换前缀重装。
- 面板：「面板能开、开关能拨，但插件没反应」九成是三处不一致——specifier 里的 `defaults`、插件读的偏好域、Darwin 通知名必须是同一个包 id。默认值永远不写盘，关掉就是原行为。
- 偏好域写成目标 App 自己的 bundle id，`icli prefs read` 才读得到（沙箱里跨域写不进去）。

## 8.5 临时文件：一律写项目内，绝不写 /tmp

- 用户 2026-10-31 19:31 原话：「临时文件写不到 /tmp。用项目内的路径！」——**所有工程、所有对话永久适用**。
- 本机 `/tmp`、`/var/tmp` 在不少调用路径上（`icli probe` 的 JavaScriptCore、Apelin 宿主工具、别的命名空间里跑的脚本）写不进或写进去也读不回；排查时白白折腾。
- 写法：`TMPD="${APELIN_PROJECT_ROOT:?}/.tmp"; mkdir -p "$TMPD"`，用完删；`.tmp/` 已进 `.gitignore`。要长期留的产物放 `docs/`、`Attachments/`、`docs/cases/`。
- 脚本里出现 `/tmp` 就是 bug：`scripts/sync-all.sh`、`scripts/errand-in-app.sh`（截图）、`scripts/fleet-live.sh`（临时标记）已全部改到 `.tmp/`。CI 工作流（macOS runner）里的 `/tmp` 不受此限。

## 9. 故障速查

| 症状 | 先查 |
|---|---|
| 进程里完全没反应、无日志 | dylib 有没有 arm64 slice（`file`）、过滤器 bundle id、`Depends` 里有没有 `mobilesubstrate`、进程是否重启过 |
| 装不上：built for … not this bootstrap | 包是给别的引导构建的；本机要装 roothide 的包 |
| 装完崩溃 | `apelin_crash_list` → `apelin_crash_read`；先看是不是钩子结构违反 R1 |
| 开关/功能不生效 | 偏好域与通知名、目标进程是否重启、站点是否真装上（诊断里的 hooks 数） |
| 设置面板没有入口 | PreferenceLoader 入口路径、bundle 名、`preferenceloader` 依赖；重启 Settings |
| 构建报 environment 错误 | 本机预期永远 unavailable；去 CI，别在本机继续试 |
| 界面动作被拒 | Apelin 在前台；先把目标 App 调到前台，并且一次做完 |

## 10. 说法纪律

- 编译通过 ≠ 装机通过 ≠ 加载生效 ≠ 界面正确。本机能覆盖到「装了 + 进程里生效」，界面部分要么用屏幕工具走通，要么写明未测。
- 本文件里的实测数字只属于这台 A11 / 这次越狱；换设备、换引导要重新实测。
- 「本机直编」这类说法在本机一律是错的，不要出现在文档、技能或承诺里。
