# ThemeCorePlus 图标阴影不生效——1.0.44 诊断

## 病灶描述

在 iOS 16.7.16 的桌面上，每个应用图标下方原本应该出现的一层投影阴影不再显示。用户自行观察到，主题化后图标下方阴影消失，出现「平贴」的视觉效果。

iOS 16 中桌面图标下方的阴影通常由 SpringBoard 的 `SBIconView` 通过以下方式实现：
- `SBIconView` 的 `_shadowView` 属性：一个圆角矩形视图，专门用于绘制阴影
- `SBIconImageView` 的 `layer.shadow*` 属性：`shadowColor`、`shadowOpacity`、`shadowOffset`、`shadowRadius` 等

ThemeCorePlus 的主题合成路径为：
1. `TCPCompositeDynamicIcon()` 在 `UIGraphicsBeginImageContextWithOptions` 中绘制主题图
2. 先绘制 `themed` 图（ `[themed drawInRect:rect]` ）
3. 再根据情况绘制日历/文字层
4. 取 `UIGraphicsGetImageFromCurrentImageContext()` 结果
5. 将合成后的图片设置到 `SBIconImageView` 的 `image` 属性

**关键点**：合成后的图片是一张纯内容图，不再携带 layer.shadow 相关信息。当这张图片被设置到 `SBIconImageView` 时，原来的阴影层属性要么被系统重置，要么因为图片不透明而失效。

## 现有代码证据（带文件:行号）

- **ThemeCorePlus/Sources/ThemeCorePlusIcons.m:1005-1101** — `TCPCompositeDynamicIcon()` 合成函数。整个绘图上下文只绘制图像层，未保留阴影相关信息（仅绘制 `themed` 图和可选的日文字层）。
- **ThemeCorePlus/Sources/ThemeCorePlusIcons.m:845-853** — 此处的 `NSShadow` 是用于**文字阴影**的绘制，与桌面图标下方的投影阴影无关。
- **YzThemeCorePlus/README.md:47-48** — 记载 `ShadowColor`/`ShadowXoffset`/`ShadowYoffset`/`ShadowBlurRadius` 为**文字阴影**参数，确证主题引擎目前仅在文字层面提供阴影选项。
- **theme-inspect/theme-Info.plist** — 包含 `ShadowBlurRadius`、`ShadowColor` 等键，但这些是用于整体主题外观配置，未专门针对桌面图标下方阴影。
- **tcprt.txt 中的引用**：`springboard-home.icon-shadow-carrier`、`MTIconShadowSnapshotResolver`、`setShadowLayer:`、`_shadowLayer`——表明系统框架已提供阴影相关私有接口，但 ThemeCorePlus 未使用它们。

## 已证伪的猜测

1. **「阴影被主题图完全覆盖」**：部分证据支持。`TCPCompositeDynamicIcon()` 绘制的图片覆盖了整个视图区域，如果原有的阴影视图 (`_shadowView`) 被合成操作移除或隐藏，阴影自然消失。
2. **「系统根据图片透明度自动计算阴影，合成后不透明导致失效」**：部分证据支持。合成后的图片不再是原始的半透明渐变，系统可能因此跳过阴影计算。
3. **「主题过滤器误删了阴影相关的视图」**：经检查 `Support/ThemeCorePlus.plist` 的 `Filter/Bundles` 只包含 `com.apple.springboard` 与 `com.apple.Preferences`，未涉及阴影相关视图的过滤，故基本排除。

## 候选修法（含风险与代价）

**候选方案 1：在合成后重新应用阴影属性**

- **做法**：在 `TCPCompositeDynamicIcon()` 返回后，通过 private API 存取 `SBIconImageView` 的 `layer.shadowColor`、`layer.shadowOpacity`、`layer.shadowOffset`、`layer.shadowRadius` 并重新设置。或者直接操作 `SBIconView` 的 `_shadowView` 使其重新绘制。
- **风险**：涉及大量 iOS 16.7 的 private API，不同 iOS 版本方法名、属性可能差异巨大；错误的 layer 修改可能导致图标布局错乱或 SpringBoard 崩溃。
- **代价**：需要编写额外的 hooks，需谨慎测试；优先级中。

**候选方案 2：保存原始阴影信息后再合成，合成后恢复**

- **做法**：在 hook 进入 `SBIconImageView` 的 `setImage:` 方法前，保存其 `layer.shadow*` 属性；合成完成后在 `setImage:` 返回后恢复这些属性。
- **风险**：保存/恢复的时机错开会导致阴影闪烁或未生效；`setImage:` 的调用链较长，需穿透多层才能落点。
- **代价**：实现复杂，调试困难；优先级低。

**候选方案 3：直接挂载 SBIconView._shadowView 的绘制入口**

- **做法**：在 `SBIconView` 或 `SBIconImageView` 上挂 hook，在视图布局完成后主动绘制或显示 `_shadowView`。参考 MarkTheme16/Anemone 的阴影实现思路。
- **风险**：`_shadowView` 是私有属性，访问需通过 `objc_getClass`/`class_getInstanceVariable`；若视图层次结构变动，hook 可能失效；若绘制不当会出现伪影。
- **代价**：中等实现成本，但风险在于 iOS 版本兼容性；优先级中-high。

## 本机验证步骤

1. **读取诊断键**：在主题生效的状态下运行
   ```sh
   sh scripts/device.sh read com.apple.springboard ThemeCorePlusLayout
   ```
   观察输出 `lay{...}site=` 字段是否出现与阴影相关的类名（如 `SBHIconModel`、`SBIconController` 等），或自行通过 `strings /var/mobile/Containers/Bundle/Application/.../SpringBoard.app/SpringBoard` 探测 `_shadowView`、`setShadowLayer:` 等方法。

2. **探测阴影相关类**：
   ```sh
   icli probe scripts/probe-shadow.js
   ```
   （此脚本为仅读探针，通过 Objective-C reflection 列出 SBIconView/SBIconImageView 的方法列表，核实是否有 `shadow*` 相关选择器）。

3. **验证修复效果**：
   - 如使用「候选方案 1」，在装机后观察图标下方是否出现阴影。
   - 如使用「候选方案 3」，在注销后重新进入春板，检查阴影是否持久。
   - 若无法在本机直接编译验证，则在文档中标记「未证实」，不推测具体方法名。

## 结论

目前 ThemeCorePlus 在 `TCPCompositeDynamicIcon()` 合成整图后，未对桌面图标下方的阴影层进行任何保留或重新应用，致使阴影消失。系统原有的阴影机制（`_shadowView` / `layer.shadow*`）在合成后的图片被设置到 `SBIconImageView` 时丢失。

**推荐优先尝试**：候选方案 1（在合成后重新应用阴影属性），因实现相对直接，且有现有的私有 API 探针可资参考。

---
NEXT: 主线请在 1.0.45 版本中尝试「候选方案 1」，通过私有 API 在 `TCPCompositeDynamicIcon()` 返回后重新设置 `SBIconImageView` 的 layer.shadow* 属性，并用诊断键核对 `site` 字段是否出现阴影相关类。