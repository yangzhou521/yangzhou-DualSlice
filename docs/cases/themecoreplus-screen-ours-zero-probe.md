# 专项案例：ThemeCorePlus 屏幕像素归属 `ours=0`（独立取证线）

> 取证对象：`pix{n=…,screen{total=…,ours=0,stock=…}}` 与 `census{…,layer{ours=0},s=[…]}` 这两组数。
> 现场版本 **0.9.16**，设备 iPhone10,1（iPhone 8，750×1334 @2x）/ iOS 16.7.16 / roothide。
> 本文**只读取证**：没有改任何源码、没有装包、没有注销。结论按「可复现的证据」写，不确定的地方明确标成未验证。

---

## 一、一句话结论

`screen{ours=0}` 里被数的那 48 个「屏幕采样点」**不是壁纸**，是**图标视图内部的 UIImageView**（文件夹图标内部的迷你网格 + 角标/配件小图）；而真正的壁纸层之所以一张都不是我们的，是因为 **ThemeCorePlus 从来没有壁纸这个功能**——源码里 0 个壁纸钩子，本机 5 个主题里 0 张壁纸素材。

所以这件事**不是「钩子没挂上」**，是两件不同的事被同一个数字串在了一起：

| 想查的东西 | 实际状态 | 性质 |
| --- | --- | --- |
| 壁纸 / 屏幕背景是不是主题的 | 永远不可能是（无素材、无钩子） | **功能未实现**，不是 bug |
| 图标内部那 48 张 stock | 文件夹迷你网格 + 角标小图，本来就不归主题管 | **设计如此**，但「诊断读数」会一直误导 |
| `layer.contents` 里 ours=0 | 判定只认对象指针，且普查深度被截断到 8 层 | **诊断不可信**，必须修，否则永远分不清「没上屏」和「上屏但认不出」 |

---

## 二、现场数据（v0.9.16，只读取出）

```
sh scripts/device.sh read com.apple.springboard ThemeCorePlusDiagnostics
```

关键片段（原样截取，未改）：

```
pix{n=98,themed=50,screen{total=64,ours=0,stock=48},clear=0,flat=0,nil=48,
    minOpaque=0.27,maxImgViews=2,dup=0,blank=[-],
    lay=[com.tencent.xin|UIImageView|19x19|5,2;
         com.apple.MobileSMS|UIImageView|19x19|5,2;
         ?|_SBIconGridWrapperView|61x61|9,9;
         ?|_SBIconGridWrapperView|61x61|9,9;
         ?|_SBIconGridWrapperView|61x61|9,9;
         ?|_SBIconGridWrapperView|61x61|9,9]}

census{ran=3,views=20,ours=0,stock=18,
       layer{total=35,ours=0,stock=31},
       disp{total=8,ours=6},
       icon{views=8,ours=6,stock=2},
       is=[SBIconImageView|ours|60x60 ×5,SBIconImageView|stock|60x60,
           SBHClockApplicationIconImageView|stock|60x60,SBIconImageView|ours|60x60],
       s=[UIImageView|stock|750x1334|-;UIImageView|stock|750x1334|-;
          UIImageView|stock|750x1334|-;UIImageView|stock|1x2|-;
          UIImageView|stock|12x12|-;UIImageView|stock|19x20|-;
          UIImageView|stock|23x23|-;UIImageView|stock|28x19|-]}

ref{views=98,pushed=98,model=0,cache=0,miss=8,purge=-}
icon{look=81,skip=0,miss=24,hit=73}
disp{look=191,hit=167,noimg=0,noicon=24}
sites=16[...]
```

站点归属表（`ThemeCorePlusHookOwners`）——进程里被换过 IMP 的只有这 6 处，全部是本插件：

```
SBIconImageView:displayedImage=ThemeCorePlus.dylib
SBIconImageView:contentsImage=ThemeCorePlus.dylib
SBIconImageView:squareContentsImage=ThemeCorePlus.dylib
SBIcon:iconImageWithInfo:=ThemeCorePlus.dylib
SBIcon:unmaskedIconImageWithInfo:=ThemeCorePlus.dylib
SBIcon:generateIconImageWithInfo:=ThemeCorePlus.dylib
```

---

## 三、这个数字到底在数什么（代码定位）

### 3.1 `pix screen{}` 只从**图标视图**往下数，跟壁纸无关

`ThemeCorePlus/Sources/ThemeCorePlusIcons.m`

- `:583 static void TCPInspectIconView(id view)` —— 整个 pix 计数只在这里发生。
- `:614` 起点是 `view.subviews`，`:670` 递归子视图，`:617` 循环上限 32 个子视图。
- 唯一的调用点是 `:1027`，在 `TCPRefreshIconImages()` 里，对**每个被刷新过的图标视图**调一次。
- 三组计数：
  - `:622 sPixelScreenTotal++`（这个图标视图里找到的 UIImageView 张数）
  - `:627 sPixelScreenThemed++`（里面那张图是我们合成的）/ `:628 …Stock++`（不是我们的）
  - `:606-610` 与 `:623` 共用一个 `sPixelNil`（displayedImage 为空 + image 为空）

**推论一：壁纸层永远进不了这个循环。** 壁纸视图（下面 4.2 的 750×1334 那三张）不是图标视图的子视图，`TCPInspectIconView` 根本走不到它。

**推论二：`screen{}` 是累计值，不是「此刻屏幕上」的快照。** 这些 `static NSInteger` 从进程启动起只 `++` 从不清零（`:552-566` 只有定义，全文没有赋值归零）。`ref{views=98,pushed=98}` 说明刷新推了 98 个视图，`pix{n=98}` 正好对上——**`total=64` 是 98 个视图历次累计出来的 64 张内部 UIImageView**。

**推论三：`nil=48` 与 `stock=48` 不是同一批。** 98 个视图里 50 个 `displayedImage` 是我们的（`themed=50`），所以 displayedImage 为空的 = 32 个；`nil` 总数 48 → 内部 UIImageView 里 image 为空的 = 16 张。于是 64 = 48 stock + 16 空 + **0 ours**。

### 3.2 `census{}` 才是「整屏普查」，但它有两个硬伤

`ThemeCorePlus/Sources/ThemeCorePlusIcons.m:711 TCPCensusInspectView(UIView *view, NSUInteger depth)`

- **硬伤 1：深度截断。** `:712 if (view == nil || depth > 8) return;` —— 只往下走 8 层。图标视图在窗口树里本身就已经在第 5~7 层（`SBHomeScreenWindow → SBIconController.view → … → SBIconListView → SBIconView → SBIconImageView`），它**内部真正画图的那一层很可能在 depth 9 以外**，被直接 return 掉。
- **硬伤 2：`ours` 只认指针身份。** `:742`/`:845`/`:861` 走 `isRenderedCGImagePointer:`（`ThemeCorePlusStore.m:997`），`:703`/`:748` 走 `isRenderedImage:`（`ThemeCorePlusStore.m:976`）——两者都只是在 `renderedImagePointers` / `renderedCGPointers` 这两个 `NSValue valueWithPointer:` 集合里找**同一个对象/同一个 CGImage 指针**（登记在 `ThemeCorePlusStore.m:952-969`，上限 400 张图 / 800 个 CGImage 指针）。

  系统只要**复制、重绘、或经 `SBHIconImageCache` 转一手**，指针就变了，于是「像素是我们的」会被判成 `stock`。

**这两条正好解释了 `disp{ours=6}` 与 `layer{ours=0}` 并存的怪现象**：视图交出来的图是我们的（disp 认得出），但画进 layer 的那张要么在 depth 9 以外没被数到，要么是系统再加工后的副本（认不出）。

---

## 四、逐条排除

### 4.1 「壁纸这层全空」= 功能不存在（证据三连）

```sh
grep -rn 'Wallpaper|wallpaper|SBDock|HomeScreen' ThemeCorePlus/Sources/   # → 0 命中
```

```
-- /Library/ThemeCore/液态玻璃.theme 目录
Bundles  IconBundles  Info.plist  axs66.otf  com.apple.mobileicons.framework
图标蒙板AnemoneEffects.zip  备用.zip
-- Bundles/ 内容（只有这些）
ClockIconBackgroundSquare*.png  SBBadgeBG@3x.png  com.apple.springboard
-- Bundles/com.apple.springboard 内容
ANEMFolderIconBG@3x.png  ClockIconBackgroundSquare@3x.png
ClockIconHourHand@3x.png  ClockIconMinuteHand@3x.png  ClockIconRedDot@3x.png  SBBadgeBG@3x.png
-- IconBundles：85 张图标（全是 *-large.png 图标素材）
```

再全盘查一遍本机 5 个主题（`/Library/ThemeCore/*`、`/Library/Themes/*`）：

```
grep -il wallpaper */Info.plist            → 无
find … -iname '*wallpaper*' -o -iname '*dock*blur*' -o -iname 'HomeScreen*'   → 无
```

**结论：本机没有任何主题带壁纸素材，插件也没有任何壁纸代码路径。** 壁纸层的 `ours` 恒等于 0 是**必然**的，不可能是「钩子没挂上」或「素材被系统覆盖」。

### 4.2 census 里那三张 750×1334 就是壁纸（且理应 stock）

`s=[UIImageView|stock|750x1334|-]` ×3 —— 750×1334 正好是本机屏幕像素尺寸（iPhone10,1 = 750×1334 @2x）。它们是壁纸/桌面背景的承载视图，系统壁纸图，不是我们的。**这不是失败，是没做。**

### 4.3 那 48 张 stock 是文件夹迷你网格 + 角标小图

`lay=[…]` 样本（6 个槽位已满，取的是前 6 张非我们的）：

| 样本 | 是什么 | 为什么不归主题 |
| --- | --- | --- |
| `?\|_SBIconGridWrapperView\|61x61\|9,9` ×4 | 文件夹图标内部的**迷你图标网格**（61×61 = 60pt 图标 + 1pt 边框） | 这张图是系统把若干迷你图标**拼**出来的合成图，主题没有「文件夹内部网格」这个素材类型 |
| `com.tencent.xin\|UIImageView\|19x19\|5,2`<br>`com.apple.MobileSMS\|UIImageView\|19x19\|5,2` | 角标/配件小图（19×19 与诊断里 `canvas=19x19` 完全一致；微信、信息都是带角标的 App） | 角标素材一次都没被问过：`badge{look=0,hit=0}` |

`SBIconImageView` 的类普查（`ThemeCorePlusBadgeCensus` / `ThemeCorePlusCensus`）坐实了这两个来源：

```
SBFolderIconImageView: … _iconGridImageClass fulfillGridImageForPageElement: _setPageElements:
                        _generateSqua…（截断） _updateRasterization …
SBIconImageView:       … contentsImage squareContentsImage displayedImage
                        updateImageAnimated: clearIconImageInfo _generateSquareContentsImage …
```

注意：**`SBIconImageView` 根本没有 `setImage:` 这个方法**（普查全表里没有）。所以旧案例里「挂 `_SBIconGridWrapperView:setImage:`」这条路只对文件夹网格那一路成立，对普通 App 图标不成立——普通图标走的是 `contentsImage`/`squareContentsImage`/`displayedImage`（这三处我们已经挂上了）。

### 4.4 `badge{look=0,hit=0}` 是个独立且更值钱的发现

角标底板站（`ThemeCorePlusBadges.m:19 → store badgeBackgroundImageForScale:`）**一次都没被调用**。也就是说 `Bundles/com.apple.springboard/SBBadgeBG@3x.png` 这张素材在设备上从来没被用过；屏幕上那 19×19 的角标图 100% 是系统图。

这条属于角标线（对话 ba1a3a02 的文件），本文只记证据，不动代码。

---

## 五、根因（三条，互相独立）

1. **壁纸层：功能未实现。** 无素材约定、无钩子、无缓存键。`ours=0` 是正确读数。
2. **图标内部层：不在接管范围。** 文件夹迷你网格（`_SBIconGridWrapperView`）与角标小图（19×19）都不是主题素材类型，站点表 `sites=16` 里也没有对应站点。`ours=0` 是设计使然。
3. **`layer.contents` 的 `ours=0`：诊断本身不可信。** 深度上限 8 + 纯指针身份判定，两者任一都会把「我们的图」判成 `stock`。在修掉这两条之前，**任何基于 `ours` 的结论都不成立**。

---

## 六、可执行修法（按优先级）

> 全部改在 `ThemeCorePlus/Sources/ThemeCorePlusIcons.m`（普查/pix 计数）与 `ThemeCorePlusStore.m`（身份登记）里。
> **`ThemeCorePlusIcons.m` 当前归对话 ba1a3a02 在改**，动手前必须先问一句「同文件吗」，得到点头再改。
> 出包只能走 CI（`.github/workflows/themecoreplus.yml`，tag 与 `VERSION` 三处同改）。

### 修法 A（最高优先，只改诊断，零行为风险）：让 `ours` 判定不再靠指针

目的：一次分清「我们的图没上屏」和「上屏了但认不出」。

1. `ThemeCorePlusStore.m` 里，合成图登记处（`:952-969`）旁边再记一份**像素指纹**：
   ```objc
   // 8×8 灰度缩略图，做平均哈希：系统复制/重绘后指针变了，指纹不变。
   static NSData *TCPImageFingerprint(UIImage *image);   // 渲染进 8x8 灰度 context，取 64 字节
   @property (nonatomic, strong) NSMutableSet<NSData *> *renderedFingerprints;
   ```
   登记时 `[self.renderedFingerprints addObject:TCPImageFingerprint(rendered)];`
2. 新增 `- (BOOL)isRenderedImageByPixels:(UIImage *)image`：先走原来的指针判定，指针不中就比指纹（允许 ±2/像素的容差，避免缩放带来的抖动）。
3. `TCPCensusInspectView` 的 `ours` 判定改成「指针 ∪ 指纹」，并在诊断里把两种命中分开计数：
   `layer{total=,ours=,byPointer=,byPixels=,stock=}`。

判读方法（改完一眼就能定性）：
- `byPixels > 0` → 图确实上屏了，之前的 `ours=0` 全是误判；
- `byPointer=0 && byPixels=0` → 我们的图真的没进 layer，才轮到去换挂点。

### 修法 B（同批做，只改普查）：去掉深度截断

`ThemeCorePlusIcons.m:712` 的 `depth > 8` 改成 `depth > 24`，并给 `sCensusViews` 的 4000 上限留出余量（`SBIconImageView` 内部层数不多，24 足够）。
理由：图标视图本身就在第 5~7 层，8 层上限会把真正画图的那一层切掉——这正是 `layer{total=35}` 偏少的原因（一屏十几个图标 + 壁纸，只数出 35 个非空 layer）。

### 修法 C（只在 A 判出「真没上屏」时才做）：加显示层站点

按 4.3 的证据，**不要**盲挂 `setImage:`（`SBIconImageView` 没有这个方法，挂了也是白挂；而且 `setImage:` 是通用选择器，容易打到无关视图 → 重影/闪烁）。

正确的站点是文件夹那一路：

```objc
// SBFolderIconImageView 负责生成文件夹内部的迷你网格图
MSHookMessageEx(objc_getClass("SBFolderIconImageView"),
                @selector(fulfillGridImageForPageElement:), …);
// 或拿到它自己的 _iconGridImageClass，在那一层替换 image
```

- 过滤条件：只对 `SBFolderIconImageView` 的实例生效；重入保护用一个 `static` 线程局部标志。
- 素材约定：主题里目前**没有**「文件夹内部网格」这个类型，要么新增（例如 `Bundles/com.apple.springboard/FolderGridImage@3x.png`），要么明确「文件夹网格保持系统拼图」——**建议先保持系统拼图**，因为文件夹内部本来就是迷你图标，主题化它的收益低、风险高（`SBFolderIconImageView` 一崩就是安全模式）。

### 修法 D（角标线，交给 ba1a3a02）：把 `badge{look=0}` 修成 `look>0`

`badge{look=0,hit=0}` 说明底板站从没被调用，而 `SBBadgeBG@3x.png` 素材是在的。这条修好后，那 2 张 19×19 的 stock 自然会变成 ours，`screen{}` 也会跟着好看——**但它不是「屏幕归属」问题的解，别把两件事混在一起。**

### 修法 E（只有用户真的要壁纸才做）：新增壁纸功能

1. 素材约定：`Wallpaper/<scale>/HomeScreen@2x.png`（或沿用 ThemeCore 的 `Bundles/com.apple.springboard/HomeScreenWallpaper@2x.png`）。
2. `TCPThemeStore` 加 `- (UIImage *)wallpaperImageForScale:`（照 `badgeBackgroundImageForScale:` 的形状写，:1043）。
3. **先取证再挂钩子**：本机壁纸承载视图在 census 里表现为**纯 `UIImageView` 750×1334**，父类链未知（`census s=` 只打自己的类名，不打父链）。最小取证改动：在 `TCPCensusInspectView` 里，对 `bounds` 等于屏幕尺寸的 UIImageView，额外把**父视图链**（最多 4 层类名）打进 `s=` 样本。拿到真类名（`PBUIWallpaperView` / `SBWallpaperView` / `_UIBackdropView` 之类）之后再挂 `image` / `contentsImage` / `setImage:`。
4. 风险提示：壁纸视图是 SpringBoard 最热的绘制路径之一，挂钩必须「没素材就原样返回」，且构造函数阶段**禁止碰任何 UIKit**（见 `docs/cases/countdownhud-safe-mode.md` 的铁律）。

---

## 七、复发时怎么一步定位

1. `sh scripts/device.sh read com.apple.springboard ThemeCorePlusDiagnostics`，先看 **`census.disp.ours` 与 `census.icon.ours`**（视图交出来的图是不是我们的）。这两个 >0 说明渲染链路是通的。
2. 再看 **`census.layer.byPixels`**（修法 A 之后才有）。=0 才是「真没上屏」。
3. 看 `pix.lay=[…]` 样本里的类名：
   - `_SBIconGridWrapperView` → 文件夹迷你网格，**正常**；
   - 尺寸 19×19 / 25×25 → 角标，去看 `badge{look,hit}`；
   - 出现 750×1334 → 那是壁纸，先确认主题里有没有壁纸素材（本机没有）。
4. **别用 `pix.screen.total` 判断「屏幕上有几张图」**——它是累计值、且只覆盖图标视图内部。
5. 站点是否真挂上，看 `ThemeCorePlusHookOwners`（`类:选择器=dylib`），不要靠猜。

---

## 八、本文未验证 / 需要点头才能继续的部分

- **没有改任何代码**，所以修法 A~E 都还没有实现，更没有实测。
- 「普通 App 图标是不是真的靠 `contentsImage` 画进 layer」这一点，本文只能从 `disp{ours=6}` + `layer{ours=0}` 的**矛盾**推断「判定或深度有问题」，**没有直接证据**证明 layer 里那张 CGImage 的像素就是我们的。要证明，必须上修法 A（指纹判定）跑一轮。
- 壁纸承载视图的**真实类名**没拿到（需要修法 E 第 3 步的父链取证）。
- 本机无工具链，任何验证都必须 CI 出包 + 装包 + 注销，属于打断用户操作的动作，**要先征得用户同意**；`ThemeCorePlusIcons.m` 还要先问 ba1a3a02 是否同文件。

---

## 九、相关文档

- `docs/cases/themecoreplus-screen-ours-zero.md` —— 同一组计数的**旧版**（v0.9.5，`screen{total=16}`）分析与方案 A/B/C。本文不覆盖它，只补正它的前提：**那一版的 `screen{}` 也不是壁纸**。
- `docs/cases/countdownhud-safe-mode.md` —— 注入 SpringBoard 的插件在构造函数阶段碰 UIKit 的崩溃铁律。
