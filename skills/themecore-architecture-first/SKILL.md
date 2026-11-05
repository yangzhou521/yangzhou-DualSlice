---
name: themecore-architecture-first
description: 做 ThemeCore 系（AppIcon 等）越狱主题插件的第一性原则：分析 bug、修复 bug、写结论全流程都要对齐 ThemeCore 0.5.1，不许自己天马行空加机制；含它的二进制实证清单（构造函数、配置键、dispatch、惰性枚举、过滤器、依赖、挂站类、生成入口）、被否掉的自我发明清单、三家竞品对比、od+awk 抽符号方法。任何改码前先读。
---

# 第一性原则：分析/修复 bug 全流程对齐 ThemeCore 0.5.1

用户 2026-11-06 00:03 / 00:30 定，**不许打破**。
原话：「ThemeCore 它没有什么明显 bug 就完全抄它的！和它架构一致！这是第一性原则你不要打破！」
「每次修复 bug 之前和分析 bug、修复 bug 时要严格对齐 ThemeCore！」

## 判断规则（bug 全流程，不只在写码时）

**ThemeCore 0.5.1 是不是这么做的？**
- 是 → 照抄，别多加动作。
- 不是 → 先别加。先查它到底怎么做（`od -c|awk` 抽符号）；查不到就先不动，**不许自己发明「保险」**。
- 只有它完全没有的功能（角标、阴影、文件夹、控制中心），才允许参考别的实现，并在注释里写明依据。

**三个环节各自怎么对齐**：
- **分析 bug 时**：先查 ThemeCore 有没有同样的东西（符号表、配置键、挂站类/选择器）。
  血泪例：`Enabled` 开关 —— 我一度以为它没有、删掉了，查符号表发现它有
  `_TCConfigurationEnabledKey` / `_TCReadConfiguration` / `isEnabled` / `setEnabled:`，于是加回。
- **修复 bug 时**：每改一处先问「这是 ThemeCore 的做法，还是我发明的？」
  修好一处再动下一处，**绝不带着「顺手优化」一起改**（一次只改一个变量）。
- **写结论时**：凡「ThemeCore 没有、我新加的」单独列出来给用户，不许混在修复里蒙混过关。

## 已被否掉的「自我发明」（别加回来）

| 我加的 | 为什么被否 |
|---|---|
| 0.6 秒延迟 `dispatch_after` | ThemeCore 的 dispatch 符号里**没有** `dispatch_after` / `dispatch_time` |
| `TCXStoreReady` 预热闸门 | 它没有 Ready 标记；线程安全靠 `dispatch_once` + `os_unfair_lock` |
| 挂站丢主队列 / 后台队列 | 它的 dispatch 符号（queue_create/qos_class/get_global_queue）是**内存压力 source 用的**，不是挂站用的 —— 别拿这个给自己加戏 |

## ThemeCore 0.5.1 架构（二进制实证）

**构造函数**：`TCIconServicesIsCurrentProcess()` 判断进程 → `TCReadConfiguration()` 读配置（含 `Enabled`）
→ `TCIconServicesInstallHooks()`（生图层）→ `TCIconShadowInstallHooks()`（阴影层）。

**配置键**：`_TCConfigurationActiveThemeKey` / `_TCConfigurationEnabledKey` /
`_TCConfigurationEnabledThemesKey`；`isEnabled` / `setEnabled:` / `isStoreEnabled` / `storeEnabled`。

**dispatch 符号**：`dispatch_async` / `dispatch_queue_create` /
`dispatch_queue_attr_make_with_qos_class` / `dispatch_get_global_queue` / `__dispatch_main_q` /
`dispatch_once` / `dispatch_source_*`（内存压力）/ `dispatch_resume`。
**没有 `dispatch_after` / `dispatch_time`**。

**文件与图片**：目录枚举 `enumeratorAtPath:`（惰性）；解码 `CGImageSource` + `kCGImageSourceShouldCache`。

**过滤器**：`Bundles: com.apple.UIKit` + `Mode: Any` + `Executables: iconservicesagent / ShareUI / sharingd`
—— **没有 SpringBoard**。

**依赖**：`mobilesubstrate (>= 0.9.5000), preferenceloader, firmware (>= 15.0)`
+ `Pre-Depends: rootless-compat (>= 0.9)`。

**挂站类**：`SBIcon` / `SBLeafIcon` / `SBApplicationIcon` / `SBHIconImageCache` /
`SBFolderIconImageCache` / `SBFolderIconImageSharedCache` / `SBHCalendarApplicationIcon` /
`SBCalendarApplicationIcon` / `SBHClockApplicationIconImageView` / `SBClockApplicationIconImageView` /
`SBWidgetIcon` / `SBHLibraryPodCategoryIcon` / `SBHLibraryAdditionalItemsIndicatorIcon` /
`ISBundleIdentifierIcon` / `TCIconServicesImageBox` / `SBIconView` / `SBIconImageView` /
`SBFolderIconView` / `SBFolderIconImageView` / `SBDockIconListView` / `SBIconListView` /
`SBRootFolderView` / `SBIconController` / `SBDisplayItem` / `SBHIconTableViewCell`。

**挂站选择器**：`iconImageWithInfo:` / `unmaskedIconImageWithInfo:` / `generateIconImageWithInfo:` /
`genericIconImageWithInfo:` / `generateIconImage:`（无参，首选）/ `getUnmaskedIconImage:` /
`realImageForIcon:` / `cachedImageForIcon:` / `imageForIcon:` / `appIconForBundleIdentifier:` /
`iconForBundleIdentifier:` / `generateImageReturningRecordIdentifiers:` / `makeImageSetForMetrics:` /
`imageSetForMetrics:` / `clearCachedImages` / `purgeCachedImages` /
`enumerateDisplayedIconViewsUsingBlock:` / `contentsImage` / `setClockPaths:` / `setModern:` /
`setHourMinuteDot:` / `setHours:` / `setMinutes:` / `setSeconds:`。

**时钟**：素材 `ClockIconBackgroundSquare` / `ClockIconHourHand` / `ClockIconMinuteHand` /
`ClockIconSecondHand` / `ClockIconBlackDot` / `ClockIconRedDot`；表盘与指针拆成子视图分别替换。

**日历**：`Info.plist` 的 `CalendarIconDateSettings` / `CalendarIconDaySettings`，字段
`FontName` / `FontSize` / `FontWeight` / `TextColor` / `TextXoffset` / `TextYoffset`，日期格式 `EEEE`。

## 三家竞品对比

**秒加载统一答案 = 图标图缓存层**（都挂 `SBHIconImageCache`）。
**MarkTheme16**：模块化快照（每类素材一个 SnapshotModule）+ 预生成 ImageSet + 换图用
`updateImageContentsWithImage:imageAppearance:isRealContentsImage:animated:`（无闪烁）。
**SnowBoard**：Base.dylib 包装（先查主题表、没有就调 orig），角标用 `SBBadgeBG`。

## 怎么从 dylib 抽这些信息（本机 strings / otool 都不可用）

```sh
F=<dylib路径>
od -c "$F" | awk '{for(i=2;i<=NF;i++){if($i ~ /^\\0/){if(s!=""){print s; s=""}else{next}} else {c=$i; gsub(/^[0-9]+$/,"",c); s=s c}}}' | sort -u
```
再 `grep -aE` 过滤类名（`^SB` / `^IS` / `^TC`）、选择器（`^[a-z][A-Za-z0-9]*:$`）、`dispatch`、
`enumerator`、`CGImageSource`、`Configuration`。包体 `dpkg-deb -x` 解到 `.tmp/`。

## 只有 ThemeCore 没有的功能才参考别人
角标、阴影、文件夹、控制中心 ThemeCore 0.5.1 都没有。iOS 16 角标底板不是图
（`_backgroundView` 是 systemRed + 圆角），底板走 `layoutSubviews`、文字走
`+_checkoutImageForText:font:highlighted:` —— 这条来自第三方 ThemeCorePlus 实测，不是 ThemeCore。

## 沉淀时并入、不新建（用户 2026-11-06 00:04）
同类内容一律并入已有条目：记忆进「硬规矩总则」，技能补进本技能，AGENTS.md 并进「🔴 第一性原则」。
不要新开重复条目。记忆满 64 条先压缩过时记录。
