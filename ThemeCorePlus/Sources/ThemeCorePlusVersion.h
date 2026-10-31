//
//  ThemeCorePlusVersion.h —— 版本号。
//
//  唯一的版本来源：诊断串、日志标记、包描述都从这里取，避免三处不一致。
//  改版本时只改这一行，并同步 scripts/build-themecoreplus.sh 的 VERSION。
//  0.9.9：普查认真正的图标视图（私有类 SBIconImageView / SBFolderIconImageView，
//          它们不是 UIImageView 子类，上一版普查漏掉了它们）。
//  0.9.8：新增屏幕归属普查（census{}）：判断屏幕上挂的图到底是不是我们合成的。
//
//  0.9.7：面板去除素材标签，与 ThemeCore 0.5.1 一致。
//
#pragma once

#define TCP_VERSION @"0.9.20"

// 面板最下方那个「运行日志」入口的开关（用户 2026-10-30 15:27）：
//   1 = 显示（开发/调试期，日志页要能随时翻、能分享）；
//   0 = 正式发布版去掉（改这一个数字即可，入口那一整段都消失）。
// 只影响设置面板的那一行；日志本身照旧记录，诊断串照旧写。
#ifndef TCP_PANEL_LOG_ENTRY
#define TCP_PANEL_LOG_ENTRY 1
#endif
