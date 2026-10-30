# SileoFix

修 SileoWallpaper 让 Sileo **「搜索软件包」输入框点不进去、键盘不弹**的问题。

- 病灶：SileoWallpaper 把源内页 / 软件源页的 `UINavigationBar` 设成
  `userInteractionEnabled = NO`，「搜索软件包」与「所有分类」都挂在这条导航栏上 → 整片死区。
- 修法：给 `UINavigationBar` 加 `hitTest:withEvent:` 旁路（点在它自己的搜索栏/控件上就接管，
  别处照旧穿透）。不改布局、不改 SileoWallpaper 的状态。
- 随包 `com.sileowallpaper.tweak` 一起安装，注入 `org.coolstar.SileoStore`；装完
  `icli app kill org.coolstar.SileoStore --force` + `icli app launch org.coolstar.SileoStore` 即生效（不用注销桌面）。
- 日志：Sileo 沙盒 `Caches/sileofix.log`（每次加载清空，首行 `loaded v…`）；
  统一日志 `icli log syslog --subsystem com.yangzhou.sileofix`。

**完整专项案例（症状、分轮取证、修法、复发处理流程、坑清单）：**
[`docs/cases/sileowallpaper-searchbar-fix.md`](../docs/cases/sileowallpaper-searchbar-fix.md)

> 下次这个插件（或 Sileo）更新后再出同类问题，先读上面那份案例的第 6 节。
