# 自定义滑条组件

只有确实需要数值行时才选 `--preferences --slider`。
完整代码只维护在 `assets/slider/`，由生成器与面板模板组合。
每个项目得到自己的 `*SliderCell`、`*SliderCellHandler` 和插件专属 selector。

## 分工

| 文件 | 负责内容 |
|---|---|
| `*SliderCell.h/.m` | 左标题、中滑条、右数值；控件复用、无障碍和事件 |
| `specifier.inc` | 添加到面板规格的示例行；默认值、最小值、最大值 |
| `controller.inc` | 面板挂 handler、读取、夹紧和调用统一保存 |
| 面板 `setPreferenceValue:specifier:` | 真正写配置、发通知或展示保存失败 |

拖动时只刷新数值，松手提交；VoiceOver 调整可直接提交，因为不一定产生触摸结束事件。
handler 为弱引用，复用时清空；显示时重新挂接并读取配置。
显式 import `PSTableCell.h`，不依赖其他头文件间接声明。
不使用 `accessoryView + detailTextLabel` 拼接右侧数值列。

## 手动维护

在生成项目的插件专属 `*Root.plist` 中修改这一行的 `label`、`key`、`default`、`min`、`max`。
读写都经控制器，不给每行另建 defaults 域或私有写文件逻辑。
多个滑条复用同一个插件专属 cell，只增加 specifier，不重复复制类。
消费端对缺键、非数字、越界值也要定义合适回退；UI 夹紧不能替代业务层输入校验。

默认数值格式是一位小数。要显示百分比或单位，改 cell 的插件专属 `updateLabel` 方法，
并确认存储值使用 0~1 还是 0~100，不要只改文本却误改实际范围。

模板提供基本三段排版，长标题截尾、数值可缩小；仍需按目标设备验收小屏、旋转、大字号和 VoiceOver。
静态工程检查不能替代真实 Preferences UI 验收。

## 常见问题

- 数值不刷新：检查 handler 挂接、配置 key 和 specifier 的 `default`。
- 滑条回弹：先看面板的保存错误，再检查目标文件路径，不要先用注销掩盖问题。
- 类找不到：确认 `.m` 在面板自身目录，面板 Makefile 收集了该文件。
- 原生 cell 与本组件混用：允许，但必须共用控制器读写通道，避免一部分读文件、一部分只读旧缓存。
