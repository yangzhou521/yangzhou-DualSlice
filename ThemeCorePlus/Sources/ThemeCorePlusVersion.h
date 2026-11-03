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
//  1.0.11（2026-10-31）：时钟改成**逐片换图** —— 表盘写进视图自己的 layer、时针/分针写进
//  系统那 5 个 sublayer 的 contents，转动交还系统；同时修掉多位数字角标的胶囊几何。
//  1.0.12（2026-11-01）：针帽太大 —— 中轴层(l2)与秒针帽层(l4)不再写 redDot 素材，
//  交还系统自画（时针/分针/秒针继续用主题素材）。
//  1.0.15（2026-11-01）：角标多位数「条状」修复 —— 中间改用素材中列竖条横向拉伸（带渐变），玻璃素材不再出现纯色带；二至五位数同路径同修。
//
#pragma once

//  1.0.41（2026-11-03）：修「注销后进安全模式」。1.0.38 新写的
//  「SBIconController→iconManager→folderIconImageCache」链在 dyld 构造函数阶段被
//  TCPReload→TCPRefreshIconImages→TCPFolderNotifyRecalc 走到，
//  +[SBIconController sharedInstance]→-[SBUIController init]→+[UIScreen mainScreen]
//  →断言→SIGABRT（崩溃报告 SpringBoard-2026-11-03-040505.ips）。现在该链
//  （TCPLiveFolderImageCache / TCPFolderNotifyRecalc / TCPRefreshIconImages）全部过
//  TCPStoreImageWorkReady 闸门，构造函数阶段一律不碰 UIKit，+2 秒开闸后照旧刷新。
//  1.0.40：设置面板页脚去掉「越狱源」那一行与整条超链接（用户
//  「我没越狱源，点它没必要」），只留居中的「作者：yangzhou」。一级页/二级页同改，
//  只动 Prefs/，引擎源码未改。1.0.39 = 面板照 ThemeCore 对齐（页脚、二级页标题+组头）。
#define TCP_VERSION @"1.0.43"

// 面板最下方那个「运行日志」入口的开关（用户 2026-10-30 15:27）：
//   1 = 显示（开发/调试期，日志页要能随时翻、能分享）；
//   0 = 正式发布版去掉（改这一个数字即可，入口那一整段都消失）。
// 只影响设置面板的那一行；日志本身照旧记录，诊断串照旧写。
#ifndef TCP_PANEL_LOG_ENTRY
#define TCP_PANEL_LOG_ENTRY 1
#endif
