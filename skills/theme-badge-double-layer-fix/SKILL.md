---
name: theme-badge-double-layer-fix
description: 越狱主题插件的角标「双层（系统红底 + 主题底板叠在一起）」「圆形素材被拉成异形」怎么查怎么修：三个计数怎么分（badge{} 恒 0 别当证据）、ourHost 与 backgroundView 的关系决定 lift 跑不跑、圆头胶囊取代 resizableImageWithCapInsets、验收看 sys{lift/bg/tree} 与 canvas=。1.0.7 已装机实测通过并由用户确认。
---

# 角标「双层 / 变形 / 不能正确显示」怎么查怎么修

适用：越狱主题类插件（SnowBoard / IconBundles / ThemeCore 类）给桌面图标角标换素材后，
用户说「角标是两层」「角标变成异形不是圆的」「角标还是系统红底」。
本机实测环境：iPhone10,1 / iOS 16.7.16 / roothide。
参考实现：`ThemeCorePlus/Sources/ThemeCorePlusBadges.m`（0.9.24 → **1.0.7 已验证**）。
完整案例：`docs/cases/themecoreplus-badge-deform-double-layer.md`。

**状态：1.0.7 已装机实测通过，用户 2026-10-31 21:0x 目视确认「角标显示正常了」。**

## ① 现象（用户原话）

- 2026-10-31 13:1x：「一个图标二层、一个图标一层」「角标加载异常」。
- 2026-10-31 20:31：「桌面图标上的角标素材显示不正常：一种是双层叠加到一起（第三方角标素材叠到了
  iOS 系统角标上了），这个问题的原因是加载的第三方角标圆形素材变形显示异常（微信的角标）——
  双层叠加、角标素材变形了，是异形不是圆形的」；「只有越狱文件夹上的角标是圆形角标」。

**「文件夹上的角标是圆的」是一条关键对照线索**：素材本身没坏，是主屏这条路把形状弄坏了。

## ② 先分清三个计数，别被 `badge{look=0}` 误导

| 诊断字段 | 对应站 | iOS 16.7 实测 |
| --- | --- | --- |
| `badge{}` / `bg{}` | 角标**背景站**（`TCPSiteKindBadgeBackground`） | **恒为 0** —— 这台系统没有那两个方法，与素材无关 |
| `tup{}` | 角标**元组站** | 0 —— 本机不走这条路 |
| `txt{}` | 角标**成图站**（主题底板 + 数字整图） | **真正在用的那条**（实测 look=130/hit=130） |

素材有没有接上，看 `txt{}` 与 `asset=`：`asset=25x25` 表示 `SBBadgeBG@3x.png` 是 75×75 px（@3x = 25pt）。

## ③ 变形：圆形素材不能被横向拉伸

- 素材 `SBBadgeBG` 是 **25×25 正方形圆形**。多位数（如「99+」）原来把画布加宽到 32×25，
  再 `resizableImageWithCapInsets:` 横向拉伸中间段 → **圆被拉成椭圆**，就是「异形不是圆的」。
- `resizableImageWithCapInsets` 的语义只适用于「两头定形、中间可拉伸」的**胶囊**素材；
  圆形/异形素材必须自己按形状画。
- **修法（1.0.7）**：圆头胶囊 —— 两端圆头用 `CGImageCreateWithImageInRect` 裁出素材左右两段
  原样等比画（不缩放、不拉伸），中间填**素材本色**。本色取素材中心像素；中心镂空时取不透明像素平均色。
- 宽度只有「一个数字」时 `canvas` 就等于素材尺寸（25×25），形状完全不变。
- **兜底**：取不到本色时**不能只画两端**（中间空 → 多位数字断成两半），
  退回「素材按比例整段铺满」—— 宁可长一点，不留洞。

## ④ 双层：真根因在「我们的图挂在哪一层」

诊断要读 `sys{…,lift=,bg=,tree=,our=}`：

```
SBIconBadgeView
  └ backgroundView  = SBDarkeningImageView   ← 系统红底（诊断里 bg=）
      └ UIImageView                          ← 我们的整图常常挂在这里（诊断里 our=UIImageView）
```

- **0.9.24/0.9.26 的老坑**：`census badge=[SBIconBadgeView|37x26|1:[SBDarkeningImageView|35x24]]`
  看起来「只有 1 个子视图、图就套在底板上」，于是修法围绕「清 ourHost 的底色/contents」。
- **1.0.7 实测的真病灶**：`our=UIImageView`、`bg=SBDarkeningImageView` —— 我们的图挂在**底板内部的
  子 image view** 上，`ourHost != bgView`。而 lift（把图搬到自己那层、把底板 `hidden`）的触发条件
  写的是 `ourHost == bgView`，于是 **lift 恒为 0**、底板永远 `shown`，双层永久留着。
- **教训**：`ourHost == bgView` 这种「假设两者同一」的判据，系统一改层级就失效。
  应该问「**我要的东西在不在这个子树里**」，而不是比视图相等。

**修法（1.0.7，已实测）**：
1. 判据改成「**底板的子树里找得到我们那张图**」（`TCPBadgeOurImageInSubtree(bgView)`）。
2. overlay 摆位用 **ourHost 在角标视图坐标系里的 frame**（`[ourHost convertRect:ourHost.bounds toView:view]`），
   不是底板的 frame —— 底板是铺满的暗化层，按它摆会让我们的图偏位。
3. 早退复检路径同样要从**底板子树**取新图（数字变了要同步），不能只读底板自身的 `image`。
4. 铁律不变：**拿不到我们的图就一个字节都不动**，绝不让角标变空白。

## ⑤ 验收（看诊断，不看屏幕）

| 字段 | 期望 | 含义 |
| --- | --- | --- |
| `sys{lift=N}` | **N > 0** | 搬图真的执行了（0 = 判据没通过，回去看 our/bg） |
| `sys{bg=…:hidden}` | hidden | 系统红底被藏起来 |
| `sys{tree=…*…}` | 有 `*` | 这一层真被清动过（`!` = 被藏） |
| `canvas=25x25` | 与 `asset=` 一致 | 单个数字圆形没被拉宽 |

1.0.7 实测：`canvas` 32x25 → **25x25**、`lift` 0 → **2**、`bg` shown → **hidden**、`tree` 出现 `*`。

装入 SpringBoard 的插件，注销后必须查 `apelin_crash_list process=SpringBoard` 无新报告。

## ⑥ 相关

- `injected-tweak-restart-app`：角标注入 SpringBoard，必须注销才加载。
- `respring-cross-team-notify` / `respring-confirm-via-island-popup`：注销要走弹窗让用户点头。
- `dynamic-icon-clock-calendar-theming`：同期修的时钟 / 日历动态图标。
- `subagent-change-review`：本轮的一条兜底建议正是只读复核线（5781b4c7）提出的。
