---
status: running
task: ThemeCorePlus 1.0.24 秒加载
next: 装 deb 验证 cachecls= 与缓存层站
prev: 1.0.23 sites=18 无缓存层站
---
# 1.0.24 断点

- 代码已改完并云编译成功（sha 1427cc1 / run 41280514589）。
- deb 已下载到真根 Documents/tcp-1.0.24.deb。
- 卡点：等用户点装包弹窗（14:30 弹过一次，被取消）。
- 装完看：`sh scripts/device.sh read com.apple.springboard ThemeCorePlusDiagnostics` 里的 `cachecls=`、`sites=`。
