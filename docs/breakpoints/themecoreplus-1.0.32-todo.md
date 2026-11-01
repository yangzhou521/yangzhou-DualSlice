# ThemeCorePlus 待办总表（2026-11-01 22:45 登记）

> 用户要求：今天要彻底一次性解决所有问题。这份是唯一权威待办。
> 状态图例：`[ ]` 未做 / `[x]` 已做待验 / `[✓]` 已装机实测通过 / `[?]` 等第三方 AI

---

## A. 正在做（1.0.32 移植 AI 逆向结果）

| 项 | 根因（AI 逆向结论） | 状态 |
| --- | --- | --- |
| 日期墨层 | 四角透明（alpha=0）拖偏背景均值 → 白底被判成墨；改「近黑选数字」 | [ ] |
| 时钟类名 | iOS 14~16 是 `SBClockApplicationIconImageView`（**无 H**），`SBHClock…` 是 17+ | [x] 已改 |
| 文件夹 mini | 真入口是 `-[SBFolderIcon miniGridCellImageForIcon:]`，不在 `SBFolderIconImageCache` | [x] 已加站 |
| 角标底板 | iOS 16 底板不是图片，是 `backgroundColor=systemRed`，走 `layoutSubviews` | [ ] |

## B. 我自己搞定，不问 AI

| 项 | 做法 | 状态 |
| --- | --- | --- |
| 秒加载方法名 | `class_copyMethodList` dump `SBHIconImageCache` 家族，grep `Image/Request/perform/fetch` | [ ] |
| 缓存 purge 方法名 | 同上，grep `purge/clear/remove/invalidate` | [ ] |
| 1.0.31 编译失败 | `dyld_register_func_for_add_image` → **`_dyld_register_func_for_add_image`**（少前导下划线） | [x] 已修 |

## C. 等第三方 AI 给确切答案（已发问，4 条）

| # | 问题 | 状态 |
| --- | --- | --- |
| 1 | `+[UIImage _applicationIconImageForBundleIdentifier:format:scale:]` 的完整签名（参数类型/返回值/format 取值） | [?] |
| 2 | 若上条不存在，设置 App（Preferences 进程）换图标该挂哪 | [?] |
| 3 | 文件图标（UTI）在 SpringBoard 内的入口方法名（只有类名 `SBHFileStackIcon`/`SBHFileStackIconImageProvider`） | [?] |
| 4 | 与 Mikkyy 并存时如何不打架（检测已被挂过？串联 IMP？） | [?] |

## D. 覆盖面：要跟 Mikkyy 一样就得加注入进程（不是技术难题，是工作量）

现在只注入 SpringBoard，所以这些地方**不跟主题**：

| 进程 | 现象 | 状态 |
| --- | --- | --- |
| `com.apple.Spotlight` | 下拉搜索里的图标 | [ ] |
| `com.apple.ShareSheet` | 分享面板 | [ ] |
| `com.apple.Preferences` | 设置 App 内的图标 | [ ]（依赖 C-1/C-2） |
| QuickLook 相关 | 文件预览 | [ ] |
| `com.apple.iconservices` | 文件/UTI 文档图标（可能必须） | [ ]（依赖 C-3） |

已在 SpringBoard 内、同一条路：主屏、Dock、App 库、文件夹、App 切换器。

## E. 已知但未做（不是 bug，是没实现）

| 项 | 说明 | 状态 |
| --- | --- | --- |
| `TCPInstallFolderSites` 文件夹底板 | 函数写好了但**从未被调用**（死代码） | [ ] |
| App 切换器 | 依赖 B（秒加载）修好 | [ ] |

---

## 验收顺序（云编译装机后按诊断键看）

1. 日历：`dyn{...ink:w,inkdrop=...}` + 视觉：深色主题底上白字、不再被白底盖
2. 时钟：`dyn{clock}` 从 0 变非 0；`clockv{found}` 非 0；表盘是主题图、指针在走
3. 文件夹：`minicell{n>0,on=1}`；视觉：文件夹里小图标跟主题
4. 角标：只剩主题底板，无红底叠加
5. 秒加载：probe 文件 `/var/mobile/Library/Preferences/YzCacheProbe.txt`（移植后改名为 `TCPCacheProbe.txt`）

## 约束（别踩）

- 角标/图标主题化在用户 2026-11-01 12:00 被点名「基本修好、钉死」——本次只做**未覆盖的新路径**，不回退已通过的部分
- 设置面板 `Prefs/` 冻结，不动
- 装包、注销一律走弹窗 + 用户点头

---

## F. 用户 2026-11-01 22:58 点名要做（我先记着，后面做）

- **注入 `com.apple.iconservices` 的探针**：过滤器加这个进程，在里面 dump 全进程所有类里
  方法名带 `Icon`/`Image`/`Generate` 的，写到 `/var/mobile/Library/Preferences/TCPIconServiceProbe.txt`。
  **纯 dump、不挂任何 hook**（那个进程崩了全系统图标不显示）。
  目的：找出 iconservicesagent 里真正产出图标图的类+方法，判断要不要走 Mikkyy 那条资源层路线。

- **用户规定（已写三样）**：搞不定就直接说，由用户去找别的 AI 完成，不许硬撑浪费时间。
  AI 生成的文件会放在 `~/Documents/wiki.qaq.apelin/第三方ai分析生成文件/`，拿到后按文件落地。
