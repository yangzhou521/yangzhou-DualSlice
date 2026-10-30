# 生成后的工程骨架

这里仅说明目录职责。可执行模板在 `assets/`，不要在本文件再复制代码维护第二份。

以 `TouchTrail`、启用面板和滑条为例：

```text
touchtrail/
|-- .github/workflows/build.yml
|-- control
|-- Makefile
|-- AxsTouchTrailBuild.mk
|-- AxsTouchTrail.plist
|-- build.sh
|-- tweak.json
|-- Hooks/
|   `-- AxsTouchTrailMain.xm
|-- Headers/
|   `-- AxsTouchTrailPrivate.h
|-- Sources/
|   |-- AxsTouchTrailConfig.h
|   |-- AxsTouchTrailConfig.m
|   |-- AxsTouchTrailPaths.h
|   `-- AxsTouchTrailPreferences.h
|-- AxsTouchTrailPrefs/
|   |-- Makefile
|   |-- AxsTouchTrailRootListController.h
|   |-- AxsTouchTrailRootListController.m
|   |-- AxsTouchTrailSliderCell.h
|   |-- AxsTouchTrailSliderCell.m
|   `-- Resources/
|       |-- Info.plist
|       `-- AxsTouchTrailRoot.plist
`-- layout/Library/PreferenceLoader/Preferences/
    `-- AxsTouchTrailPrefs.plist
```

- `Hooks/`：按功能拆分 Logos hook。不是所有插件都该 hook `UIApplication`。
- `Headers/`：确认过的系统私有声明，只声明需要的接口。
- `Sources/`：配置、路径以及后续插件业务实现。
- `*Prefs/`：只放面板代码与资源，不重复编译 Tweak 的 Objective-C 类。
- `layout/`：随包安装的入口与资源，按未加越狱前缀的逻辑位置放置。
- `tweak.json`：生成身份与组件记录，供 doctor 使用；不是构建配置，不会自动重写代码。
- `*Build.mk`：两工程共同使用的部署和架构设置；Makefile 仍是构建的权威配置。
- `.github/workflows/build.yml`：常用 GitHub 构建/发布流程，标题自动使用插件显示名；`--no-github-actions` 可省略。

无面板时不生成 `*Prefs/` 与 PreferenceLoader 入口；无滑条时不生成滑条类。
增加文件时沿用完整插件前缀。重命名后同步更新 Makefile、import、plist 与 `tweak.json`。

修改模板会影响下次生成，不会自动修改既有项目。
