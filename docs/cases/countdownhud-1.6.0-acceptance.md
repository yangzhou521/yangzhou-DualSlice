# 案例：CountdownHUD 1.6.0「点胶囊跳回发消息的对话」验收记录

时间：2026-10-31（设备 iPhone10,1 / iOS 16.7.16 / roothide）
插件：CountdownHUD 1.6.0（`com.yangzhou.countdownhud`）
产物：CI run 41155920001，commit `c5981b5b`，tag `countdownhud-v1.6.0`，deb 20780 B（arm64 + arm64e 双切片）

## 一句话

1.6.0 让灵动岛胶囊**可点**：带对话 id 的请求里，点胶囊直接 `openURL: apelin://conversation/<sid>`
跳回发消息的那条对话；不带 id 的老请求**照旧不吃触摸**。本机已装、已实测通过。

## 一、途中那个「矛盾」：磁盘已是 1.6.0，诊断还是 v1.5.0

现象：磁盘上的 dylib 明明是 1.6.0，`CountdownHUDDiagnostics` 却报 `v1.5.0`。

排查过并**排除**的可能：

| 猜想 | 实测 | 结论 |
| --- | --- | --- |
| 代码没编进去 | dylib 里 `grep -a` 得到 `1.6.0`、`link=%@;taps=%lu` | 排除 |
| 过滤器不匹配 | `Support/CountdownHUD.plist` 只含 `com.apple.springboard` | 排除 |
| 装了第二份同名 dylib | 全盘只有 jbroot 下那一份 | 排除 |
| 包版本没升 | `icli pkg list` → `com.yangzhou.countdownhud` 1.6.0 | 排除 |
| 诊断拼接写错 | 1.6.0 会写 `link=`/`taps=`，1.5.0 不会 | 排除 |

**真根因：SpringBoard 进程一直没重启。** 设备 boot time `1793337525`（10-30 13:18:45 CST），
SpringBoard PID 56743 已连续运行约 20.8 小时；而 1.6.0 的 dylib 是 10-31 09:34 才装进去的。
**注入型插件只在目标进程启动时加载**（见技能 `injected-tweak-restart-app`），所以老进程当然还跑 1.5.0。

推论（通用）：看到「磁盘是新版、诊断是旧版」，先查目标进程的启动时间，
别急着改代码或重装 —— 重装对已经跑着的进程毫无作用。

## 二、验收矩阵（`scripts/verify-countdownhud.sh --sid <对话 id>`，实测 10 项全过）

| # | 验证项 | 期望 | 实测 |
| --- | --- | --- | --- |
| ① | 诊断版本 | `v1.6.0`（shows 归零 = SpringBoard 换过新代码） | ✓ |
| ② | 带 `HUD_SID` 发纯文案 | 诊断 `link=<sid>`、`mode=plain` | ✓ |
| ③ | 点胶囊 | `taps` 0→1（胶囊真吃到这一下） | ✓ |
| ④ | 点胶囊后的前台 | 变成 Apelin（`apelin://conversation/<sid>` 生效） | ✓ |
| ⑤ | 不带 `HUD_SID` 再发 | 诊断 `link=none` | ✓ |
| ⑥ | 这时点胶囊 | `taps` 不变 —— 老行为没被改坏 | ✓ |
| ⑦ | 注销倒计时那条路 | 仍不可点（无 sid → 不吃触摸） | ✓ |
| ⑧ | 1.5.0 的 `?` 注销确认弹窗 | 没坏（`alerts=`/`ans=` 仍在，回归正常） | ✓ |
| ⑨ | `apelin_crash_list`（SpringBoard） | 无新报告 | ✓ |
| ⑩ | `--selftest` | 7 项解析自检全过（不碰设备） | ✓ |

脚本自身的三条坑（写脚本时踩的）：

1. `device.sh read` 有的版本直接打印诊断串、有的打印 JSON —— 要从 `"value"` 行取，别硬取第一行。
2. `icli app frontmost` 的字段是 **`bundle_id`**（不是 `bundleIdentifier`）。
3. 岛是 DynamicX 造的假岛，**宽度会变** —— 点屏幕的坐标要从诊断里的 `island=` 实时算，别写死。

## 三、机制要点（1.6.0 做了什么）

- 请求文件多一个**可选的第 4 段** = 对话 session id：`<epoch>|<秒数>|<标签>|<sid>`。
- 有 sid 时 `CHWindow` 的 `hitTest`/`pointInside` **只在胶囊自身矩形内**返回胶囊；
  屏幕别处照旧返回 nil 穿透 —— 不会因为这一改吃掉触摸。
- 点一下的顺序：**先收起胶囊，再 `openURL: apelin://conversation/<sid>`**。
- sid 只认「十六进制 + 连字符」形状（8~64 位），别的内容一律当没有（防拼出奇怪的 URL）。
- 诊断串末尾多了 `link=<sid>|none` 与 `taps=<累计点击次数>`；点一次 `taps` +1。
- `alerts=` / `ans=` 是 1.5.0 注销确认弹窗的延续，**不要删**。

用法：`HUD_SID=<对话 id> sh scripts/hud-notify.sh 8 "完成：<一句话>"`（不带 `HUD_SID` = 老的纯文案）。

## 四、未测试

- 点胶囊后是否**精确落在**那一条会话（只确认了前台变成 Apelin，没有截屏比对当前会话 id）。
- `?` 注销确认弹窗在**别的 App 前台**时的遮挡与生效情况。
