# 本仓库怎么干活（AGENTS.md）

🈲 **对话语言强制中文**：所有回复正文与思考过程必须简体中文，禁止英文段落。仅代码块、命令、路径、版本号、报错原文可英文。每次回复首句必须是中文结论。

---

## 🔴 第一性原则：与 ThemeCore 0.5.1 架构完全一致（2026-11-06 00:03 定，不许打破）

**用户原话**：「ThemeCore 它没有什么明显 bug 就完全抄它的！和它架构一致！这是第一性原则你不要打破！」「不要你自己天马行空乱写！」

**动手前先问：ThemeCore 0.5.1 是不是这么做的？**
- 是 → 照抄，别多加动作。
- 不是 → 先别加，先查它怎么做；查不到就先不动，**不许自己发明「保险」**。
- 只有它完全没有的功能（角标、阴影、文件夹、控制中心）才参考别的实现，并写明依据。

**已被否掉的自我发明（别加回来）**：
| 我加的 | 为什么被否 |
|---|---|
| 0.6 秒延迟 `dispatch_after` | ThemeCore 没有 `dispatch_after` / `dispatch_time` |
| `TCXStoreReady` 预热闸门 | ThemeCore 没有 Ready 标记；线程安全靠 `dispatch_once` + `os_unfair_lock` |
| 挂站丢主队列 | ThemeCore 用 `dispatch_async` + `QOS_CLASS_UTILITY` 串行队列 |

**ThemeCore 0.5.1 架构（二进制实证，照抄依据）**：
- 构造函数只做：`TCIconServicesIsCurrentProcess()` → `TCIconServicesInstallHooks()`（生图层）→ `TCIconShadowInstallHooks()`（阴影层）
- dispatch 只有：`dispatch_async` / `dispatch_queue_create` / `dispatch_queue_attr_make_with_qos_class` / `dispatch_get_global_queue` / `__dispatch_main_q` / `dispatch_once` / `dispatch_source_*`
- 文件枚举 `enumeratorAtPath:`（惰性）；解码 `CGImageSource` + `kCGImageSourceShouldCache`
- 过滤器：`Bundles: com.apple.UIKit` + `Mode: Any` + `Executables: iconservicesagent/ShareUI/sharingd`（**没有 SpringBoard**）
- 依赖：`mobilesubstrate, preferenceloader, firmware` + `Pre-Depends: rootless-compat (>= 0.9)`
- 偏好域 `com.susudear.themecore`，键 `ActiveTheme` / `EnabledThemes`，通知 `com.susudear.themecore.reload`
- 首选生成入口 `generateIconImage:`（无参），不只有 `iconImageWithInfo:`
- 挂站类与选择器全集见技能 `themecore-architecture-first`

**怎么从 dylib 抽实证**（本机 strings / otool 都不可用）：
```sh
od -c "$F" | awk '{for(i=2;i<=NF;i++){if($i ~ /^\\0/){if(s!=""){print s; s=""}else{next}} else {c=$i; gsub(/^[0-9]+$/,"",c); s=s c}}}' | sort -u
```

---

## 开工第 0 步（新对话 / 复活 / 换人，都先做）

```sh
sh scripts/resume.sh          # 交接块：任务链 + 未清 pending + 装机现状 + 接手提示词
sh scripts/fleet-live.sh 30   # 谁在跑（每次回复前都跑，几秒、只读、免卡）
sh scripts/safemode-check.sh  # 约 80 秒，只读：判安全模式 / 版本漂移 / 插件在不在跑
```

把「任务链、当前步、未清 pending」**原样报一句给用户**，再按 `next` / `pending` 继续。
**不许凭对话历史猜进度**——历史会死、会被压缩、会换人，进度只写在 `scripts/WORK-STATE.json`。

---

## 🔴 开机交付对账清单（2026-11-05 23:27 定，优先级高于一切改码）

**病根**：以前「注销 → 用户报一个 bug → 改一个 → 推云编译 → 又报一个」，一轮一轮烧额度。

1. **注销回来第一件事：对账，不是改码。** 读 `WORK-STATE.json` 的 `buglog` + 用户这轮报的问题，
   逐条列「已修好的 / 还没修的 / 待验证的 / 新报的」，**先把对账单报给用户**（一行一条：id、现象、状态）。
2. **一次只改一个变量，但攒成一批一次推。** 全部改完 + 静态自查（符号引用、版本三处一致、plist 结构）
   才 push 一次。不许改一条推一次。
3. **buglog 是唯一权威，必须落盘。** 用户说「修好了」→ 当场 status 改「已修（版本，用户确认）」+ 写 `proof`；
   报新 bug → 当场加一条，带 `id/where/symptom/reported/proof/status/fix`。**不许只回在对话里。**
4. **推送前做交付对账**：确认「这批要解决的 = buglog 里 status 非『已修』的全部」，多改的漏改的都要说。

落地：技能 `workspace-bug-ledger`。

---

## 回复前强制四问 + 必守七条

**四问**：① 完整链是什么？→ 读 WORK-STATE 的 `chain`/`step`；
② 我走到第几步？→ 读它，不靠脑子记；
③ 下一步要不要用户点头？要（装包/注销/VPN/删东西）→ **当轮弹窗**；不要 → **现在就做**，不许「等你指示」收尾；
④ **手上还欠哪些账？** → 读 `buglog` + `pending`，看到当场开干。每项只有「做完并验证」或「用户明说取消」。

**四条硬判据**：代码改完 / 编译成功 / 汇报 / **写进待办文件** 都不算完。

**必守七条**：① 四问 + 任务链 + pending 落盘；② 需点头的当轮弹窗，不需点头的现在就做；
③ 第三方 AI 提示词必须是代码块；④ 搞不定就直说；⑤ 动设备前通知 + 弹窗 + 点头，装完 SpringBoard 插件查崩溃；
⑥ 插话做完用「胶囊 + 弹窗」双通道催装包（取消/超时不算拒绝，下轮再弹）；
⑦ 对话会死 → 每阶段更新 WORK-STATE.json。

**交接协议三重冗余**：`WORK-STATE.json` + `resume.sh` + 提交信息末尾 `NEXT:` 行。
**禁止重建**看护 / 心跳 / 黑板 / 唤醒队列（已实测失败并全部删除）。

---

## 仓库里有什么（当前只做 AppIcon）

| 路径 | 是什么 |
|---|---|
| `ThemeCoreX/Sources/` | AppIcon 主题库、路径、偏好、诊断、版本（类前缀 `TCX`） |
| `ThemeCoreX/Hooks/` | 挂站模块：Main / Icons / Badge / Shadow / Clock / Calendar / Folders / BundleImages |
| `ThemeCoreX/Headers/` | 私有声明（`TCXPrivate.h`） |
| `Prefs/AppIconPrefs/` | 设置面板：`Root.plist` + `TCXRootListController.m` |
| `Support/AppIcon.plist` | 注入过滤器（与 ThemeCore 逐字一致） |
| `Support/AppIconPreferenceLoader.plist` | 设置里那一行的入口 |
| `scripts/build-appicon.sh` | AppIcon 构建脚本（**只在 CI 上跑**） |
| `.github/workflows/appicon.yml` | AppIcon 云编译 + 发 Release |
| `CountdownHUD/` | 灵动岛胶囊（独立包，用户仍在用） |
| `scripts/` | 交接、装包、注销、通知等工具脚本 |
| `docs/cases/` | 历史案例复盘（旧线过程记录都在这，不进 AGENTS.md） |

**已废弃**：ThemeCorePlus 1.0.x 线（2026-11-04 21:48 取消，由 AppIcon 承接）、SileoWallpaper 修复线。
它们的源码与案例仍留在仓库里做参考，但**不再维护、不许再引用其变量名**。

---

## 怎么出包（本机编不了）

本机 iPhone10,1（A11 / iOS 16.7.16 / roothide）缺 `FEAT_LRCPC`，装不上 Command Line Tools，
**没有工具链，也不要在本机找**。所有 .deb 走 GitHub Actions 云编译：
macOS runner 上 clang 直编 arm64 + arm64e 两片 + lipo + ldid + dpkg-deb。

改完源码 push 到 `main` → `appicon.yml` 触发（paths 过滤，只有 `ThemeCoreX/**`、`Prefs/**`、
`Support/AppIcon*`、`scripts/build-appicon.sh`、工作流自身变动才触发）→ 同一次运行发 Release。

**版本三处必须一致**：`ThemeCoreX/Sources/TCXVersion.h` 的 `TCX_VERSION`、
`scripts/build-appicon.sh` 的 `VERSION`、`.github/workflows/appicon.yml` 的 `env.VERSION`。
tag 与包版本一致（`appicon-v<版本>`）。

**盯云编译：每 30 秒查一次**（用户 2026-11-06 定）：
```sh
for i in $(seq 1 10); do R=$(icli probe scripts/ci-status.js 2>&1 | grep -o 'status=[a-z]* concl=[a-z]*' | head -1); echo "$(date +%H:%M:%S) $R"; case "$R" in *completed*) break;; esac; sleep 30; done
```
看到 `completed` 才停；一轮最多 10 次；success 立刻下载 deb + 弹窗。**报状态前必须重查**，
`ci-status.js` 只列最近 3 次 run，别把别人的旧 run 当成这次的。

---

## 装到本机

下载走 `icli probe`（本机没有 curl/wget/python3），写到真根 `/var/mobile/Documents/`。
装包统一走 `scripts/install-deb.sh`（**只装不注销**）→ 装完 `scripts/post-install-respring.sh`
单独弹窗问注销（2026-11-05 22:57 用户定「装包不注销，装完弹窗由我决定」）。

装包需要 root：`irisin-cli install --yes <deb>`，只装自己项目的包。**绝不用 apt / dpkg / sudo。**

装完 SpringBoard 插件、注销后必查 `apelin_crash_list` 无新报告。

---

## 设备状态自己查（全权限）

凡是要设备 / 插件 / 云端**此刻状态**才能决定下一步的事——读诊断、`irisin-cli list`、读
`<jbroot>/var/lib/dpkg/status`、下载校验、读 plist、界面树、GitHub API——**一律自己查完再汇报**，
不把查询推回用户、不让他截图替我。

**免批准卡片**（卡片来自设置「使用屏幕前先询问」，只能用户自己关）：日常走 `sh scripts/device.sh`：
`read/write/clear <域> [键]`、`kill <bid>`、`launch <bid>`、列进程 `launchctl list`。
**仍只有 icli 能做**：`app frontmost`、`ui tree`、`ui tap`、`input`、`screen shot`。

**进 GitHub 必查 Apelin 更新**：`ci-status.js` 输出末尾自动带版本比对，汇报写一句「本机 X / 最新 Y」。
有新版当轮就要通知（胶囊 + 正文），不许只「顺便提一句」。

---

## roothide 路径铁律

引导根＝`/private/var/containers/Bundle/Application/.jbroot-<哈希>`，**每次重越狱都可能换**。
- 代码用 `jbroot()`；脚本用 `$APELIN_PROJECT_ROOT` / `$HOME`；plist 用 `@PREFIX@` / `@ROOTFS@`
- **引导里的东西在 jbroot 内**：tweak dylib、dpkg 台账 `<jbroot>/var/lib/dpkg/status`
- **用户数据在真根**：`/rootfs/var/mobile/Library/Preferences`、`/rootfs/var/mobile/Documents`
- 两者混用会误判「文件不存在 / 包没装」

---

## 注入型插件不必注销

tweak 只在过滤器命中的进程**启动时**加载 → 重启那个进程就完成注入。
App 类 → `device.sh kill` + `device.sh launch`；设置面板 → 退出设置再进。
**只有**插件注入 SpringBoard（桌面图标、HUD、控制中心）或改了过滤器时才注销。

**注销**：`sh scripts/respring-guard.sh --ask <秒> <标签>`（屏幕弹窗，用户点「立即注销」才注销）。
不带 `--confirm` 永远不注销。倒计时 5 秒。

**通知用户三通道**：正文 + 灵动岛胶囊 `sh scripts/hud-notify.sh 8 "!<一句话>"` + `apelin_notification_send`。
胶囊前缀：`!` 纯文案 / `?` 注销弹窗 / `#` 请开 VPN 弹窗。
**安全模式**下胶囊与弹窗都不显示 → 只走正文 + 系统通知，装包用 `install-deb.sh`（SAFEMODE_DIRECT）。

---

## 当前状态

见 `scripts/WORK-STATE.json`（**唯一权威**：task / status / step / chain / next / buglog / pending）。
人读版 `scripts/WORK-STATE.md`。每推进一个阶段立刻更新，不许攒到收尾。
