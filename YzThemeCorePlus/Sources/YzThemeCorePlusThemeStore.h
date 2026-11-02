#pragma once

#import <UIKit/UIKit.h>

// Loads the active theme once per reload and exposes O(1) resource
// lookups for high-frequency hooks. Directory scanning never happens
// inside a hook; it only happens on reload.
@interface YzThemeCorePlusThemeStore : NSObject

+ (instancetype)yz_themecoreplus_shared;

// Bumped on every reload; used in badge cache keys so a re-themed
// badge never collides with a stale SpringBoard cache entry.
@property (atomic, readonly) NSUInteger yz_themecoreplus_generation;

// YES when the active theme ships badge resources or BadgeSettings.
@property (atomic, readonly) BOOL yz_themecoreplus_hasBadgeConfiguration;

// Parsed Info.plist BadgeSettings of the active theme (may be empty).
@property (atomic, readonly) NSDictionary *yz_themecoreplus_badgeSettings;

- (void)yz_themecoreplus_reload;

// Boolean override from the active theme's Info.plist (e.g. IconCornerMask).
- (BOOL)yz_themecoreplus_themeFlagForKey:(NSString *)key defaultValue:(BOOL)defaultValue;

- (NSString *)yz_themecoreplus_iconPathForBundleID:(NSString *)bundleID scale:(CGFloat)scale;
- (UIImage *)yz_themecoreplus_badgeBackgroundImageForScale:(CGFloat)scale;
- (UIImage *)yz_themecoreplus_renderedIconForBundleID:(NSString *)bundleID
                                                 size:(CGSize)size
                                                scale:(CGFloat)scale
                                            applyMask:(BOOL)applyMask;

// SpringBoard 资源图（时钟表盘/指针等），按 Anemone 命名约定从主题里取：
//   <主题>/Bundles/com.apple.springboard/<name>@2x.png 或 <主题>/<name>@2x.png
- (UIImage *)yz_themecoreplus_springboardImageNamed:(NSString *)name scale:(CGFloat)scale;

// Preference panel support (called rarely).
- (NSArray<NSDictionary *> *)yz_themecoreplus_availableThemes;
- (NSUInteger)yz_themecoreplus_iconCountForThemeAtPath:(NSString *)path;

// 面板计数按「槽」分辨：图标槽数 icons/ + IconBundles/ + Bundles/，角标槽数 Badges/ +
// Bundles/com.apple.springboard/ 里的底板图（2026-11-02 用户报那个「(0 个图标)」的修法）。
+ (NSUInteger)yz_themecoreplus_countIconsInThemePath:(NSString *)themePath;
+ (NSUInteger)yz_themecoreplus_countBadgesInThemePath:(NSString *)themePath;
- (NSString *)yz_themecoreplus_activeThemeName;
- (UIColor *)yz_themecoreplus_colorWithCSSString:(NSString *)css;

@end
