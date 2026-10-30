---
name: respring-notify-countdown
description: 装 deb、注销（respring）、重启目标进程前必须先给用户发 Apelin 通知并倒计时 5 秒再执行；离开 Apelin 去别的 App 取证后必须自己回到 Apelin。任何工程、任何对话、任何设备操作都适用。
---

# 通知 + 倒计时 5 秒，取证后回 Apelin

**任何工程、任何对话都适用。** 用户 2026-10-30 三次要求过（原话：「下次你安装插件注销的话！给我通知📢一下！」
「说好的倒计时五秒钟通知呢！给我一点准备也没有」「这个影响到我正常使用手机了！很严重！会丢失数据的！」）。
漏过的原因：这条只写在记忆里，不是每个会话都会读到 —— 所以现在是技能 + 工程 AGENTS.md 双重写死。

## 一、两种动作，两种规矩

### A. 会让屏幕黑一下 / 打断用户当前操作的动作 —— 必须通知 + 倒计时 5 秒

- 安装 / 升级 deb：`irisin-cli install --yes --json /rootfs/var/mobile/Documents/<name>.deb`（root）
- 注销：`icli sb respring`
  **本机没有 `icli respring`**（2026-10-30 实测报 `Unexpected argument 'respring'`），只有 `icli sb respring`。
  Apelin 的 `apelin_device_respring`、`apelin_package_confirm_loaded`（`respring: true`）同样算注销。
- 重启目标进程：`icli app kill <bundle-id> --force`

**固定三步，顺序不能变：**

1. `apelin_notification_send`：标题 ≤40 字，正文一两句说清「动了什么 + 为什么 + 下一步」。
   通知只在 Apelin 不在前台时可见；Apelin 在前台时，同一段话同时写进回复。
2. 回复里明说「5 秒后注销」，然后**真的等 5 秒**：`sh scripts/respring-guard.sh 5`（工程里有这个脚本）或 `sleep 5`。
   走过场不算。
3. 才执行安装 / 注销 / 杀进程。

通知配额：每回合最多 3 条、间隔 ≥30 秒。一次动作链（装包 → 随后注销）可以第一条通知里就说清
「装完会注销」，注销前若已达 30 秒，再发第二条。

### B. 只是耗时、不动屏幕的动作 —— 不发通知

下载、云编译（GitHub Actions）、读诊断、改源码、跑 probe。发了只会变成噪音。

## 二、离开 Apelin 取证，必须自己回来

任何工程都一样：去设置或别的 App 看屏幕、点元素、截图，回来这一步由我自己做，绝不要求用户手动切回
（用户 2026-10-30：「不要再让我手动回来」）。

- 单次外出 ≤60 秒；不需要看屏幕的长步骤（编译、下载、装包）不占屏幕。
- 回程写在 `trap EXIT/INT/TERM` 里，报错、超时、Ctrl-C 都会回。
- 末尾用 `icli app frontmost` 校验并打印「回到 Apelin: <前台 bundle-id>（外出 N 秒）」。
- 本工程现成脚本：`sh scripts/errand-in-app.sh <bundle-id> [秒] [要点的元素文字]…`
  —— 一次调用就把证据（截图 + `icli ui tree`）带回来。
- 点元素用 `icli ui tap "<文字>"`，不要用坐标（列表里跑偏过）。
- 汇报里写清这次外出多少秒。

## 三、汇报要求

在回复里写清：这次通知了什么、倒计时了没有、外出多少秒。没做就明说没做，别含糊。
