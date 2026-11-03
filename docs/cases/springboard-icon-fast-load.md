# ThemeCorePlus 注销后桌面图标「秒加载」不实现——1.0.44 诊断

## 病灶描述

用户反馈：注销（respring）后，桌面图标一批一批刷出来，需要等待几秒钟才全部变成主题图标。期望行为是注销后立即（或极快地）显示所有主题化图标，无渐进加载延迟。

当前的图标加载路径（按 likely 顺序）包括：
1. **ThemeCorePlusStore 图缓存**：主题引擎内部的缓存，优先提供已缓存的主题图
2. **TCPRefreshIconImages()**：刷新所有图标图的函数，通常在 SpringBoard 启动后被调用
3. **文件夹图缓存**：文件夹图标的独立缓存机制
4. **SBIconView 的图标图替换时机**：SBIconView 在布局子视图后，通过 `- (void)layoutSubviews` 或类似时机替换图标图

诊断输出（`sh scripts/device.sh read com.apple.springboard ThemeCorePlusLayout`）中的关键字段示例：
```
lay{rst=0,sav=1,tick=1,force=0,site=-SBHIconModel:_saveIconState,model=adopt:iconModel,last=baseline,...}
```
以及缓存相关：
```
cachecls=PKIconImageCache,SBFolderIconImageCache,SBHIconImageCache
cache=nocache
```

## 现有代码证据（带文件:行号）

- **ThemeCorePlus/Sources/ThemeCorePlusHooks.h:195-197** — 註记：「秒加载要挂的缓存层真入口靠它实测出来，不靠猜（1.0.30 已证伪 SBHIconImageCache 三兄弟）」。定义了 `TCPInstallIconCacheLayerSitesV2()` 等函数，用于按选择器名而非类名挂载缓存层。

- **ThemeCorePlus/Sources/ThemeCorePlusHooks.m:697-810** — 缓存层挂载实况（`sCacheHookReport`）。1.0.25 起改按「声明者」挂（`TCPInstallIconCacheLayerSitesV2`），但仍未挂上。详细记录了各类的 method 探测结果（`cache=nohook`、`cache=PKIconImageCache/SBFolderIconImageCache/SBHIconImageCache` 但 `cache=nocache`）。

- **ThemeCorePlus/Sources/ThemeCorePlusHooks.h:264** — `TCPRefreshIconImages(void)`：刷新图标图的入口函数。在主题加载或重新激活时被调用，但可能未在注销后及时触发。

- **ThemeCorePlus/Sources/ThemeCorePlusFolders.m:39-104** — 文件夹图标缓存入口。固定类名直取 `SBFolderIconImageCache`，但系统未主动调用其方法，需额外调用 `TCPDirFoldRefresh()` 兜底。

- **YzThemeCorePlus/README.md:92** — 「未实现：秒加载/缓存层（需 probe SBHIconImageCache 真实取图方法）」。确认秒加载在当前版本未完全实现。

- **theme-inspect/ 目录** — 包含 Shadow/ 相关配置，但不直接涉及秒加载缓存链路。

## 已证伪的猜测

1. **「读 84 张 PNG 慢」**：部分证据不支持。iOS 16 的 PNG 解码在 GPU/硬件辅助下，单张图解码耗时不足以造成数秒级的全局延迟。且 84 张图并非同时加载，而是分批请求。

2. **「等 SpringBoard 自己请求图慢」**：部分证据支持。SpringBoard 在图标视图重建后，通过 `- [SBIconImageView image]` 或缓存获取图片，如果缓存未命中，会重新从文件/素材目录读取，这可能引入延迟。

3. **「图标视图重建后没命中缓存」**：最可能的根因。注销后 SpringBoard 会重新构建所有 SBIconView 实例，如果缓存（`SBFolderIconImageCache`、`SBHIconImageCache` 等）未被声明为「声明者」并持久化，每次重建都需重新取图，导致一批一批刷出的现象。

## 候选修法（含风险与代价）

**候选方案 1：预解码常驻内存（预热缓存）**

- **做法**：在主题加载完成后，主动解码所有 84 张（或 relevant）PNG 图片并存入 `NSCache` 或关联的缓存类（`SBHIconImageCache`、`SBFolderIconImageCache` 等），确保注销后重建时直接从内存取图，无磁盘 I/O 延迟。
- **风险**：内存占用显著增加（84 张 @3x 图片约 84 × 200KB ≈ 16.8MB，取决于实际资源大小）；若解码时机不当可能在注销动画期间抢占系统资源。
- **代价**：中等实现成本，需确保在主题启动时一次性预热，避免注销时重复解码；优先级 middle。

**候选方案 2：提前把缓存路径指到主题图**

- **做法**：在 ThemeCorePlusStore 或缓存类的取图入口中，优先从主题素材目录读取图片路径，绕过系统默认的缓存查找流程。利用已有的 `TCPThemeStore` 的 `iconImageForBundleID:size:scale:cornerRadius:` 方法，在注销后直接指向主题缓存而非原始图片。
- **风险**：需修改缓存类的方法实现，涉及 private API；若主题素材目录结构变动，缓存路径可能失效；可能与系统的其他缓存机制冲突。
- **代价**：中-high 实现复杂度，需谨慎处理路径兼容性；优先级 middle。

**候选方案 3：在 SBIconView 首次布局就同步给图**

- **做法**：hook `SBIconView` 的 `layoutSubviews`（或 `SBIconImageView` 的 `awakeFromNib` / `drawView`），在视图首次布局完成后，同步把主题图直接设置到 `image` 属性，并标记缓存已命中，避免后续重复请求。
- **风险**：`layoutSubviews` 调用时机多，需小心只在首次布局时干预；若在注销动画期间 hook 失效，可能导致图标闪烁或错位；需要确保在所有入口（ Dock、主屏、切换器）均生效。
- **代价**：较高实现复杂度，需穿透多个视图类；优先级 lower（因风险最高）。

## 本机验证步骤

1. **读取缓存诊断键**：在注销前后分别运行
   ```sh
   sh scripts/device.sh read com.apple.springboard ThemeCorePlusLayout
   ```
   观察 `cache=` 字段变化：注销前是 `cache=nocache` 还是有具体类名；注销后是否仍旧相同，或是否出现 `cache=0` / `cache=miss` 等标记。

2. **探测缓存类方法**：
   ```sh
   icli probe scripts/probe-cache.js
   ```
   （仅读探针，通过 Objective-C reflection 列出 SBIconImageCache / SBFolderIconImageCache 等类的方法列表，核实是否有 `iconImageWithInfo:` 等入口，以及是否被 ThemeCorePlus 的 hooks 挂过）。

3. **计时验证**：
   - 注销前记录时间（通过设备控制台或 `apelin_log_read process=SpringBoard`）。
   - 注销后观察图标加载的时间点，对比「秒加载」与「普通加载」的时间差。
   - 若能通过 `TCPCacheProbe.txt`（`/var/mobile/Library/Preferences/TCPCacheProbe.txt`）中的计时字段进一步定位慢在哪一步。

4. **验证修复效果**：
   - 装入修复方案后，注销观察图标是否一次性全部出现，而非一批一批。
   - 通过 `apelin_crash_list process=SpringBoard` 确认注销后无新的崩溃报告。

## 结论

注销后图标一批一批刷出的根因最可能是：**图标缓存类（`SBFolderIconImageCache`、`SBHIconImageCache` 等）未被声明为「声明者」并持久化，注销后 SpringBoard 重新构建 SBIconView 时未命中缓存，须重新从素材目录读取图片。**

**推荐优先尝试**：候选方案 1（预解码常驻内存），因其相对安全，仅在主题启动时预热缓存，不改动核心取图逻辑，且直接解决「重新读取」的延迟问题。

---
NEXT: 主线请在 1.0.45 版本中尝试「候选方案 1」，在 `TCPThemeStore` 主题加载完成后主动解码主题图并存入缓存（如 `SBHIconImageCache` 或自建 `NSCache`），并用诊断键 `cache=` 核对注销前后是否从 `nocache` 变为有效缓存命中；必要时结合 `TCPRefreshIconImages()` 确保在注销后及时触发刷新。