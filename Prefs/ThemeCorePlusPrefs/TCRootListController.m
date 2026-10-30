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

#pragma mark - 二级页：生效主题（纯 UIKit 列表）

// 之前那一版是 PSListController 子类 + PSLinkCell 行。装机后点进这一页，设置进程当场闪退，
// 崩在 Preferences 内部给 specifier 准备元数据那一步（同一页在 icli 探针里却 1 段 6 行齐全，
// 验不到真凶）。这一版换成纯 UIKit 的 UITableViewController：
//   · 表格的数据源、代理、勾选、返回，全是 UIKit 公开 API，Preferences 一行都不碰；
//   · Preferences 只负责把我们的控制器 push 进导航栈（它 push 任何 UIViewController 都行）；
//   · 没有再覆盖 reloadSpecifiers / setSpecifiers:，也就没有那套段落缓存的坑。
// 这样「点进来闪退」的入口在结构上就不存在了，页面本身也更好用：带副标题和勾选。
@interface TCPThemeChooserController : UITableViewController
@end

@implementation TCPThemeChooserController {
    NSArray<NSString *> *_rows;             // 第 0 项固定为空串 = 系统原生外观
    NSMutableArray<NSString *> *_selected;  // 勾选顺序 = 叠加顺序：靠后的主题覆盖靠前的
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

// 不重写 initWithNibName:bundle:：UITableViewController 的两个指定初始化器互相派发的话，
// 重写它会变成递归。Preferences 无论用哪个入口建我们，得到的都是同一个可用的表格页。

- (NSString *)title {
    return @"生效主题";
}

// Preferences 把 detail 控制器 push 进来之后，会给它塞几样东西（specifier、父控制器、根控制器）。
// 我们是纯 UIKit 页，用不上它们；但**不接住**就会 unrecognized selector —— 这正是上一版二级页
// 闪退的形态（探针里直接 alloc/init 就没事，因为探针不塞这些）。所以全部实现成空操作。
- (void)setSpecifier:(id)specifier {}
- (id)specifier { return nil; }
- (void)setParentController:(id)parentController {}
- (id)parentController { return nil; }
- (void)setRootController:(id)rootController {}
- (id)rootController { return nil; }
// PSListController 的指定初始化器：Preferences 若按老路建 detail 页会调它，也收给同一个入口。
- (instancetype)initForRootList {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 56.0;
    // 多选页勾完不自动返回（要继续勾别的），所以给一个明确的出口；Preferences 的返回按钮同样能回去。
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonItemStyleDone
                                                      target:self
                                                      action:@selector(tcpFinish)];
    [self tcpReloadThemes];
}

- (void)tcpFinish {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)tcpReloadThemes {
    TCPThemeStore *store = [TCPThemeStore shared];
    [store reload];                       // 进来就重扫：新加的主题立刻能选
    // 已经生效的叠加链（store 只给确实存在的目录，顺序就是叠加顺序）。
    _selected = [NSMutableArray array];
    for (NSString *path in store.themePaths) {
        if ([path isKindOfClass:[NSString class]] && path.length > 0) [_selected addObject:path];
    }
    NSMutableArray<NSString *> *rows = [NSMutableArray arrayWithObject:@""];
    [rows addObjectsFromArray:[store availableThemePaths]];
    _rows = rows;
    [self.tableView reloadData];
}

// 第 0 段只有一行（系统原生外观）；第 1 段从 _rows[1] 开始，所以行号要 +1。
- (NSString *)tcpPathAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger row = indexPath.section == 0 ? 0 : indexPath.row + 1;
    if (row < 0 || row >= (NSInteger)_rows.count) return @"";
    return _rows[(NSUInteger)row];
}

// 这个主题排在叠加链第几层（1 起）；0 = 没勾。
- (NSInteger)tcpLayerForPath:(NSString *)path {
    NSUInteger index = [_selected indexOfObject:path];
    return index == NSNotFound ? 0 : (NSInteger)index + 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _rows.count > 0 ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return (NSInteger)_rows.count - 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    return [NSString stringWithFormat:@"主题（%lu 个）", (unsigned long)(_rows.count - 1)];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"可以多选：勾几个就叠几层，副标题里的「第 N 层」就是叠加顺序 —— 数字大的盖住数字小的（同一张素材谁在上层就用谁的）。"
               @"「图标包 ＋ 角标包」这种各管一块的组合随便勾；重叠的部分后勾的那个说了算。再点一次 = 取消这一层。";
    }
    if (section == 1) {
        return @"勾完点右上角「完成」（或左上角返回）。选中立刻生效，不用注销：桌面图标会自己重取一遍图。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"TCPThemeChoiceCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }

    NSString *path = [self tcpPathAtIndexPath:indexPath];
    if (path.length == 0) {
        cell.textLabel.text = @"系统原生外观";
        cell.detailTextLabel.text = _selected.count > 0
            ? @"点它 = 清空全部主题"
            : @"不套任何主题素材";
        cell.accessoryType = _selected.count == 0 ? UITableViewCellAccessoryCheckmark
                                                  : UITableViewCellAccessoryNone;
        return cell;
    }

    NSString *name = path.lastPathComponent;
    if ([name hasSuffix:@".theme"]) name = [name stringByDeletingPathExtension];
    cell.textLabel.text = name;
    // 副标题写它所在的根目录名：面板扫到的主题可能来自 /Library/ThemeCore，也可能来自 /Library/Themes
    NSString *root = [path stringByDeletingLastPathComponent].lastPathComponent;
    if (root.length == 0) root = path;
    NSInteger layer = [self tcpLayerForPath:path];
    cell.detailTextLabel.text = layer > 0
        ? [NSString stringWithFormat:@"叠加第 %ld 层 · %@", (long)layer, root]
        : root;
    cell.accessoryType = layer > 0 ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *path = [self tcpPathAtIndexPath:indexPath];
    if (path.length == 0) {
        [_selected removeAllObjects];                       // 系统原生外观 = 清空整条链
    } else {
        NSInteger layer = [self tcpLayerForPath:path];
        if (layer > 0) {
            [_selected removeObjectAtIndex:(NSUInteger)(layer - 1)];   // 再点一次 = 去掉这一层
        } else if (_selected.count >= TCPMaxThemeLayers) {
            // 到上限就明说，别静默丢掉用户这一勾（诊断里也只会显示前 8 层）。
            UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"最多叠 %lu 层", (unsigned long)TCPMaxThemeLayers]
                                                    message:@"每多一层都要把整个主题目录重扫一遍，叠太多既卡又没法排查是哪层出的问题。先取消一层再勾。"
                                             preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        } else {
            [_selected addObject:path];                                // 后勾的 = 更上层（覆盖先勾的）
        }
    }
    // 只留 ThemePaths 一个键：旧的两个键是单主题时代的写法，留着只会跟叠加链打架。
    // 空数组 = 删键 = 系统原生外观（传 nil 给 CFPreferencesSetAppValue 就是删）。
    NSArray<NSString *> *chain = _selected.count > 0 ? [_selected copy] : nil;
    TCPWritePreference(TCPKeyThemePaths, chain);
    TCPWritePreference(TCPKeyThemePath, nil);
    TCPWritePreference(TCPKeyThemeName, nil);
    TCPPostPreferencesChanged();                            // SpringBoard 收到立刻重读 + 重取图标图

    [tableView reloadData];                                 // 停在原地继续勾，不自动返回
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

// 主题入口：根页一行「生效主题：<当前>」，点进去是我们自己的列表页（TCPThemeChooserController）。
// detail 类交给 Preferences push —— 但那一页是纯 UIKit，没有 specifier 流程，见文件上半部分。
- (PSSpecifier *)tcpThemeEntryRow {
    TCPThemeStore *store = [TCPThemeStore shared];
    NSArray<NSString *> *active = store.themePaths;
    NSString *current = store.themeName;
    if (current.length == 0 && active.count > 0) {
        current = active.lastObject.lastPathComponent;   // 「液态玻璃.theme」→「液态玻璃」
        if ([current hasSuffix:@".theme"]) current = [current stringByDeletingPathExtension];
    }
    NSString *title = @"生效主题：系统原生外观";
    if (current.length > 0) {
        title = active.count > 1
            ? [NSString stringWithFormat:@"生效主题：%@（%lu 层叠加）", current, (unsigned long)active.count]
            : [NSString stringWithFormat:@"生效主题：%@", current];
    }

    return [PSSpecifier preferenceSpecifierNamed:title
                                          target:self
                                             set:nil
                                             get:nil
                                         detail:NSClassFromString(@"TCPThemeChooserController")
                                            cell:TCPPSLinkCell
                                            edit:nil];
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

    TCPThemeStore *store = [TCPThemeStore shared];
    [specs addObject:[self tcpGroupWithHeader:@"主题"
                                       footer:[NSString stringWithFormat:
                                               @"v%@ · %@\n点「生效主题」从 %lu 个主题里挑：可以多选（叠加），靠后的覆盖靠前的。",
                                               TCP_VERSION, TCPCurrentStatusLine(),
                                               (unsigned long)[store availableThemePaths].count]]];
    [specs addObject:[self tcpSwitchNamed:@"启用主题美化" key:TCPKeyEnabled]];
    [specs addObject:[self tcpThemeEntryRow]];

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

    if ([key isEqualToString:TCPKeyThemePaths]) {
        // 以实际生效的叠加链为准（也可能来自旧的 ThemePath / ThemeName，或 shell 手写的路径）。
        return [TCPThemeStore shared].themePaths ?: @[];
    }
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
        // 一旦有谁写单主题键，叠加链就退位：两个键不共存，免得规则说不清。
        TCPWritePreference(TCPKeyThemePaths, nil);
        if (chosen.length == 0) {
            TCPWritePreference(TCPKeyThemePath, nil);   // 「系统原生外观」
        }
    }

    TCPPostPreferencesChanged();   // 立刻通知 SpringBoard 重读快照、重排图标
    [self reloadSpecifiers];
}

#pragma mark 按钮动作

- (void)tcpRestoreNativeAppearance {
    TCPWritePreference(TCPKeyThemePaths, nil);   // 叠加链
    TCPWritePreference(TCPKeyThemePath, nil);    // 旧的两个单主题键一并清掉
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
