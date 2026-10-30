//
//  TCRootListController.m —— 设置面板（设置 ▸ 主题美化 +）的根列表控制器。
//
//  为什么要有代码、而不是纯 plist 面板：生效主题必须现场扫盘才知道（纯 plist 只能写死名字）。
//  面板里只有这一个类，没有二级控制器；单元全部在这里现场生成。
//
//  不链接 Preferences.framework：本机（A11）没有可用工具链，SDK 里的 Preferences.tbd 无法核对，
//  所以把 PSListController / PSSpecifier 的少数符号留到加载期解析（见 scripts/build-themecoreplus.sh
//  的 PREFS_LDFLAGS）。代价是这里只能声明我们用得到的成员，绝不能给私有类写消息发送。
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "ThemeCorePlusKeys.h"
#import "ThemeCorePlusPreferences.h"
#import "ThemeCorePlusStore.h"
#import "ThemeCorePlusVersion.h"

#pragma mark - Preferences 框架的最小声明（符号留到加载期）

// 单元类型：Preferences 的私有枚举，数值多年不变（Choicy / DynamicX 的面板用的是同一套）。
enum {
    TCPPSGroupCell    = 0,
    TCPPSLinkCell     = 1,
    TCPPSLinkListCell = 2,   // 点进去从一组值里选一个（勾选列表）
    TCPPSSwitchCell   = 6,
    TCPPSButtonCell   = 13,
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
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
- (void)setButtonAction:(SEL)action;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)reloadSpecifiers;
- (void)setPreferenceValue:(id)value specifier:(id)specifier;
- (id)readPreferenceValue:(id)specifier;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

#pragma mark - 状态与诊断文本

// 状态行以**实际解析结果**为准：说真话，别按配置猜。
static NSString *TCPCurrentStatusLine(void) {
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) {
        return @"当前：系统原生外观（没有挂主题）";
    }
    return [NSString stringWithFormat:@"当前：%@", store.themeName.length > 0 ? store.themeName : @"?"];
}

// 诊断写在**目标进程自己的**偏好域：SpringBoard 的在 com.apple.springboard，
// 本进程（设置本身也注入了插件）的在它自己的域。两个都读不到就说明还没重启过进程。
static NSString *TCPDiagnosticsText(void) {
    NSString *text = nil;
    CFStringRef fromSpringBoard = CFPreferencesCopyAppValue((__bridge CFStringRef)TCPKeyDiagnostics,
                                                            CFSTR("com.apple.springboard"));
    if (fromSpringBoard != NULL) {
        text = (__bridge_transfer NSString *)fromSpringBoard;
    }
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        CFStringRef fromHere = CFPreferencesCopyAppValue((__bridge CFStringRef)TCPKeyDiagnostics,
                                                         kCFPreferencesCurrentApplication);
        if (fromHere != NULL) {
            text = (__bridge_transfer NSString *)fromHere;
        }
    }
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return @"还没有读到诊断：重启一次桌面后回到这里再看。";
    }
    if (text.length > 420) {
        text = [[text substringToIndex:420] stringByAppendingString:@"…"];
    }
    return text;
}

#pragma mark - 面板

// 基类是 PSListController（它的真身由设置 App 在加载期提供，所以只声明、不实现）。
// 漏了这一行会被当成根类（-Wobjc-root-class）：super 全部失效、父类方法全看不见。
@interface TCRootListController : PSListController
@end

@implementation TCRootListController {
    // ★★ 这个名字是有承重的，别加自己的前缀（本机实测过）：
    // PSListController 的表格数据源（numberOfSectionsInTableView: / tableView:numberOfRowsInSection:）
    // 读的不是 -[self specifiers]，而是它自己那个名叫 _specifiers 的存储；子类里用同样的名字声明，
    // 运行期就跟父类那一格合成同一个 ivar，写进去表格才看得见。
    // 叫 _tcpSpecifiers 时（0.6.0 装机复现）：kvc _specifiers = null、表格 0 段、
    // tableView:numberOfRowsInSection: 直接 NSRangeException 越界，面板一片空白但 specifiers() 返回 13。
    // 对照 VerticalDockPrefs / SystemBoxPrefs / HammerItPrefs 三个能用面板：二进制里只有 _specifiers，
    // 且都没有 setSpecifiers —— 它们靠的就是这个名字。
    NSArray *_specifiers;
}

#pragma mark 生成单元

- (PSSpecifier *)tcpGroupWithHeader:(NSString *)header footer:(NSString *)footer {
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:header ?: @""];
    if (footer.length > 0) {
        [group setProperty:footer forKey:@"footerText"];
    }
    return group;
}

// 开关单元：值写进我们自己的偏好域（defaults + key 两个属性就是 Preferences 的约定）。
- (PSSpecifier *)tcpSwitchNamed:(NSString *)name key:(NSString *)key {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:name
                                                      target:self
                                                         set:@selector(setPreferenceValue:specifier:)
                                                         get:@selector(readPreferenceValue:)
                                                      detail:nil
                                                        cell:TCPPSSwitchCell
                                                        edit:nil];
    [spec setProperty:TCPPreferencesDomain forKey:@"defaults"];
    [spec setProperty:key forKey:@"key"];
    return spec;
}

// 主题选择：写的是 ThemePath（绝对路径，最不容易有歧义），第一个选项是「系统原生外观」。
- (PSSpecifier *)tcpThemePicker {
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithObject:@""];
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:@"系统原生外观"];
    for (NSString *path in [[TCPThemeStore shared] availableThemePaths]) {
        [values addObject:path];
        [titles addObject:path.lastPathComponent];
    }

    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:@"生效主题"
                                                      target:self
                                                         set:@selector(setPreferenceValue:specifier:)
                                                         get:@selector(readPreferenceValue:)
                                                      detail:nil
                                                        cell:TCPPSLinkListCell
                                                        edit:nil];
    [spec setProperty:TCPPreferencesDomain forKey:@"defaults"];
    [spec setProperty:TCPKeyThemePath forKey:@"key"];
    [spec setValues:values titles:titles];
    return spec;
}

- (PSSpecifier *)tcpButtonNamed:(NSString *)name action:(SEL)action {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:name
                                                      target:self
                                                         set:nil
                                                         get:nil
                                                      detail:nil
                                                        cell:TCPPSButtonCell
                                                        edit:nil];
    [spec setButtonAction:action];
    return spec;
}

- (NSArray *)tcpBuildSpecifiers {
    // 每次建表都重扫：主题列表和状态行才是新的。
    [[TCPThemeStore shared] reload];

    NSMutableArray *specs = [NSMutableArray array];
    NSArray *fromPlist = [self loadSpecifiersFromPlistName:@"Root" target:self];
    if (fromPlist.count > 0) {
        [specs addObjectsFromArray:fromPlist];
    }

    [specs addObject:[self tcpGroupWithHeader:@"主题"
                                       footer:[NSString stringWithFormat:@"v%@ · %@",
                                               TCP_VERSION, TCPCurrentStatusLine()]]];
    [specs addObject:[self tcpThemePicker]];
    [specs addObject:[self tcpSwitchNamed:@"启用主题美化" key:TCPKeyEnabled]];

    [specs addObject:[self tcpGroupWithHeader:@"功能开关"
                                       footer:@"四项默认全开：主题里没有对应素材时，插件本身就是空转。"]];
    [specs addObject:[self tcpSwitchNamed:@"图标（主屏 / 文件夹 / 聚焦）" key:TCPKeyIconsEnabled]];
    [specs addObject:[self tcpSwitchNamed:@"文件夹底板" key:TCPKeyFoldersEnabled]];
    [specs addObject:[self tcpSwitchNamed:@"角标底图" key:TCPKeyBadgesEnabled]];
    [specs addObject:[self tcpSwitchNamed:@"系统图片替换" key:TCPKeyFilesEnabled]];

    [specs addObject:[self tcpGroupWithHeader:@"回滚"
                                       footer:@"回滚只清配置，不动主题目录里的任何文件。"]];
    [specs addObject:[self tcpButtonNamed:@"恢复系统原生外观" action:@selector(tcpRestoreNativeAppearance)]];
    [specs addObject:[self tcpButtonNamed:@"重新扫描主题" action:@selector(tcpRescanThemes)]];

    [specs addObject:[self tcpGroupWithHeader:@"诊断"
                                       footer:[NSString stringWithFormat:@"%@\n作者：yangzhou", TCPDiagnosticsText()]]];
    return specs;
}

#pragma mark 生命周期

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self tcpBuildSpecifiers];
    }
    return _specifiers;
}

- (void)reloadSpecifiers {
    _specifiers = nil;
    [super reloadSpecifiers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isViewLoaded) {
        [self reloadSpecifiers];   // 回到面板就刷新状态行与诊断
    }
}

#pragma mark 读写偏好

- (id)readPreferenceValue:(id)specifier {
    NSString *key = [specifier propertyForKey:@"key"];

    if ([key isEqualToString:TCPKeyThemePath]) {
        // 以实际生效的主题为准（也可能来自 ThemeName，或 shell 手写的路径）。
        NSString *active = [TCPThemeStore shared].themePath;
        return active.length > 0 ? active : @"";
    }
    id value = [super readPreferenceValue:specifier];
    if (value == nil) {
        return @YES;   // 键不存在 = 没设置 = 默认开（与 dylib 侧 TCPConfig 的默认值一致）
    }
    return value;
}

- (void)setPreferenceValue:(id)value specifier:(id)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    [super setPreferenceValue:value specifier:specifier];

    if ([key isEqualToString:TCPKeyThemePath]) {
        NSString *chosen = [value isKindOfClass:[NSString class]] ? value : @"";
        // ThemePath 和 ThemeName 留两个只会互相打架：这里只用 ThemePath。
        TCPWritePreference(TCPKeyThemeName, nil);
        if (chosen.length == 0) {
            TCPWritePreference(TCPKeyThemePath, nil);   // 「系统原生外观」
        }
    }

    TCPPostPreferencesChanged();   // 立刻通知 SpringBoard 重读快照、重排图标
    [self reloadSpecifiers];
}

#pragma mark 按钮动作

- (void)tcpRestoreNativeAppearance {
    TCPWritePreference(TCPKeyThemePath, nil);
    TCPWritePreference(TCPKeyThemeName, nil);
    TCPPostPreferencesChanged();
    [self reloadSpecifiers];
}

- (void)tcpRescanThemes {
    [[TCPThemeStore shared] reload];
    TCPPostPreferencesChanged();
    [self reloadSpecifiers];
}

@end
