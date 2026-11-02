#pragma once

#import <Preferences/PSListController.h>

// 图标主题槽。读/写 IconTheme（回退旧键 ActiveTheme）。
@interface YzThemeCorePlusThemeListController : PSListController
- (NSString *)yz_themecoreplus_themeKind; // @"icon" / @"badge"，子类覆盖
@end

// 角标主题槽。读/写 BadgeTheme（回退旧键 ActiveTheme）。
@interface YzThemeCorePlusBadgeThemeListController : YzThemeCorePlusThemeListController
@end
