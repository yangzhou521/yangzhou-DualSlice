---
name: themecore-architecture-first
description: 做 ThemeCore 系（AppIcon 等）越狱主题插件时的第一性原则：架构与 ThemeCore 0.5.1 完全一致，不许自己天马行空加机制；含它的二进制实证清单（构造函数、dispatch、惰性枚举、过滤器、依赖、挂站类、生成入口）、被否掉的自我发明清单、三家竞品（ThemeCore / SnowBoard / MarkTheme16）架构对比与可借鉴点、以及怎么用 od+awk 从 dylib 抽类名选择器。任何改码前先读。
---

# 第一性原则：与 ThemeCore 0.5.1 架构完全一致

用户 2026-11-06 00:03：「ThemeCore 它没有什么明显 bug 就完全抄它的！和它架构一致！
这是第一性原则你不要打破！」「不要你自己天马行空乱写！」
合并自原 `theme-engine-architecture-comparison`。

## 判断规则（每次动手前先问）

**ThemeCore 0.5.1 是不是这么做的？**
- 是 → 照抄，一个动作都别自己加。
- 不是 → 先别加。先查它到底怎么做；查不到就先不动，**不许自己发明一个「保险」**。
- 只有它完全没有的功能（角标、阴影、文件夹、控制中心），才允许参考别的实现，并在注释里写明依据。

## 已被否掉的「自我发明」（别加回来）

| 我加的 | 为什么被否 |
|---|---|
| 0.6 秒延迟 `dispatch_after` | ThemeCore 的 dispatch 符号里**没有** `dispatch_after` / `dispatch_time` |
| `TCXStoreReady` 预热闸门 | 它没有 Ready 标记；线程安全靠 `dispatch_once` + `os_unfair_lock` |
| 挂站丢主队列 | 它用 `dispatch_async` + `QOS_CLASS_UTILITY` 串行队列 |

## ThemeCore 0.5.1 架构（二进制实证）

**构造函数**只做两件事，前面套进程判断：
```
TCIconServicesIsCurrentProcess()
  → TCIconServicesInstallHooks()   // 生图层
  → TCIconShadowInstallHooks()     // 阴影层
```

**dispatch**（全部）：`dispatch_async` / `dispatch_queue_create` /
`dispatch_queue_attr_make_with_qos_class` / `dispatch_get_global_queue` /
`__dispatch_main_q` / `dispatch_once` / `dispatch_source_*`（内存压力）/ `dispatch_resume`。
**没有 `dispatch_after` / `dispatch_time`。**

**文件与图片**：目录枚举 `enumeratorAtPath:`（惰性），不用 `contentsOfDirectoryAtPath:`；
解码 `CGImageSource` + `kCGImageSourceShouldCache`（惰性解码）。

**过滤器**：`Bundles: com.apple.UIKit` + `Mode: Any` + `Executables: iconservicesagent / ShareUI / sharingd`
—— **没有 SpringBoard**，靠 `com.apple.UIKit` 进桌面。别改成进程白名单。

**依赖**：`mobilesubstrate (>= 0.9.5000), preferenceloader, firmware (>= 15.0)`
+ `Pre-Depends: rootless-compat (>= 0.9)`

**偏好与通知**：域 `com.susudear.themecore`，键 `ActiveTheme` / `EnabledThemes`（复数），
通知 `com.susudear.themecore.reload` 与 `com.susudear.themecore/reload`（两种都发）。

**主题根**：`/Library/ThemeCore`；素材目录认 `AnemoneEffects` / `Effects` / `Iconomatic`。

**挂站类**：`SBIcon` / `SBLeafIcon` / `SBApplicationIcon` /
`SBHIconImageCache` / `SBFolderIconImageCache` / `SBFolderIconImageSharedCache` /
`SBHCalendarApplicationIcon` / `SBCalendarApplicationIcon` /
`SBHClockApplicationIconImageView` / `SBClockApplicationIconImageView` /
`SBWidgetIcon` / `SBHLibraryPodCategoryIcon` / `SBHLibraryAdditionalItemsIndicatorIcon` /
`ISBundleIdentifierIcon` / `TCIconServicesImageBox` /
`SBIconView` / `SBIconImageView` / `SBFolderIconView` / `SBFolderIconImageView` /
`SBDockIconListView` / `SBIconListView` / `SBRootFolderView` / `SBIconController` /
`SBDisplayItem` / `SBHIconTableViewCell`

**挂站选择器**：`iconImageWithInfo:` / `unmaskedIconImageWithInfo:` /
`generateIconImageWithInfo:` / `genericIconImageWithInfo:` / `generateIconImage:`（无参，**首选**） /
`getUnmaskedIconImage:` / `realImageForIcon:` / `cachedImageForIcon:` / `imageForIcon:` /
`appIconForBundleIdentifier:` / `iconForBundleIdentifier:` /
`generateImageReturningRecordIdentifiers:` / `makeImageSetForMetrics:` / `imageSetForMetrics:` /
`clearCachedImages` / `purgeCachedImages` / `enumerateDisplayedIconViewsUsingBlock:` /
`contentsImage` / `setClockPaths:` / `setModern:` / `setHourMinuteDot:` / `setHours:` /
`setMinutes:` / `setSeconds:`

**时钟**：素材名 `ClockIconBackgroundSquare` / `ClockIconHourHand` / `ClockIconMinuteHand` /
`ClockIconSecondHand` / `ClockIconBlackDot` / `ClockIconRedDot`；
表盘与指针**拆成子视图分别替换**，指针仍由系统驱动（时间保持活的）。

**日历**：`Info.plist` 的 `CalendarIconDateSettings` / `CalendarIconDaySettings`，
字段 `FontName` / `FontSize` / `FontWeight` / `TextColor` / `TextXoffset` / `TextYoffset`，
日期格式 `EEEE`。权重用 `UIFontWeightRegular/Bold/Black/Heavy/Light/Medium`。

## 三家竞品对比（2026-11-01 二进制取证）

**① 秒加载的统一答案 = 图标图缓存层。** 三家全挂 `SBHIconImageCache`：
MarkTheme16 用 `iconImageWithInfo:traitCollection:options:`，ThemeCore 用
`iconImageWithInfo:` / `generateIconImageWithInfo:`，SnowBoard 用 `iconImageForIcon:orig:` 包装。
图在**缓存层被替换** → 视图建出来第一次从缓存拿就是主题图 → 零延迟零强刷。

**② MarkTheme16 独有的构造（最强，可借鉴）**：
- 模块化快照架构：每类素材一个 SnapshotModule（IconMask / Overlay / Shadow / Clock / Calendar /
  Badge / Folder / Static / UIResource / StatusBar / Dialer），各带 Contract/Configuration/Resolver/Reload
- **预生成 ImageSet**：主题应用时合成为成品图集就地安装，运行时零合成成本
- 时钟指针图集 `SBHClockHandsImageSet` + reloadHandler
- 换图用 `updateImageContentsWithImage:imageAppearance:isRealContentsImage:animated:`（无闪烁）
- 素材走 `/var/mobile/Library/Application Support/MarkTheme/`，主题由管理器 App 推进来

**③ SnowBoard**：Base.dylib 做公共包装（先查主题表、没有就调 orig），素材读 `/Library/Themes`，
角标用 `SBBadgeBG`，刷新用 `reloadIconImage` / `reloadIcons`。

## 怎么从 dylib 抽这些信息（本机 strings / otool 都不可用）

```sh
F=<dylib路径>
od -c "$F" | awk '{for(i=2;i<=NF;i++){if($i ~ /^\\0/){if(s!=""){print s; s=""}else{next}} else {c=$i; gsub(/^[0-9]+$/,"",c); s=s c}}}' | sort -u
```
再 `grep -aE` 过滤类名（`^SB` / `^IS` / `^TC`）、选择器（`^[a-z][A-Za-z0-9]*:$`）、
`dispatch`、`enumerator`、`CGImageSource`。包体用 `dpkg-deb -x` 解到 `.tmp/` 分析。

## 只有 ThemeCore 没有的功能才参考别人
角标、阴影、文件夹、控制中心 ThemeCore 0.5.1 都没有，可以看第三方实现但要写明依据。
例：iOS 16 角标底板不是图（`_backgroundView` 是 systemRed + 圆角），底板走 `layoutSubviews`、
文字走 `+_checkoutImageForText:font:highlighted:` —— 来自第三方 ThemeCorePlus 在本机的实证。

## 沉淀时并入、不新建（用户 2026-11-06 00:04）
同类内容一律**并入已有条目**：记忆进「硬规矩总则」，技能补进本技能，AGENTS.md 并进「🔴 第一性原则」。
不要新开重复条目。记忆满 64 条时先压缩过时记录腾位置。
