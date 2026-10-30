---
name: settings-switch-ui
description: 给越狱插件写「系统设置」面板（PreferenceLoader 面板、二级页）时使用：凡是有选择/开关的地方，一律用 iOS 原生 UISwitch（与设置里「启用插件」那颗同款），不许用对号/勾选标记；含多选列表用开关时的顺序语义与写法。
---

# 系统设置里的插件开关：一律用原生 UISwitch，不用对号

用户 2026-10-30 17:09 / 17:11 定的硬规矩，**适用于所有工程、所有对话**。原话：

> 插件面板的选择开关的按钮形状和 iOS 设置内的按钮保持一致！像启用插件开关一样！
> 以后凡是应用到系统设置的插件，全部插件的开关都是按钮开关！不要用对号！
> 不要用这个不好看不好用！

## 规定

插件只要挂在系统设置里（PreferenceLoader 面板，含二级页），**凡是有「选择」的地方，右端一律是 iOS 原生开关 `UISwitch`**：

- 观感必须与设置里「启用插件」那颗开关**完全一致**（同一个控件、同一种绿、同样的尺寸）。
- **明确不许用**：
  - `UITableViewCellAccessoryCheckmark`（对号）；
  - 自己画 / 贴图的对号、勾选框、圆点选中等自绘选择态；
  - `UITableViewCellAccessoryDetailButton`、`UITableViewCellAccessoryDisclosureIndicator` 之类拿来冒充「选上了」。
  - 灰色小字写状态（如「已选」）**不能代替开关**；状态文字可以有，开关不能少。
- 功能开关、单选、多选一视同仁：**全都是开关**。

## 怎么写

**用 PSSpecifier 的面板（PSListController 系）**：选项用 `PSSwitchCell`（`PSSpecifier` 的 `cell` 字段），
key 就是偏好键，行为与设置里的开关逐像素相同。别用 `PSLinkListCell` / `PSRadioGroup` 做多选或单选列表
—— 那正是对号那一套。

**纯 UIKit 的面板页（`UITableViewController` 等）**：把 `UISwitch` 放进 `cell.accessoryView`：

```objc
@interface XXSwitchCell : UITableViewCell
@property (nonatomic, strong, readonly) UISwitch *xxSwitch;
@end

@implementation XXSwitchCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        _xxSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
        self.accessoryView = _xxSwitch;   // 系统开关；不设 accessoryType（那就是对号）
    }
    return self;
}
@end
```

配套细节（都是踩过的）：

- **单元复用**：`cellForRow` 里每次先 `[cell.switch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];`
  再 `addTarget:`，否则拨一颗开关会连带触发别的行。
- **越界 / 无效行**：开关 `enabled = NO`、`on = NO`，别让人拨到空行。
- **行本体可点**：`didSelectRowAtIndexPath:` 应与拨开关**走同一个写入口**（用户习惯「点一下选上」）。
- **写入口唯一**：开关与点行都调同一个方法（如 `-xxxToggleItemAtIndex:`），里面读旧值 → 取反 → 写偏好
  → 发变更通知 → `reloadData`。
- **超限拒绝**：数量到上限时弹窗说明，并且**把开关拨回原位**（`reloadData`），不静默丢选择。

## 页面里只留「要开关的项目本身」

同一个用户要求（2026-10-30 17:1x）：「选择主题 里面只有主题项目，用来开关选择主题素材包！别的不要有！
别的功能默认开启！它们没素材既不生效也不加载！」——列表页面上**只放要开关的那些项目**：

- 段落标题、页脚说明、功能清单、诊断串、用法解释 **都不写**（面板正文不写功能说明，是同一个要求）。
- 别的功能**默认开启**就用默认值，不要在面板上摆一排开关让它开；没有素材时它自然什么都不做。
- 需要解释的规则（如「打开顺序 = 生效顺序」）宁可靠行副标题一句话，也不要在页面底部堆一段。

## 多选列表：顺序语义改为「打开顺序」

多选（例如 ThemeCorePlus 的多主题叠加）用开关后，语义写成**打开的顺序就是生效顺序**：靠后打开的盖住靠前的；
关掉开关 = 取消这一项。这条语义**不必写成页脚**——页脚按上一节的要求删掉了，用户在行副标题里看得到层级。
不要再用「勾选顺序」这种说法。

## 自检清单

- [ ] 面板里所有选项行右端都是 `UISwitch`，与设置里「启用插件」那颗观感一致（不是对号）。
- [ ] 全工程 `grep -i 'Checkmark|CheckMark'` 无命中。
- [ ] 点整行与拨开关行为完全一致，写入的是同一个偏好键。
- [ ] 复用单元不串行（removeTarget 到过位），越界行开关停用。
- [ ] 列表页除项目行之外没有多余文字（没有段落标题、没有页脚说明、没有功能清单）。

## 落地与凭据（本仓库）

- 本工程首个实例：`Prefs/ThemeCorePlusPrefs/TCRootListController.m` 的 `TCPThemeSwitchCell`（ThemeCorePlus 0.9.3 起）。
- 硬性规定同时写在工程 `AGENTS.md` 的「硬规矩」一节；全局记忆里也有一条。
- 本机技能目录 `~/Documents/wiki.qaq.apelin/skills/` 改动后跑 `sh scripts/sync-skills.sh` 推回
  `yangzhou521/yangzhou-DualSlice` 的 `skills/`，再 commit + push 到 `main`，两边必须一致。
