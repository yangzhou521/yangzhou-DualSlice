---
name: respring-notify-countdown
description: 装 deb、注销（respring）、重启目标进程前必须先给用户发 Apelin 通知并倒计时 5 秒再执行；离开 Apelin 取证后必须自己回到 Apelin。任何工程、任何对话都适用。
---

# 装包 / 注销 / 重启进程前的通知与倒计时

**任何工程、任何对话都适用。** 用户 2026-10-30 要求过两次，仍然漏过两次（原因是这条只写在记忆里，
不是每个会话都会读到），所以做成技能。

## 什么时候必须做

只要动作会让屏幕黑一下，或者打断用户正在做的事：

- 安装 / 升级 deb：`irisin-cli install`
- 注销：`icli respring`、`apelin_device_respring`、`apelin_package_confirm_loaded`（`respring: true` 也算注销）
- 重启目标进程：`icli app kill <bundle-id> --force`

下载、云编译、读诊断、改源码**不算**，不发通知（否则通知会被当成噪音）。

## 固定三步，顺序不能变

1. `apelin_notification_send`：标题不超过 40 字，正文一两句，说清「动了什么 + 为什么 + 下一步」。
2. 在回复里明说「5 秒后注销」，然后**真的等 5 秒**（`sh scripts/respring-guard.sh 5` 或 `sleep 5`）。
   走过场不算。
3. 才真正执行安装 / 注销 / 杀进程。

## 本工程（yangzhouDualSlice / ThemeCorePlus）的固定写法

```sh
# 第 1 步用工具：apelin_notification_send（脚本发不了通知）
# 第 2 步：倒计时 + 注销（本工程唯一注销入口）
sh scripts/respring-guard.sh 5
# 装包（root:true；同样先通知、再倒计时）
irisin-cli install --yes --json /rootfs/var/mobile/Documents/<name>.deb
```

`respring-guard.sh` 会打印 5→1 再 `icli respring`；不许绕过它直接 `icli respring`。

## 收尾：离开 Apelin 取证后必须自己回来

去设置或别的 App 取证，一律用 `sh scripts/errand-in-app.sh <bundle-id> [秒] [元素文字]…`：
回程写在 `trap EXIT/INT/TERM` 里，单次外出 ≤60 秒，末尾用 `icli app frontmost` 校验并打印秒数。
绝不要求用户手动切回 Apelin。

## 汇报时

在回复里写清这次外出了多少秒、注销前通知了什么。没做就明说没做，别含糊。
