//
//  TCRootListController.m —— 设置面板（设置 ▸ 主题美化 +）。
//
//  换成 ThemeCore 0.5.1 那种**标准 specifier 面板**：根页（TCRootListController）+ 二级页
//  （TCThemeListController）都是干净的 PSListController 子类，行由 Root.plist / 代码生成的
//  PSSpecifier 描述，值读写交给 Preferences 框架。
//
//  1.0.39（2026-11-03）：用户要求「与 ThemeCore 面板保持一致」，照
//  $JB/Library/PreferenceBundles/ThemeCorePrefs.bundle/Root.plist 的写法补齐：
//   · 一级页页脚 = 「作者：yangzhou」；二级页：导航标题「选择主题」、组头「可用主题」、
//     同款页脚，列表为空时给「没有找到主题」。
//  1.0.40（2026-11-03）：用户「我没越狱源，点它没必要」→ 页脚去掉「越狱源」那一行与
//     整条超链接（不再用 PSFooterHyperlinkView / footerHyperlinkRange /
//     footerHyperlinkAction / `tcOpenRepository:`），只留居中的「作者：yangzhou」。
//
//  两个历史坑（详见 AGENTS.md「面板空白」与「选择主题页」两节），务必别踩回去：
//   · 早先有一版二级页是「声明不全 / 纯 UIKit 页 + PSLinkCell」，Preferences push 时会往它身上
//     塞 specifier / parentController / rootController 并准备 specifier 元数据，接不住就
//     unrecognized selector 当场闪退。0.5.1 用的是标准 PSListController 子类，基类自带这些方法，
//     所以不崩 —— 本文件两个控制器都严格继承 PSListController，不重写那套入口。
//   · 「面板空白 0 段 0 行」：PSListController 的**段落缓存只在父类入口 setSpecifiers: 里重建**；
//     子类自己声明的 _specifiers ivar 框架读不到，只写 ivar 会 0 段。本机实测（icli probe）只有
//     [self setSpecifiers:...] 能立刻变成有段有行。所以本文件保留旧代码验证过的骨架：
//     `-specifiers` 惰性 build 返回，`viewWillAppear:`/`reloadSpecifiers` 里走一次 setSpecifiers:
//     把数组交给框架重建段落缓存（带防递归标志）。
//
//  不链接 Preferences.framework：本机（A11）没有可用工具链，SDK 里的 Preferences.tbd 无法核对，
//  所以把 PSListController / PSSpecifier 的少数符号留到加载期解析（见 scripts/build-themecoreplus.sh
//  的 PREFS_LDFLAGS）。代价是这里只能声明我们用得到的成员，绝不能给私有类写消息发送。
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "ThemeCorePlusKeys.h"
#import "ThemeCorePlusPaths.h"
#import "ThemeCorePlusPreferences.h"
#import "ThemeCorePlusStore.h"
#import "ThemeCorePlusVersion.h"

#pragma mark - Preferences 框架的最小声明（符号留到加载期）

// 单元类型：Preferences 的私有枚举，数值多年不变（Choicy / DynamicX 的面板用的是同一套）。
enum {
    TCPPSGroupCell   = 0,
    TCPPSLinkCell    = 1,
    TCPPSSwitchCell  = 6,
    TCPPSButtonCell  = 13,
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

#pragma mark - 页脚（1.0.42：二级页不再显示作者）
//
// 用户 2026-11-03 06:00：「作者：yangzhou 不要在第二级界面显示了，删掉它」——
// 二级页（选择主题）底部的「作者：yangzhou」组单元与生成它的两个静态函数一并删除。
// 一级页那个页脚仍在 Prefs/ThemeCorePlusPrefs/Root.plist 里承载（用户没让删一级页）。
// 「越狱源」超链接早在 1.0.40 就删了：PSFooterHyperlinkView / footerHyperlinkRange /
// footerHyperlinkAction 全部不用，「点开仓库」那条路径（原 TCPOpenProjectRepository()）也不存在了。

#pragma mark - 偏好里存着的叠加链（总开关关着时引擎不解析，面板要显示「存着什么」）

// 与旧纯 UIKit 页同一套逻辑：按当前隐根重解析一遍，旧写法（ThemePath / ThemeName）也读得懂。
static NSArray<NSString *> *TCPStoredThemeChain(void) {
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    NSDictionary *values = TCPReadPreferences() ?: @{};

    id raw = values[TCPKeyThemePaths];
    if ([raw isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)raw) {
            if (chain.count >= TCPMaxThemeLayers) break;
            if (![entry isKindOfClass:[NSString class]] || [entry length] == 0) continue;
            NSString *resolved = TCPReResolveThemePath((NSString *)entry);
            if (resolved.length > 0 && ![chain containsObject:resolved]) [chain addObject:resolved];
        }
    }
    if (chain.count > 0) return chain;

    id single = values[TCPKeyThemePath];
    if ([single isKindOfClass:[NSString class]] && [(NSString *)single length] > 0) {
        NSString *resolved = TCPReResolveThemePath((NSString *)single);
        if (resolved.length > 0) return @[ resolved ];
    }
    id name = values[TCPKeyThemeName];
    if ([name isKindOfClass:[NSString class]] && [(NSString *)name length] > 0) {
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *root in TCPSourceThemeRoots()) {
            for (NSString *candidate in @[ name, [(NSString *)name stringByAppendingPathExtension:@"theme"] ]) {
                NSString *full = [root stringByAppendingPathComponent:candidate];
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) return @[ full ];
            }
        }
    }
    return @[];
}

#pragma mark - 二级页：选择主题（TCThemeListController，标准 PSListController）

// 一行一个主题，右端是**系统开关**（PSSwitchCell —— 与设置里「启用插件」那颗同一个控件、同一套观感，
// 不用对号）。开着的顺序就是叠加顺序（靠后开的覆盖靠前的），关掉 = 取消这一层；点整行 = 拨开关
// （PSSwitchCell 的原生行为，两条路都走框架同一个 set/get 入口）。
// 版面照 ThemeCore 的 TCThemeListController：导航标题「选择主题」、组头「可用主题」、底部作者页脚。

@interface TCThemeListController : PSListController
@end

@implementation TCThemeListController {
    NSArray *_specifiers;                    // 子类缓存（照旧代码：名字就叫 _specifiers，再走 setSpecifiers: 桥接）
    NSArray<NSString *> *_paths;             // 主题目录，一行一个
    NSMutableArray<NSString *> *_selected;   // 叠加链：靠后的覆盖靠前的
    BOOL _tcpApplyingSpecifiers;             // setSpecifiers: 回头调 reloadSpecifiers 时防递归
}

// 扫盘：主题列表与已选链都取新值。每次 push 进二级页都会新建本控制器，所以这里扫的是最新的。
- (void)tcpLoadThemes {
    TCPThemeStore *store = [TCPThemeStore shared];
    [store reload];

    _selected = [NSMutableArray array];
    for (NSString *path in store.themePaths) {
        if ([path isKindOfClass:[NSString class]] && path.length > 0) [_selected addObject:path];
    }
    // 总开关关着时 store.themePaths 为空，但偏好里存着的层还在 —— 按偏好原文显示，别显示成「全关」。
    if (_selected.count == 0) {
        for (NSString *path in TCPStoredThemeChain()) {
            if (![_selected containsObject:path]) [_selected addObject:path];
        }
    }

    NSMutableArray<NSString *> *rows = [NSMutableArray arrayWithArray:(store.availableThemePaths ?: @[])];
    // 开着的层必须在表里有一行，否则用户关不掉它（目录被改名 / 少了素材时 available 就不再列它）。
    for (NSString *path in _selected) {
        if (![rows containsObject:path]) [rows addObject:path];
    }
    _paths = [rows copy];
}

// 这个主题排在叠加链第几层（1 起）；0 = 没开。
- (NSInteger)tcpLayerForPath:(NSString *)path {
    NSUInteger index = [_selected indexOfObject:path];
    if (index == NSNotFound) {
        // 存的可能是「上一个隐根时代」的旧路径（roothide 重越狱会换 .jbroot-xxxx 名字），
        // 精确比对对不上时退一步按目录名对一次；只在没有精确命中时才退，免得同名主题两行一起开。
        NSString *name = path.lastPathComponent;
        for (NSUInteger i = 0; i < _selected.count; i++) {
            if ([_selected[i].lastPathComponent isEqualToString:name]) { index = i; break; }
        }
    }
    return index == NSNotFound ? 0 : (NSInteger)index + 1;
}

// 一个主题 = 一行 PSSwitchCell；把主题路径存在 specifier 的 key 里，set/get 凭它认行。
- (PSSpecifier *)tcpSwitchForPath:(NSString *)path {
    NSString *name = path.lastPathComponent;
    if ([name hasSuffix:@".theme"]) name = [name stringByDeletingPathExtension];

    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:name
                                                      target:self
                                                         set:@selector(setThemeSelected:specifier:)
                                                         get:@selector(themeSelected:)
                                                      detail:nil
                                                        cell:TCPPSSwitchCell
                                                        edit:nil];
    [spec setProperty:path forKey:@"key"];
    return spec;
}

#pragma mark 开关的 get / set（唯一写入口）

// 开没开这一层：框架拨动 / 渲染开关时调它读值。
- (id)themeSelected:(PSSpecifier *)specifier {
    NSString *path = [specifier propertyForKey:@"key"];
    return @([self tcpLayerForPath:path] > 0);
}

// 开关与点整行（PSSwitchCell 原生行为）都走到这里。
- (void)setThemeSelected:(id)value specifier:(PSSpecifier *)specifier {
    NSString *path = [specifier propertyForKey:@"key"];
    if (path.length == 0) return;

    BOOL on = [value boolValue];
    NSInteger layer = [self tcpLayerForPath:path];

    if (on && layer == 0) {
        if (_selected.count >= TCPMaxThemeLayers) {
            // 到上限就明说，别静默丢掉这一开；_selected 没动，reload 后开关自然回到关。
            UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"最多叠 %lu 层", (unsigned long)TCPMaxThemeLayers]
                                                    message:@"每多一层都要把整个主题目录重扫一遍，叠太多既卡又没法排查是哪层出的问题。先关掉一层再开。"
                                             preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            [self reloadSpecifiers];
            return;
        }
        [_selected addObject:path];                                  // 后开的 = 更上层（覆盖先开的）
    } else if (!on && layer > 0) {
        [_selected removeObjectAtIndex:(NSUInteger)(layer - 1)];      // 关掉 = 取消这一层
    }

    // 只留 ThemePaths 一个键；空数组 = 删键 = 系统原生外观。
    NSArray<NSString *> *chain = _selected.count > 0 ? [_selected copy] : nil;
    TCPWritePreference(TCPKeyThemePaths, chain);
    TCPWritePreference(TCPKeyThemePath, nil);
    TCPWritePreference(TCPKeyThemeName, nil);
    TCPPostPreferencesChanged();                                     // SpringBoard 收到立刻重读 + 重排图标
}

#pragma mark 生命周期（照旧代码的稳定骨架）

- (NSArray *)tcpBuildSpecifiers {
    [self tcpLoadThemes];
    NSMutableArray *specs = [NSMutableArray array];
    [specs addObject:[PSSpecifier groupSpecifierWithName:@"可用主题"]];
    for (NSString *path in _paths) {
        [specs addObject:[self tcpSwitchForPath:path]];
    }
    if (_paths.count == 0) {
        // 一个主题都没扫到：把原因写在组脚里，别让用户面对一张白页。
        PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:@""];
        [empty setProperty:@"没有找到主题：把 .theme 目录放进 SnowBoard / IconBundles 的主题路径后重进本页。"
                    forKey:@"footerText"];
        [specs addObject:empty];
    }
    // 1.0.42：二级页不再追加「作者：yangzhou」页脚（用户 2026-11-03 06:00）。
    return specs;
}

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self tcpBuildSpecifiers];
    }
    return _specifiers;
}

- (void)reloadSpecifiers {
    _specifiers = [self tcpBuildSpecifiers];
    if (_tcpApplyingSpecifiers) {
        [super reloadSpecifiers];
        return;
    }
    [super reloadSpecifiers];
    _tcpApplyingSpecifiers = YES;
    [self setSpecifiers:_specifiers];   // 段落缓存只在父类这个入口重建
    _tcpApplyingSpecifiers = NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择主题";            // 与一级页那一行同名（Preferences 一般也会自己塞，重复无害）
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isViewLoaded) {
        [self reloadSpecifiers];
    }
}

@end

#pragma mark - 根页（TCRootListController）

// 版面照 ThemeCore 0.5.1：
//   通用 = 启用插件（PSSwitchCell，Root.plist 承载，域 com.yangzhou.themecoreplus）
//   主题 = 选择主题（PSLinkCell → TCThemeListController）＋ 刷新图标（PSButtonCell，action=refreshIcons）
//   底部 = 作者：yangzhou（纯文字居中，1.0.40 起不再有「越狱源」链接）
// 诊断串、功能说明、运行日志入口都不再出现（用户要求面板简洁）。

@interface TCRootListController : PSListController
@end

@implementation TCRootListController {
    NSArray *_specifiers;                // 照旧代码：子类缓存 + setSpecifiers: 桥接
    BOOL _tcpApplyingSpecifiers;
}

- (NSArray *)tcpBuildSpecifiers {
    // 版面（含页脚）整段交给 Root.plist；这里不再追加版本号 footer（ThemeCore 的面板也没有版本号行）。
    return [self loadSpecifiersFromPlistName:@"Root" target:self];
}

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self tcpBuildSpecifiers];
    }
    return _specifiers;
}

- (void)reloadSpecifiers {
    _specifiers = [self tcpBuildSpecifiers];
    if (_tcpApplyingSpecifiers) {
        [super reloadSpecifiers];
        return;
    }
    [super reloadSpecifiers];
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

// 「刷新图标」：广播 Darwin 通知，SpringBoard 里的插件收到后重读快照、清视图与缓存、当场重新出图。
// 不弹窗（用户 2026-10-30 14:49 要求），屏幕上的变化本身就是反馈。
- (void)refreshIcons {
    TCPPostPreferencesChanged();
}

@end
