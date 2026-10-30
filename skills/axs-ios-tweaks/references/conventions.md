# 命名与个人约定

## 插件身份

以下以英文名 `TouchTrail`、小写标识 `touchtrail`、显示名“触摸轨迹”为例。
生成器要求小写标识等于英文名转小写，避免一个项目出现多套不相关命名。
英文名与标识只接受 ASCII 字母、数字；英文名首字母大写，标识首字母小写。
显示名用于设置和包展示，可用中文，不能反过来作为 Objective-C 标识符。
默认生成的 GitHub Release 标题也使用显示名，避免每次手改工作流中的插件名称。

| 项目 | 示例 |
|---|---|
| Debian 包名、偏好域 | `com.axs.touchtrail` |
| 自定义类、协议、常量前缀 | `AxsTouchTrail` |
| C 函数、新增 selector 前缀 | `axs_touchtrail_` |
| Tweak 目标、注入过滤器 | `AxsTouchTrail`、`AxsTouchTrail.plist` |
| 配置层文件、类 | `AxsTouchTrailConfig.h/.m`、`AxsTouchTrailConfig` |
| 面板目录、bundle | `AxsTouchTrailPrefs` |
| 面板控制器 | `AxsTouchTrailRootListController` |
| 面板规格文件 | `AxsTouchTrailRoot.plist` |
| 滑条类、协议 | `AxsTouchTrailSliderCell`、`AxsTouchTrailSliderCellHandler` |
| 配置通知名 | `com.axs.touchtrail.preferences-changed` |
| 自定义资源包 | `AxsTouchTrailResources.bundle` |

`Axs` 只代表作者，不能单独用于所有插件的类名。不要生成 `AxsConfig`、`AxsManager`、
`AxsSliderCell`、`Main.xm`、`kDomain`、`axs_reload` 这类缺少插件身份的自定义名称。

标准文件 `Makefile`、`control`、`Info.plist`、`build.sh`、`tweak.json` 保留工具约定。
系统 override、被 hook 的原方法、协议规定的 selector 不重命名。
新增 category 方法和关联对象 key 必须带插件前缀；新 category 名也要带类前缀。
生成器不会改变系统类名，也不会为规避冲突而改第三方 API。

两个插件不得故意复用同一英文名、包名。生成器不维护全局注册表，创建前应检索已有项目。
Windows 与部分 macOS 文件系统不区分大小写，不能只改大小写来区分项目。

## 个人配置

统一编辑 [assets/defaults.json](../assets/defaults.json)：

- `author`、`class_prefix`、`package_prefix`、`section`：作者和品牌约定。
- `version`、`minimum_ios`：新工程本地初始版本（默认 `5.2.0`）和最低系统版本；CI 包版本另统一为 `5.2.0-${{ github.run_number }}`。
- `sdk_version`：编译 SDK，统一为 `16.5`；生成时同步用于主工程、面板与 CI 下载路径，不使用 `latest`。
- `repository_url`：源、图标 URL 和描述页 URL 的基础地址。
- `telegram_url`、`telegram_fallback`：TG 主链接和网页兜底。
- `qq_url`：“QQ交流群组”的唯一链接配置；没有未经确认的网页兜底。

不要在模板或文档中另存一份这些链接。生成器将配置写进新项目，使项目脱离 skill 后仍可维护。
之后改默认配置不会修改旧项目；旧项目可在插件专属控制器中手动更新。

## 修改已有项目

先检索旧类名、文件名、selector、plist 中的 `cellClass`、`detail`、bundle、配置域和通知名，
再成组迁移。不要只改文件名而遗漏运行时字符串或 Makefile。

不要为了命名整理随意变更已发布包的 `Package` 和偏好域，否则升级关系和用户配置会断开。
已发布项目若需要换包名，应单独设计兼容迁移，并在真机验证。

## 实体模板

生成后的布局见 [工程骨架](boilerplate.md)。模板占位符由生成脚本替换：

- `__PREFIX__`：完整类/文件前缀。
- `__SYMBOL__`：函数/selector 前缀，不含最后一个连接下划线。
- `__DOMAIN__`：完整包名和配置域。
- `__DISPLAY__`：显示名；脚本按 Objective-C 或 XML 上下文转义。

只在 `assets/` 维护模板代码。文档解释职责，不再复制整套实现。
