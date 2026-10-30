//
//  ThemeCorePlusVersion.h —— 版本号。
//
//  唯一的版本来源：诊断串、日志标记、包描述都从这里取，避免三处不一致。
//  改版本时只改这一行，并同步 scripts/build-themecoreplus.sh 的 VERSION。
//
#pragma once

#define TCP_VERSION @"0.9.6"

// 面板最下方那个「运行日志」入口的开关（用户 2026-10-30 15:27）：
//   1 = 显示（开发/调试期，日志页要能随时翻、能分享）；
//   0 = 正式发布版去掉（改这一个数字即可，入口那一整段都消失）。
// 只影响设置面板的那一行；日志本身照旧记录，诊断串照旧写。
#ifndef TCP_PANEL_LOG_ENTRY
#define TCP_PANEL_LOG_ENTRY 1
#endif
