# 本机（Apelin / roothide）适配与验证

本技能生成的是 Theos 工程。想让同一个插件在本机（Apelin 工程）跑，或把已有 Theos 工程搬过来，
按本文件；其余约定仍以 `references/` 下各专题为准。

## 先确认本机能不能编

**结论先行：本机（iPhone10,1 / A11 / iOS 16.7.16）目前装不了任何 Command Line Tools。**
Apple 目录里的 CLT 全部要求 `FEAT_LRCPC`，A11 没有这个特性，`apelin_toolchain_list` 会把它们都标成
"This toolchain requires CPU features this device lacks"。

所以：

- 本技能的 GitHub Actions 工作流（或任何有 Theos 的机器）是构建途径；
- 本机只负责**安装与验证**（`irisin-cli` 安装、respring、确认加载）；
- 不要在本机上承诺"直接编译"，也不要写"本机直编闭环"这类流程；工具链能不能装以
  `apelin_toolchain_list` 的实时结果为准，不沿用旧记录。

## 架构与包标签

| 事实 | 本机实测（2026-10-28） |
|---|---|
| 系统进程架构 | `SpringBoard` 是 `Mach-O 64-bit arm64` |
| 注入器 | `ellekit`（`libellekit.dylib`），universal arm64 + arm64e |
| 已装 tweak dylib | `/usr/lib/TweakInject` 下 58 个：52 个 fat（arm64+arm64e）、6 个仅 arm64、**0 个仅 arm64e** |
| 包标签 | 163 个已装包写 `Architecture: iphoneos-arm64e` |

- `Architecture: iphoneos-arm64e` 是 roothide 的**安装标签**，与 dylib 里真实的 slice 无关；不要为了让标签名好看去改成 `iphoneos-arm64`。
- 被注入的 dylib 必须有 **arm64** slice：本机所有进程都是 arm64，只含 arm64e slice 的 dylib 在这里注入不进去。fat 里同时带 arm64e 无害。
- 查切片用 `file <dylib>`：本机有 `file`。`lipo`、`otool`、`nm` 不在本机，只在工具链里；文档里不要写"用 lipo -info 看架构"这种在本机执行不了的办法。
- A12+ 上 arm64e 进程与 arm64 slice 的关系与 A11 不同，不要用 A11 的结论去推断 A12+ 的产物；要覆盖 A12+ 就老老实实出 fat。

## 迁移 `%hook` 时的硬要求

- 钩类方法：`MSHookMessageEx(cls, sel, (IMP)Hooked, (IMP *)&Original)`；类方法钩元类 `object_getClass(cls)`（`object_getClass((id)cls)` 等价）。
- **钩前判空**：`objc_getClass()` 为 nil 就跳过；`class_getInstanceMethod(cls, sel)` 为 nil 也跳过——否则拿到 nil 的 original，一调用就崩。
- **constructor 时机**：`__attribute__((constructor))` 执行时目标框架不一定已加载，`objc_getClass` 拿到 nil 是常态。判空不够就改用延后钩子（等到目标进程起来、或首次调用某方法时再装），不要把"没日志"当成钩子写错。
- C 函数钩子：

```objc
static void (*orig_func)(int);
static void hooked_func(int x) { orig_func(x); /* 业务 */ }
MSHookFunction((void *)target_func, (void *)hooked_func, (void **)&orig_func);
```

  `MSHookFunction` 没有类与 selector，目标地址自己拿（`dlsym` 或直接引用 SDK 里的符号）。
- `%orig` 就是调用保存的 original；可以多次调用，但要考虑副作用与重入，且"业务在前还是在后"保持一致。
- 钩函数、保存的 original、全局变量一律 `static`，名字带插件前缀（见 [命名与个人约定](conventions.md)）。
- `@available` 写具体版本，例如 `@available(iOS 16.0, *)`，不要照抄 `x.0`。

## 过滤器

最小形态：

```xml
<key>Filter</key>
<dict>
  <key>Bundles</key>
  <array><string>com.apple.springboard</string></array>
</dict>
```

- 文件名与 dylib 同名（去掉 `.dylib`），与 dylib 一起放 `Library/MobileSubstrate/DynamicLibraries/`。
- 在 Apelin 工程里**不要自己放**这个 plist：写 `package.tweakFilter`，由打包器生成（apelin-project-description）。
- 只覆盖实际需要的进程；把 SpringBoard 加进无关插件的过滤器只会制造崩溃面。

## 依赖（`Depends`）

- 注入器依赖在本机写成 `mobilesubstrate`（roothide 的 ellekit 提供这个虚拟包），有设置面板再加 `preferenceloader`。
- 本机实例：`com.axs.cpufree` 的 `Depends: mobilesubstrate, preferenceloader`。
- 构建完用 `dpkg-deb -I <deb>` 核对 `Architecture`、`Depends`、`Version`，不要只看源 `control`。
- Apelin 工程里这些写在 `package.depends`（按 bootstrap 区分用 `dependsByBootstrap`）。
- `irisin-cli install` 有自己的 `--dry-run`（只检查、不改动），可用来核对依赖与 roothide 路径，需要 root；但它**不能**用来安装我们自己项目产出的 deb——那条路只走 `apelin_package_install`。

## 设置面板与配置一致性

- 面板：`/Library/PreferenceBundles/<Name>.bundle`；入口：`/Library/PreferenceLoader/Preferences/<Name>.plist`（`entry` 里 `bundle`、`detail`、`cell`=`PSLinkCell`、`isController`、`label`）。
- 面板是配置文件唯一的写入方，tweak 不写默认值（沿用 SKILL.md 的约定）。
- 行上的 `defaults`（域）、tweak 读的域、通知名必须是同一个包 id：面板 `PostNotification` 发 `<包 id>/changed`，tweak 侧 `notify_register_dispatch` 监听同名。
- 排错加一条：**面板能开、开关能拨，但 tweak 没反应** → 查三处是否同一个包 id（行 `defaults`、tweak 读的域、通知名），再查 tweak 是否在监听。

## 路径

- Theos 工程里的 `jbroot()` / `ROOT_PATH_NS()` 在 Apelin 工程里换成 `ApelinBootstrapPath()`（apelin-bootstrap-paths 技能）；roothide 下 `@PREFIX@` 为空、`@ROOTFS@` 是 `/rootfs`。
- 不要写死 jbroot：它的名字每次越狱都变。

## 加载标记与"装上了 ≠ 加载了"

- 保留工程模板的加载标记行：字面量、不带格式符、值标 `%{public}`。改成带变量的日志，`apelin_package_confirm_loaded` 就匹配不到。
- 验证顺序固定：构建 → 安装 → respring（SpringBoard 插件用 `apelin_package_confirm_loaded` 的 `respring: true`）→ 看到标记行才算加载。
- 没有任何日志时按序查：过滤器 bundle id → 注入器依赖是否在 `Depends` → 目标进程的 `apelin_log_read`。

## 文档卫生

- 不要在本技能里复制一份 `apelin-project.json` 字段表：它是 Apelin 的、会变，读 apelin-project-description 技能与实际 schema。
- 本文件的实测数据只代表当前这台 A11；换设备（A12+、rootless）要重新实测，不要把结论平移。
