# 专项案例：Sileo 搜索框点不进去 —— SileoWallpaper 死区修复（SileoFix 1.0.4）

> 装机实测：**2026-10-30 23:18 用户亲口确认「正常了 / bug 修复好了」**。
> 组件源码 `SileoFix/Sources/SileoFix.m`，合并进包 `com.sileowallpaper.tweak` 0.1.9。
> 下次 SileoWallpaper 或 Sileo 更新导致同类问题，**先读本文第 6 节 checklist**。

---

## 1. 一句话结论

SileoWallpaper 把「源内页 / 软件源页」的 `UINavigationBar` 设成了
`userInteractionEnabled = NO`，而「搜索软件包」搜索栏与左边的「所有分类」按钮**都挂在
这条导航栏上**，于是整片变成死区：点了没反应、键盘不弹、打不了字。
修法＝给 `UINavigationBar` 加一条 `hitTest:withEvent:` 旁路（点在导航栏自己的
`UISearchBar` / `UIControl` 上就接管，别处照旧穿透），由随包安装的 `SileoFix.dylib` 完成，
壁纸效果一行没动。

## 2. 症状与判定（先确认是这一案）

- 任意软件源详情页：「搜索软件包」输入框点不进去、键盘不弹、`icli input type` 也打不进。
- **同一个导航栏上的「所有分类」按钮同样点不动** —— 这片一起死。
- 同一时刻「已安装」等页的导航栏**可交互、点得动**。
- 不是键盘坏、不是触控坏、不是全局：只有特定页面、且是同一块区域整片失效。

出现上面三条同时成立，基本可以直接按本案处理。

## 3. 病灶是怎么钉死的（本案例最值钱的部分：分轮取证）

本案不是一眼看出来的，走了四轮；**这套方法可以直接套用到任何「点了没反应」的插件冲突**。

| 轮次 | 做了什么 | 得到什么 |
| --- | --- | --- |
| 1.0.1 | 猜「SileoWallpaper 的装饰盖板吃掉了触摸」，给输入控件做 hitTest 检查 | **先崩了**：`UITextField` 与 `UISearchBar` 的 `didMoveToWindow` 共用一个原 IMP 槽，第二站覆盖第一站，文本框移动窗口时执行 search bar 的实现 → 点底栏「软件包」即闪退 |
| 1.0.2 | 修崩溃：改成**一站一槽**；加落地日志 | 日志写 `/var/mobile/Library/Preferences` **被沙盒拒，一个字都没落下** → 改写到 App 沙盒 `NSCachesDirectory` |
| 1.0.3 | 只取证、不改行为。对搜索栏**中心点**做 hitTest | 命中的**就是 `UISearchBarTextField` 自己** → **否定「盖板吃触摸」假设**（命中后 return，等于没查）。于是补三处量：① 全部 `UIWindow`（lvl/hidden/alpha/key，壁纸可能自建独立窗口，主窗口 hitTest 看不见它）；② 搜索栏与文本框各自的 delegate、`canBecomeFirstResponder`、`editable`；③ 真实 `TouchBegan` 落在搜索栏区域内时的命中链 + 键盘窗口是否出现 |
| 1.0.4 | 读 1.0.3 的现场日志 | 日志里源内页与软件源页的 `UINavigationBar` 显示 `(noUI)`，而已安装页的导航栏可交互 —— **病灶钉死，改成因修复** |

**关键推论（容易反复踩）**：主窗口 `hitTest` 返回控件 **≠** 触摸一定送到。

- 父视图 `userInteractionEnabled = NO` 时，`hitTest` 在那一层就早退，返回 nil；
- 导航栏只有 44 高时，**溢出的搜索栏连 `pointInside` 都过不去**；
- 壁纸若自建独立 `UIWindow`（windowLevel 更高），主窗口的 hitTest 根本看不见它 ——
  所以「谁接到这一下」必须用真实触摸事件量，不能只算几何。

## 4. 修法（1.0.4）实现要点

1. **给 `UINavigationBar` 新增一站 `hitTest:withEvent:`**：`class_getInstanceMethod` 取它当前的 IMP
   当原实现（它没自己实现，取到的是 `UIView` 那份），再 `class_addMethod` 挂上自己的；
   失败才 `class_replaceMethod`。**绝不 `MSHookMessageEx` 到父类 `UIView`**（那会把全 App 的视图拖下水）。
2. 旁路逻辑：导航栏可交互且点在其 bounds 内 → **完全走系统原样**（「已安装」页就是这么点的）；
   否则在导航栏子树里找 `UISearchBar`（优先）与 `UIControl`，逐个 `pointInside:` + `hitTest:` 判真实归属，
   命中就接管返回该视图；**找不到返回 nil**（照旧穿透，壁纸与列表不受影响）。
3. **不改布局、不改 SileoWallpaper 设的状态**（不去把导航栏重新打开交互），只在命中层面让位。
4. 保留的兜底（不进主路径，但别删）：
   - `sendEvent:` 里对真实触摸做几何兜底（只处理「装饰盖板」：类名前缀 `SW` / 含 `Backdrop` /
     `UIVisualEffectView` / `_UIBackdropView`，命中则 `userInteractionEnabled = NO`，
     并在下一轮 main queue 里把焦点交给 `UITextField` 或触发 `UIControl`）；
   - `viewDidAppear` / `didMoveToWindow` 后重试 + 1.5 秒一次的 sweeper（共 40 次），对付异步布局。

## 5. 构建、发布、装机

- **一个包两个 dylib**（都注入 `org.coolstar.SileoStore`，见 `Support/SileoFix.plist`）：
  `SileoWallpaper.dylib`（`OriginalPlugin/` 里那份原二进制，**逐字节不改**，CI 用 sha256 核对）
  ＋ 现场编译的 `SileoFix.dylib`。
- 构建 `scripts/build-sileowallpaper.sh`（**只在 CI 的 macOS runner 上跑**，本机 A11 没有工具链）：
  roothide、`arm64 + arm64e` 双片、`lipo`、把 substrate 依赖改写成
  `@loader_path/.jbroot/usr/lib/libsubstrate.dylib`、`ldid -S` 签 SileoFix、
  原插件**不重签**（重签会改字节）、`dpkg-deb -b --root-owner-group`。
- 云编译工作流 `.github/workflows/sileowallpaper.yml`，触发路径：
  `OriginalPlugin/**`、`SileoFix/**`、`Support/SileoFix*`、`scripts/build-sileowallpaper.sh`、工作流自身；
  同一次运行发 Release `sileowallpaper-v<pkg 版本>`。
- **版本三处必须一起改**（工作流里有自检闸门，不一致直接红）：
  `SileoFix.m` 的 `#define SW_VERSION`、build 脚本的 `FIX_VERSION`、包 `VERSION` ↔ workflow 的 `tag_name`。
- 装机（须 root，真根前缀）：`irisin-cli install --yes --json /rootfs/var/mobile/Documents/<deb>`
- 生效：**注入型插件不用注销桌面** —— `icli app kill org.coolstar.SileoStore --force`
  → `icli app launch org.coolstar.SileoStore`。

## 6. 插件更新后再出问题时：最快处理流程

1. **先判症状**：源内页搜索框 + 左按钮一起点不动、已安装页正常 → 大概率同因，按 2→5 步走。
2. **读现场日志**（Sileo 沙盒 `Caches/sileofix.log`，每次加载清空，首行 `loaded v…`）：
   - 首行版本对不对？不对说明包没装上 / 没重启目标进程。
   - 点一下搜索框，看有没有 `navHitTest 接管 <nav …> -> UISearchBarTextField<…> at <x,y>`。
     - **没有接管行** → 旁路没被走到：Sileo 换了导航栏类名/层级，或死区不在导航栏（走第 3 步重新定位）。
     - **有接管行但键盘仍不出** → 看 `becomeFirstResponder … -> 1/0 first=` ：
       `-> 0` 是被 delegate 的 `textFieldShouldBeginEditing` 之类拦了；**压根没有这一行**说明触摸仍没到文本框。
3. **重新定位（复用 1.0.3 的三处量，别凭猜）**：全部窗口一览 → 搜索栏/文本框的 delegate 与
   `canBecomeFirstResponder` → 真实 `TouchBegan` 命中链。日志里 `(noUI)` 标记就是「谁被禁了交互」的直证。
4. **SileoWallpaper 本体更新时**：若它换了盖板类名前缀（不再 `SW*` 或不再用 `UIVisualEffectView`），
   更新 `SWIsDecorative()`；若它不再关导航栏交互，**旁路留着无害**（可交互时走原路）。
5. 改完 → 版本三处同改 → push `main` → 等 CI 绿 → 装机 → kill + launch → 读日志确认，再让用户点一次。

## 7. 坑清单（血泪换来的）

- **一站一槽**：每个 hook 站一个独立的静态原 IMP。共槽会把 Sileo 打崩（v1.0.1 的事故）。
- 日志**必须写 App 沙盒**（`NSCachesDirectory`）；Sileo 无权写 `/var/mobile/Library/Preferences`。
- `os_log` 用**默认级别**（不是 `os_log_info`），否则默认不进统一日志，诊断会瞎。
- 只处理「装饰盖板」类视图；把 Sileo 自己的视图禁掉会把 App 弄坏。
- build 脚本里变量后紧跟全角「（」会被 runner 的 shell 当成变量名的一部分，
  `set -u` 报 `VERSION: unbound variable` → 写成 `${VERSION}`。
- shell 读日志/写请求时**别乱加 `/rootfs` 前缀**：那会读到真实数据卷的另一处，看到的是旧文件。
- roothide 隐根前缀每次重新越狱都可能变：文档、脚本、代码里**只写相对位置或用运行时变量**。

## 8. 文件地图

| 路径 | 是什么 |
| --- | --- |
| `SileoFix/Sources/SileoFix.m` | 修复本体（含 1.0.1→1.0.4 的逐版说明与诊断日志） |
| `Support/SileoFix.plist` | 注入过滤器（`org.coolstar.SileoStore`） |
| `OriginalPlugin/SileoWallpaper.{dylib,plist}` | 原壁纸插件本体，逐字节不改 |
| `scripts/build-sileowallpaper.sh` | 云编译脚本（roothide 双片 + 合并包） |
| `.github/workflows/sileowallpaper.yml` | CI：版本自检 + 构建 + Release |
| `scripts/errand-sileo-search-test.sh` | 外出取证脚本（trap 保回 Apelin） |
