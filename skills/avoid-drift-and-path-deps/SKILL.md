---
name: avoid-drift-and-path-deps
description: 防止在修 ThemeCore 系越狱插件时跑偏和路径依赖：下结论前必须取证（od+awk 抽符号表）、改文件前先重读、一次只改一件事、改完对照 ThemeCore；路径只用三种写法（jbroot 运行时探测 / $APELIN_PROJECT_ROOT 相对路径 / 真根用户数据加 /rootfs），probe 读的文件放项目内 .tmp/ 不放 /tmp。任何改码、写结论、动路径前先读。
---

# 防跑偏 / 防路径依赖

用户 2026-11-06 00:33 复盘后写死，**不许再犯**。

## 一、跑偏的根因（这几轮实际犯的）

1. **把「推断」当「实证」**：没看 ThemeCore 二进制就断言它「挂站用后台队列」，其实是内存压力 source 用的；
   凭印象删了 `Enabled` 开关，它其实有 `_TCConfigurationEnabledKey` / `_TCReadConfiguration` / `isEnabled`。
2. **连续改同一文件不重读**：构造函数改好几次，每次都基于上一版，偏了没发现。
3. **一次改多件事**：把「回退延迟」和「删开关」混在一起，错一起犯。

## 防跑偏的四个动作（不是口号）

1. **下结论前必须取证**：说「ThemeCore 有/没有 X」之前，先 `od -c | awk` 抽一遍符号表看；
   没查就明说「我还没查，这是猜的」，**不许用猜测当结论写进代码或文档**。
   ```sh
   F=<dylib路径>
   od -c "$F" | awk '{for(i=2;i<=NF;i++){if($i ~ /^\\0/){if(s!=""){print s; s=""}else{next}} else {c=$i; gsub(/^[0-9]+$/,"",c); s=s c}}}' | sort -u
   ```
2. **改一个文件前先重读它**：不凭记忆改，`file_read` 重读当前内容再动手；改完读一遍 diff。
3. **一次只改一件事**：一个变量、一处逻辑、一条结论。改完验证再碰下一处；「顺手优化」一律不做。
4. **改完立刻对照 ThemeCore**：凡改了 ThemeCore 有对应物的东西（构造函数、开关、挂站、路径），
   改完拿符号表/实证再对一遍，确认是「它的做法」而不是「我的新发明」。

## 二、路径依赖的根因

1. 把 jbroot 绝对路径（`/private/var/containers/Bundle/Application/.jbroot-xxx`）写死进探针脚本。
2. 用 `/tmp` 放解包文件，但 `icli probe` 跑在自己的进程/沙箱里看不到 `/tmp` → 白扫。
3. 用户数据（`/var/mobile/...`）和引导数据（jbroot 内）混用，路径写错就误判「文件不存在 / 包没装」。

## 路径只有三种写法（别的都错）

1. **代码**：`jbroot()` / `ApelinBootstrapPath()` 运行时探测，绝不写死哈希。
2. **shell**：用 `$APELIN_PROJECT_ROOT`、`$HOME`、相对路径；要真根用户数据才写 `/rootfs/var/mobile/...`。
3. **探针（icli probe）要读的文件**：放进**项目内** `.tmp/`（它能看到项目），**绝不放 `/tmp`**；
   probe 里能写死的只有「项目内相对路径」，不写 jbroot 绝对路径。
4. 先判「这文件属于引导还是用户数据」再拼前缀：
   - tweak dylib、dpkg 台账 → jbroot 内（`<jbroot>/var/lib/dpkg/status`）
   - 偏好、下载、截图 → 真根 `/rootfs/var/mobile/...`

## 铁律速查

- 改 ThemeCore 系代码：先问「ThemeCore 是不是这么做的」，查不到就先不动。
- 下结论：先取证，没取证就说「还没查」。
- 改文件：先重读，一次一处。
- 动路径：代码 jbroot()、shell 用变量、probe 用项目内 .tmp/。
