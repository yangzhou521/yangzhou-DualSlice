//
//  TCXRootListController.m —— AppIcon 设置面板（设置 ▸ AppIcon）。
//
//  版面完全照 ThemeCore 0.5.1 的面板形状（证据：ThemeCorePrefs.bundle/Root.plist）：
//    通用  = 启用插件（PSSwitchCell，Root.plist 承载）
//    主题  = 选择主题（PSLinkCell → TCXThemeListController）＋ 刷新图标（PSButtonCell）
//    样式  = 图标遮罩 / 阴影 / 角标 / 时钟 / 日历（PSSwitchCell）
//    页脚  = 作者：yangzhou
//
//  两条历史坑，别踩回去（详见旧面板 TCRootListController.m 的注释）：
//   · 二级页必须是标准 PSListController 子类：Preferences 会往它身上塞 specifier /
//     parentController / rootController，接不住就 unrecognized selector 闪退。
//   · 段落缓存只在父类入口 setSpecifiers: 里重建；只写子类 ivar 会「面板空白 0 段 0 行」。
//
//  不链接 Preferences.framework（面板编译用 -undefined dynamic_lookup），
//  所以这里只声明用得到的成员，绝不给私有类乱发消息。
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "TCXPaths.h"

#pragma mark - Preferences 框架的最小声明

enum {
    TCXPSGroupCell  = 0,
    TCXPSLinkCell   = 1,
    TCXPSwitchCell  = 6,
    TCXPSButtonCell = 13,
};

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name
                                  target:(id)target
                                     set:(SEL)set
                                     get:(SEL)get
                                  detail:(Class)detail
                                    cell:(NSInteger)cell
                                    edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)setSpecifiers:(NSArray *)specifiers;
- (void)reloadSpecifiers;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

#pragma mark - 偏好（与插件读的是同一个文件 com.yangzhou.appicon.plist）

static NSString *const kTCXPrefsDomain = @"com.yangzhou.appicon";
static NSString *const kTCXReloadName = @"com.yangzhou.appicon.reload";

static id TCXReadPref(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                       (__bridge CFStringRef)kTCXPrefsDomain);
    return value ? (__bridge_transfer id)value : nil;
}

static void TCXWritePref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kTCXPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kTCXPrefsDomain);
}

// 跨进程让 SpringBoard 重读快照并重画图标（TCXIcons.m 里的 TCXReloadCallback 收）。
static void TCXPostReload(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kTCXReloadName,
                                         NULL, NULL, true);
}

#pragma mark - 主题扫描（规则必须与 ThemeCoreX/Sources/TCXStore.m 一致）

static BOOL TCXLooksLikeTheme(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) return NO;
    for (NSString *sub in @[@"Info.plist", @"IconBundles", @"Icons", @"icons", @"Bundles"]) {
        if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:sub]]) return YES;
    }
    return NO;
}

static NSUInteger TCXIconCount(NSString *themePath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger total = 0;
    for (NSString *sub in @[@"IconBundles", @"Icons", @"icons"]) {
        NSString *dir = [themePath stringByAppendingPathComponent:sub];
        for (NSString *entry in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
            if ([[entry pathExtension].lowercaseString isEqualToString:@"png"]) total++;
        }
    }
    return total;
}

// 素材根与插件同一个：<jbroot>/Library/Themes（jbroot 运行时探测，绝不写死）。
static NSArray<NSString *> *TCXThemeDirs(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    NSString *root = TCXThemesRoot();
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) return dirs;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:root error:NULL] ?: @[];
    for (NSString *entry in [entries sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if ([entry hasPrefix:@"."]) continue;
        NSString *child = [root stringByAppendingPathComponent:entry];
        if (TCXLooksLikeTheme(child)) [dirs addObject:child];
    }
    return dirs;
}

static NSString *TCXDisplayName(NSString *path) {
    NSString *name = [path lastPathComponent];
    return [name.pathExtension.lowercaseString isEqualToString:@"theme"]
        ? [name stringByDeletingPathExtension] : name;
}

// 当前真正生效的主题名（与 TCXStore 的挑选规则一致：指定了就按名字找，没指定就挑图标最多的第一个）。
static NSString *TCXEffectiveThemeName(void) {
    NSArray<NSString *> *dirs = TCXThemeDirs();
    NSString *wanted = TCXReadPref(@"ActiveTheme");
    if ([wanted isKindOfClass:[NSString class]] && wanted.length > 0) {
        for (NSString *path in dirs) {
            NSString *name = [path lastPathComponent];
            if ([name isEqualToString:wanted] ||
                [[name stringByDeletingPathExtension] isEqualToString:wanted] ||
                [[[name stringByDeletingPathExtension] lowercaseString] isEqualToString:wanted.lowercaseString]) {
                return name;
            }
        }
    }
    for (NSString *path in dirs) {
        if (TCXIconCount(path) > 0) return [path lastPathComponent];
    }
    return [dirs.firstObject lastPathComponent];
}

#pragma mark - 二级页：选择主题（TCXThemeListController）

// 一行一个主题，右端是**系统开关**（PSSwitchCell —— 与设置里「启用插件」那颗同款，不用对号）。
// 单选取一：打开某行 = ActiveTheme 写成它，其余行自动关；关掉当前那行会弹回（要全关请关总开关）。
@interface TCXThemeListController : PSListController
@end

@implementation TCXThemeListController {
    NSArray *_specifiers;
    NSArray<NSString *> *_dirs;
    NSString *_effective;             // 当前生效主题的目录名（带 .theme 后缀，与磁盘一致）
    BOOL _applyingSpecifiers;
}

- (void)tcyLoadThemes {
    _dirs = TCXThemeDirs();
    _effective = TCXEffectiveThemeName();
}

- (BOOL)tcyIsEffective:(PSSpecifier *)specifier {
    NSString *path = [specifier propertyForKey:@"key"];
    return path.length > 0 && [path isEqualToString:_effective ?: @""];
}

- (PSSpecifier *)tcySwitchForPath:(NSString *)path {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:TCXDisplayName(path)
                                                      target:self
                                                         set:@selector(tcySetTheme:specifier:)
                                                         get:@selector(tcyThemeOn:)
                                                      detail:nil
                                                        cell:TCXPSwitchCell
                                                        edit:nil];
    [spec setProperty:path forKey:@"key"];
    return spec;
}

- (id)tcyThemeOn:(PSSpecifier *)specifier {
    return @([self tcyIsEffective:specifier]);
}

- (void)tcySetTheme:(id)value specifier:(PSSpecifier *)specifier {
    NSString *path = [specifier propertyForKey:@"key"];
    if (path.length == 0) return;
    NSString *dirName = [path lastPathComponent];

    if ([value boolValue]) {
        TCXWritePref(@"ActiveTheme", dirName);
        TCXPostReload();
        _effective = dirName;
    } else if ([self tcyIsEffective:specifier]) {
        // 单选：当前主题不许就地关掉（关掉会回落到默认主题，看起来像没反应）。
        // 恢复开关状态就行，不弹窗。
        _effective = TCXEffectiveThemeName();
    }
    [self reloadSpecifiers];
}

- (NSArray *)tcyBuildSpecifiers {
    [self tcyLoadThemes];
    NSMutableArray *specs = [NSMutableArray array];

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"可用主题"];
    [group setProperty:@"同一时间只启用一个主题。想恢复系统原样，请回上一页关掉「启用插件」。"
                forKey:@"footerText"];
    [specs addObject:group];

    for (NSString *path in _dirs) {
        [specs addObject:[self tcySwitchForPath:path]];
    }
    if (_dirs.count == 0) {
        PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:@""];
        [empty setProperty:[NSString stringWithFormat:@"没有找到主题：把主题目录放进 %@ 后重进本页。",
                            TCXThemesRoot()]
                    forKey:@"footerText"];
        [specs addObject:empty];
    }
    return specs;
}

- (NSArray *)specifiers {
    // 关键：Preferences 靠父类的 _specifiers 缓存去建表格行与绑定事件。
    // 只返回自己算的数组、不交给 setSpecifiers:，结果就是「只画出 group 的说明文字、
    // 下面一行主题都没有」（用户 2026-11-05 23:20 报的正是这个）。
    if (_specifiers == nil) {
        NSArray *built = [self tcyBuildSpecifiers];
        [self setSpecifiers:built];   // 走父类入口，缓存与表格才一致
        _specifiers = built;
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择主题";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isViewLoaded) [self reloadSpecifiers];
}

@end

#pragma mark - 根页（TCXRootListController）

@interface TCXRootListController : PSListController
@end

@implementation TCXRootListController {
    NSArray *_specifiers;
    BOOL _applyingSpecifiers;
}

- (NSArray *)tcyBuildSpecifiers {
    return [self loadSpecifiersFromPlistName:@"Root" target:self];
}

- (NSArray *)specifiers {
    // 同主题页：结果必须交给父类 setSpecifiers:，否则 Preferences 内部缓存在空，
    // 表格只画出分组说明、开关一行都没有（表现就是「点了没反应」）。
    if (_specifiers == nil) {
        NSArray *built = [self tcyBuildSpecifiers];
        if (built.count > 0) [self setSpecifiers:built];
        _specifiers = built;
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 每次进来重读一次偏好值，但不重建 specifier 对象本身。
    for (PSSpecifier *spec in self.specifiers) {
        NSString *key = [spec propertyForKey:@"key"];
        if (![key isKindOfClass:[NSString class]] || key.length == 0) continue;
        id value = TCXReadPref(key);
        if (value) [spec setProperty:value forKey:@"value"];
    }
    [self reloadSpecifiers];
}

// 「刷新图标」：广播 Darwin 通知，SpringBoard 里的插件收到后重读快照、清缓存、当场重新出图。
- (void)refreshIcons {
    TCXPostReload();
}

@end