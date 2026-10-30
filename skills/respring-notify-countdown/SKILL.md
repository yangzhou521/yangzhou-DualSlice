---
name: respring-notify-countdown
description: 装 deb、注销（respring）、重启目标进程前，必须先让用户真的看见「5 秒后执行」并倒计时；离开 Apelin 取证后必须自己回到 Apelin；注销前先查崩溃循环，避免把 SpringBoard 打进安全模式。任何工程、任何对话都适用。
---

# 通知 + 倒计时 5 秒，取证后回 Apelin

**任何工程、任何对话都适用。** 用户 2026-10-30 反复要求过（原话：「下次你安装插件注销的话！给我通知📢一下！」
「说好的倒计时五秒钟通知呢！给我一点准备也没有」「这个影响到我正常使用手机了！很严重！会丢失数据的！」
「安全模式了！注销又没通知我！多少次了！」）。

## 零、为什么会「通知了但用户没收到」（2026-10-30 11:05 事故，必读）

那一次我确实调了 `apelin_notification_send` 并返回 Sent，然后注销 —— 用户仍然什么都没看到，
而且注销把 SpringBoard 打进**安全模式**。三条硬事实：

1. **通知只在 Apelin 不在前台时可见。** 用户正盯着 Apelin 聊天看你干活时，通知等于不存在。
   → 所以「5 秒后注销」这句话**必须写进聊天回复正文**，那才是用户一定会看到的唯一位置。
2. 写过正文还不算，要**真的等**：`sh scripts/respring-guard.sh 5`（或 `sleep 5`），再执行。
3. 注销前不查崩溃循环，就会把设备反复打成安全模式（那次 `consecutiveCrashCount=7`）。

## 一、两种动作，两种规矩

### A. 会让屏幕黑一下 / 打断用户当前操作的动作 —— 必须通知 + 倒计时 5 秒

- 安装 / 升级 deb：`irisin-cli install --yes --json /rootfs/var/mobile/Documents/<name>.deb`（root）
- 注销：`icli sb respring`
  **本机没有 `icli respring`**（2026-10-30 实测报 `Unexpected argument 'respring'`），只有 `icli sb respring`。
  Apelin 的 `apelin_device_respring`、`apelin_package_confirm_loaded`（`respring: true`）同样算注销。
- 重启目标进程：`icli app kill <bundle-id> --force`

**固定四步，顺序不能变：**

1. **前置检查（新增，最重要）**：`apelin_crash_list`（process 填目标进程，如 SpringBoard），
   读最新报告的 `consecutiveCrashCount` 与崩溃栈。
   - ≥2，或这次启动就崩过 → **不许注销**。先把插件停用（关功能 / 把 dylib 改名 / 卸载），
     确认新进程不会再崩，再按下面三步走。
   - 刚装上的包还没验证过不崩 → 先别注销；要注销就在通知里写明「可能再进安全模式」。
2. `apelin_notification_send`：标题 ≤40 字，正文一两句说清「动了什么 + 为什么 + 下一步」，
   并**同时把「5 秒后注销」写进回复正文**（通知在 Apelin 前台时看不见）。
3. 真的等 5 秒：`sh scripts/respring-guard.sh 5` 或 `sleep 5`。走过场不算。
4. 才执行安装 / 注销 / 杀进程。

通知配额：每回合最多 3 条、间隔 ≥30 秒。一次动作链（装包 → 随后注销）第一条通知里就说清
「装完会注销」，注销前若已过 30 秒，再发第二条。

### B. 只是耗时、不动屏幕的动作 —— 不发通知

下载、云编译（GitHub Actions）、读诊断、改源码、跑 probe。发了只会变成噪音。

## 二、已经进了安全模式怎么办

- 安全模式 = 目标进程崩过，ellekit 的 MobileSafety 起了一份不加载 tweak 的进程。
  此时**不要反复注销重试**，每试一次都是一次黑屏 + 一次崩溃。
- 顺序永远是：读崩溃报告（`apelin_crash_*` 或 `/var/mobile/Library/Logs/CrashReporter`）→ 定位 → 改代码
  → 云编译 → 装 → 才注销。
- 需要立刻让用户手机恢复可用：把插件 dylib 临时改名（root），注销一次；修好后再改回。
- 汇报时把崩溃栈的关键几帧抄给用户看，并说清「这次注销后会不会再进安全模式」。

## 三、离开 Apelin 取证，必须自己回来

- 单次外出 ≤60 秒；不需要看屏幕的长步骤（编译、下载、装包）不占屏幕。
- 回程写在 `trap EXIT/INT/TERM` 里，报错、超时、Ctrl-C 都会回。
- 末尾用 `icli app frontmost` 校验并打印「回到 Apelin: <前台 bundle-id>（外出 N 秒）」。
- 现成脚本：`sh scripts/errand-in-app.sh <bundle-id> [秒] [要点的元素文字]…`
- 点元素用 `icli ui tap "<文字>"`，不要用坐标（列表里跑偏过）。
- 汇报里写清这次外出多少秒。

## 四、汇报要求

在回复里写清：通知了什么、正文里有没有写「5 秒后」，倒计时了没有，查崩溃了没有，外出多少秒。
没做就明说没做，别含糊。
