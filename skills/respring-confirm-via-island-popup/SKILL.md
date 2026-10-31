---
name: respring-confirm-via-island-popup
description: 注销、装包、请用户开 VPN 需要用户确认时怎么在屏幕上弹窗：respring-guard.sh 的 --ask/--install 用法、--confirm 已不再跳过弹窗、vpn-guard.sh 的用法与退出码、倒计时 5 秒、以及为什么不能只在对话里等文字回复。用户 2026-10-31 21:26 硬指令「注销装包VPN弹窗」。
---

# 注销 / 装包 / VPN：一律屏幕弹窗

用户 2026-10-31 21:26 硬指令原话：「注销装包VPN弹窗」。
用户 21:28 在「一次弹窗」与「两次弹窗」之间选了 **A：一次弹窗搞定装包+注销**。

**铁律：这三类事情没有任何"跳过弹窗"的路径，不许只在对话里等文字回复。**

## 一、注销 / 装包：`scripts/respring-guard.sh`

### 三种调用

| 用法 | 行为 |
| --- | --- |
| `sh scripts/respring-guard.sh 5 标签` | 只警告：屏幕胶囊 + 终端，**退出码 3，什么都不做** |
| `sh scripts/respring-guard.sh --ask 5 标签` | **弹确认框**，用户点「立即注销」→ 倒计时 → `sbreload`；取消=4 / 超时=5 |
| `sh scripts/respring-guard.sh --ask 5 --install <deb> 标签` | **一次点击搞定装包+注销**（见下） |

**`--confirm` 已经不再跳过弹窗**（2026-10-31 21:26 起）：它现在等价于 `--ask`，保留只为老脚本不报错。
原因：`--confirm` 历史上被用来「用户口头答应了就直接注销」，用户明确要求改成一律弹窗。

### 装包 + 注销一次完成（推荐用法）

```sh
sh scripts/respring-guard.sh --ask 5 --install /rootfs/var/mobile/Documents/xxx.deb "装 1.0.8"
```

流程：弹窗 → 用户点「立即注销」→ 倒计时 5 秒 → 脚本打印 `CONFIRMED` 并退出 0。
**脚本自己不装包**（它是 mobile，`irisin-cli` 要 root），所以调用方要在同一回合接着：

1. `irisin-cli install --yes --json <deb>`（`root: true`）
2. `sbreload`
3. 查 `apelin_crash_list process=SpringBoard` 无新报告

用户全程**只点一次**。

### 倒计时时长

**5 秒**（用户 21:22「原来是5秒的继续5秒」）。不要擅自改成 10 秒 —— 试过一次被要求退回。

## 二、VPN：`scripts/vpn-guard.sh`

```sh
sh scripts/vpn-guard.sh 20 "push 失败，需要开 VPN"
```

- 不做任何设备动作，只是把「要不要开 VPN」搬到屏幕上。
- 退出码：`0`=确认开 VPN / `4`=取消 / `5`=超时 / `6`=请求写不出去（多半没装 CountdownHUD）。
- 借用同一个 `?` 弹窗（按钮文案是插件固定的，所以**标签里要写清楚要确认的是什么**）。

**什么时候才弹它**：按 `notify-before-git-push`，要 push 时**先自己直接试 push**；
通了就直接干、只发胶囊「已推送」，**不通才**弹这个窗。绝不在 push 前就让用户先开 VPN。

## 三、实现细节（改这个脚本时要知道）

- 请求文件：`/rootfs/var/mobile/Library/Preferences/.countdownhud-request`，内容 `<epoch>|<秒数>|<标签>[|<sid>]`；
  `!` = 纯文案、`?` = 确认弹窗。
- 答案文件：同目录 `.countdownhud-answer`，`<epoch>|confirm|cancel|timeout`；
  **只认 epoch ≥ 本次请求**的答复，防止读到上一次的旧答案。
- 依赖 CountdownHUD 1.5.0+；没装时 `?` 写不出去 → 退出码 6，这时只能退回对话里说明。
- 弹窗的「立即注销」按钮在 1.6.1+ 会由插件自己 `spawn sbreload`；
  `--install` 模式必须同时用 `RESPRING_GUARD_NO_RESPRING=1` 的思路**避免插件抢先注销**，
  否则会在装包之前就注销了（装了个旧包）。

## 四、边界

- 「使用屏幕前询问」开着时，每条 `icli` 还会额外弹 Apelin 的系统卡；这个开关只有用户能关。
- 弹窗超时 = 什么都不做，绝不自动继续。取消 = 什么都不做。
- 用户点完了，**正文仍要写清「为什么 / 多久 / 下一步」** —— 弹窗只解决"让他在屏幕上选择"，不替代说明。

## 相关

- `respring-notify-countdown`：CountdownHUD 的技术细节与胶囊渲染判据。
- `notify-before-git-push`：push 与 VPN 的先后顺序。
- `notify-any-screen`：胶囊跨界面的用法。
