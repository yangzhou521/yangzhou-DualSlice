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

## 9. 安全模式与崩溃循环自救（2026-10-31 实测事故，铁律）

**事故**：ThemeCorePlus 0.9.21 装到 SpringBoard 后，设备进安全模式，`consecutiveCrashCount: 5`。

**崩溃报告长这样**（`SpringBoard-2026-10-31-104430.ips`）：

```
bug_type 309 / EXC_BREAKPOINT / SIGTRAP / faultingThread 0（主线程）
procLaunch 10:44:25  captureTime 10:44:28   ← 启动 3 秒就死
栈：TCPInitialize → TCPLayoutInstall → TCPLayoutHookSave → CF_forwarding_prep_0
    → ___forwarding___ → ___forwarding___.cold.3
寄存器：OBJC_CLASS_$_ISOverlayEmbossedFolder + selector isSubclassOfClass:
consecutiveCrashCount 5 / throttleTimeout 5
```

**根因**：构造函数（dyld initializer）里 `objc_getClassList` 枚举**全进程所有类**，对每一个类发
`[c isSubclassOfClass:base]`；其中某个类不响应这条类方法 → 消息转发失败 → `SIGTRAP`。
构造函数里崩 = 每次启动都崩 = 连崩 5 次 = 安全模式。**`@try` 救不了这种 trap。**

**四条铁律（写任何注入 SpringBoard 的插件都照做）**：

1. **判类关系用 C 函数**：`class_getSuperclass()` 一路往上走，返回 `nil` 即到头。
   绝不对「从 `objc_getClassList` / `objc_copyClassList` 枚举出来的类」发 `isSubclassOfClass:`、
   `isKindOfClass:`、`respondsToSelector:` 这类消息 —— 来路不明就可能不响应。
2. **构造函数只做纯赋值**：枚举类、`MSHookMessageEx`、建窗口、碰 UIKit / `UIScreen mainScreen` 全部
   挪到启动后主队列的第一拍（延迟 ≥1 秒）。构造函数里崩会把用户送进安全模式。
3. **启动护栏文件**：跑重活前写 `<数据目录>/.xxx-launch-guard`，跑完 `unlink`；下次启动发现它还在
   ＝上次就死在这里 → **整段跳过**并在诊断里记 `safeskip=1`。宁可功能不生效，绝不连崩。
4. **挂站前验签名**：`method_getNumberOfArguments`（只挂 `== 2` 的零参数方法）、
   `method_getTypeEncoding` 核对；宁可一个都不挂。

**安全模式怎么认、怎么出**：

| 现象 | 含义 |
|---|---|
| 屏幕顶部「安全模式」 | SpringBoard 连崩被系统保护 |
| 所有插件同时失效 | 注入被整体禁用 |
| `device.sh read <域> <键>` **仍读得到旧值** | `defaults` 值会残留，**读到诊断 ≠ 插件在跑**，别被骗 |

出路：`irisin-cli show <包>` 核对当前版本 → 回滚到已知good版本（`irisin-cli install --yes --json
/rootfs/var/mobile/Documents/<good>.deb`，须 root）→ **用户点头** → `sh scripts/respring-guard.sh
--confirm 5 "注销"` → 复查 `apelin_crash_list process=SpringBoard` 不再新增即脱离。

**纪律**：一个版本只许一条线装一次；装前 `irisin-cli show` 核对、装后立刻查 crash list；
**出过崩溃的版本号永不复用**（0.9.21 已废，下一版从 0.9.22 起）。

**单线修复纪律**（用户 2026-10-31 10:56 原话「只准一个对话机器人着手修复安全模式！其它机器人立即停止⏹️工作！
同步通告全员！修复后第一时间通告全员后让他们继续工作！」）：

1. 进安全模式后**只留一条修复线**，它独占：改代码、触发云编译、装包、注销、回滚。
2. **其它对话立即停手**：不改相关源码、不 push、不建 CI run、不装包、不注销；只回一句「收到，已停手」。
   停手范围是**整个受影响的包**（ThemeCorePlus / CountdownHUD）及其装包与注销，不只是崩溃的那个文件。
3. 修复线自己验完（版本对、诊断对、`apelin_crash_list` 无新增）→ **第一时间广播「已修复，可以继续」**
   + 各自被冻结的那一步 → 才准复工。**没通告前谁都不许复工。**
4. 广播用 `apelin_conversation_send`，一次一条、三行以内：现状 / 谁是唯一修复线 / 其它人现在做什么。
5. **排查有结论就发一条、修复完成再发一条**，不许等修完才说（用户 2026-10-31 11:0x 原话
   「安全模式排查！修复早后都要第一时间通告全员知道！」）。
6. **一个 bug 只许一条线改**（用户原话「做到一个 bug 不要被全员反复修改回归耽误用户时间」）：改码权只属于
   `version-lock.txt` 的 owner；别的线有新线索只发消息，不动手；owner 一轮只出一个改动（改→push→编→装→验），
   禁止「装 A 不行又装 B」；出过崩溃的版本号永不复用。
7. **`tick` 有 60 秒写盘节流**：状态没变时诊断里的 `tick` 最多旧 60 秒，量「插件活没活」要隔 70 秒读两次；
   7 秒内两次不动不能判死（2026-10-31 11:03 差点误判）。
8. **事故解决后必须把三段分析发给全员**（用户 2026-10-31 11:1x「安全事故原因过程解决后的分析发给全员！」）：
   原因（直接原因/崩点/为什么升级成事故/根因归类）→ 过程（怎么发现、耽误在哪、哪一步判断错了）→
   解决与复盘（怎么救回来、以后怎么防、规矩落到哪个文件）。模板：`docs/cases/springboard-safemode-0.9.21.md`。
   **只修不写复盘 = 没修完。**
9. **根因没定位前不许注销、不许装新包**（用户 2026-10-31 11:16「在没有真正排查出安全事故的原因情况下不要让他们注销」）：
   注销是验证手段不是排查手段（会掩盖崩溃现场与旧诊断值）。顺序固定：**读 ips 定位 → 改码 → 云编译 → 装包 → 最后注销**；
   注销须用户当轮点头，排查期任何人不得自行发起注销。详见 `docs/cases/springboard-safemode-0.9.21.md`。

**防回滚三件套**（2026-10-31 落地并实测，防止「修复线刚回滚、别的线又装回坏版本」）：

| 文件 | 作用 |
| --- | --- |
| `scripts/version-lock.txt` | `owner`=唯一修复线 sid、`version`=唯一允许装在机上的版本、`dylib_sha256`、`deb_sha256`。只有 owner 改 |
| `scripts/deb-guard.sh` | 装包/注销唯一入口：非 owner **exit 6**，版本不符锁 **exit 7**；`check` 只读比对锁与机上实况 |
| `scripts/safemode-check.sh` | 一条命令体检（只读）：版本 / dylib 指纹 / 最近崩溃 / `ThemeCorePlusLayout` 的 tick 是否在涨 |

```sh
sh scripts/safemode-check.sh                      # 0 健康 1 连崩或安全模式 2 版本漂移 3 插件没在跑 9 读数缺失
sh scripts/deb-guard.sh check                     # 锁 vs 机上
GUARD_SID=<自己 sid> sh scripts/deb-guard.sh install <deb>   # 只有 owner 能过
GUARD_SID=<自己 sid> sh scripts/deb-guard.sh respring 5 注销   # 过了归属关，仍要用户点头 + --confirm
```

**在安全模式的硬证据**：最新 ips 的 `consecutiveCrashCount ≥ 5` ＋ SpringBoard 的 pid 自那次崩溃后没换过 ＋
`ThemeCorePlusLayout` 的 `tick` 不再增长（注入被 ellekit 关掉）。**读到诊断 ≠ 插件在跑**，诊断值是崩溃前的残留。
脱困 = 回滚到锁里的版本（已 good 就跳过）→ 用户点头 → 注销一次，SpringBoard 全新启动即恢复注入。

## 10. 故障速查

| 症状 | 先查 |
|---|---|
| 进程里完全没反应、无日志 | dylib 有没有 arm64 slice（`file`）、过滤器 bundle id、`Depends` 里有没有 `mobilesubstrate`、进程是否重启过 |
| 装不上：built for … not this bootstrap | 包是给别的引导构建的；本机要装 roothide 的包 |
| 装完崩溃 | `apelin_crash_list` → `apelin_crash_read`；先看是不是钩子结构违反 R1 |
| 开关/功能不生效 | 偏好域与通知名、目标进程是否重启、站点是否真装上（诊断里的 hooks 数） |
| 设置面板没有入口 | PreferenceLoader 入口路径、bundle 名、`preferenceloader` 依赖；重启 Settings |
| 构建报 environment 错误 | 本机预期永远 unavailable；去 CI，别在本机继续试 |
| 界面动作被拒 | Apelin 在前台；先把目标 App 调到前台，并且一次做完 |
| 进了安全模式 | 见第 9 节：读 crash 的 `consecutiveCrashCount` → 回滚 → 用户点头注销 → 复查不再新增 |

## 11. 说法纪律

- 编译通过 ≠ 装机通过 ≠ 加载生效 ≠ 界面正确。本机能覆盖到「装了 + 进程里生效」，界面部分要么用屏幕工具走通，要么写明未测。
- 本文件里的实测数字只属于这台 A11 / 这次越狱；换设备、换引导要重新实测。
- 「本机直编」这类说法在本机一律是错的，不要出现在文档、技能或承诺里。
