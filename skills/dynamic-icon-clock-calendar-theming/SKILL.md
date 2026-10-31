---
name: dynamic-icon-clock-calendar-theming
description: 系统动态图标（时钟 com.apple.mobiletimer、日历 com.apple.mobilecal）主题化怎么修：为什么挂 layoutSubviews 永远不触发（clockv{look=0}）、要改成主动定时找视图重画、表盘与指针怎么自己合成让指针保持活、日历别用 multiply/screen 混合模式而要用「墨层」提取（否则白底黑字压深色底=看不见字）。
---

# 时钟 / 日历图标主题化（iOS 16.7 实测）

适用：主题类插件（ThemeCorePlus 等）换主屏图标时，用户报「时钟和日历一直不换主题素材」/
「日历只有底图没有数字」。本机：iPhone10,1 / iOS 16.7.16 / roothide。

## ① 时钟：为什么「挂 layoutSubviews」永远不生效

0.9.17 → 1.0.6 一直坚信「时钟视图自己画表盘和指针，所以要挂它的 `layoutSubviews` 换表盘」。
1.0.6 装机实测否掉了这个前提：

```
clockv{look=0,hit=0,miss=0,last=-}
```

`look=0` = **钩子一次都没被调用**（不是「找不到表盘」，`last=-` 说明连函数体都没进）。
也就是说 iOS 16.7 的 `SBHClockApplicationIconImageView` **建好之后再也不会重新 layout** ——
它的图来自图标图缓存，界面上没有任何东西会触发它重排。

**结论：对这类「不重排」的视图，挂回调是死路，必须自己主动去找它。**

修法（1.0.7，已实测 `clockv{look=0,hit=1,tick=1,found=1}`）：

```objc
void TCPClockTick(void) {          // 主队列里遍历窗口树找 SBHClockApplicationIconImageView
    Class cls = NSClassFromString(@"SBHClockApplicationIconImageView");
    ... 遍历 windows 的子树，逐个调 TCPClockViewApply(view) ...
}
```

在构造函数里挂两个 `dispatch_after`（3 秒、12 秒）加一个 **30 秒的 `dispatch_source_t` 定时器**。
定时器必须是**文件级静态**持有（ARC 下 `dispatch_source_t` 是对象，放局部变量函数返回即取消 ——
0.9.17 的 `tick=0` 就是这个坑）。

## ② 时钟：指针要「活」，就得自己按时间重画

- Store 里 `com.apple.mobiletimer` 只登记了**表盘**（`ClockIconBackgroundSquare`），
  指针素材（`ClockIconHourHand` / `ClockIconMinuteHand` / `ClockIconRedDot`）不在图标表里 ——
  直接 `iconImageForBundleID:` 只能拿到一块没有指针的表盘。
- 所以自己合成：表盘铺底 → 按当前 `NSCalendar` 的时/分算角度画两根针 → 画红点。
  指针素材要先量 alpha 包围盒再缩放（`TCPAlphaBounds`），否则 248×547 的画布会把针缩成看不见。
- 合成图盖成视图上的一个 `UIImageView`（overlay，带 tag 认领），每 30 秒重画一次 ——
  时针分针精度到分钟，30 秒刷新足够，视觉上是活的。
- overlay 每拍都要 `bringSubviewToFront:`，系统后来插进来的层要压回去。

## ③ 日历：别用 multiply / screen 混合模式

早期做法是「主题底图 + 系统整图按亮度选 multiply（白底）或 screen（深底）」。用户反馈
「日历在某一版显示了底图，没有显示文字」。

原因很直白：系统日历整图是**白底 + 黑数字**。multiply 压在深色主题底上 →
白底变成主题色、黑数字还是黑 → **深底上根本看不见字**；screen 压在浅底上 → 白字也看不见。
**混合模式解决不了「墨要跟着底图换颜色」这件事。**

正确做法（1.0.7，实测 `dyn{…ink:w,lum=0.14,cov=0.82}`）：

1. 把系统图缩到 ≤96px 读像素，四角平均当**背景色**；
2. 每个像素与背景色的差异归一化当**墨强度**，写进一张 RGB 图；
3. 用 `CGContextClipToMask(ctx, rect, mask)` 裁剪，然后填一个纯色 ——
   **底图暗填白、底图亮填黑**（`TCPPixelStatsForImage(themed).luminance <= 0.5` 判暗）。

这样文字永远和底图有对比度，底图也保持主题的样子。

注意 `CGBitmapContextCreate` 的 `bytesPerRow` 必须与你 buffer 的排布一致
（RGBA = `w*4`）；用 `kCGImageAlphaNoneSkipLast` 时 `ClipToMask` 按**亮度**取值。

## ④ 验收

| 字段 | 期望 | 含义 |
| --- | --- | --- |
| `clockv{tick=N}` | 持续增长 | 主动刷新在跑（不动 = 定时器没持有住） |
| `clockv{found=N}` | ≥1 | 真在屏幕树里找到了时钟视图 |
| `clockv{hit=N}` | > 0 | 主题表盘真盖上了 |
| `dyn{last=…ink:w/b,lum=…}` | 有 `ink:` 前缀 | 走的是墨层路径，不再是 mul/scr |
| `dyn{…cov=0.8+}` | 覆盖率正常 | 合成结果不是空白 |

装完 SpringBoard 插件必须查 `apelin_crash_list process=SpringBoard` 无新报告。

## ⑤ 相关

- `a11-roothide-ondevice`：云编译双切片、装包与注销流程。
- `theme-badge-double-layer-fix`：同批修的角标问题。
- `injected-tweak-restart-app`：注入 SpringBoard 的插件只能靠注销加载。
