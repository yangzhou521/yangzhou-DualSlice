# 越狱环境与路径

路径实现只维护在 `assets/base/Sources/__PREFIX__Paths.h`。
本文件解释边界，不再保留多套可复制的扫描实现。

## 两类路径

| 类型 | 规则 |
|---|---|
| 随 deb 安装的只读资源 | 从未转换的逻辑路径，经工具链 API 转换一次 |
| 跨进程用户配置 | 面板与 Tweak 使用同一个插件专属 `preferencesPath` |
| iOS 系统框架 | 不把系统 `/System/Library/...` 当作插件安装资源加前缀 |

Rootful/Rootless 的移动用户偏好使用 `/var/mobile/Library/Preferences/<包名>.plist`，
不能因为 deb 安装在 `/var/jb` 就自动把移动用户偏好也加上该前缀。
Roothide 分支用它自己的 `jbroot()` 转换同一逻辑配置路径。
在沙盒宿主中是否可读、面板是否可写，仍需真机验证，路径转换不是权限授予。

## 官方接口

- Rootful/Rootless 资源路径：Theos 的 `<rootless.h>` 与 `ROOT_PATH_NS_VAR`。
- Roothide：由 `THEOS_PACKAGE_SCHEME_ROOTHIDE` 编译条件选择 `<roothide.h>` 与 `jbroot()`。
- 不根据“机器装了某个头文件”推断运行环境，不扫描 `.jbroot*` 决定写入目标。
- 输入必须是未转换路径，已经转换的结果不能再次转换。
- 同一源码分别按 scheme 编译，不承诺同一个 dylib 跨全部环境直接运行。

本次整理核对过的上游资料：

- [Theos rootless.h](https://github.com/theos/headers/blob/master/rootless.h)
- [Roothide rootless.h](https://github.com/roothide/headers/blob/master/rootless.h)
- [Roothide 兼容宏](https://github.com/roothide/headers/blob/master/rootless-compat.h)
- [Roothide 开发说明](https://github.com/roothide/Developer)

上述头文件由对应工具链提供。不把第三方实现复制进 skill，不下载或执行远程安装脚本。
缺头文件、链接失败时修复对应工具链，不用一个硬编码随机根或猜测的 `dlsym` 函数签名代替。
具体是否需要额外链接选项以工具链和依赖为准，不继续把“永远不要链接某库”写成跨版本规则。

## 配置一致性

读写规则见 [配置与面板](preferences.md)。新模板使用单一规范文件和同域 defaults 回退，
不写多份候选文件，也不缓存扫描到的随机目录。

旧项目如果采用多文件镜像，升级前先比较权威副本与用户已有值。
不要未经迁移把新模板套进旧项目，尤其不要更改已发布包的配置域。
原文档关于 prefshook、交换文件和键盘进程的经验保留在
[排错与验证记录](troubleshooting.md)，不等于这次新实现的真机结论。

## 打包

所有 scheme 的 clean、工具链和 deb 检查集中在 [构建与环境](building.md)。
三种环境要分别测试面板入口、开关持久化、通知、实际路径和资源加载。
Roothide 普通 App/可执行文件的额外 entitlement 需求不应未经判断直接套给所有 tweak；
超出当前 dylib/PreferenceBundle 模板的 daemon、App 等类型应按上游说明单独配置。
