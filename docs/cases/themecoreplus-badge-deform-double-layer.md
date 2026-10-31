# 案例：角标「双层 + 圆形素材被拉成异形」——ThemeCorePlus 1.0.7

- 设备：iPhone10,1（A11）/ iOS 16.7.16 / roothide
- 时间：2026-10-31 20:31 用户报 → 20:5x 装机实测通过 → 21:0x 用户确认「角标显示正常了」
- 代码：`ThemeCorePlus/Sources/ThemeCorePlusBadges.m`
- 提交：`e9f36854`（1.0.7 主体）、`a13c628a`（前向声明编译修复）
- 技能：`theme-badge-double-layer-fix`

## 一、用户报的病灶（原话）

> 桌面图标上的角标素材显示不正常：一种是双层叠加到一起（用户第三方角标素材叠加到了 iOS 系统角标上了），
> 这个问题的原因是加载的第三方角标圆形素材变形显示异常（这个是微信图标的角标、同时双层叠加、
> 角标素材变形了是异形不是圆形的）！只有桌面上的（越狱）文件夹上的角标是圆形角标！

拆成三条：

1. 双层：主题角标 + 系统红底叠在一起；
2. 变形：第三方**圆形**素材被拉成椭圆（微信最明显）；
3. 对比线索：文件夹上的角标是正常的圆形 —— 说明素材本身没问题，是主屏这条路把形状弄坏了。

## 二、诊断读数（装 1.0.6 时）

```
badge=1;asset=25x25;canvas=32x25;fit=1.00
sys{look=373,hid=248,wait=1,skip=0,host=0,lift=0,tree=SBDarkeningImageView,
    bg=SBDarkeningImageView:shown,img=nil,c=nil,our=UIImageView}
txt{look=130,hit=130}
```

两条决定性信息：

- `canvas=32x25` 对 `asset=25x25` —— 画布被加宽到 32，**25×25 的正圆被拉成 32×25 的椭圆**，正是「异形」。
- `our=UIImageView` + `bg=SBDarkeningImageView` —— 我们的图挂在**系统底板内部的子 image view** 上，
  两者不是同一个视图。

## 三、根因

### 3.1 变形

`TCPThemedBadgeTextImage` 里多位数字（如「99+」）走：

```objc
CGFloat width = MAX(naturalWidth, ceil(textSize.width + side * 0.5));
UIImage *stretchable = [asset resizableImageWithCapInsets:… resizingMode:UIImageResizingModeStretch];
[stretchable drawInRect:canvas];
```

`resizableImageWithCapInsets` 的语义是「中间那一段横向拉伸、两头不变」——
对**胶囊形**素材是对的，对**正方形正圆**素材就是把圆拉成椭圆。素材恰好是后者。

### 3.2 双层

1.0.3 写的 lift（把我们的图搬到自己的兄弟层、再把系统底板 `hidden`）判据是：

```objc
if (ourHost != nil && bgView != nil && ourHost == bgView) { … }
```

`ourHost` 是「握着我们那张图的视图」，在本机它是底板的**子视图**，永远不等于 `bgView`，
于是 lift 一次都没跑 → `lift=0`、底板永远 `shown` → 双层永久留在屏幕上。

**这是一个「判据比现实更严格」的典型**：注释里写的是「本机只有一个子视图、图就套在底板上」，
而系统升级后结构变成了三层。

## 四、修法

### 4.1 圆头胶囊（取代横向拉伸）

新增 `TCPDrawBadgePill(asset, rect)`：

- 画布宽 ≤ 素材宽：素材按自然比例铺满高度、居中（**圆的还是圆的**）；
- 画布更宽：两端各画一个**完整圆头**（用 `CGImageCreateWithImageInRect` 从素材左右裁出，
  等比、不缩放），中间那段用**素材本色**填满。

素材本色 `TCPBadgeAssetFillColor(asset)`：先取中心像素；中心透明（素材镂空）就取不透明像素的平均色。

**兜底（21:0x 复核后补）**：取不到本色时**不能只画两端**（中间空 → 多位数字会断成两半），
退回 `TCPDrawAssetAspectFitted` 整段铺满 —— 宁可长一点，不留洞。

### 4.2 lift 放宽判据

```objc
// 只要「底板的子树里找得到我们那张图」就搬 —— 那才是真正的判据
if (bgView != nil && TCPBadgeOurImageInSubtree(bgView) != nil) {
    liftedNow = TCPBadgeLiftOurImage(view, bgView);
}
```

配套两处：

- overlay 的 frame 用 **ourHost 在角标视图坐标系里的位置**
  （`[ourHost convertRect:ourHost.bounds toView:view]`），不是底板的 frame ——
  底板是铺满的暗化层，按它摆会让我们的图偏位；
- 早退复检路径（`TCPBadgeHideSystemBackground` 开头）也要从**底板子树**取新图、
  按 ourHost 定位，否则数字变了不同步。

铁律保留：**拿不到我们的图就一个字节都不动**，绝不让角标变空白。

## 五、验收（1.0.7 装机实测）

| 字段 | 装前 | 装后 | 含义 |
| --- | --- | --- | --- |
| `canvas=` | `32x25` | **`25x25`** | 圆形不再被拉宽 |
| `sys{lift=}` | `0` | **`2`** | 搬图真执行了 |
| `sys{bg=}` | `:shown` | **`:hidden`** | 系统红底被藏 |
| `sys{tree=}` | 无 `*` | **`…*`** | 这一层真被清动过 |

- SpringBoard 崩溃列表：无新报告。
- 用户 2026-10-31 21:0x 目视确认：**「角标显示正常了」**。

## 六、踩过的坑

1. **前向声明位置**：`TCPCompositeCalendarInk` 的前向声明被插在定义前的注释处（行 577），
   而调用在行 558 → CI 报 `undeclared function` + `static declaration follows non-static declaration`。
   前向声明必须写在**调用点之前**。修复提交 `a13c628a`。
2. **`resizableImageWithCapInsets` 不是万能**：它假设素材是「两头定形、中间可拉伸」的胶囊；
   对圆形/异形素材必须自己按形状画。
3. **判据别写死结构**：`ourHost == bgView` 这种「假设了两者同一」的判据，系统一改层级就失效；
   应该问「**我要的东西在不在这个子树里**」。

## 七、相关

- 技能 `theme-badge-double-layer-fix`（本条案例的通用化版本）
- 同期修的另外两条：`dynamic-icon-clock-calendar-theming`（时钟 / 日历）
- 复核记录：`docs/review/1.0.7-review.md`（`5781b4c7` 线只读复核，三项无硬伤 + 一条兜底建议已采纳）
