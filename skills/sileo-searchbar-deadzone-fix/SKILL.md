---
name: sileo-searchbar-deadzone-fix
description: 当 Sileo 的搜索框/按钮「点了没反应、键盘不弹」，或任何 iOS 插件冲突造成局部触摸死区、点击无响应时使用。含分轮取证法、hitTest 旁路修法、一站一槽铁律与复发处理流程。
---

# Sileo 搜索框死区 / 插件冲突致「点了没反应」的定位与修复

案件：SileoWallpaper 把源内页 `UINavigationBar` 设 `userInteractionEnabled=NO`，搜索框与「所有分类」整片失效。
修复本体 `SileoFix/Sources/SileoFix.m`（v1.0.4），合并包 `com.sileowallpaper.tweak` 0.1.9，2026-10-30 装机实测通过。
完整案例文档：仓库 `docs/cases/sileowallpaper-searchbar-fix.md`（入口 `SileoFix/README.md`）。

## 一、判定是不是这一案
同时成立三条才按本案处理：
1. 源内页/软件源页「搜索软件包」点不进去、键盘不弹。
2. 同一导航栏上的「所有分类」也点不动（同一片一起死）。
3. 同一时刻「已安装」页导航栏可交互、点得动。

## 二、分轮取证法（可套用任何点击无响应）
- **1.0.1 定位**：先别改行为，给目标控件做 hitTest 检查。
  ⚠️ `UITextField` 与 `UISearchBar` 的 `didMoveToWindow` **共用原 IMP 槽会互相覆盖** → 点底栏就闪退。
  → 铁律：**一站一槽**，每个 hook 站一个独立静态原 IMP。
- **1.0.2 落地日志**：写 `/var/mobile/Library/Preferences` **被沙盒拒**，一个字都不落。
  → 日志必须写 App 沙盒 `NSCachesDirectory`；`os_log` 用**默认级别**（不是 `os_log_info`）。
- **1.0.3 三处量**：① 全部 `UIWindow`（lvl/hidden/alpha/key，壁纸可能自建高 level 窗口）；② 控件 delegate + `canBecomeFirstResponder` + `editable`；③ 真实 `TouchBegan` 落在目标区域的命中链 + 键盘窗口是否出现。
- **1.0.4 读日志**：出现 `(noUI)` 标记 = 谁被禁了交互，直接坐实病灶。

**关键推论**：主窗口 `hitTest` 返回控件 **≠** 触摸一定送到。父视图 `userInteractionEnabled=NO` 会在那层早退；导航栏只有 44 高时溢出的搜索栏连 `pointInside` 都过不去；壁纸自建独立窗口时主窗口根本看不见它。「谁接到这一下」只能用真实触摸事件量。

## 三、修法（hitTest 旁路）
1. `class_getInstanceMethod` 取 `UINavigationBar` 当前 IMP 当原实现（它没自己实现 → 取到 `UIView` 那份），`class_addMethod` 挂自己的；失败才 `class_replaceMethod`。
   **绝不 MSHook 父类 `UIView`** —— 会把全 App 视图拖下水。
2. 旁路：导航栏可交互且点在 bounds 内 → 完全走系统原样；否则在导航栏子树找 `UISearchBar`（优先）/`UIControl`，逐个 `pointInside:`+`hitTest:` 判归属，命中就接管；**找不到返回 nil**（照旧穿透）。
3. 不改布局、不改原插件设的状态，只在命中层面让位。
4. 兜底（保留但别删）：`sendEvent:` 几何兜底只处理装饰盖板（类名 `SW*`/`Backdrop`/`UIVisualEffectView`/`_UIBackdropView`）；`viewDidAppear`/`didMoveToWindow` 后重试 + 1.5 秒一次 sweeper 40 次。

## 四、复发处理（插件更新后再坏）
1. 读 Sileo 沙盒 `Caches/sileofix.log`（每次加载清空，首行 `loaded v…`）：版本对不对。
2. 点一下搜索框：有没有 `navHitTest 接管 <nav …> -> UISearchBarTextField<…> at <x,y>`。
   - 没有接管行 → 旁路没走到（Sileo 换了导航栏类名/层级，或死区不在导航栏）→ 重做三处量。
   - 有接管行但键盘不出 → 看 `becomeFirstResponder … -> 1/0 first=`；`-> 0` = 被 delegate 拦；压根没这行 = 触摸仍没到文本框。
3. SileoWallpaper 本体更新：换盖板类名前缀就改 `SWIsDecorative()`；它不再关导航栏交互则旁路留着无害。
4. 改完 → 版本三处同改 → push main → CI 绿 → 装机 → kill+launch → 读日志 → 让用户点一次。

## 五、构建发布装机
- 一包两 dylib，都注入 `org.coolstar.SileoStore`（`Support/SileoFix.plist`）：原 `SileoWallpaper.dylib` **逐字节不改**（CI 有 sha256 闸门，重签会改字节）＋ 现场编译的 `SileoFix.dylib`。
- 构建 `scripts/build-sileowallpaper.sh`（**只在 CI macOS runner 跑**，本机 A11 无工具链）：roothide、arm64+arm64e 双片、lipo、substrate 依赖改写成 `@loader_path/.jbroot/usr/lib/libsubstrate.dylib`、`ldid -S` 只签 SileoFix、`dpkg-deb -b --root-owner-group`。
- 工作流 `.github/workflows/sileowallpaper.yml`，发 Release `sileowallpaper-v<pkg 版本>`。
- **版本三处必须一起改**：`SileoFix.m` 的 `#define SW_VERSION`、脚本 `FIX_VERSION`、包 `VERSION` ↔ workflow `tag_name`（有自检闸门）。
- 装机（须 root，真根前缀）：`irisin-cli install --yes --json /rootfs/var/mobile/Documents/<deb>`
- 生效：**注入型插件不必注销桌面** —— `icli app kill org.coolstar.SileoStore --force` → `icli app launch org.coolstar.SileoStore`。

## 六、坑清单
- 一站一槽（v1.0.1 共槽把 Sileo 打崩）。
- 日志写 App 沙盒 `NSCachesDirectory`，别写 `/var/mobile/Library/Preferences`。
- `os_log` 用默认级别。
- 只禁「装饰盖板」类视图，禁掉 Sileo 自己的视图会把 App 弄坏。
- build 脚本变量后紧跟全角「（」→ 写成 `${VERSION}`，否则 `set -u` 报 unbound variable。
- shell 读日志别乱加 `/rootfs` 前缀，会读到旧文件。
- roothide 隐根前缀每次重新越狱会变：文档/脚本/代码只写相对位置或运行时变量。
- 装机后**必须重启目标进程**（kill+launch）才注入生效，读日志版本确认。
