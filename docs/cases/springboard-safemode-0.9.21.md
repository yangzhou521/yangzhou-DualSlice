# 案例：ThemeCorePlus 0.9.21 把 SpringBoard 打进安全模式（2026-10-31 完整排查·修复·验收过程）

> 用途：**模板**（任何崩溃循环 / 安全模式 / 数据丢失事故照这三段写）+ 本次实况。
> 规矩：事故解决后必须按本文三段「原因 / 过程 / 解决与复盘」发给全员，并同步 AGENTS.md + 技能 + 记忆。
> 只修不写复盘 = 没修完。

---

## 〇、一句话版本（广播用，三行）

> 0.9.21 在 dyld 构造函数里对枚举出的第三方类发 `isSubclassOfClass:` → forwarding 崩 → ellekit 连崩 5 次关掉注入 = 安全模式；
> 回滚 0.9.19 + 注销一次即恢复。今后：构造阶段只用 C API、**根因没定位前不许注销**、一个 bug 只许一条线改、
> 装包注销一律过 `scripts/deb-guard.sh`、修完立刻通告全员并附三段复盘。

---

## 一、原因（为什么会崩）

| 项 | 内容 | 证据 |
| --- | --- | --- |
| 直接原因 | `ThemeCorePlus/Sources/ThemeCorePlusLayout.m` 的 `TCPLayoutHookSave()` 在 **dyld 构造函数阶段**枚举全进程所有类，逐个发 `[c isSubclassOfClass:base]` | 崩溃报告寄存器 `objc-selector: isSubclassOfClass:`、`symbol: OBJC_CLASS_$_ISOverlayEmbossedFolder` |
| 崩点 | 枚举到 `ISOverlayEmbossedFolder`（IconSupport 第三方类）时它**还没 realize**，消息进 forwarding | 栈：`___forwarding___.cold.3 → ___forwarding___ → _CF_forwarding_prep_0` |
| 崩在哪一步 | `TCPInitialize → TCPLayoutInstall → TCPLayoutHookSave` | 栈帧 imageIndex 36（ThemeCorePlus.dylib） |
| 异常类型 | `EXC_BREAKPOINT / SIGTRAP`（forwarding 的断言陷阱，不是普通段错误） | `exception.codes = 1` |
| 升级成安全模式 | ellekit 计数 `consecutiveCrashCount 3→4→5`，第 5 次后**关掉该进程注入** → SpringBoard 无插件启动 = 安全模式 | ips: `"consecutiveCrashCount": 5` |
| 根因归类 | **构造阶段做重活 + 对来路不明的类发 ObjC 消息**（不是「版本没写完」这种普通 bug） | 同类前科：CountdownHUD 1.4.0 构造函数里用 `UISelectionFeedbackGenerator` → `+[UIScreen mainScreen]` → SIGABRT |

**为什么这类写法必死**：`objc_getClassList` 会把**尚未 realize 的类**也列出来；给它发任何消息都走 `__forwarding__`，
在 dyld 初始化早期会撞上断言陷阱。判父子关系根本不���要发消息——`class_getSuperclass()` 是纯 C，永远安全。

---

## 二、过程（完整时间线，含走错的判断）

### 阶段 A：出事（10:37–10:44）

| 时间 | 事件 |
| --- | --- |
| 10:37 / 10:38 / 10:44 | 三份 `SpringBoard-2026-10-31-*.ips`，**栈完全一致** → 不是偶发，是确定性崩 |
| — | 崩的都是**同一个新装版本** 0.9.21；崩点全在构造函数 |
| — | `consecutiveCrashCount` 递增到 5 → ellekit 关闭注入 → 之后 SpringBoard 一直是 pid 61168 不换（安全模式特征） |

### 阶段 B：排查（走了哪些弯路）

1. **先看栈，不先猜**：三份 ips 同一栈 → 直接锁定构造函数路径，而不是「主题渲染慢」「图标错位」那些表层现象。
2. **对照源码定位行**：崩栈里的 `TCPLayoutHookSave` → 回到 `ThemeCorePlusLayout.m` 找到那段枚举 + 发消息的代码（当时在 303 行附近）。
3. **弯路 ①：把「读到诊断」当成「插件在跑」**。安全模式下 `ThemeCorePlusLayout` 诊断键**仍然存在**（是崩溃前写下的旧值），
   于是早期一度判断「插件还在跑、不是它崩的」。**教训：诊断键存在 ≠ 进程活着，要看 `tick` 是否在涨。**
4. **弯路 ②：读数间隔太短**。`tick` 有 60 秒写盘节流，7 秒内两次读数不动就差点误判「插件没跑」。
   **教训：量活没活要隔 70 秒读两次。**
5. **弯路 ③：多线并行改同一个问题**。回滚由一条线做、读诊断由另一条做、还有线在准备装新包，
   用户看到的是「修了又坏、坏了又修」。**教训：一个 bug 只允许一条线改码/编译/装包/注销。**
6. **弯路 ④：版本复用**。0.9.21 崩了以后还打算在同号上覆盖重发。**教训：出过崩溃的版本号永不复用。**

### 阶段 C：定位与止损（10:50–11:0x）

1. 用 `class_getSuperclass()` 父类链替换 `isSubclassOfClass:`（不再向枚举出的类发消息）。
2. 把「挂站 + 枚举类」从构造函数**移到 5 秒定时器第一拍**（主队列，启动完成后，类都已 realize）。
3. 构造函数只保留纯赋值 + 文件读写 + 建定时器（不碰任何运行时类，不碰 UIKit）。
4. 挂站前验签名：只挂**零参数**方法（`method_getNumberOfArguments == 2`）且返回 `void`，
   带参数的 `saveIconStateAndWait:` 一类挂上去会丢参数、把系统写盘弄坏。
5. **启动护栏** `.tcp-launch-guard`：重活开始前写文件、跑完删掉；下次启动它还在 = 上次崩在这段重活里 →
   整段跳过（诊断 `safeskip=1`），宁可布局功能不生效也绝不再送 SpringBoard 进安全模式。
6. **版本号** 0.9.21 作废 → 下一版 **0.9.22**。

### 阶段 D：恢复设备（用户批准后）

| 步骤 | 命令 | 结果 |
| --- | --- | --- |
| 确认无新崩溃 | 崩溃列表（10:44 后无新报告） | 安全 |
| 确认磁盘版本 | dylib SHA `80c7e236…`（0.9.19），mtime 09:31 | 与锁一致 |
| 用户点头 | 「注销」 | 批准 |
| 倒计时 + 注销 | `sh scripts/respring-guard.sh --confirm 5 "退出安全模式"` | 5 秒倒计时 → 成功，退出码 0 |
| 验证新进程 | SpringBoard pid **61168 → 61921** | 全新启动，安全模式解除 |
| 验证插件活 | `ThemeCorePlusLayout` 的 `tick` **1 → 25** | 定时器在跑，注入恢复 |
| 验证 HUD | `hud-notify.sh` → `shows=2`、`scene=SBSystemApertureWindowScene` | HUD 正常 |
| 验证无新崩溃 | 崩溃列表 | 无新报告 |

### 阶段 E：善后

- 复盘写成本文 + AGENTS.md「硬规矩」+ 技能 `a11-roothide-ondevice` 第 9 节 + 记忆；
- 三段复盘**发给全员**（本节〇的「一句话版本」）；
- 防回滚三件套：`scripts/version-lock.txt`（owner + 版本 + dylib SHA）、`scripts/deb-guard.sh`
  （非 owner 装包/注销 exit 6、版本不符 exit 7、`check` 只读）、`scripts/safemode-check.sh`
  （0 健康 / 1 连崩或安全模式 / 2 版本漂移 / 3 插件没在跑 / 9 读数缺失）。

---

## 三、解决与复盘（以后怎么做 = 硬规矩）

1. **根因没定位前，不许注销、不许装新包**（用户 2026-10-31 11:16 原话「在没有真正排查出安全事故的原因情况下不要让他们注销」）。
   注销是**验证手段**，不是排查手段：根因不明就注销，等于拿用户的桌面做随机试验，还会掩盖证据
   （注销后 pid 变了、崩溃现场没了）。顺序固定：**先读 ips 定位 → 改码 → 编译 → 装 → 最后才注销**。
2. **构造阶段禁重活**：dyld 构造函数里禁止碰 UIKit、禁止向 `objc_getClassList` 枚举出的类发任何 ObjC 消息；
   判类只用 `class_getSuperclass()`，查方法只用 `class_getMethodList()`。
3. **一个 bug 只许一条线改**：改码/编译/装包/注销权归 `scripts/version-lock.txt` 的 owner；其他线只提交线索，
   不自行改动、不自行装包。一轮只出一个改动，禁止「装 A 不行又装 B」。
4. **版本号不复用**：出过崩溃的版本号作废，下一版换新号。
5. **诊断存在 ≠ 插件在跑**：以 `tick` 是否在涨为准（隔 70 秒读两次）。
6. **装包/注销纪律**：一律走 `scripts/deb-guard.sh`；注销须用户当轮明确点头
   （`respring-guard.sh --confirm 5 <标签>`），并有正文 + 灵动岛胶囊双通道知情。
7. **修完立刻通告全员**：三段复盘（原因 / 过程 / 解决与复盘）+ 一句话版本 + 文档路径，
   同一提交里带上 AGENTS.md、技能、记忆（本地 + 云端同步）。
8. **注入 SpringBoard 的新插件，注销后必须查崩溃列表**，有更新的报告 = 装坏了（先回滚）。

---

## 四、这次暴露的「环境性坑」清单（与代码无关，但同样致命）

- 隐根 roothide：jbroot 前缀每次重新越狱会变 → 代码/脚本里绝不写死路径，用 `$APELIN_PROJECT_ROOT` / `@PREFIX@` / 运行时解析。
- 本机（A11 / iOS 16.7.16）**没有工具链** → 所有 deb 一律 GitHub Actions 云编译（arm64 + arm64e 双切片），
  本机只能装包 + 验证；`apelin-project.json` 里**不声明** `external.script`（声明了本机必失败）。
- 装入 SpringBoard 的插件改完**必须注销**才生效；注入 App 的插件划掉后台重开即可，别为等注销挂起任务。
