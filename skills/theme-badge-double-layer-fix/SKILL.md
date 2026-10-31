---
name: theme-badge-double-layer-fix
description: 越狱主题插件的角标「双层/不正确显示」怎么查怎么修：先分清 badge{look=0}（背景站，iOS 16.7 无此方法，恒 0）与 txt{}（成图站，才是真在用），再看 sys{tree=…*,host=} 判断系统底板清没清；含 ourHost 只跳清 contents、两路独立失败计数、8 次放弃闸等做法。
---

# 角标「双层 / 不能正确显示」怎么查怎么修

适用：越狱主题类插件（SnowBoard / IconBundles / ThemeCore 类）给桌面图标角标换素材后，
用户说「角标是两层」「角标不对」「角标还是系统红底」。本机实测环境：iPhone10,1 / iOS 16.7.16 / roothide。
参考实现：`ThemeCorePlus/Sources/ThemeCorePlusBadges.m`（0.9.24 / 0.9.26 两轮）。

## ① 背景（用户原话与现象）

- 2026-10-31 用户：「一个图标二层、一个图标一层」「角标加载异常」——屏幕上一个角标格里
  **系统纯色底板 + 主题底板**叠在一起；我们的透明玻璃底板明明画上了，底下却压着系统红底。
- 同时存在一个误判陷阱：诊断里 `badge{look=0,hit=0}` 很容易被当成「主题角标素材一次都没被用上」。

## ② 触发条件

读到诊断串里有 `badge{…}` / `txt{…}` / `sys{…tree=…}`，且用户抱怨角标显示不对时，先读本技能再改代码。

## ③ 做法

### 第一步：先分清三个计数，别被 `badge{look=0}` 误导

角标有三站，各自有独立计数（`Badges.m` 里的 `sBadgeBackLook/…Tuple…/…Text…`）：

| 诊断字段 | 对应站 | iOS 16.7 实测 |
| --- | --- | --- |
| `badge{}` / `bg{}` | 角标**背景站**（`TCPSiteKindBadgeBackground`） | **恒为 0** —— 这台系统根本没有那两个方法，不是「素材没接上」 |
| `tup{}` | 角标**元组站**（`_checkoutImageForText:font:highlighted:` 返回的 tuple） | 0 —— 本机不走这条路 |
| `txt{}` | 角标**成图站**（BadgeTextImage，主题底板+数字整图） | **真正在用的那条**，实测 `txt{look=133,hit=133}` |

判断素材有没有接上，看 `txt{}` 与 `asset=`：
- `asset=25x25` ← 成图站用的素材尺寸。核对主题文件：`file` 命令看 `SBBadgeBG@3x.png`
  应是 75×75 px（@3x = 25pt），与诊断吻合即素材正常。
- 主题里的角标素材可能放在 `Bundles/<bundleid>/SBBadgeBG@3x.png`（Anemone 风格）或
  主题根目录（SnowBoard 风格）。索引链：`Store.m` 把 `Bundles/<bundleid>/` 下非 icon 的图
  按文件名收进 namedMap（`SBBadgeBG@3x` → `sbbadgebg`），`badgeBackgroundImageForScale:` 走
  `imageForNamedAsset:@"SBBadgeBG"` 取到。取到就说明**接线是通的**。

### 第二步：确认双层的真正病灶（本机结构）

诊断 `census badge=[SBIconBadgeView|37x26|1:[SBDarkeningImageView|35x24]]` —— 每格角标
**只有 1 个子视图** = `backgroundView`（`SBDarkeningImageView`，系统红底），
**我们的整图就套在它身上**（不是它内部的 UIImageView）。

于是清理逻辑里那句 `if (target == ourHost) continue;` 会把整只 view 让开 →
系统底板永远留着 → 双层。**这是「ourHost 从未被清过底色」，不是「清理逻辑从未生效」。**

### 第三步：0.9.24 的三处修法（`Badges.m`）

1. `target == ourHost` **只跳过「清 image / 清 layer.contents」**（碰这两样会清掉我们自己的图），
   `backgroundColor` 与 `layer.backgroundColor` **照清**。
2. 只有 `cleared > 0`（真清动过）才挂「已收拾」标记；没清动就留给下一次布局重试 ——
   原来无条件挂标记，而系统底板是**延迟绘制**的，于是「第一次扫时还没画上来」的格子永久双层。
3. 重试要有上限，但**两条失败路径要用两个独立计数键**：
   - `TCPBadgeMissImageKey`：等不到我们的图（看到图就归零）；
   - `TCPBadgeStuckKey`：看到了却清不动（真清动才归零）；
   连续 8 次无进展才放弃（`TCP_BADGE_GIVE_UP`）。
   **绝不在 `setText:` / `didMoveToWindow` 里清零**：那两处在滚动/复用时频繁触发，
   一清零闸门永远开着，等于恢复每帧全扫的发热（用户「特别卡、发热烫手」）。

### 第四步：0.9.26 的续作

0.9.24 只清了 ourHost 的**底色**；若系统红底其实画在 `layer.contents` 里仍会留着。
补一步：ourHost 本身是装着我们那张图的 `UIImageView` 时，连 `layer.contents` 一起清 ——
UIKit 会按 `image` 重新渲染，我们的图不会丢。并加计数 → 诊断 `sys{…,host=N}`。

### 若仍双层：第二轮「图另挂兄弟视图」

把我们的图另挂一个兄弟 `UIImageView` 到 `SBIconBadgeView` 上，再把 `SBDarkeningImageView`
整个 `hidden = YES`。判据要加一条「搬完我们的图仍在树里」（`sawOurs` 复检），
否则宁可不搬 —— 不许出现角标空白。

## ④ 验收 / 证据

- `sys{…tree=…*…}` 出现 `*` = 这一层真被清过（`*` = touched，`!` = 被藏）。
- `sys{…host=N}` 的 N > 0 = contents 那一步真的执行了。
- `txt{look>0,hit>0}` = 成图站在干活（别拿 `badge{}` 判断）。
- `skip=` 不再暴涨（暴涨 = 大量布局撞在「已收拾」早退上）。
- 屏幕：角标只剩主题那一层，底下没有系统红底。
- 装入 SpringBoard 的插件，注销后必须查 `apelin_crash_list process=SpringBoard` 无新报告。

## ⑤ 与其他技能的关系

- `injected-tweak-restart-app`：注入型插件改完不必注销桌面；但**角标这条注入的是 SpringBoard**，
  必须注销才加载新版本。
- `respring-cross-team-notify`：注销要走四步（发全员通知 → 正文写清 → 弹窗 → 用户点头）。
- `a11-roothide-ondevice`：本机环境与云编译（双切片、CI 出包、deb-guard 装包）流程。
- `tweak-skill-capture-standard`：本技能按它的结构写；同类问题先读后写、别复读。
- 专项案例复盘见仓库 `docs/cases/`。

**状态说明**：0.9.24 与 0.9.26 均已云编译出包（CI run 41168497476 / 41171106635），
**但截至 2026-10-31 13:1x 尚未装机验证** —— 装机与注销由统一调度台排期，装后按上面三条验收。
