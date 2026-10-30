# 构建与环境

## 环境边界

Python 生成和静态检查可以在 Windows、Linux 等环境运行，只依赖 Python 3.8+ 标准库。
Theos 编译需要另外配置支持的构建环境、iOS SDK、clang/链接器、Logos、打包工具及依赖头文件。
不要把静态检查通过报告成“已经编译成功”。

```sh
python3 scripts/doctor.py /work/touchtrail
python3 scripts/doctor.py /work/touchtrail --environment --scheme rootless
```

`--environment` 只读检查 `THEOS`、部分必要文件、头文件和 PATH，不安装、不运行构建、不连接设备。
它不能证明 SDK 完整、架构支持、依赖库齐全、API 可用或 Minis 导入兼容。

## GitHub Actions（常用方式）

生成器默认附带 `.github/workflows/build.yml`，来自常用“编译模板”的工作流，实体模板维护在
`assets/github-actions/.github/workflows/build.yml`。原始编译模板目录不被生成器读取或修改，
因此复制 skill 到其他设备后不依赖桌面的绝对路径。

保留模板中的 `macos-14`、Xcode `15.4`、iPhoneOS `16.5` SDK、roothide/theos、
构建产物上传和 Release 发布流程；默认只开 Rootless。
这些是沿用的个人配置，不表示本次已在 GitHub runner 验证，后续按实际 runner 可用性维护。

原模板第 112 行“根据插件名称修改此处”在生成时替换为插件显示名，例如：

```yaml
name: "触摸轨迹 v${{ steps.bump.outputs.package_version }}"
```

所有插件的 CI 包版本固定采用 `5.2.0-${{ github.run_number }}`，例如 `5.2.0-123`。
不再使用插件初始版本替换前缀，也不增加运行次数偏移。
新工程本地初始版本为 `5.2.0`；CI 构建前写入带运行次数的版本到 `control`，
Release 标签和标题使用同一完整包版本。修改模板不会回写已经生成的项目。

CI 使用 `sh build.sh "${{ matrix.build_variant }}"`，每个矩阵任务只构建自己的环境，
所以本地和 CI 共用清理、scheme 选择与失败停止行为。矩阵只维护 `build_variant`；
原模板的 `package_scheme` 映射交给 `build.sh`，避免两处分别改出不一致的环境。
要增加 Rootful/Roothide，在矩阵里按需取消对应项注释。

推送到 `main/master` 或手动触发工作流会上传产物并创建 Release，工作流保留 `contents: write`。
生成器不会替用户推送仓库或触发 Actions。发布前检查名称、版本、依赖、分支和权限。
不需要工作流时使用 `--no-github-actions`，只生成本地构建入口。

## 本地构建

在生成的项目目录执行：

```sh
sh build.sh rootless
sh build.sh rootful rootless
sh build.sh roothide
sh build.sh all
```

无参数默认只构建 Rootless；`all` 明确要求三种环境。每种 scheme 前都会单独 `make clean`，
失败即停止，不会继续打后续包。脚本显式传入 scheme，避免继承外部 Rootless 环境变量误打 Rootful。
不会安装 deb、删除用户配置、重启进程或注销设备。

Rootful 和 Rootless 使用相应的 Theos；Roothide 需要兼容的 roothide/theos 工具链。
同一个 shell 运行 `all` 前须确保当前工具链确实支持全部 scheme；否则分环境构建。
这是一份源码多次编译，不是一份二进制直接换标签。

## 编译配置

主工程与面板共用插件专属 `*Build.mk`，统一架构、SDK 和目标系统版本。
默认架构是 `arm64 arm64e`，按设备和工具链能力明确调整，不静默删架构。
Rootless/Roothide 的最低部署版本至少为 15.0。
SDK 统一固定为 `16.5`，唯一生成配置为 `assets/defaults.json` 的 `sdk_version`。
生成器同时替换共享 `*Build.mk` 的 TARGET 与 CI 安装 SDK 的版本，不使用 `latest` 或 `last`。
不要在主 Makefile 或面板 Makefile 中再定义另一份 TARGET，否则会出现包含顺序覆盖。
本地构建前需要准备对应 SDK；GitHub 工作流负责下载配置的 SDK。

例如 Rootless 的 `TARGET = iphone:clang:16.5:15.0`，其中 `16.5` 是编译 SDK，
`15.0` 是最低部署版本，二者不是同一设置。Rootful 默认最低部署版本仍为 `14.0`。
固定 SDK 不是将插件限制为仅支持 iOS 16.5；实际系统兼容性还取决于代码及所用 API。
新增 API 超出该 SDK 时，应明确升级 `sdk_version` 并检查对应 SDK 和工具链是否可用，
而不是偷偷改成 `latest`。更改配置只影响之后生成的工程。

默认 `DEBUG ?= 0`、`FINALPACKAGE ?= 1`；调试时可显式传命令行覆盖。
ARC 由 `-fobjc-arc` 明确启用，不声称 Theos 所有项目默认 ARC。
保留编译警告，不加通用的 `-Wno-error` 或吞掉所有警告。

主工程自动收集 `Hooks/*.xm` 和 `Sources/*.m`，面板收集自身目录的 `.m`。
增加 `.mm`、`.x`、C/C++ 或子目录时，手动扩展对应文件清单；不会自动递归收集所有文件。
系统框架、私有框架和额外库按实际使用增加。

## deb 验收

产物通常位于项目的 `packages/`，实际以 Theos 输出为准：

```sh
dpkg-deb -I packages/实际包名.deb
dpkg-deb -c packages/实际包名.deb
```

逐个确认包名、版本、架构、依赖、注入过滤器、dylib、面板 bundle 和 PreferenceLoader 入口。
`layout/` 按未加越狱前缀的路径组织，由 scheme 处理安装布局；不要手动套两遍 `/var/jb`。
Scheme 的具体产物架构和处理方式以当前工具链为准，不仅凭源 `control` 推断。
图标与描述页 URL 只是生成的发布约定，不代表资源已上传或可访问。

安装、覆盖已有包、重启目标进程和注销设备属于后续明确操作，构建脚本不会自动执行。

## Minis

整个 skill 自包含，不需要复制 `ios-dev` 的证书、Apple ID 登录、配对或 IPA 安装脚本。
若 Minis 能加载目录型 skill，保留根 `SKILL.md` 和全部 `assets/`、`scripts/`、`references/`；
具体导入入口和压缩格式以该版本 Minis 的实际能力为准，这次未进行导入测试。

“能导入 skill”“能生成工程”“能在 Minis 内编译 deb”“能在越狱设备加载”是四件事。
先在 Minis 的工作目录执行生成与检查，再验证其 Theos/SDK/依赖，最后用对应设备验收 deb。
不能根据 `ios-dev` 的 IPA 工具链示例推定它已经具备 Theos 或越狱运行环境。
