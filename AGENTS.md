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
icli respring            # 或让 Apelin 的 respring 工具来
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

## 硬规矩

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

- 两个产品都只走过云编译，**本机尚未装机验证过**；本文档随每次验证更新。
- 未做（阶段二）：管理器 App（导入/解包 .deb、预编译不可变成品、revision 切换与回滚）、
  作者素材 `图标蒙板AnemoneEffects.zip`、只有 `IconBundles/icon.png` 的角标主题。

## 外出取证：去别的 App，必须回到 Apelin

用户在聊天里看不到屏幕：进设置（或任何别的 App）取证时，屏幕离开 Apelin 就是黑箱，所以单次
外出**有时限、且收尾必定回到 Apelin**。用户 2026-10-30 明确要求「不要再让我手动回来」：
他自己切回来会打断「设置屏上的面板是否正常」的现场判断，也不方便他随时回来看我们干活。规矩：

- 默认上限 **60 秒**（实测一次完整往返 14 秒），汇报里写清这次外出了多少秒。
- 不需要看屏幕的长步骤（云编译、下载、装包）**不占屏幕**，屏幕留在 Apelin，
  只有真要动屏幕的那十几秒才外出。
- 不要停在设置里汇报，也不要把验证推回给用户。

机制：`sh scripts/errand-in-app.sh <bundle-id> [秒] [要点的元素文字]` —— **一次调用就把证据带回来**：
进目标 App → `icli ui tap "<文字>"` 按 label 点元素 → 截图 → `icli ui tree` 界面元素树 → 回程。
回程写在 `trap EXIT/INT/TERM` 里（报错、超时、Ctrl-C 都会回），末尾用 `icli app frontmost` 校验并打印
`回到 Apelin: <前景 bundle-id>（外出 N 秒）`。本机实测（2026-10-30）：完整往返 14 秒，
回程后前台 = `wiki.qaq.apelin`。

读界面结构：`icli ui tree [--human] [--clickable-only]`（本机 `icli screen describe` /
`icli screen ocr` 恒返回 `screen capture failed`）；Apelin 的 `apelin_screen_read_tree` 只在
前台就是目标 App 时才有意义。`icli screen shot` 可用，要给用户看时 `cp` 进工程再 `file_show`。
点元素别用坐标（`icli screen tap x y` 在列表里跑偏过），用 `icli ui tap "<文字>"`。

