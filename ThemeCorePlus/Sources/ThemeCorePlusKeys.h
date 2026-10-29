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
// 生效的主题：ThemePath 是绝对路径（优先），ThemeName 是在主题根目录里按名字找。
// 两个都不给 = 不挂主题 = 系统原生外观（回滚就是这么做的）。
static NSString * const TCPKeyThemePath = @"ThemePath";
static NSString * const TCPKeyThemeName = @"ThemeName";
// 功能独立开关，各自默认开。
static NSString * const TCPKeyIconsEnabled = @"IconsEnabled";
static NSString * const TCPKeyFoldersEnabled = @"FoldersEnabled";
static NSString * const TCPKeyBadgesEnabled = @"BadgesEnabled";
static NSString * const TCPKeyFilesEnabled = @"FilesEnabled";
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
