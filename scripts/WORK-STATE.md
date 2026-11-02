# 工作断点台账（WORK-STATE）

**规则：任何一轮开工，第一件事读这里；任何一轮结束，最后一件事件更新这里。**
用户不会回顾对话历史——断点只在这个文件里。每条只写：目标 / 做到哪 / 下一步 / 卡谁。

---

## 当前主线：ThemeCorePlus 图标主题化覆盖（调度台 = 3d91f924，本线）

- **目标**：图标主题化全覆盖 + 日历/文件夹修好 + 秒加载。
- **做到哪**（2026-11-02 15:35 复核）：
  - ✅ **1.0.38 云编译已绿**（提交 `9990eef5` + `320d6e47`；工作流「Build ThemeCorePlus」run **41407144542** = success；Release `themecoreplus-v1.0.38`，deb `com.yangzhou.themecoreplus_1.0.38_iphoneos-arm64e.deb` 169748B，sha256 `a41c16a9…`）。用户 15:31 明说**只编译不装包** → 未下载、未装、未注销。
  - ✅ **交付版 ThemeCore+ 5.2.0 云编译也已绿**（`fa7af10` → 工作流「Build YzThemeCorePlus」run **41406267743** = success）。
  - 1.0.38 编译失败的三处根因都已修：Icons.m 的 `static` 冲突、Store.m 缺声明、以及面板链接期 `Undefined symbols _TCPLiveIconImageCache`（定义搬进共享源码 Store.m）。
  - **本机现状变了**：用户已把 ThemeCorePlus **卸载**（dpkg 无条目、注入目录无 dylib），磁盘只剩 CountdownHUD（dpkg 1.6.8，未注销所以内存里还是 1.6.7）。之前读到的 `v1.0.37;icon{look=887,hit=779}` 是偏好陈旧残留。
  - **1.0.38 云编译失败根因已定位并修好**（run 41383241825 / 提交 5f1ac95，check-run「Build (roothide)」failure、annotations 为空＝编译错误）：① `ThemeCorePlusIcons.m:164` 把 `TCPLiveIconImageCache` 写成 `static`，与 `ThemeCorePlusHooks.h:269` 的外部声明冲突；② `ThemeCorePlusStore.m` 调它却无声明（新 clang 把隐式声明当错误）。修法：Icons.m 去掉 `static`、Store.m 加前向声明。
  - 1.0.38 的内容：开闸时先清系统图标缓存（SBIconController→iconManager→iconImageCache）再让视图重出图（治「秒加载」）；文件夹取图失败按 `noid`/`nopath` 分类记账。
  - **布局保存已打通**：`lay{rst=0,sav=1,tick=337,hooked=2,model=adopt:iconModel}`。
  - 安全模式已退出（1.0.36 修构造函数闸门；退出靠**完整关机重启**，sbreload/killall 杀不动 SpringBoard）。
  - **第二遍 probe 已读**（mtime 11:32）：段头与第一遍完全相同，**没有新增类**；`TCPIconServiceProbe.txt` 仍不存在（iconservicesagent 侧那路没通）。
- **下一步（用户 15:31 说停，等指示，不主动往下走）**：
  1. 用户点头才下载 `com.yangzhou.themecoreplus_1.0.38_iphoneos-arm64e.deb` 到 `/rootfs/var/mobile/Documents/`（**先下完再弹窗**问装不装）；
  2. 装机前先定身份：交付版 5.2.0 与自研线共用 `com.yangzhou.themecoreplus` → 先问「换 id 还是先卸旧版」；
  3. 装机后读 `ref{...purge=<方法名><次数>}`、`grid{…}`、`icon{look,hit}`，判秒加载那一步有没有真走到。
- **卡谁**：等用户指示（装包/注销才需点头）。

## 并行的第二件事：交付版 ThemeCore+ 5.2.0 移植（本线，2026-11-02 14:5x）

- **目标**：把用户交付的 Theos 工程 **ThemeCore+ 5.2.0**（纯 ObjC，作者 yangzhou）移植进本仓库，
  用**云编译的 clang 直编**（不走 Theos 构建规则），**只编不装**（用户原话「直接编译就行」）。
- **做到哪**：
  - ✅ **云编译已绿**（2026-11-02 15:35）：工作流「Build YzThemeCorePlus」run **41406267743**（`fa7af10`）= success（前两次 failure 的编译/链接错误均已修）。**只编不装，未装机。**
  - 交付件已落进 `YzThemeCorePlus/`（`Hooks/*.m` 5 个 + `Sources/*` 11 个 + `Prefs/*` 6 个 + README + tweak.json），
    `Support/YzThemeCorePlus.plist`（只注入 com.apple.springboard）与 `Support/YzThemeCorePlusPreferenceLoader.plist`
    （设置里那一行「ThemeCore+」）已就位；未引用的临时图标源文件已删。
  - `scripts/build-yzthemecoreplus.sh`：clang 直编 `YzThemeCorePlus.dylib`（arm64+arm64e，lipo）+ 面板 bundle
    `YzThemeCorePlusPrefs`；ldid 签名、substrate 依赖改相对路径、切片缺失即 fail、dpkg-deb 打包。
    `PACKAGE_ID=com.yangzhou.themecoreplus`（交付件 control 原值）、`VERSION=5.2.0`。
  - `.github/workflows/yzthemecoreplus.yml`：paths 过滤只认 `YzThemeCorePlus/**`、`Support/YzThemeCorePlus*.plist`、
    本脚本与自身；三处版本号（头文件/脚本/env）不一致就不编；报错压成一条 annotation；发 Release
    tag `yzthemecoreplus-v5.2.0`。
- **下一步**：push 到 main 触发云编译 → 读 check-run annotations（匿名可读）确认 success。
- **卡谁**：不卡。**装不装是另一件事** —— 交付件与自研那条线**共用包名 `com.yangzhou.themecoreplus`**，
  两者同时装会抢挂 SpringBoard 同名方法、共用偏好文件，装机前必须先跟用户定身份（换 id 或先卸旧的）。

## 别人在干的（不碰他的文件）

- **01db0a06（主线执行线）**：改 `ThemeCorePlusIcons.m`（日历墨层 `TCPCompositeCalendarInk`：保留星期红字、日期数字完整、底图明暗分别配色）+ `ThemeCorePlusFolders.m`（mini 文件夹，`foldernotify{n=0,last=nocache}` 拿不到 `SBFolderIconImageCache` 单例）。走云编译。

## 已冻结（不许动）

- 桌面图标主题化 + 角标（1.0.16 起冻结，用户 12:00 确认修好）。
- 时钟（用户 11-02 说「时钟不动」）。
- 生效叠加链保持 `[角标：透明玻璃, 液态玻璃.theme]` —— 用户 11-02 明令：**不要加别的主题覆盖自己补的素材**；420 个白图标 = 没补素材的 app，正常，不管。

## 悬置（用户点名才做）

- 长岛显示长文字（当前无此能力，文字长了只会缩字号）。
- 文件图标（UTI）覆盖、与 Mikkyy 并存、Spotlight/ShareSheet/QuickLook 进程覆盖。

## 规矩三样同步

`sh scripts/sync-all.sh` → `git_commit(all:true)` → `git_push`（AGENTS.md + skills/ + memory/）。
