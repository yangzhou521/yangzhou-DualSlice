---
name: icli-status-self-check
description: 用户 2026-10-30 16:30 授权「icli 状态以后你自己查，给你全权限」：凡是需要设备/插件/云端此刻状态的事，一律自己动手查完再汇报，不把查询推回用户；装包、注销、杀进程仍必须先通知并倒计时 5 秒。任何工程、任何对话都适用。
---

# 设备状态自己查，不问用户（全权限）

用户 2026-10-30 16:30 原话：「icli状态以后你自己查 给你全权限」。**适用于每一个对话、每一个工程。**

## 一句话规矩

凡是「要设备/插件/云端此刻的状态才能决定下一步」的事，一律**自己动手查完再汇报**：
不把查询推回用户、不问「你能看一下吗」、不让他替我截图或读屏、不来回确认同一件事。
一次查不到就换一条路（换命令、换域、换探针），不是回头问。

## 不必问、直接查的范围

- **插件状态**：`icli prefs read <域> <诊断键>`（如 `com.apple.springboard ThemeCorePlusDiagnostics`）、
  `icli prefs read/write/delete`（写偏好也算日常动作，但写完要看效果）、`icli prefs domains`。
- **进程与前台**：`icli app frontmost`、`icli app list`、`icli proc …`、`icli ps` 之类的**读**动作。
- **包的状态**：`irisin-cli list` / `irisin-cli show <pkg>`、读 `/var/lib/dpkg/status`、
  比对已装文件与包内文件（`cmp`）。
- **文件与下载**：`icli probe` 跑脚本用 `NSData` 拉云端资产并校验（大小、`sha256sum`、`cmp`）、
  列目录、读 plist、`grep -a` 抽二进制字符串。
- **界面证据**：`icli button home`、`icli app launch <bid>`、`apelin_screen_read_tree`、
  `icli ui tree`（受下面的「屏幕开关」约束）。
- **云端状态**：GitHub API 读 workflow run 状态、check-run annotations、Release 资产清单
  （本机没有 curl/python3，用 `apelin_web_fetch` 或 `icli probe`+`NSData`）。
- **本机环境**：路径、jbroot 哈希、可用工具、磁盘、偏好域内容——先查再说话，不凭记忆断言。

## 全权限不等于免仪式（不变的三条）

1. **装包**（`irisin-cli install`）、**注销**（`icli sb respring`）、**重启目标进程**
   （`icli app kill … --force`）之前：先 `apelin_notification_send`（短标题＋一两句：装了什么 /
   为什么注销 / 下一步），聊天正文写明「5 秒后执行」，再 `sh scripts/respring-guard.sh 5 <标签>`
   真等 5 秒，然后才动手。
2. **离开 Apelin 取证**（桌面 / 插件设置内 / 别的 App）单次硬上限 60 秒，目标 15~30 秒，
   出去前一句预告、回来一句交代秒数，`trap` 里强制 `icli app launch wiki.qaq.apelin`。
3. **截图**每次都要用户当次明确同意（会连他屏幕上的其他内容一起截走）。

## 边界

- **Ask Before Using the Screen** 开着时，Apelin 自己的卡片仍会为读屏/交互/每条 icli 命令询问：
  那是用户的开关，**只能他自己在设置里关，我不代关**；卡来了正常走，不要因此反复解释。
- 仍然不碰：系统关键设置、别的包的删除/降级、Apelin/Irisin/引导自身的包。
- 「自己查」也包括**自己查错**：命令报错先自己换写法重试，再把结论和证据一起写进汇报，
  不把原始报错原样丢给用户当问题。
- 汇报里写清**我实际查到了什么**（命令结论、诊断串关键字段），不写「应该」「大概」。
