# ThemeCorePlus `screen{ours=0}`：主题图没上屏的根因分析

**日期**：2026-10-31
**诊断来源**：`icli prefs read com.apple.springboard ThemeCorePlusDiagnostics`
**版本**：v0.9.5（自报），包 0.9.5，主题「液态玻璃」

## 症状

```
pix{n=30,themed=18,screen{total=16,ours=0,stock=12},clear=0,flat=0,nil=12,...}
disp{look=144,hit=123,noimg=0,noicon=21}
icon{look=34,skip=0,miss=12,hit=22}
ref{views=30,pushed=30,model=0,cache=0,miss=10,purge=-}
```

- **合成了 18 张主题图**（`themed=18`），图本身不透明、有内容（`clear=0,flat=0,minCov=0.85`）
- **显示层钩子确实在替换**：`disp{look=144,hit=123}`——`displayedImage`/`contentsImage`/`squareContentsImage` 被调了 144 次，123 次成功返回了主题图
- **但屏幕上 0 张是我们的**：`screen{ours=0,stock=12}`——扫描 16 个 UIImageView，0 张持有主题图，12 张持有系统原图
- **缓存清理完全失败**：`ref{cache=0,purge=-}`——`iconImageCache` 上找不到任何已知的 purge 方法

## 根因

### 一句话

**iOS 16 的 `SBIconImageView` 不用 `displayedImage` / `contentsImage` 的返回值来填充它内部的 UIImageView**。ThemeCorePlus 的钩子确实拦截了这些 getter 并返回了主题图，但系统渲染路径绕过了这些 getter——图标图由 IconServices 生成后直接 `setImage:` 到内部 `_SBIconGridWrapperView`（UIImageView 子类）上，钩子的返回值被丢弃。

### 详细链路

```
系统正常渲染路径（不被我们的钩子拦截）：
  IconServices 生成图标图
    → SBHIconImageCache 缓存
      → SBIconImageView:updateImageAnimated: 从缓存取图
        → _SBIconGridWrapperView:setImage: ← ← 实际设图的地方（我们没挂）
          → 屏幕上显示 stock 图

ThemeCorePlus 的钩子路径（挂了但返回值被丢弃）：
  SBIcon:iconImageWithInfo: ← 我们挂了（hit=22），返回主题图
  SBIconImageView:displayedImage ← 我们挂了（hit=123），返回主题图
  SBIconImageView:contentsImage ← 我们挂了，返回主题图
  SBIconImageView:squareContentsImage ← 我们挂了，返回主题图
  
  但 updateImageAnimated: 不用这些 getter 的返回值来设 UIImageView.image
  → UIImageView 仍然持有 IconServices 给的 stock 图
```

### 证据

1. **`displayedImage` 返回主题图（themed=18）但 UIImageView 持有原图（ours=0）**：同一个视图，getter 说主题图、实际显示原件——说明 getter 的返回值没被用于设图。

2. **`lay=` 字段揭示了实际持图的类**：
   ```
   ?|_SBIconGridWrapperView|61x61|9,9（×4）
   com.tencent.xin|UIImageView|19x19|5,2
   com.apple.MobileSMS|UIImageView|19x19|5,2
   ```
   `_SBIconGridWrapperView`（UIImageView 子类，61×61pt = 图标尺寸）持有 stock 图。
   `UIImageView`（19×19pt = 角标/小图标）也持有 stock 图。
   这些类**不在 ThemeCorePlus 的钩子站点列表里**。

3. **HookOwners 诊断**只显示 ThemeCorePlus 挂了 SBIcon 和 SBIconImageView 的 getter 方法。`_SBIconGridWrapperView` 不在 census 类列表里，`setImage:` 也没被任何类声明（在已检查的类中）。

4. **代码注释自证**（Hooks.h 第 70-73 行）：
   > iOS 16 起 SBIcon 的 -iconImageWithInfo: 在 SpringBoard 里没有调用者
   > （实测 look=0，站点挂了但一次没被问过），图由 IconServices 生成、经缓存直接交给视图显示。
   > MarkTheme16 0.2.0 则整套 MTIcon*SnapshotModule 挂在 IconServices 的图集管线上。

   注释写的是 `look=0`，但当前诊断是 `look=34`——因为 `TCPRefreshIconImages` 主动调 `updateImageAnimated:` 触发了钩子。但触发归触发，返回值仍被丢弃。

5. **MarkTheme16 能正常换图标**（AGENTS.md 记载），它挂的是 IconServices 管线（`MTIcon*SnapshotModule`），不是 SBIcon/SBIconImageView 的 getter——印证了 getter 路径在 iOS 16 上无效。

6. **缓存清理失败**：`iconImageCache` 对象不响应 `purgeCache`/`purgeAllCaches`/`purgeCaches`/`clearCache`/`removeAllObjects` 中任何一个（`cache=0, purge=-`）。即使清了缓存，重新取图仍走 IconServices，不会经过我们的钩子。

## 修复方向

### 方案 A（推荐）：挂 `_SBIconGridWrapperView:setImage:`——最后一公里拦截

在 `setImage:` 这一站拦截：当系统给图标 UIImageView 设图时，把 stock 图换成主题图。

- **前提**：需要先确认 `_SBIconGridWrapperView` 是否自己声明了 `setImage:`（R2 规则：只挂类自己声明的方法）。如果没有，考虑挂基类 `UIImageView:setImage:` 但用视图树过滤（只替换在 `SBIconImageView` 子树里的 UIImageView）。
- **风险**：`setImage:` 是高频方法，必须轻量过滤 + 重入保护。
- **需要做的事**：
  1. 把 `_SBIconGridWrapperView` 加入 census 类列表，CI 出包后确认它是否声明 `setImage:`
  2. 如果声明了——按 R2 直接挂
  3. 如果没声明——考虑 `class_addMethod` 添加 `setImage:` 的 hook（像 SileoFix 那样），或用 method swizzling

### 方案 B：挂 IconServices 管线

仿 MarkTheme16 的 `MTIcon*SnapshotModule`，直接在 IconServices 的图集生成阶段替换。

- **优点**：一劳永逸，所有用 IconServices 的地方都换
- **缺点**：需要逆向 IconServices API，工作量大

### 方案 C：找正确的缓存清理方法

当前 `iconImageCache` 上试的 5 个方法名都不对。iOS 16.7 上可能叫别的名字。

- **缺点**：即使清了缓存，重新取图仍走 IconServices，**不能单独解决问题**——只能作为方案 A/B 的辅助

## 当前状态

- **ThemeCorePlus 0.9.5 已装且加载正常**（`active=1, theme=液态玻璃`）
- **主题素材解析正常**（`layers=1, named=7, mask=1`）
- **图标本体合成正常**（18 张图，不透明、有内容）
- **钩子站点安装正常**（16 个站点，全部 ThemeCorePlus 拥有）
- **唯一问题**：合成的主题图没到达屏幕——渲染管线旁路了所有已挂的 getter

## 下一步

1. 把 `_SBIconGridWrapperView` 与 `UIImageView` 加入 census 类列表
2. 在 `ThemeCorePlusIcons.m` 新增 `setImage:` 站点（方案 A）
3. CI 出包 → 装机 → 读 census 确认 → 读诊断确认 `screen.ours > 0`
4. 如果方案 A 无效（`_SBIconGridWrapperView` 没声明 `setImage:`），转方案 B
