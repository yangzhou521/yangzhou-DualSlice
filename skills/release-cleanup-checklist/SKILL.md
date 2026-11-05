---
name: release-cleanup-checklist
description: ThemeCore 系越狱插件发正式版前的收尾清单：全面对照 ThemeCore 架构、删掉整套诊断与验证残留（diag/TCXNoteSite/计数/探针/临时字段）、删掉已废弃插件的构建脚本与 workflow，让源码与构建干净整洁。只在打算发正式版时用。
---

# 正式版收尾清理（用户 2026-11-06 01:22 定）

用户原话：「最后一版本要全面检查架构上和 ThemeCore 是否一致！日志诊断在最后一个正式版本删掉，
也删除多余没用的检测验证手段和代码文件和其它没用的构建等，最后要做到架构上干净整洁！」

**只在准备发正式版时做，开发期不要删诊断**（诊断是唯一取证手段）。

## 四步

### 1. 全面对照 ThemeCore 架构
逐项过一遍，每项写「一致」或「ThemeCore 无此功能，依据 X」：
- 构造函数结构（判断进程 → 读配置 → 挂生图层 → 挂呈现层）
- 过滤器 plist
- 依赖字段（Depends / Pre-Depends）
- 挂站类与选择器清单
- 素材根路径
- 配置键与通知名
- 首选生成入口

### 2. 删诊断整套
- `ThemeCoreX/Sources/TCXDiag.h` 整个文件
- `TCXWriteDiagnostics`、`TCXDiagWrite`、`TCXDiagWriteForce`
- `diag.txt` 写入与 `/var/mobile/Library/AppIcon/` 目录创建
- 诊断偏好键（如 `AppIconDiagnostics`）
- 各模块的计数与埋点：`TCXNoteSite`、`TCXCountIconLook`、`TCXCountIconHit`、
  `TCXCountBadgeLook`、`TCXCountShadow`、`TCXRecordError`、所有 `TCXNoteSite(@"...")` 调用
- `TCXMain.m` 里的 `sSites` / `sIconLook` / `sIconHit` / `sBadgeLook` / `sShadowApplied` /
  `sLastBundle` / `sLastError` 这些只服务于诊断的静态变量

### 3. 删调试/验证残留
- 任何 `TCXProbe*`、临时探针文件
- 只为验证加的字段（如诊断串里的 `bundles=` / `assets=`）
- `docs/breakpoints/` 里已完成的任务文件
- `scripts/` 里一次性脚本（`ci-*.js` 保留在用的 `ci-status.js`、`download-*.js` 等）
- `.tmp/` 下解包残留（不进 git，但本地也清）
- `IndexedBundleCount` / `IndexedAssetCount` 这类只给诊断用的接口

### 4. 删没用的构建
- `scripts/build-*.sh` 里已废弃插件的（themecoreplus / sileowallpaper / dualslice 等）
- 对应的 `.github/workflows/*.yml`
- 但**先问用户**要不要留旧线的构建，别自己删
- 保留：当前插件的 build 脚本、它的 workflow、`scripts/` 里仍在用的工具
  （device.sh / install-deb.sh / post-install-respring.sh / respring-guard.sh /
   hud-notify.sh / vpn-guard.sh / fleet-live.sh / resume.sh / sync-all.sh / safemode-check.sh）

## 验收标准
- 正式版源码里搜不到「诊断」「探针」「验证」「临时」「diag」「probe」这类残留
- 构建脚本只留当前在做的插件
- 编译通过、装包后功能与清理前一致（清理不能改行为）

## 底线
**清理只删不该进正式版的东西，绝不顺手改功能逻辑。** 改功能是另一件事，分开做。
