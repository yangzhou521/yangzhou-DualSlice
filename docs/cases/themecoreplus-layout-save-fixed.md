# ThemeCorePlus 布局保存（图标摆位崩溃/注销后不丢）—— 1.0.28 打通

## 三个拦路虎（按发现顺序）

1. **启动护栏文件残留** → `lay{safeskip=1,tick=0,site=none}`
   `/var/mobile/Library/ThemeCorePlus/.tcp-launch-guard` 是 0.9.22 加的防崩溃护栏：
   重活前写、跑完删；下次启动它还在 = 上次崩在这段 → 整段跳过。
   1.0.24 崩过之后文件一直没删，之后每次启动都被跳过。
   **修法**：`rm` 掉那一个文件，下次启动就重新尝试。

2. **保存站挂错类** → `site=none,probe=-`
   枚举 `SBIconModel`/`SBIconController` 家族永远找不到写盘入口。
   借 IconRestore/IconOrder 的思路点名兜底，1.0.27 实测（`named:` 行）：
   - `SBIconModelPropertyListFileStore:_save` = **nil**（IconRestore 的类，本机没有）
   - `SBDefaultIconModelStore:saveCurrentIconState` = **nil**（IconOrder 的类，本机没有）
   - `SBHIconModel:saveCurrentIconState` = **nil**
   - **`SBHIconModel:_saveIconState` = OK** ← iOS 16.7 真正的布局写盘入口
   另有 `-SBIconController:_updateIconModelStore`。

3. **拿到模型实例** → `model=-,last=noinstance`
   站挂上了但系统不主动调它，self 永远拿不到。
   1.0.28：主动 `SBIconController +sharedInstance` → `-iconModel`，`model=adopt:iconModel`。

## 最终诊断（1.0.28 实测）

```
lay{rst=0,sav=1,tick=1,force=0,
    site=-SBHIconModel:_saveIconState,-SBIconController:_updateIconModelStore,
    model=adopt:iconModel,last=baseline,...}
```

## 验收清单
- 挪图标等 30 秒 → `sav` 涨、`force` 涨、`/var/mobile/Library/ThemeCorePlus/IconState.backup.plist` mtime 变新。
- 注销后图标还在且 `rst=0`。
- 把 `/var/mobile/Library/SpringBoard/IconState.plist` 挪走再注销 → `rst=1,last=restored`。
- `apelin_crash_list process=SpringBoard` 无新报告。

## 仍未修
- **缓存层站**：`sites=18` 里仍没有，`cachecls=PKIconImageCache,SBFolderIconImageCache,SBHIconImageCache` 三个类都在，
  但 `cache=nocache`。秒加载没生效。1.0.25 已改成按「声明者」挂（`TCPInstallIconCacheLayerSitesV2`），
  仍未挂上，下一步看 `cache=` 诊断输出。
