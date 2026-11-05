---
name: respring-confirm-via-island-popup
description: 注销、装包、请开 VPN 需要用户确认时怎么在屏幕上弹窗：装包与注销已彻底分家（2026-11-05 用户定「装包不注销，装完弹窗由我决定」）、install-deb.sh 只放行装包、post-install-respring.sh 单独问注销、respring-guard.sh 的 --ask 用法、倒计时 5 秒、为什么不能只在对话里等文字回复。
---

# 注销 / 装包 / VPN：一律屏幕弹窗

用户 2026-10-31 21:26 硬指令原话：「注销装包VPN弹窗」。
用户 2026-11-05 22:57 改规矩原话：「你可以装包不注销的以后都这样 装包后直接给我弹窗 我来决定注销不注销！」

**铁律：这三类事情没有任何"跳过弹窗"的路径，不许只在对话里等文字回复。**

## 零、装包与注销彻底分家（2026-11-05 22:57 起，最新规矩，优先于下文旧描述）

以前一次弹窗把「装包」和「注销」捆死，用户想攒几条线一起注销就没得选。现在是**两步**：

1. **只装包**：`sh scripts/install-deb.sh <deb> "<标签>"`
   - 正常环境打印 `INSTALL_OK` → 调用方立刻 `irisin-cli install --yes --json <deb>`（root），**不弹窗、不注销**。
   - 安全模式打印 `SAFEMODE_DIRECT` → 同样**只装不注销**，装完用正文 + `apelin_notification_send` 告知。
2. **装完再问**：`sh scripts/post-install-respring.sh "<标签>" 120`
   - `REVIVE_CONFIRMED` → 用户点了「立即注销」→ 调用方 5 秒倒计时 + `sbreload`；
   - `NO_RESPRING` → 用户点「稍后」或超时 → **什么都不做，绝不自动注销**；
   - `SAFEMODE_QUIET` → 弹窗显示不出来，只走正文 + 系统通知。

**绝对禁止**：装完包自己 `sbreload`；拿「装包就等于要注销」当理由催用户点头。
用户可能正攒着几条线一起注销，擅自重启会打断别人的活。

## 一、注销 / 弹窗：`scripts/respring-guard.sh`

### 三种调用

| 用法 | 行为 |
| --- | --- |
| `sh scripts/respring-guard.sh 5 标签` | 只警告：屏幕胶囊 + 终端，**退出码 3，什么都不做** |
| `sh scripts/respring-guard.sh --ask 5 标签` | **弹确认框**，用户点「立即注销」→ 倒计时 → `sbreload`；取消=4 / 超时=5 |
| `sh scripts/respring-guard.sh --ask 5 --install <deb> 标签` | 旧的「一次点击搞定装包+注销」——**2026-11-05 起不再默认用**，只在用户明确要求「装了就注销」时用 |

**`--confirm` 已经不再跳过弹窗**（2026-10-31 21:26 起）：它现在等价于 `--ask`，保留只为老脚本不报错。

### 旧的一步式（仅在用户明确要求时）

```sh
sh scripts/respring-guard.sh --ask 5 --install /rootfs/var/mobile/Documents/xxx.deb "装 1.0.8"
```

弹窗 → 用户点「立即注销」→ 倒计时 5 秒 → 脚本打印 `CONFIRMED` 退出 0。脚本自己不装包，
调用方紧接着 `irisin-cli install --yes --json <deb>`（root）+ `sbreload` + 查崩溃。

### 倒计时时长

**5 秒**（用户 21:22「原来是5秒的继续5秒」）。不要擅自改成 10 秒。

## 二、VPN：`scripts/vpn-guard.sh`

```sh
sh scripts/vpn-guard.sh 20 "push 失败，需要开 VPN"
```

- 不做任何设备动作，只把「要不要开 VPN」搬到屏幕上。
- 退出码：`0`=确认开 VPN / `4`=取消 / `5`=超时 / `6`=请求写不出去（多半没装 CountdownHUD）。
- 借用同一个 `?` 弹窗，标签里要写清楚要确认的是什么。

**什么时候才弹它**：按 `notify-before-git-push`，要 push 时**先自己直接试 push**；
通了就直接干、只发胶囊「已推送」，**不通才**弹这个窗。绝不在 push 前就让用户先开 VPN。

## 三、实现细节

- 请求文件：`/rootfs/var/mobile/Library/Preferences/.countdownhud-request`，内容 `<epoch>|<秒数>|<标签>[|<sid>]`；
  `!` = 纯文案、`?` = 确认弹窗。
- 答案文件：同目录 `.countdownhud-answer`，`<epoch>|confirm|cancel|timeout`；
  **只认 epoch ≥ 本次请求**的答复，防止读到上一次的旧答案。
- 依赖 CountdownHUD 1.5.0+；没装时 `?` 写不出去 → 退出码 6，只能退回对话里说明。
- 弹窗的「立即注销」按钮在 1.6.1+ 会由插件自己 `spawn sbreload`；
  `--install` 模式必须同时用 `RESPRING_GUARD_NO_RESPRING=1` 避免插件抢先注销。

## 四、边界

- 「使用屏幕前询问」开着时，每条 `icli` 还会额外弹 Apelin 的系统卡；这个开关只有用户能关。
- 弹窗超时 = 什么都不做，绝不自动继续。取消 = 什么都不做。
- 用户点完了，**正文仍要写清「为什么 / 多久 / 下一步」** —— 弹窗只解决"让他在屏幕上选择"，不替代说明。

## 相关

- `respring-notify-countdown`：CountdownHUD 的技术细节与胶囊渲染判据。
- `notify-before-git-push`：push 与 VPN 的先后顺序。
- `notify-any-screen`：胶囊跨界面的用法。
