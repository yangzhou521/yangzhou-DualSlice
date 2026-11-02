#import "YzThemeCorePlusThemeStore.h"
#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusPaths.h"
#import "YzThemeCorePlusPrivate.h"   // UIKit 私有圆角方法 bezierPathWithRoundedRect:byRoundingCorners:cornerInsets: 的声明

// Directory conventions kept compatible with the existing ecosystem:
//   <jbroot>/Library/ThemeCore/<Theme>/IconBundles/<bundleid>[-large][@2x].png (SnowBoard/IconBundles)
//   <jbroot>/Library/ThemeCore/<Theme>/icons/<bundleid>@2x.png          (ThemeCore)
//   <jbroot>/Library/Themes/<Name>.theme/Bundles/<bundleid>/icon@2x.png (Anemone)
//   /var/mobile/Library/Themes/<Name>.theme/...                         (mobile themes)
//   Badges/SBBadgeBG@2x.png or SBBadgeBG.png                            (badge background)

static NSString * const kCompatThemeDir = @"/Library/ThemeCore";
static NSString * const kSystemThemeDir = @"/Library/Themes";
static NSString * const kMobileThemeDir = @"/var/mobile/Library/Themes";

static NSArray<NSString *> *yz_themecoreplus_themeRootDirectories(void) {
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *compat = yz_themecoreplus_resourcePath(kCompatThemeDir);
    if (compat.length) [roots addObject:compat];
    NSString *system = yz_themecoreplus_resourcePath(kSystemThemeDir);
    if (system.length) [roots addObject:system];
    [roots addObject:kMobileThemeDir];
    return roots;
}

static NSDictionary *yz_themecoreplus_themeInfoPlistAtPath(NSString *themePath) {
    for (NSString *candidate in @[@"Info.plist", @"themeinfo.plist"]) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
            [themePath stringByAppendingPathComponent:candidate]];
        if (info.count > 0) return info;
    }
    return @{};
}

static NSString *yz_themecoreplus_themeNameValue(id value) {
    return ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0)
        ? (NSString *)value : nil;
}

static NSDictionary *yz_themecoreplus_badgeSettingsFromInfo(NSDictionary *info) {
    id settings = info[@"BadgeSettings"] ?: info[@"ThemeLib-BadgeSettings"];
    return [settings isKindOfClass:[NSDictionary class]] ? settings : @{};
}

@implementation YzThemeCorePlusThemeStore {
    NSUInteger _generation;
    NSCache *_renderCache;
    // bundleID(lowercased) -> @{@"3": path, @"2": path, @"0": path}
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *_iconPaths;
    NSDictionary<NSString *, NSString *> *_badgeBackgroundPaths;
    NSDictionary *_themeInfo;          // 图标主题的 Info.plist（可能为空）
    NSDictionary *_badgeThemeInfo;     // 角标主题的 Info.plist
    NSString *_activeThemePath;        // 图标主题的目录
    NSString *_badgeThemePath;         // 角标主题的目录
    NSDictionary *_badgeSettings;
    BOOL _hasBadgeConfiguration;
}

+ (instancetype)yz_themecoreplus_shared {
    static YzThemeCorePlusThemeStore *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _renderCache = [[NSCache alloc] init];
        [_renderCache setCountLimit:512];
        [self yz_themecoreplus_reload];
    }
    return self;
}

- (NSUInteger)yz_themecoreplus_generation {
    return _generation;
}

- (NSDictionary *)yz_themecoreplus_badgeSettings {
    return _badgeSettings;
}

- (BOOL)yz_themecoreplus_hasBadgeConfiguration {
    return _hasBadgeConfiguration;
}

- (NSString *)yz_themecoreplus_activeThemeName {
    return _activeThemePath.lastPathComponent;
}

- (void)yz_themecoreplus_reload {
    YzThemeCorePlusConfig *config = [YzThemeCorePlusConfig yz_themecoreplus_shared];
    // 图标与角标各一个槽（用户 2026-11-02 16:10 报的「只能二选一」）。
    // 旧键 ActiveTheme 保留兼容：哪个槽没设，就用它补哪个。
    NSString *legacy = yz_themecoreplus_themeNameValue(
        [config yz_themecoreplus_valueForKey:@"ActiveTheme" defaultValue:nil]);
    NSString *iconName = yz_themecoreplus_themeNameValue(
        [config yz_themecoreplus_valueForKey:@"IconTheme" defaultValue:nil]) ?: legacy;
    NSString *badgeName = yz_themecoreplus_themeNameValue(
        [config yz_themecoreplus_valueForKey:@"BadgeTheme" defaultValue:nil]) ?: legacy;

    NSString *iconPath = [self.class yz_themecoreplus_themePathForName:iconName];
    NSString *badgePath = [self.class yz_themecoreplus_themePathForName:badgeName];

    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *iconPaths = @{};
    NSDictionary<NSString *, NSString *> *badgePaths = @{};
    NSDictionary *themeInfo = @{};
    NSDictionary *badgeThemeInfo = @{};
    NSDictionary *badgeSettings = @{};

    if (iconPath) {
        themeInfo = yz_themecoreplus_themeInfoPlistAtPath(iconPath);
        iconPaths = [self.class yz_themecoreplus_iconMapForThemePath:iconPath];
    }
    if (badgePath) {
        badgeThemeInfo = yz_themecoreplus_themeInfoPlistAtPath(badgePath);
        badgePaths = [self.class yz_themecoreplus_badgeMapForThemePath:badgePath];
        badgeSettings = yz_themecoreplus_badgeSettingsFromInfo(badgeThemeInfo);
    }

    // 旧主题一身两用：图标槽里可能有角标素材，角标槽里可能有图标素材。
    // 缺的那一边互相补位，免得用户只选了一个槽就丢掉另一类资源。
    if (iconPaths.count == 0 && badgePath) {
        iconPaths = [self.class yz_themecoreplus_iconMapForThemePath:badgePath];
        if (themeInfo.count == 0) themeInfo = badgeThemeInfo;
    }
    if (badgePaths.count == 0 && badgeSettings.count == 0 && iconPath) {
        badgePaths = [self.class yz_themecoreplus_badgeMapForThemePath:iconPath];
        badgeSettings = yz_themecoreplus_badgeSettingsFromInfo(themeInfo);
    }

    BOOL hasBadge = badgePaths.count > 0 || badgeSettings.count > 0;

    // Atomic swap; hooks read these dictionaries concurrently.
    _iconPaths = iconPaths;
    _badgeBackgroundPaths = badgePaths;
    _themeInfo = themeInfo;
    _badgeThemeInfo = badgeThemeInfo;
    _badgeSettings = badgeSettings;
    _hasBadgeConfiguration = hasBadge;
    _activeThemePath = iconPath;
    _badgeThemePath = badgePath;
    [_renderCache removeAllObjects];
    _generation = _generation + 1;
}

// 主题名 → 目录（先 /Library/ThemeCore，再 /Library/Themes，最后 /var/mobile/Library/Themes；
// 目录名带不带 .theme 都认）。
+ (NSString *)yz_themecoreplus_themePathForName:(NSString *)name {
    if (name.length == 0) return nil;
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *root in yz_themecoreplus_themeRootDirectories()) {
        for (NSString *suffix in @[@"", @".theme"]) {
            NSString *candidate = [[root stringByAppendingPathComponent:name]
                stringByAppendingString:suffix];
            if ([manager fileExistsAtPath:candidate]) return candidate;
        }
    }
    return nil;
}

#pragma mark - Resource maps

// Enumerates the theme once; hooks only ever read the finished map.
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)yz_themecoreplus_iconMapForThemePath:(NSString *)themePath {
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *map = [NSMutableDictionary dictionary];
    NSFileManager *manager = [NSFileManager defaultManager];

    void (^registerVariant)(NSString *, CGFloat, NSString *) = ^(NSString *baseID, CGFloat scale, NSString *path) {
        if (baseID.length == 0 || path.length == 0) return;
        NSString *key = baseID.lowercaseString;
        NSMutableDictionary *variants = map[key] ?: [NSMutableDictionary dictionary];
        if (!variants[@(scale).stringValue]) variants[@(scale).stringValue] = path;
        map[key] = variants;
    };

    NSString *iconsDir = [themePath stringByAppendingPathComponent:@"icons"];
    for (NSString *file in [manager contentsOfDirectoryAtPath:iconsDir error:nil]) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
        NSString *base = [file stringByDeletingPathExtension];
        CGFloat scale = 0;
        NSRange at = [base rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) {
            NSString *suffix = [base substringFromIndex:at.location];
            base = [base substringToIndex:at.location];
            if ([suffix isEqualToString:@"@3x"]) scale = 3;
            else if ([suffix isEqualToString:@"@2x"]) scale = 2;
            else if ([suffix isEqualToString:@"@1x"]) scale = 1;
            else continue; // "@2x~iphone" style suffixes only appear in Bundles/ layouts
        }
        registerVariant(base, scale, [iconsDir stringByAppendingPathComponent:file]);
    }

    // SnowBoard / IconBundles 格式（2026-11-02 加）：IconBundles/<bid>-large.png = 高分辨率那档，
    // <bid>@Nx.png 自带档位，<bid>.png = 任意档（按 0 记，取图时兜底）。
    // 本机「液态玻璃」的 84 个图标全在这里 —— 旧版只读 icons/ 与 Bundles/，一个都认不到，
    // 于是面板显示「(0 个图标)」、桌面一个图标也不换。这是两个 bug 的同一个根。
    NSString *iconBundlesDir = [themePath stringByAppendingPathComponent:@"IconBundles"];
    for (NSString *file in [manager contentsOfDirectoryAtPath:iconBundlesDir error:nil]) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
        NSString *base = [file stringByDeletingPathExtension];
        if ([base hasSuffix:@"~iphone"]) base = [base substringToIndex:base.length - 7];
        CGFloat scale = 0;
        if ([base hasSuffix:@"-large"]) {
            base = [base substringToIndex:base.length - 6];
            scale = 3;
        }
        NSRange at = [base rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) {
            NSString *suffix = [base substringFromIndex:at.location];
            base = [base substringToIndex:at.location];
            if ([suffix isEqualToString:@"@3x"]) scale = 3;
            else if ([suffix isEqualToString:@"@2x"]) scale = 2;
            else if ([suffix isEqualToString:@"@1x"]) scale = 1;
            else continue;
        }
        registerVariant(base, scale, [iconBundlesDir stringByAppendingPathComponent:file]);
    }

    NSString *bundlesDir = [themePath stringByAppendingPathComponent:@"Bundles"];
    for (NSString *bundleID in [manager contentsOfDirectoryAtPath:bundlesDir error:nil]) {
        NSString *bundleDir = [bundlesDir stringByAppendingPathComponent:bundleID];
        BOOL isDirectory = NO;
        if (![manager fileExistsAtPath:bundleDir isDirectory:&isDirectory] || !isDirectory) continue;
        for (NSString *candidate in @[@"icon@3x.png", @"icon@2x.png", @"icon@2x~iphone.png",
                                      @"icon~iphone.png", @"icon.png"]) {
            NSString *path = [bundleDir stringByAppendingPathComponent:candidate];
            if (![manager fileExistsAtPath:path]) continue;
            CGFloat scale = 0;
            if ([candidate containsString:@"@3x"]) scale = 3;
            else if ([candidate containsString:@"@2x"]) scale = 2;
            registerVariant(bundleID, scale, path);
            break;
        }
    }
    return map;
}

// 文件名 → 它在 SnowBoard/Anemone 里声明的档位（0 = 没写档位，取图时按 3→2→0 兜底）。
static CGFloat yz_themecoreplus_scaleFromFileName(NSString *file) {
    NSString *base = [file stringByDeletingPathExtension];
    if ([base hasSuffix:@"-large"]) return 3;
    NSRange at = [base rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location == NSNotFound) return 0;
    NSString *suffix = [base substringFromIndex:at.location];
    if ([suffix hasPrefix:@"@3x"]) return 3;
    if ([suffix hasPrefix:@"@2x"]) return 2;
    if ([suffix hasPrefix:@"@1x"]) return 1;
    return 0;
}

static BOOL yz_themecoreplus_isBadgeBackgroundFileName(NSString *file) {
    NSString *lower = file.lowercaseString;
    if (![lower hasSuffix:@".png"]) return NO;
    // SBBadgeBG / SBBadgeBackground / BadgeBG 三种常见命名都收。
    return [lower containsString:@"badgebg"] || [lower containsString:@"badgebackground"];
}

+ (NSDictionary<NSString *, NSString *> *)yz_themecoreplus_badgeMapForThemePath:(NSString *)themePath {
    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSString *> *dirs = @[@"Badges", @"Bundles/com.apple.springboard", @""];
    for (NSString *dir in dirs) {
        NSString *dirPath = dir.length ? [themePath stringByAppendingPathComponent:dir] : themePath;
        NSArray<NSString *> *files = [manager contentsOfDirectoryAtPath:dirPath error:nil] ?: @[];
        for (NSString *file in files) {
            if (!yz_themecoreplus_isBadgeBackgroundFileName(file)) continue;
            NSString *key = @(yz_themecoreplus_scaleFromFileName(file)).stringValue;
            if (!map[key]) map[key] = [dirPath stringByAppendingPathComponent:file];
        }
    }
    return map;
}

- (NSString *)yz_themecoreplus_iconPathForBundleID:(NSString *)bundleID scale:(CGFloat)scale {
    if (bundleID.length == 0) return nil;
    NSDictionary *variants = _iconPaths[bundleID.lowercaseString];
    if (!variants) return nil;
    for (NSNumber *candidate in @[@(scale), @3, @2, @0]) {
        NSString *path = variants[candidate.stringValue];
        if (path) return path;
    }
    return nil;
}

#pragma mark - Rendering

- (UIImage *)yz_themecoreplus_badgeBackgroundImageForScale:(CGFloat)scale {
    NSString *path = nil;
    for (NSNumber *candidate in @[@(scale), @3, @2, @0]) {
        path = _badgeBackgroundPaths[candidate.stringValue];
        if (path) break;
    }
    if (!path) return nil;
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image) return nil;
    CGSize pixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    if (pixels.width < 8 || pixels.height < 8) return image;
    // The stock badge background stretches as the text grows; apply matching
    // cap insets so rounded corners survive wide "99+" badges.
    UIEdgeInsets cap = UIEdgeInsetsMake(pixels.height * 0.4, pixels.width * 0.4,
                                        pixels.height * 0.4, pixels.width * 0.4);
    return [image resizableImageWithCapInsets:cap resizingMode:UIImageResizingModeStretch];
}

- (BOOL)yz_themecoreplus_themeFlagForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = _themeInfo[key];
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    return defaultValue;
}

- (UIImage *)yz_themecoreplus_renderedIconForBundleID:(NSString *)bundleID
                                                 size:(CGSize)size
                                                scale:(CGFloat)scale
                                            applyMask:(BOOL)applyMask {
    if (size.width <= 0 || size.height <= 0) return nil;
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.0f|%.0f|%.0f|%lu|%d",
        bundleID.lowercaseString, size.width, size.height, scale,
        (unsigned long)_generation, applyMask ? 1 : 0];
    UIImage *cached = [_renderCache objectForKey:cacheKey];
    if (cached) return cached;

    NSString *path = [self yz_themecoreplus_iconPathForBundleID:bundleID scale:scale];
    if (!path) return nil;
    UIImage *raw = [UIImage imageWithContentsOfFile:path];
    if (!raw) return nil;

    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = scale > 0 ? scale : raw.scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect bounds = CGRectMake(0, 0, size.width, size.height);
        if (applyMask) {
            CGFloat radius = 0.2237 * MIN(size.width, size.height);
            // 交付版用 UIKit 私有 `…cornerInsets:`；本机 UIKit 没实现它时会 unrecognized selector
            // 崩在 SpringBoard，所以先探再用，退回公开的 `…cornerRadii:`（几何等价）。
            UIBezierPath *mask = nil;
            if ([UIBezierPath respondsToSelector:NSSelectorFromString(
                    @"bezierPathWithRoundedRect:byRoundingCorners:cornerInsets:")]) {
                mask = [UIBezierPath bezierPathWithRoundedRect:bounds
                                             byRoundingCorners:UIRectCornerAllCorners
                                                 cornerInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
            } else {
                mask = [UIBezierPath bezierPathWithRoundedRect:bounds
                                             byRoundingCorners:UIRectCornerAllCorners
                                                 cornerRadii:CGSizeMake(radius, radius)];
            }
            [mask addClip];
        }
        [raw drawInRect:bounds];
    }];
    if (result) [_renderCache setObject:result forKey:cacheKey];
    return result;
}

- (UIImage *)yz_themecoreplus_springboardImageNamed:(NSString *)name scale:(CGFloat)scale {
    if (name.length == 0 || _activeThemePath.length == 0) return nil;
    NSArray<NSString *> *dirs = @[
        [_activeThemePath stringByAppendingPathComponent:@"Bundles/com.apple.springboard"],
        _activeThemePath,
    ];
    NSArray<NSString *> *suffixes = @[@"@3x", @"@2x", @""];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        for (NSString *suf in suffixes) {
            NSString *path = [[dir stringByAppendingPathComponent:name] stringByAppendingFormat:@"%@.png", suf];
            if ([fm fileExistsAtPath:path]) {
                UIImage *img = [UIImage imageWithContentsOfFile:path];
                if (img) return img;
            }
        }
    }
    return nil;
}

#pragma mark - Theme listing (preference panel / diagnostics)

+ (NSUInteger)yz_themecoreplus_countIconsInThemePath:(NSString *)themePath {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSUInteger count = 0;
    NSString *iconsDir = [themePath stringByAppendingPathComponent:@"icons"];
    for (NSString *file in [manager contentsOfDirectoryAtPath:iconsDir error:nil]) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"png"]) count++;
    }
    // IconBundles/：一个 bundle 只算一次（-large 与 @2x 同属一个图标）。
    NSMutableSet<NSString *> *iconBundlesIDs = [NSMutableSet set];
    NSString *iconBundlesDir = [themePath stringByAppendingPathComponent:@"IconBundles"];
    for (NSString *file in [manager contentsOfDirectoryAtPath:iconBundlesDir error:nil]) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
        NSString *base = [file stringByDeletingPathExtension];
        if ([base hasSuffix:@"~iphone"]) base = [base substringToIndex:base.length - 7];
        if ([base hasSuffix:@"-large"]) base = [base substringToIndex:base.length - 6];
        NSRange at = [base rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) base = [base substringToIndex:at.location];
        if (base.length) [iconBundlesIDs addObject:base.lowercaseString];
    }
    count += iconBundlesIDs.count;

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

+ (NSUInteger)yz_themecoreplus_countBadgesInThemePath:(NSString *)themePath {
    return [self yz_themecoreplus_badgeMapForThemePath:themePath].count;
}

+ (NSArray<NSDictionary *> *)yz_themecoreplus_scanThemes {
    NSMutableArray<NSDictionary *> *themes = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *root in yz_themecoreplus_themeRootDirectories()) {
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
            [themes addObject:@{
                @"name": name,
                @"path": path,
                @"iconCount": @([self yz_themecoreplus_countIconsInThemePath:path]),
                @"badgeCount": @([self yz_themecoreplus_countBadgesInThemePath:path]),
            }];
        }
    }
    return themes;
}

- (NSArray<NSDictionary *> *)yz_themecoreplus_availableThemes {
    return [self.class yz_themecoreplus_scanThemes];
}

- (NSUInteger)yz_themecoreplus_iconCountForThemeAtPath:(NSString *)path {
    return [self.class yz_themecoreplus_countIconsInThemePath:path];
}

- (UIColor *)yz_themecoreplus_colorWithCSSString:(NSString *)css {
    return [self.class yz_themecoreplus_colorWithCSSString:css];
}

+ (UIColor *)yz_themecoreplus_colorWithCSSString:(NSString *)css {
    if (![css isKindOfClass:[NSString class]] || css.length == 0) return nil;
    NSString *text = [css stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([text hasPrefix:@"#"]) {
        NSScanner *scanner = [NSScanner scannerWithString:text];
        scanner.scanLocation = 1;
        unsigned int value = 0;
        if (![scanner scanHexInt:&value]) return nil;
        CGFloat red, green, blue, alpha = 1.0;
        switch (text.length - 1) {
            case 3:
                red = ((value >> 8) & 0xF) / 15.0;
                green = ((value >> 4) & 0xF) / 15.0;
                blue = (value & 0xF) / 15.0;
                return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
            case 6:
                red = ((value >> 16) & 0xFF) / 255.0;
                green = ((value >> 8) & 0xFF) / 255.0;
                blue = (value & 0xFF) / 255.0;
                return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
            case 8:
                red = ((value >> 24) & 0xFF) / 255.0;
                green = ((value >> 16) & 0xFF) / 255.0;
                blue = ((value >> 8) & 0xFF) / 255.0;
                alpha = (value & 0xFF) / 255.0;
                return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
            default:
                return nil;
        }
    }
    static NSDictionary<NSString *, UIColor *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{@"white": [UIColor whiteColor], @"black": [UIColor blackColor],
                  @"red": [UIColor redColor], @"green": [UIColor greenColor],
                  @"blue": [UIColor blueColor], @"orange": [UIColor orangeColor],
                  @"yellow": [UIColor yellowColor], @"purple": [UIColor purpleColor],
                  @"pink": [UIColor systemPinkColor], @"gray": [UIColor grayColor],
                  @"cyan": [UIColor cyanColor], @"magenta": [UIColor magentaColor],
                  @"clear": [UIColor clearColor]};
    });
    return names[text.lowercaseString];
}

@end
