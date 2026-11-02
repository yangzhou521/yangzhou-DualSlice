#import "YzThemeCorePlusThemeListController.h"
#import "YzThemeCorePlusPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

// The preference bundle scans themes itself; the tweak dylib keeps its own
// snapshot inside SpringBoard. Same directory rules, no shared state needed.
// 5.3.0：图标与角标各一个槽（用户 2026-11-02 报的「只能二选一」）。
// 行文案的计数也按槽算：图标槽数 icons/ + IconBundles/ + Bundles/，
// 角标槽数 Badges/ + Bundles/com.apple.springboard/ 的底板图。
static NSArray<NSString *> *yz_themecoreplus_themeRoots(void) {
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    for (NSString *logical in @[@"/Library/ThemeCore", @"/Library/Themes"]) {
        NSString *resolved = yz_themecoreplus_resourcePath(logical);
        if (resolved.length) [roots addObject:resolved];
    }
    [roots addObject:@"/var/mobile/Library/Themes"];
    return roots;
}

// 一个 bundle 只算一次（-large 与 @2x 同属一个图标）。
static NSUInteger yz_themecoreplus_countIconBundles(NSString *themePath) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    NSString *dir = [themePath stringByAppendingPathComponent:@"IconBundles"];
    for (NSString *file in [manager contentsOfDirectoryAtPath:dir error:nil]) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
        NSString *base = [file stringByDeletingPathExtension];
        if ([base hasSuffix:@"~iphone"]) base = [base substringToIndex:base.length - 7];
        if ([base hasSuffix:@"-large"]) base = [base substringToIndex:base.length - 6];
        NSRange at = [base rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) base = [base substringToIndex:at.location];
        if (base.length) [ids addObject:base.lowercaseString];
    }
    return ids.count;
}

static NSUInteger yz_themecoreplus_countIcons(NSString *themePath) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSUInteger count = 0;
    NSString *iconsDir = [themePath stringByAppendingPathComponent:@"icons"];
    for (NSString *file in [manager contentsOfDirectoryAtPath:iconsDir error:nil]) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"png"]) count++;
    }
    NSString *bundlesDir = [themePath stringByAppendingPathComponent:@"Bundles"];
    for (NSString *bundleID in [manager contentsOfDirectoryAtPath:bundlesDir error:nil]) {
        NSString *bundleDir = [bundlesDir stringByAppendingPathComponent:bundleID];
        BOOL isDirectory = NO;
        if (![manager fileExistsAtPath:bundleDir isDirectory:&isDirectory] || !isDirectory) continue;
        for (NSString *candidate in @[@"icon@3x.png", @"icon@2x.png", @"icon@2x~iphone.png",
                                      @"icon~iphone.png", @"icon.png"]) {
            if ([manager fileExistsAtPath:[bundleDir stringByAppendingPathComponent:candidate]]) {
                count++;
                break;
            }
        }
    }
    return count + yz_themecoreplus_countIconBundles(themePath);
}

static NSUInteger yz_themecoreplus_countBadges(NSString *themePath) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSUInteger count = 0;
    for (NSString *dir in @[@"Badges", @"Bundles/com.apple.springboard", @""]) {
        NSString *dirPath = dir.length
            ? [themePath stringByAppendingPathComponent:dir] : themePath;
        for (NSString *file in [manager contentsOfDirectoryAtPath:dirPath error:nil]) {
            NSString *lower = file.lowercaseString;
            if (![lower hasSuffix:@".png"]) continue;
            if ([lower containsString:@"badgebg"] || [lower containsString:@"badgebackground"]) {
                count++;
            }
        }
    }
    return count;
}

@implementation YzThemeCorePlusThemeListController

- (NSString *)yz_themecoreplus_themeKind {
    return @"icon";
}

// 图标槽 → IconTheme；角标槽 → BadgeTheme；都没设时回退旧键 ActiveTheme。
- (NSString *)yz_themecoreplus_themeKey {
    if ([[self yz_themecoreplus_themeKind] isEqualToString:@"badge"]) return @"BadgeTheme";
    return @"IconTheme";
}

- (NSString *)yz_themecoreplus_activeTheme {
    id value = yz_themecoreplus_readPreferences()[[self yz_themecoreplus_themeKey]];
    if (![value isKindOfClass:[NSString class]]) {
        value = yz_themecoreplus_readPreferences()[@"ActiveTheme"];
    }
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [NSMutableArray array];
        BOOL isBadge = [[self yz_themecoreplus_themeKind] isEqualToString:@"badge"];

        PSSpecifier *intro = [PSSpecifier preferenceSpecifierNamed:@"可用主题"
                                                            target:self set:nil get:nil
                                                            detail:nil cell:PSGroupCell edit:nil];
        [intro setProperty:isBadge
            ? @"角标主题素材：Badges/SBBadgeBG.png 或 Bundles/com.apple.springboard/SBBadgeBG.png，可配 Info.plist BadgeSettings。"
            : @"图标主题素材：icons/<bundleid>@2x.png、IconBundles/<bundleid>-large.png 或 Bundles/<bundleid>/icon@2x.png。"
                   forKey:@"footerText"];
        [items addObject:intro];

        PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:
            isBadge ? @"不使用角标主题（恢复原版角标）" : @"不使用图标主题（恢复原版图标）"
                                                            target:self set:nil get:nil
                                                            detail:nil cell:PSButtonCell edit:nil];
        clear.buttonAction = @selector(yz_themecoreplus_clearTheme:);
        [items addObject:clear];

        NSString *active = [self yz_themecoreplus_activeTheme];
        BOOL hasActive = active.length > 0;
        PSSpecifier *list = [PSSpecifier preferenceSpecifierNamed:@"主题列表"
                                                           target:self set:nil get:nil
                                                           detail:nil cell:PSGroupCell edit:nil];
        if (hasActive) {
            [list setProperty:[NSString stringWithFormat:@"当前%@主题：%@",
                               isBadge ? @"角标" : @"图标", active] forKey:@"footerText"];
        } else {
            [list setProperty:@"当前未启用。" forKey:@"footerText"];
        }
        [items addObject:list];

        for (NSDictionary *theme in [self yz_themecoreplus_scanThemes]) {
            NSString *name = theme[@"name"];
            NSUInteger count = isBadge
                ? [theme[@"badgeCount"] unsignedIntegerValue]
                : [theme[@"iconCount"] unsignedIntegerValue];
            PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:
                [NSString stringWithFormat:@"%@（%lu 个%@）", name, (unsigned long)count,
                                           isBadge ? @"角标" : @"图标"]
                target:self set:@selector(setPreferenceValue:specifier:)
                  get:@selector(readPreferenceValue:)
                detail:nil cell:PSSwitchCell edit:nil];
            [row setProperty:name forKey:@"themeName"];
            [row setProperty:[self yz_themecoreplus_themeKey] forKey:@"key"];
            [row setProperty:@(NO) forKey:@"default"];
            [items addObject:row];
        }
        _specifiers = items;
    }
    return _specifiers;
}

- (NSArray<NSDictionary *> *)yz_themecoreplus_scanThemes {
    NSMutableArray<NSDictionary *> *themes = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *root in yz_themecoreplus_themeRoots()) {
        for (NSString *entry in [manager contentsOfDirectoryAtPath:root error:nil]) {
            if ([entry hasPrefix:@"."]) continue;
            BOOL isDirectory = NO;
            NSString *path = [root stringByAppendingPathComponent:entry];
            if (![manager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) continue;
            NSString *name = entry;
            if ([name.pathExtension.lowercaseString isEqualToString:@"theme"]) {
                name = [name stringByDeletingPathExtension];
            }
            NSString *key = name.lowercaseString;
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            [themes addObject:@{@"name": name,
                                @"path": path,
                                @"iconCount": @(yz_themecoreplus_countIcons(path)),
                                @"badgeCount": @(yz_themecoreplus_countBadges(path))}];
        }
    }
    return themes;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *themeName = [specifier propertyForKey:@"themeName"];
    return @([[self yz_themecoreplus_activeTheme].lowercaseString
        isEqualToString:themeName.lowercaseString]);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (![value isKindOfClass:[NSNumber class]]) return;
    NSString *themeName = [specifier propertyForKey:@"themeName"];
    BOOL turningOn = [value boolValue];
    NSString *active = [self yz_themecoreplus_activeTheme];
    BOOL isActive = [active.lowercaseString isEqualToString:themeName.lowercaseString];
    if (turningOn == isActive) return;

    NSError *error = nil;
    BOOL ok;
    if (turningOn) {
        ok = yz_themecoreplus_writePreference([self yz_themecoreplus_themeKey], themeName, &error);
    } else {
        ok = yz_themecoreplus_writePreference([self yz_themecoreplus_themeKey], nil, &error);
    }
    if (!ok) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"主题未切换"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)yz_themecoreplus_clearTheme:(PSSpecifier *)sender {
    NSError *error = nil;
    if (!yz_themecoreplus_writePreference([self yz_themecoreplus_themeKey], nil, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"主题未切换"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    _specifiers = nil;
    [self reloadSpecifiers];
}

@end

@implementation YzThemeCorePlusBadgeThemeListController

- (NSString *)yz_themecoreplus_themeKind {
    return @"badge";
}

@end