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
- (void)setSpecifiers:(NSArray *)specifiers;
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

#pragma mark - 二级页：生效主题（行由我们自己造）

// 为什么不再用 cell=PSLinkListCell + setValues:titles:：0.6.0 装机版点「生效主题」推入的那一页
// 设备上是 0 段 0 行（同一份 specifier 在离线探针里却有 6 行），框架内部怎么取值我们验不到。
// 这里只依赖一个必然成立的事实：PSListController 会为 detail 类 push 一页；那一页有什么行，
// 由 -specifiers 自己说了算。
@interface TCPThemeListController : PSListController
@end

@implementation TCPThemeListController {
    NSArray *_specifiers;
    BOOL _tcpApplyingSpecifiers;
}

- (NSString *)title {
    return @"生效主题";
}

- (NSArray *)tcpBuildChoices {
    TCPThemeStore *store = [TCPThemeStore shared];
    [store reload];   // 进来就重扫：新加的主题立刻能选

    NSString *current = store.themePath;
    if (![current isKindOfClass:[NSString class]]) {
        current = @"";
    }

    NSMutableArray *specs = [NSMutableArray array];
    PSSpecifier *head = [PSSpecifier groupSpecifierWithName:@"选中即生效"];
    // footer 里写扫盘结果：这一行就是「设置进程到底看见几个主题」的证据。
    [head setProperty:[NSString stringWithFormat:@"%@\n扫到 %lu 个主题（另有「系统原生外观」）",
                       TCPCurrentStatusLine(), (unsigned long)[store availableThemePaths].count]
              forKey:@"footerText"];
    [specs addObject:head];

    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObject:@""];
    [paths addObjectsFromArray:[store availableThemePaths]];
    for (NSString *path in paths) {
        NSString *name = path.length > 0 ? path.lastPathComponent : @"系统原生外观";
        PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:name
                                                          target:self
                                                             set:@selector(tcpChooseTheme:)
                                                             get:nil
                                                          detail:nil
                                                            cell:TCPPSLinkCell
                                                            edit:nil];
        [spec setProperty:path forKey:@"tcpThemePath"];
        if ([path isEqualToString:current]) {
            [spec setProperty:@YES forKey:@"checked"];
        }
        [specs addObject:spec];
    }
    return specs;
}

// 点一行：写 ThemePath、通知 SpringBoard、退回上一页。
- (void)tcpChooseTheme:(PSSpecifier *)specifier {
    id path = [specifier propertyForKey:@"tcpThemePath"];
    if (![path isKindOfClass:[NSString class]]) {
        path = @"";
    }

    if ([path length] > 0) {
        TCPWritePreference(TCPKeyThemePath, path);
    } else {
        TCPWritePreference(TCPKeyThemePath, nil);   // 「系统原生外观」= 清掉
    }
    TCPWritePreference(TCPKeyThemeName, nil);
    TCPPostPreferencesChanged();

    [self.navigationController popViewControllerAnimated:YES];
}

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self tcpBuildChoices];
    }
    return _specifiers;
}

- (void)reloadSpecifiers {
    _specifiers = [self tcpBuildChoices];

    if (_tcpApplyingSpecifiers) {
        [super reloadSpecifiers];
        return;
    }

    [super reloadSpecifiers];
    // 同根面板：段落缓存只在父类 setSpecifiers: 入口里重建，改完数组必须再走一次它。
    _tcpApplyingSpecifiers = YES;
    [self setSpecifiers:_specifiers];
    _tcpApplyingSpecifiers = NO;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isViewLoaded) {
        [self reloadSpecifiers];
    }
}

@end

#pragma mark - 面板

// 基类是 PSListController（它的真身由设置 App 在加载期提供，所以只声明、不实现）。
// 漏了这一行会被当成根类（-Wobjc-root-class）：super 全部失效、父类方法全看不见。
@interface TCRootListController : PSListController
@end

@implementation TCRootListController {
    // 名字照父类叫 _specifiers（别加自己的前缀），但**光有这个名字不够**：本机逐组实测（icli probe）：
    //   view() 之后 --specifiers 早就被调过、这里也拿到了 13 个单元，表格却依旧 0 段 0 行；
    //   只把这 13 个写进 _specifiers（KVC 直接写）也一样 0 段；
    //   交给父类自己的入口 [self setSpecifiers:...] 才立刻变成 5 段 8 行，而且重复调用稳定。
    // 结论：段落缓存不是"读数组时现算"的，它只在父类那个入口里重建 —— 所以本类改完数组后
    // 必须再走一次 setSpecifiers:（见 -reloadSpecifiers）。叫 _tcpSpecifiers 时（0.6.0 装机复现）
    // 连数组都看不见：kvc _specifiers = null、表格 0 段、tableView:numberOfRowsInSection: 直接
    // NSRangeException 越界，面板一片空白但 specifiers() 返回 13。
    NSArray *_specifiers;
    BOOL _tcpApplyingSpecifiers;   // setSpecifiers: 万一回头调 reloadSpecifiers，别无限递归
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

// 主题选择：写的是 ThemePath（绝对路径，最不容易有歧义）。这一行只负责 push 二级页
// （TCPThemeListController，行由它自己造）；它自己不写任何偏好，所以 set 留空。
- (PSSpecifier *)tcpThemePicker {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:@"生效主题"
                                                      target:self
                                                         set:nil
                                                         get:@selector(readPreferenceValue:)
                                                      detail:[TCPThemeListController class]
                                                        cell:TCPPSLinkCell
                                                        edit:nil];
    [spec setProperty:TCPPreferencesDomain forKey:@"defaults"];
    [spec setProperty:TCPKeyThemePath forKey:@"key"];
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
    // 每次重建数组（状态行/诊断/主题列表都要是新的），顺序不能反：
    _specifiers = [self tcpBuildSpecifiers];

    if (_tcpApplyingSpecifiers) {
        // 已经在 setSpecifiers: 里绕回来了：只把数组和表格刷新一遍就停手。
        [super reloadSpecifiers];
        return;
    }

    [super reloadSpecifiers];
    // 父类的 reloadSpecifiers 会按"当时的数组"重排段落缓存，而它不认我们新算的这份；
    // 走它自己的入口把缓存按新数组建起来，表格才有段有行（本机 icli probe 逐组验证过）。
    _tcpApplyingSpecifiers = YES;
    [self setSpecifiers:_specifiers];
    _tcpApplyingSpecifiers = NO;
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
