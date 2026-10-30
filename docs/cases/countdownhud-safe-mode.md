# 案例：CountdownHUD 1.4.0 把 SpringBoard 搞崩，设备进安全模式

时间：2026-10-31 03:31（设备 iPhone10,1 / iOS 16.7.16 / roothide）
插件：CountdownHUD 1.4.0（`com.yangzhou.countdownhud`）

## 现象

- 03:29 左右 SpringBoard 崩溃循环，设备自动进安全模式。
- 崩溃报告：`SpringBoard-2026-10-31-033134.ips`（03:31:32 抓取）。
- 用户原话：「安全模式了」。

## 病灶

崩溃栈（关键三帧）：

```
-[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:]
+[UIScreen mainScreen]
+[UIFeedbackGenerator _defaultCoordinateSpace]
-[UIFeedbackGenerator init]
CHInitialize                       ← CountdownHUD.dylib 的 dyld 构造函数
invocation function for block in dyld4::Loader::findAndRunAllInitializers
```

异常类型 `EXC_CRASH` / `SIGABRT`，`asi: libsystem_c.dylib: abort() called`，
`lastExceptionBacktrace` 里是同一个 `+[UIScreen mainScreen]` 断言。

1.4.0 为了实现「要动设备之前先来一下最弱的震动」，在 `CHInitialize()`（`__attribute__((constructor))`）
里就调用了 `CHPrepareHaptic()`，而它会 `[[UISelectionFeedbackGenerator alloc] init]`。

**问题在于时机**：dyld 构造函数阶段 SpringBoard 的 UIKit 还没初始化完，
`UISelectionFeedbackGenerator init` → `_defaultCoordinateSpace` → `+[UIScreen mainScreen]`
→ 命中 UIKit 的断言（此时 mainScreen 不可用）→ NSException → abort。

**一个注入 SpringBoard 的插件在构造函数里碰 UIKit，是能直接把桌面搞崩的。**

## 修法（1.4.1）

1. **生成器惰性创建**：`UISelectionFeedbackGenerator` 不在构造函数里 new，
   改成第一次真要震的时候（主线程、已经有 windowScene、UIKit 完全活着）才创建。
2. **构造阶段只做安全的事**：`CHPrepareHaptic()` 现在只 `[gHapticGenerator prepare]`
   一只**已经存在**的生成器；没有就立即 return，什么都不做。
3. **整段包 @try**：`CHFireWeakHaptic()` 用 `@try/@catch` 包住，抛异常就记日志、
   把生成器置 nil、安静跳过 —— 震动是锦上添花，绝不能拿桌面去换。
4. `CHFireWeakHaptic()` 改返回 `BOOL`，非主线程时直接返回 NO（主线程外不能碰 UIKit）。

版本号三处同步：`CHVersion`（源码）、`VERSION`（`scripts/build-countdownhud.sh`）、
工作流的 `tag_name` / release 名 / `deb-url` 注解（`countdownhud-v1.4.1`）。

## 复发防线

- **注入 SpringBoard 的插件，构造函数里只准碰 Foundation，不准碰 UIKit**
  （`UIView` / `UIScreen` / `UIWindow` / `UIColor` / 任何 `UI*` 类）。
- 需要 UIKit 的东西一律延后：等 windowScene 有了、或第一次真正要用时再创建。
- 装完包先**重启目标进程**看是否崩（SpringBoard 插件要注销），确认没有新的
  SpringBoard 崩溃报告才算装好。

## 相关

- 插件源码：`CountdownHUD/Sources/CountdownHUD.m`
- 构建脚本：`scripts/build-countdownhud.sh`
- 云编译工作流：`.github/workflows/countdownhud.yml`
