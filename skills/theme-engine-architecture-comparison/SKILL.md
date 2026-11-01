---
name: theme-engine-architecture-comparison
description: 越狱主题引擎（MarkTheme16/ThemeCore/SnowBoard）与 ThemeCorePlus 的架构对比与可借鉴点：挂载层级、秒加载机制、刷新机制、模块化构造。做主题插件架构优化、分析竞品、或决定挂哪一层时读。
---

# 主题引擎架构对比（iOS 16.7 / roothide 实测取证，2026-11-01）

对三个已装主题引擎的 dylib 二进制符号取证（grep -a 提取类名/选择器/路径），与 ThemeCorePlus 对比的结论。

## ① 秒加载的统一答案：图标图缓存层

三家全挂在 **SBHIconImageCache**（图标图缓存）：
- MarkTheme16：36 处引用，`iconImageWithInfo:traitCollection:options:`
- ThemeCore 0.5.1：`iconImageWithInfo:` / `generateIconImageWithInfo:` / `contentsImage`
- SnowBoard：Base 层 `iconImageForIcon:orig:` 包装 + `IconImageForBundleIdentifier`

图标图在**缓存层被替换** → 视图建出来第一次从缓存拿图就是主题图 → 零延迟、零强刷。
ThemeCorePlus 原来漏了这层（icon 站 excluding 里的 "Cache" 把缓存类挡了）→ 桌面先显示
缓存预热好的系统原图、等强刷才换（「进桌面先原生几秒」的根因）。1.0.22 起补挂：
`TCPInstallInstanceSitesForClassPrefixes(@[@"SBHIconImageCache"], @[], @[iconImageWithInfo:, unmaskedIconImageWithInfo:], TCPSiteKindIconImageInfo)`。

## ② MarkTheme16 独有的构造（最强，值得抄）

1. **模块化快照架构**：每类素材一个 SnapshotModule——MTIconMask / MTIconOverlay / MTIconShadow /
   MTIconAppearanceSnapshot / MTClockIconSnapshot / MTCalendarIconComposite / MTBadgeSnapshot /
   MTFolderIconSnapshot / MTStaticIconSnapshot / MTUIResourceSnapshot / MTStatusBar / MTDialer。
   每个 Module 自带 Contract（配置契约）、Configuration、Resolver、Reload handler。
2. **预生成 ImageSet**：514 处 ImageSet 引用、ImageSetAttemptInstallation——素材在主题应用时就
   合成为成品图集并就地安装，运行时零合成成本（我们每次现合成 + NSCache 兜底）。
3. **时钟指针图集**：SBHClockHandsImageSet 独立指针集 + reloadHandler——指针跟系统换图节奏走。
4. **换图用 iOS 16 正式 API**：`updateImageContentsWithImage:imageAppearance:isRealContentsImage:animated:`
   （带外观参数、无交叉淡化闪烁），不是 updateImageAnimated:。
5. **素材走 Application Support**：`/var/mobile/Library/Application Support/MarkTheme/`（+Diagnostics/
   +PublishInbox），主题由管理器 App 推送进来（PublishInbox），不扫 /Library/Themes。

## ③ ThemeCore 0.5.1 / SnowBoard（与我们最接近）

- TC0.5.1：`com.susudear.themecore.plist` + Darwin 通知 `themecore.reload` → reloadIcons +
  clearCachedImages + purgeCache + updateImageAnimated —— 刷新机制与我们同构。
  额外挂：SBFolderIconImageSharedCache（文件夹拼图缓存）、SBIconController、SBIconView。
- SnowBoard：Base.dylib 做公共包装（`iconImageForIcon:orig:` 模式：先查主题表、没有就调 orig），
  素材读 /Library/Themes，角标用 SBBadgeBG，`reloadIconImage`/`reloadIcons` 刷新。

## ④ ThemeCorePlus 对齐清单（已做 / 可做）

已做（1.0.22）：缓存层站（秒加载）、站点挂齐即强刷、补挂轮次 0/0.3/1/2、0 秒首拍 + 2.5 秒兜底、
热刷新链路含角标视图/时钟/文件夹 mini 通知、一站一槽 + R2「类自己声明才挂」。

可借鉴（下一版候选，架构层）：
1. **预生成 ImageSet**：主题应用时把常用尺寸合成好存 Application Support，冷启动零合成。
2. **换图 API 升级**：`updateImageContentsWithImage:imageAppearance:isRealContentsImage:animated:`
   替代 updateImageAnimated:（无闪烁）。
3. **模块化快照**：时钟/日历/角标各自独立模块 + Contract，而不是现在的一个大文件一族函数。
4. **诊断也走 Application Support**（现在写 Preferences/themecoreplus-logs）。

## ⑤ 方法论

分析竞品 dylib 不用工具链：`grep -aoE '符号正则' <dylib>` 直接对二进制提符号（本机无 strings，
用 grep -a）；注入过滤器看包里的 *.plist；包体用 dpkg-deb -x 解到项目 .tmp/ 分析。
