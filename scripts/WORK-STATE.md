# 工作断点台账（WORK-STATE）

**规则：任何一轮开工，第一件事读这里；任何一轮结束，最后一件事件更新这里。**
用户不会回顾对话历史——断点只在这个文件里。每条只写：目标 / 做到哪 / 下一步 / 卡谁。

---

## 当前主线：ThemeCorePlus 图标主题化覆盖（调度台 = 3d91f924，本线）

- **目标**：图标主题化全覆盖 + 日历/文件夹修好 + 秒加载。
- **做到哪**：
  - **1.0.37 已装并在跑**（dpkg=1.0.37、诊断 `v1.0.37;active=1`、无新崩溃）。
  - **日历墨层已生效**：`dyn{last=com.apple.mobilecal:60x60@2,base+ink,cov=0.78}` —— 1.0.37 之前只画底图，现在底图+墨层都画。
  - **布局保存已打通**：`lay{rst=0,sav=1,tick=337,hooked=2,model=adopt:iconModel}`（`SBHIconModel:_saveIconState` + `SBIconController -iconModel`）。
  - 安全模式已退出（1.0.36 修构造函数闸门；退出靠**完整关机重启**，sbreload/killall 在 roothide 上杀不动 SpringBoard）。
  - **CountdownHUD 1.6.7 已装未注销**（磁盘 dylib 10:57 新，SpringBoard 内存仍是 1.6.6）。
- **下一步**：
  1. **一次注销**让 HUD 1.6.7（两行长文字）生效 —— 需用户点头，先弹窗；
  2. 注销后重读 `TCPCacheProbe.txt`（第二遍）确认新增站点有没有 hit；
  3. 按 probe 定秒加载路线（缓存层 / 视图层 / 动态图标，**一次只改一条路线**）。
- **卡谁**：注销需用户点头；其余不卡。

## 别人在干的（不碰他的文件）

- **01db0a06（主线执行线）**：改 `ThemeCorePlusIcons.m`（日历墨层 `TCPCompositeCalendarInk`：保留星期红字、日期数字完整、底图明暗分别配色）+ `ThemeCorePlusFolders.m`（mini 文件夹，`foldernotify{n=0,last=nocache}` 拿不到 `SBFolderIconImageCache` 单例）。走云编译。

## 已冻结（不许动）

- 桌面图标主题化 + 角标（1.0.16 起冻结，用户 12:00 确认修好）。
- 时钟（用户 11-02 说「时钟不动」）。
- 生效叠加链保持 `[角标：透明玻璃, 液态玻璃.theme]` —— 用户 11-02 明令：**不要加别的主题覆盖自己补的素材**；420 个白图标 = 没补素材的 app，正常，不管。

## 悬置（用户点名才做）

- 长岛显示长文字（当前无此能力，文字长了只会缩字号）。
- 文件图标（UTI）覆盖、与 Mikkyy 并存、Spotlight/ShareSheet/QuickLook 进程覆盖。

## 规矩三样同步

`sh scripts/sync-all.sh` → `git_commit(all:true)` → `git_push`（AGENTS.md + skills/ + memory/）。
