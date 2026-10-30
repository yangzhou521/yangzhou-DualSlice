---
name: injected-tweak-restart-app
description: 注入型插件（tweak）装好或改完后先别注销桌面：把目标 App 后台划掉再打开（或 icli app kill + app launch）就完成注入立即生效；只有插件本身注入 SpringBoard 时才需要注销，且注销要走通知+5秒+对话协调。任何工程、任何对话都适用。
---

# 注入型插件：灭掉 App 重开就生效，不必注销桌面

**用户 2026-10-30 21:24 原话（硬性规定，所有工程、所有对话、永久适用）：**
「这些注入型的插件在安装后 划掉后台重进软件和插件内就能实现功能完全注入！不必重新注销桌面！
这个常识写进硬性规定、记忆和技能包内！并同步到云端！以后所有的对话和工程在工作时想要注销的时候
看看这个常识性的知识！这些注入型的插件划掉后台重进软件和插件内就立即生效！」
**用户 2026-10-30 21:34 再次强调（构建 / 修改 / 修复 / 编译插件时也先看这条）：**
「构建、修改、修复、编译插件的时候看看这个常识性的知识！」

## 为什么

tweak 的 dylib 是**进程启动时**由 dyld / ellekit 按过滤器（`Support/<Tweak>.plist` 的 Filter）
加载进目标进程的。已经跑着的进程不会因为磁盘上的 dylib 变了就重新加载 —— 但也**不需要**注销整台
SpringBoard 才能读到新代码：只要那个进程重开一次就够了。注销会黑屏、打断用户、可能进安全模式，
是成本最高的一步。

| 改动落在哪 | 怎么生效 | 要注销吗 |
| --- | --- | --- |
| 注入 App 的 tweak（微信、备忘录、设置…） | 划掉那个 App 再打开 | **不用** |
| 设置面板（PreferenceBundles bundle / Root.plist / 面板代码） | 退出「设置」再进 | **不用** |
| 只改了偏好的默认值 / 读取逻辑 | 重开目标 App | **不用** |
| 注入 SpringBoard 的 tweak（桌面图标、HUD、控制中心…） | — | **要**（走通知 + 5 秒 + 对话协调） |
| 改过滤器 plist、改包布局（装到别的目录）、换 install_name | 对应进程重开 | App 层不用；SpringBoard 层要 |

## 标准做法

1. 装包完成后先**别** respring。
2. 重开目标进程：
   - 命令行：`icli app kill <bundle-id> --force` → `icli app launch <bundle-id>`
   - 或让用户自己上划划掉那个 App，再点开。
   - 设置面板：退出设置再进（`icli app kill com.apple.Preferences --force` 也行）。
3. 验证：读该 App 域里的诊断键，确认版本号/计数变了，例如
   `icli prefs read <bundle-id> <Tweak>Diagnostics` → `v1.2.0;…`。
   这才是「注入成功」的证据，不是屏幕黑没黑。
4. 只有目标进程本身就是 SpringBoard，或改的是 SpringBoard 侧的钩子/过滤器，才走注销：
   先 `cross-chat-coordination`（查全部工程与对话、别打断它们）→ `apelin_notification_send`
   → 回复正文写「5 秒后执行」→ `sh scripts/respring-guard.sh 5 <标签>` 真等 → 才 `icli sb respring`。
   细则见技能 `respring-notify-countdown`。
5. `icli app kill` 仍是「重启目标进程」，用户在别的对话里可能正在测同一个 App：杀之前扫一眼
   `apelin_conversation_list`，必要时打招呼；杀自己的目标 App 不必等 5 秒，但要在正文说一句。

## 汇报

回复里写：重启了哪个进程、读了哪个诊断键、看到什么值（版本号变没变）。没重开就说没重开。
