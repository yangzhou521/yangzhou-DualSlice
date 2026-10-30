---
name: axs-ios-tweaks
description: 为 iOS 越狱 deb 插件创建和维护 Theos 工程，包含插件专属命名、可选 PreferenceLoader 面板、自定义滑条，以及 Rootful、Rootless、Roothide 打包与配置适配。用于 tweak 工程，不用于普通 IPA 的签名和侧载。
---

# Axs-ios-Tweaks

生成可手动维护的 deb 插件工程。沿用 Axs 个人约定，但所有自定义文件、类、协议、函数和新增 selector 都必须带插件命名空间，不复用裸 `AxsConfig`、`AxsSliderCell`、`axs_reload` 等通用名称。

## 工作流程

1. 明确插件英文名、小写标识、显示名、目标进程、最低 iOS 版本和所需打包环境。已有工程先检查现有结构，不重新生成覆盖。
2. 阅读 [命名与个人约定](references/conventions.md)。英文名用于代码，显示名可用中文；不要把作者前缀当作插件命名空间。
3. 新工程通过 `scripts/create.py` 生成，默认附带常用 GitHub Actions 构建/发布工作流。按需启用设置面板和滑条，不默认添加无关模式、参数、服务或全局注入。
4. 在插件专属 `Hooks/`、`Headers/`、`Sources/` 文件中实现需求。按模块拆分，新增私有声明应来自实际目标，不保留虚构类。
5. 有设置面板时阅读 [配置与面板](references/preferences.md)；有滑条时再读 [滑条组件](references/custom-slider-cell.md)。面板是配置文件的唯一写入方，Tweak 不持久化默认值。
6. 涉及资源路径或多环境时阅读 [越狱适配](references/jailbreak-adaptation.md)。配置与只读资源分开解析，不扫描目录决定配置写入位置。
7. 按 [构建与环境](references/building.md) 检查、编译并核对 deb。失败时查 [排错与验证记录](references/troubleshooting.md)。
8. 要在本机（Apelin / roothide）运行、安装，或把工程搬进 Apelin 时，先读 [本机适配与验证](references/apelin-device.md)：本机装不了工具链，构建在 CI 或电脑上做，本机只负责安装与验证。

## 生成示例

在 skill 目录执行，输出目录必须不存在：

```sh
python3 scripts/create.py /work/touchtrail --name TouchTrail --id touchtrail --display-name "触摸轨迹" --preferences --slider
python3 scripts/doctor.py /work/touchtrail
```

只需要核心插件时省略 `--preferences --slider`。生成器仅生成文件，不安装依赖、不编译、不安装插件、不注销设备。`--bundle` 可指定注入 Bundle ID，默认仅 SpringBoard。

默认生成 `.github/workflows/build.yml`，沿用个人编译模板的 macOS/Xcode、SDK 和 Rootless 配置。
主工程、面板与 CI 的 SDK 统一为 `16.5`，由 `assets/defaults.json` 的 `sdk_version` 同步生成；TARGET 只在共享 `*Build.mk` 定义。
Release 标题自动使用插件显示名，不保留“根据插件名称修改此处”；所有插件的 CI 包版本统一为 `5.2.0-${{ github.run_number }}`。
工作流会在推送到 `main/master` 或手动触发时构建并发布 Release，上传前先检查名称、版本和触发条件。
仅本地构建时加 `--no-github-actions`。详见 [构建与环境](references/building.md)。

在 Windows 可用 `python` 替代 `python3`。生成脚本只依赖 Python 3.8+ 标准库。Minis 中也以同一目录为入口，但须按构建文档实查其环境；不承诺未经验证的导入方式或手机端 deb 编译。

## 实现边界

- 自定义标识使用生成的类前缀和函数前缀；系统 override、协议要求的 selector 和工具链固定文件名保持原样。
- 默认不启用带面板的插件；无面板工程默认启用，由实际需求决定是否增加开关。
- `enabled` 关闭时保持原行为；`%orig` 的调用时机和返回值按目标方法语义决定，不能统一规定先调用或永不调用。
- 过滤器只覆盖需要的进程。检查目标类、方法及 iOS 版本，避免不必要的全局 hook。
- UI 更新在主线程；高频 hook 只读配置快照，不扫目录、读文件或创建 defaults。对象复用、缓存和清理按实际负载落实。
- 自定义非交互浮层不接管触摸。复杂逻辑写简短原因注释，不为每次修改追加历史流水注释。
- 保留编译警告。生成器与 doctor 通过不代表 Theos 编译或真机测试通过；分别报告验证范围。

## 维护入口

| 要维护的内容 | 唯一入口 |
|---|---|
| 作者、包域、源地址、TG、QQ 深链接、SDK 版本 | `assets/defaults.json` |
| 默认生成的代码、Makefile、plist | `assets/base/`、`assets/preferences/`、`assets/slider/` |
| GitHub Actions 构建与发布 | `assets/github-actions/.github/workflows/build.yml` |
| 参数替换、文件生成 | `scripts/create.py` |
| 工程与工具链只读检查 | `scripts/doctor.py` |
| 原理、适配边界、人工验收 | `references/` 对应专题 |
| 本机（roothide）架构标签、依赖、面板与通知一致性、加载验证 | `references/apelin-device.md` |

修改模板后可生成示例工程，用 `scripts/doctor.py` 检查结构与引用。默认值只影响之后生成的项目，不会自动修改已发布插件。原安装目录中的另一个 skill 副本也不会自动同步。
