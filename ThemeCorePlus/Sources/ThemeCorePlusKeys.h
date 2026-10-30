//
//  ThemeCorePlusKeys.h —— 配置键名。
//
//  一处定义，三处共用：dylib 读、管理器 App 写、shell 验证时往 config.plist 里塞。
//  键名不带前缀：它们只活在我们自己的偏好域 com.yangzhou.themecoreplus 里。
//
#pragma once

#import <Foundation/Foundation.h>

// 总开关。键不存在时视为开（主题里没有对应素材时插件本身就是空转）。
static NSString * const TCPKeyEnabled = @"Enabled";
// 生效的主题（单个，旧写法）：ThemePath 是绝对路径（优先），ThemeName 是在主题根目录里按名字找。
// 两个都不给 = 不挂主题 = 系统原生外观（回滚就是这么做的）。
static NSString * const TCPKeyThemePath = @"ThemePath";
static NSString * const TCPKeyThemeName = @"ThemeName";
// 多主题叠加：绝对路径的**有序数组**，顺序就是叠加顺序 —— **数组中靠后的覆盖靠前的**
// （面板里「第 N 层」越大越上层）。这个键存在且非空时优先，ThemePath / ThemeName 只是兼容旧配置。
static NSString * const TCPKeyThemePaths = @"ThemePaths";
// 最多叠几层：每层都要整目录扫一遍，层数太多拖慢重载，也没法排查是哪层出的问题。
// 面板勾到第 9 层会直接拒绝并说明，store 侧也按这个数截断（两边同一个常量）。
static const NSUInteger TCPMaxThemeLayers = 8;
// 分类素材开关已删（用户 2026-10-30 16:59）：IconsEnabled / FoldersEnabled / BadgesEnabled /
// FilesEnabled 四个键不再使用 —— 四类素材一律全换，没有分类开关，所以键也从这里去掉。
// 图标圆角遮罩（没有作者遮罩素材时的兜底）。默认关：先保证不动原图。
static NSString * const TCPKeyIconCornerMask = @"IconCornerMask";
// 作者素材：主题目录下的相对路径。缺省时按内置候选名去找。
static NSString * const TCPKeyAuthorMask = @"AuthorMask";
static NSString * const TCPKeyBaseImage = @"BaseImage";
static NSString * const TCPKeyIconOverlay = @"IconOverlay";
// 角标文字样式（可选）：颜色用 #RRGGBB，字体名是 PostScript 名。
static NSString * const TCPKeyBadgeTextColor = @"BadgeTextColor";
static NSString * const TCPKeyBadgeFontName = @"BadgeFontName";
static NSString * const TCPKeyBadgeFontSize = @"BadgeFontSize";
// 诊断键名：dylib 写到**目标进程自己的**偏好域（沙箱只允许写自己的域），
// 所以 SpringBoard 里的诊断在 com.apple.springboard 域。
static NSString * const TCPKeyDiagnostics = @"ThemeCorePlusDiagnostics";
// 运行日志（ThemeCorePlusLog.h）：同样写在目标进程自己的域，面板跨域读它显示/复制。
// 与诊断分开是有原因的：诊断在每次 reload 被整串覆盖，中间发生的事只有日志留得住。
static NSString * const TCPKeyRuntimeLog = @"ThemeCorePlusLog";
// 是否记日志（默认开）。排查完可以关掉，省得白写盘。
static NSString * const TCPKeyLogEnabled = @"LogEnabled";
