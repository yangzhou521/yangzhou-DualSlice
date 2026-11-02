#import "YzThemeCorePlusThemeListController.h"
#import "YzThemeCorePlusPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

// The preference bundle scans themes itself; the tweak dylib keeps its own
// snapshot inside SpringBoard. Same directory rules, no shared state needed.
static NSArray<NSString *> *yz_themecoreplus_themeRoots(void) {
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    for (NSString *logical in @[@"/Library/ThemeCore", @"/Library/Themes"]) {
        NSString *resolved = yz_themecoreplus_resourcePath(logical);
        if (resolved.length) [roots addObject:resolved];
    }
    [roots addObject:@"/var/mobile/Library/Themes"];
    return roots;
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
    return count;
}

@implementation YzThemeCorePlusThemeListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [NSMutableArray array];
        PSSpecifier *intro = [PSSpecifier preferenceSpecifierNamed:@"可用主题"
                                                            target:self set:nil get:nil
                                                            detail:nil cell:PSGroupCell edit:nil];
        [intro setProperty:@"图标：icons/<bundleid>@2x.png 或 Bundles/<bundleid>/icon@2x.png；角标：Badges/SBBadgeBG.png + Info.plist BadgeSettings。"
                   forKey:@"footerText"];
        [items addObject:intro];

        PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:@"不使用主题（恢复原版图标）"
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
            [list setProperty:[NSString stringWithFormat:@"当前主题：%@", active] forKey:@"footerText"];
        } else {
            [list setProperty:@"当前未启用任何主题。" forKey:@"footerText"];
        }
        [items addObject:list];

        for (NSDictionary *theme in [self yz_themecoreplus_scanThemes]) {
            NSString *name = theme[@"name"];
            PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:
                [NSString stringWithFormat:@"%@（%@ 个图标）", name, theme[@"iconCount"]]
                target:self set:@selector(setPreferenceValue:specifier:)
                  get:@selector(readPreferenceValue:)
                detail:nil cell:PSSwitchCell edit:nil];
            [row setProperty:name forKey:@"themeName"];
            [row setProperty:@"ActiveTheme" forKey:@"key"];
            [row setProperty:@(NO) forKey:@"default"];
            [items addObject:row];
        }
        _specifiers = items;
    }
    return _specifiers;
}

- (NSString *)yz_themecoreplus_activeTheme {
    id value = yz_themecoreplus_readPreferences()[@"ActiveTheme"];
    return [value isKindOfClass:[NSString class]] ? value : nil;
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
                                @"iconCount": @(yz_themecoreplus_countIcons(path))}];
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
        ok = yz_themecoreplus_writePreference(@"ActiveTheme", themeName, &error);
    } else {
        ok = yz_themecoreplus_writePreference(@"ActiveTheme", nil, &error);
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
    if (!yz_themecoreplus_writePreference(@"ActiveTheme", nil, &error)) {
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
