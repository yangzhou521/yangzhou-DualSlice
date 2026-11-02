# ThemeCore+

轻量化桌面图标 + 通知角标主题插件（rootless，iOS 15+，SpringBoard 注入）。作者：yangzhou

在原版 ThemeCore 只能换图标的基础上，补上了**桌面通知角标（Badge）主题化**：角标背景图、角标文字颜色/字体/字号/阴影/大小写/偏移全部由主题控制，且兼容 ThemeCore 与 Anemone 的主题目录格式。

## 主题格式

插件按以下顺序扫描主题目录（先找到的优先）：

1. `<jbroot>/Library/ThemeCore/<主题名>/`（ThemeCore 原生格式）
2. `<jbroot>/Library/Themes/<主题名>.theme/`（rootless Anemone 格式）
3. `/var/mobile/Library/Themes/<主题名>.theme/`（移动目录手工安装）

### 图标

```
<主题>/
├── icons/<bundleid>@3x.png      # ThemeCore 风格（@2x.png、无后缀也可）
└── Bundles/<bundleid>/icon@2x.png   # Anemone 风格
```

- 查找顺序：@3x → @2x → 无后缀。
- `com.apple.mobilecal`（日历）：主题提供底图时叠加系统实时日期数字（按底图明暗填黑/白字）；未提供底图则保留系统动态图标。

### 通知角标

```
<主题>/
├── Badges/SBBadgeBG@2x.png      # 角标背景（推荐，圆角图）
├── SBBadgeBG@2x.png             # 兼容 Anemone 经典位置
└── Info.plist                   # 角标文字样式（见下）
```

背景图会按 40% cap insets 九宫格拉伸，宽角标（如 99+）不会变形。

`Info.plist` 的 `BadgeSettings`（兼容 `ThemeLib-BadgeSettings`，与 Anemone 完全同键）：

| 键 | 类型 | 说明 |
|---|---|---|
| `TextColor` | 字符串 | 角标文字颜色，CSS 颜色（`#FF0000` / `#RGB` / 颜色名），默认白色 |
| `FontName` | 字符串 | 字体 PostScript 名，默认系统字体 |
| `FontSize` | 数值 | 字号，默认 16 |
| `WidthChange` / `HeightChange` | 数值 | 文字画布宽/高增量 |
| `TextXoffset` / `TextYoffset` | 数值 | 文字偏移 |
| `TextCase` | 字符串 | `lowercase` / `uppercase` |
| `ShadowColor` | 字符串 | 文字阴影颜色（留空不加阴影） |
| `ShadowXoffset` / `ShadowYoffset` / `ShadowBlurRadius` | 数值 | 文字阴影参数 |

主题没提供角标资源/配置时，角标保持系统原样，零影响。

### 主题 Info.plist 额外键

- `IconCornerMask`（BOOL）：主题级圆角遮罩开关，优先于面板全局开关（默认开启，圆角率 0.2237）。
- `CalendarLiveDate`（BOOL）：日历是否叠加实时日期数字（默认 YES，设为 NO 则退回整图替换）。

### 时钟图标

时钟主题资源放在 `<主题>/Bundles/com.apple.springboard/` 下（Anemone 命名约定，也可放 `<主题>/` 根目录）：

```
ClockIconBackgroundSquare@2x.png   表盘
ClockIconHourHand@2x.png           时针
ClockIconMinuteHand@2x.png         分针
ClockIconSecondHand@2x.png         秒针
ClockIconBlackDot@2x.png           中心点（黑）
ClockIconRedDot@2x.png             中心点（红）
```

## 设置面板（设置 → ThemeCore+）

- 启用插件
- 选择主题（列表显示每个主题的图标数量，点按即切换；顶部可"不使用主题"）
- 图标圆角遮罩
- 启用角标主题
- 刷新图标（广播配置通知，尝试免注销刷新；未生效时注销一次）

## 构建

本地（macOS/Linux，Theos + rootless 环境）：

```sh
make package THEOS_PACKAGE_SCHEME=rootless
```

或直接推送 GitHub：仓库自带 `.github/workflows/build.yml`（macOS + iOS 16.5 SDK + rootless），推送后在 Actions 里产出 deb 并发布 Release。

## 实现要点 / 已知限制

- 图标 hook：`-[SBApplicationIcon iconImageWithInfo:]`（NeonBoard 在 iOS 14–17 验证过的路径）；角标 hook：`SBIconBadgeView` 的 `_checkoutBackgroundImage`/`_checkoutBackgroundImageTuple`/`_checkoutImageForText:`，iOS 16+ 用 `SBHIconAccessoryCountedMapImageTuple` 包装并带代际 cache key。
- 免注销刷新依赖 `SBIconController relayoutIcons`，部分系统版本图标缓存不重建时需要注销。
- 已实现：时钟（换表盘+指针、保持走时，`SBClockApplicationIconImageView`）、日历（叠加实时日期）、文件夹 mini 拼图（`SBFolderIcon miniGridCellImageForIcon:`）、角标底板（`SBIconBadgeView layoutSubviews`，iOS 16 底板为纯色非图片）。未实现：秒加载/缓存层（需 probe `SBHIconImageCache` 真实取图方法）、图标阴影。
- 本工程由 axs-ios-tweaks 模板生成，真机测试未做，编译与三环境（rootless/rootful/roothide）验收按模板文档执行。
