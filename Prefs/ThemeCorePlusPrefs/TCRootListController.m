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
#import "ThemeCorePlusPaths.h"
#import "ThemeCorePlusPreferences.h"
#import "ThemeCorePlusStore.h"
#import "ThemeCorePlusLog.h"
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

// 诊断原文由日志页显示（面板正文里不再出现技术串：用户 2026-10-30 14:5x 明确要求正式版去掉
// 「已认出：icon{…}」那行脚注——那是调试信息，不该占着用户的面板）。
static NSString *TCPDiagnosticsText(NSUInteger limit);

// 诊断写在**目标进程自己的**偏好域：SpringBoard 的在 com.apple.springboard，
// 本进程（设置本身也注入了插件）的在它自己的域。两个都读不到就说明还没重启过进程。
static NSString *TCPDiagnosticsText(NSUInteger limit) {
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
    if (limit > 0 && text.length > limit) {
        text = [[text substringToIndex:limit] stringByAppendingString:@"…"];
    }
    return text;
}

#pragma mark - 二级页：运行日志（纯 UIKit 页面 + 系统分享）

// 用户 2026-10-30 14:58 要的「日志入口」：调试时要看得见，出问题时要能把日志发出来。
// 做法照本机装着的 IPSLog（com.axs.ipslog 5.2.0，作者 Axs）那套：纯 UIKit 页面 + 系统分享面板
//（UIActivityViewController / UIPasteboard），日志列表与全文各是独立控制器，不碰 Preferences 的
// specifier 机制 —— 这一页因此不会有「点进来闪退」那类问题。
//   · 只读 UITextView（等宽字体），能选中所以能只复制几行；下拉刷新重读；
//   · 右上角「分享」把整段文本交给系统（微信 / 备忘录 / 邮件 / 拷贝都在这张面板里）；
//   · 内容 = 桌面进程那份日志（真干活的是它）＋ 本进程那份，前面贴一段诊断原文。
@interface TCPLogViewController : UIViewController
@end

@implementation TCPLogViewController {
    UITextView *_logView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _logView = [[UITextView alloc] initWithFrame:CGRectZero];
    _logView.editable = NO;
    _logView.selectable = YES;
    _logView.alwaysBounceVertical = YES;
    _logView.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular];
    _logView.textContainerInset = UIEdgeInsetsMake(10, 10, 12, 10);
    _logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_logView];
    [NSLayoutConstraint activateConstraints:@[
        [_logView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_logView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_logView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(tcpReloadLogText)
      forControlEvents:UIControlEventValueChanged];
    _logView.refreshControl = refresh;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(tcpShareLog)];
    [self tcpReloadLogText];
}

- (NSString *)tcpLogText {
    NSString *diagnostics = TCPDiagnosticsText(1200);
    NSString *path = TCPLogFilePath();
    NSString *footer = path.length > 0
        ? [NSString stringWithFormat:@"—— 完整日志文件：%@（Filza 可取，每个进程一份）", path]
        : @"—— 日志文件写不进去，这段文本就是全部。";
    return [NSString stringWithFormat:@"=== 诊断（桌面进程写的）===\n%@\n\n%@\n\n%@",
            diagnostics, TCPLogCombinedText(@"com.apple.springboard", 200), footer];
}

- (void)tcpReloadLogText {
    _logView.text = [self tcpLogText];
    [_logView.refreshControl endRefreshing];
}

- (void)tcpShareLog {
    UIActivityViewController *share =
        [[UIActivityViewController alloc] initWithActivityItems:@[ [self tcpLogText] ]
                                           applicationActivities:nil];
    // iPad 的分享面板是 popover，必须有锚点，缺了会崩；iPhone 上这两行无害。
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}

@end

#pragma mark - 二级页：选择主题

// 分类素材开关整组删掉（用户 2026-10-30 16:59 / 17:00）：「素材开关」那四行（应用图标 / 文件夹 /
// 角标 / 系统界面图）连同下面那段说明一起从面板上删掉，四类素材一律全换，没有关掉的入口；
// 哪一类有多少件，直接写在每个主题自己那一行的副标题里 —— 功能全在「主题」里。

// 主题选择页。之前那一版是 PSListController 子类 + PSLinkCell 行：装机后点进这一页，设置进程当场闪退，
// 崩在 Preferences 内部给 specifier 准备元数据那一步（同一页在 icli 探针里却 1 段 6 行齐全，
// 验不到真凶）。这一版换成纯 UIKit 的 UITableViewController：
//   · 表格的数据源、代理、勾选、返回，全是 UIKit 公开 API，Preferences 一行都不碰；
//   · Preferences 只负责把我们的控制器 push 进导航栈（它 push 任何 UIViewController 都行）；
//   · 没有再覆盖 reloadSpecifiers / setSpecifiers:，也就没有那套段落缓存的坑。
// 这样「点进来闪退」的入口在结构上就不存在了，页面本身也更好用：带副标题，右端是系统开关。
#pragma mark - 选择主题页的行单元

// 主题行的右端是**系统开关**（UISwitch —— 与设置里「启用插件」那颗是同一个控件、同一套观感），
// 不再用对号。用户 2026-10-30 17:09~17:11 定的硬规矩（已写入技能包 settings-switch-ui）：
// 凡是挂进系统设置的插件，选项一律用系统开关，不用对号。
// 行本体照样可点（点行 = 拨这颗开关），保留原来「点一下选上、再点一下取消」的手感。
@interface TCPThemeSwitchCell : UITableViewCell
@property (nonatomic, strong, readonly) UISwitch *tcpSwitch;
@end

@implementation TCPThemeSwitchCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        _tcpSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
        _tcpSwitch.accessibilityLabel = @"选中这个主题";
        self.accessoryView = _tcpSwitch;      // 右端开关，与设置里一样；不设 accessoryType（那就是对号）
    }
    return self;
}

@end

@interface TCPThemeChooserController : UITableViewController
@end

#pragma mark 行的副标题（第几层 + 这个目录里有几件素材）

// 素材分类的中文名（分类常量在 ThemeCorePlusStore.h，判定在引擎里，面板只负责显示）。
static NSString *TCPMaterialLabel(NSString *kind) {
    if ([kind isEqualToString:TCPMaterialIcons]) return @"图标";
    if ([kind isEqualToString:TCPMaterialFolders]) return @"文件夹";
    if ([kind isEqualToString:TCPMaterialBadges]) return @"角标";
    if ([kind isEqualToString:TCPMaterialFiles]) return @"界面图";
    return kind;
}

// 偏好里**存着**的叠加链（不管总开关开没开）：路径照当前隐根重解析一遍。
// 为什么要单独读一次：总开关关掉时引擎不解析主题（store.themePaths 变成空数组），
// 但用户原来选的那几层还躺在偏好里；面板若照着 store 显示，就会把「存着两层」显示成
// 「全都关着」，接着随便拨一下就把那两层覆盖掉。面板要显示的是「存着什么」。
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

    // 旧写法（单主题两个键）：ThemePath 优先，其次按 ThemeName 在主题根里找。
    id single = values[TCPKeyThemePath];
    if ([single isKindOfClass:[NSString class]] && [single length] > 0) {
        NSString *resolved = TCPReResolveThemePath((NSString *)single);
        if (resolved.length > 0) return @[ resolved ];
    }
    id name = values[TCPKeyThemeName];
    if ([name isKindOfClass:[NSString class]] && [name length] > 0) {
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

@implementation TCPThemeChooserController {
    NSArray<NSString *> *_rows;             // 主题目录，一行一个（顶部「系统原生外观」那行已删）
    NSMutableArray<NSString *> *_selected;  // 勾选顺序 = 叠加顺序：靠后的主题覆盖靠前的
    NSDictionary<NSString *, NSDictionary *> *_summaries;   // 每行素材件数：进页面时扫一次，滚动不再扫盘
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
    // 与 ThemeCore 的面板叫法一致（用户 2026-10-30 15:19）：这一页标题就是「选择主题」，
    // 与根页那一行的名字相同，别自己造一个「生效主题」。
    return @"选择主题";
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
    self.tableView.rowHeight = 62.0;   // 开关行与主题行都带一句副标题，56 会被截
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
    // 总开关关着时引擎不解析主题，store.themePaths 是空的 —— 但偏好里存着的层还在。
    // 这时按偏好原文显示（见 TCPStoredThemeChain 的注释），面板才不会把「存着两层」显示成「全关」。
    if (_selected.count == 0) {
        for (NSString *path in TCPStoredThemeChain()) {
            if (![_selected containsObject:path]) [_selected addObject:path];
        }
    }
    // 只列主题本身。「系统原生外观」那一行已删（用户 2026-10-30 17:03）：
    // 想回滚就把开着的层一层层关掉（拨开关、点这一行都行），空链就是系统原生外观。
    NSMutableArray<NSString *> *rows = [NSMutableArray arrayWithArray:([store availableThemePaths] ?: @[])];
    // 开着的层必须在表里有一行，否则用户关不掉它：主题目录被改名/少了素材探针文件时，
    // availableThemePaths 就不再列它，而偏好里还挂着它 —— 补到表尾。
    for (NSString *path in _selected) {
        if (![rows containsObject:path]) [rows addObject:path];
    }
    _rows = [rows copy];
    // 每行的素材件数在这里算一次（浅扫目录，不读图）：滚动时 cellForRow 只查表，不再扫盘。
    NSMutableDictionary<NSString *, NSDictionary *> *summaries = [NSMutableDictionary dictionary];
    for (NSString *path in _rows) {
        NSDictionary *summary = [store materialSummaryForThemePath:path];
        summaries[path] = summary ?: @{};
    }
    _summaries = [summaries copy];
    [self.tableView reloadData];
}

// 一行一个主题目录（「系统原生外观」那行删掉后不再需要行号偏移）。
- (NSString *)tcpPathAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger row = indexPath.row;
    if (row < 0 || row >= (NSInteger)_rows.count) return @"";
    return _rows[(NSUInteger)row];
}

// 这个主题排在叠加链第几层（1 起）；0 = 没勾。
- (NSInteger)tcpLayerForPath:(NSString *)path {
    NSUInteger index = [_selected indexOfObject:path];
    if (index == NSNotFound) {
        // 存的可能是「上一个隐根时代」的旧路径（roothide 重越狱会换 .jbroot-xxxx 名字），
        // 这样精确比对就对不上了；退一步按目录名对一次。同名主题可能同时存在于两个根里，
        // 所以只在没有精确命中时才退这一步，免得两行一起被勾上。
        NSString *name = path.lastPathComponent;
        for (NSUInteger i = 0; i < _selected.count; i++) {
            if ([_selected[i].lastPathComponent isEqualToString:name]) { index = i; break; }
        }
    }
    return index == NSNotFound ? 0 : (NSInteger)index + 1;
}

// 行的副标题：这一层排第几（叠加顺序靠后的覆盖靠前的）+ 这个目录里各类素材各有几件。
// 本次修：这一行以前从来没被赋过值 —— rowHeight 62 给副标题留的位置一直是空的，
// 用户看不出「哪一层在上面」，也看不出一个主题到底带了什么（四个分类开关已经删了）。
- (NSString *)tcpSubtitleForPath:(NSString *)path layer:(NSInteger)layer total:(NSInteger)total {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    if (layer > 0) {
        NSString *rank = [NSString stringWithFormat:@"第 %ld 层", (long)layer];
        if (total > 1 && layer == total) rank = [rank stringByAppendingString:@"（最上层）"];
        [parts addObject:rank];
    }

    NSDictionary<NSString *, NSNumber *> *summary = _summaries[path] ?: @{};
    for (NSString *kind in @[ TCPMaterialIcons, TCPMaterialFolders, TCPMaterialBadges, TCPMaterialFiles ]) {
        NSInteger count = summary[kind].integerValue;
        if (count <= 0) continue;
        [parts addObject:[NSString stringWithFormat:@"%@ %ld", TCPMaterialLabel(kind), (long)count]];
    }

    return parts.count > 0 ? [parts componentsJoinedByString:@" · "] : @"这个目录里没有素材";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // 只剩一段：主题列表（顶部「系统原生外观」那一段与分类素材开关都已删）
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_rows.count;
}

// 这一页**只有主题行**（用户 2026-10-30 17:1x：「选择主题 里面只有主题项目，用来开关选择主题素材包！
// 别的不要有！」）：段落标题与页脚说明都不再有 —— 段落标题（「主题（N 个）」）和那一大段叠加规则
// 都是页面自己贴上去的字，不是主题项目本身。别的功能（图标 / 文件夹 / 角标 / 系统界面图）一律默认开启，
// 面板上不给开关，主题里没那类素材就自然不换、也不会去加载它。

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"TCPThemeChoiceCell";
    TCPThemeSwitchCell *cell = (TCPThemeSwitchCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[TCPThemeSwitchCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                         reuseIdentifier:identifier];
    }
    // 单元是复用的：每次都得把上一行留下的 target 摘掉，否则拨一颗开关会连带触发别的行。
    [cell.tcpSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.detailTextLabel.numberOfLines = 2;

    NSString *path = [self tcpPathAtIndexPath:indexPath];
    if (path.length == 0) {
        // 越界（表格刷新与数据不同步）时给个空单元，别把主题名写到别人的行上；开关也停用，别让人拨到空行。
        cell.textLabel.text = @"";
        cell.detailTextLabel.text = @"";
        cell.tcpSwitch.tag = -1;
        cell.tcpSwitch.on = NO;
        cell.tcpSwitch.enabled = NO;
        return cell;
    }

    NSString *name = path.lastPathComponent;
    if ([name hasSuffix:@".theme"]) name = [name stringByDeletingPathExtension];
    cell.textLabel.text = name;
    // 右端：系统开关，开 = 这一层生效（与设置里「启用插件」那颗开关同款）
    NSInteger layer = [self tcpLayerForPath:path];
    cell.tcpSwitch.enabled = YES;
    cell.tcpSwitch.tag = (NSInteger)indexPath.row;
    cell.tcpSwitch.on = (layer > 0);
    cell.detailTextLabel.text = [self tcpSubtitleForPath:path
                                                   layer:layer
                                                   total:(NSInteger)_selected.count];
    [cell.tcpSwitch addTarget:self action:@selector(tcpSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    return cell;
}

// 开关被拨动：行号记在 tag 上，直接当索引使（单元复用后 tag 每次都会重写，不会串行）
- (void)tcpSwitchChanged:(UISwitch *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= _rows.count) {
        [self.tableView reloadData];       // 越界：把开关拨回它该在的位置
        return;
    }
    [self tcpToggleThemeAtIndex:(NSUInteger)sender.tag];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self tcpToggleThemeAtIndex:(NSUInteger)indexPath.row];   // 点行 = 拨这颗开关，两条路行为一致
}

// 选中 / 取消一层：唯一的写入口（开关与点行走的都是这里）
- (void)tcpToggleThemeAtIndex:(NSUInteger)row {
    NSString *path = row < _rows.count ? _rows[row] : nil;
    if (path.length == 0) return;                               // 越界的空行：什么都不做

    NSInteger layer = [self tcpLayerForPath:path];
    if (layer > 0) {
        [_selected removeObjectAtIndex:(NSUInteger)(layer - 1)];   // 关掉开关 = 去掉这一层
    } else if (_selected.count >= TCPMaxThemeLayers) {
        // 到上限就明说，别静默丢掉用户这一开（诊断里也只会显示前 8 层）。
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"最多叠 %lu 层", (unsigned long)TCPMaxThemeLayers]
                                                message:@"每多一层都要把整个主题目录重扫一遍，叠太多既卡又没法排查是哪层出的问题。先关掉一层再开。"
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self.tableView reloadData];                            // 把这颗开不上去的开关拨回原位
        return;
    } else {
        [_selected addObject:path];                                // 后开的 = 更上层（覆盖先开的）
    }
    // 只留 ThemePaths 一个键：旧的两个键是单主题时代的写法，留着只会跟叠加链打架。
    // 空数组 = 删键 = 系统原生外观（传 nil 给 CFPreferencesSetAppValue 就是删）。
    NSArray<NSString *> *chain = _selected.count > 0 ? [_selected copy] : nil;
    TCPWritePreference(TCPKeyThemePaths, chain);
    TCPWritePreference(TCPKeyThemePath, nil);
    TCPWritePreference(TCPKeyThemeName, nil);
    TCPPostPreferencesChanged();                            // SpringBoard 收到立刻重读 + 重取图标图

    [self.tableView reloadData];                                 // 停在原地接着拨，不自动返回
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

// 主题入口：根页一行「选择主题」，右侧灰字写当前生效的（ThemeCore 就是这个样子：
// 标题固定、状态在右边）。点进去是我们自己的列表页（TCPThemeChooserController）。
- (PSSpecifier *)tcpThemeEntryRow {
    TCPThemeStore *store = [TCPThemeStore shared];
    NSArray<NSString *> *active = store.themePaths;
    NSString *current = store.themeName;
    if (current.length == 0 && active.count > 0) {
        current = active.lastObject.lastPathComponent;   // 「液态玻璃.theme」→「液态玻璃」
        if ([current hasSuffix:@".theme"]) current = [current stringByDeletingPathExtension];
    }
    NSString *state = @"系统原生外观";
    if (current.length > 0) {
        // store.themeName 已经是「按叠加顺序用 + 连起来」的全名，再补「（N 层）」只是重复一遍。
        state = current;
    }

    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:@"选择主题"
                                                       target:self
                                                          set:nil
                                                          get:nil
                                                       detail:NSClassFromString(@"TCPThemeChooserController")
                                                         cell:TCPPSLinkCell
                                                         edit:nil];
    [spec setProperty:state forKey:@"value"];
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

    // 版面照 ThemeCore 原样（用户 2026-10-30 14:37 给的参照）：
    //   通用 = 启用插件
    //   主题 = 选择主题 + 刷新图标
    //   底部 = 作者
    // 回滚不用单独按钮：在「选择主题」里把开着的层一层层关掉就是回滚（用户 2026-10-30 17:03
    // 让把列表顶部那行「系统原生外观（点它 = 清空全部主题）」去掉，那一行右端的开关本身就说清了状态）。
    // 用户 2026-10-30 15:13/15:14 连着两条要求：**面板要简洁**（照 ThemeCore 0.5.1 的样子，
    // 别写功能说明）——「开关只是用不用」这类解释、功能清单、诊断串一律不出现在面板正文里。
    // 用户 2026-10-30 16:0x 曾把四个功能开关（应用图标 / 文件夹 / 角标 / 系统界面图）收进「选择主题」
    // 那一页，16:59 / 17:00 又要求整组删掉：四类素材一律全换，面板上不留分类开关，
    // 每个主题带了哪些素材写在它自己那一行的副标题里 —— 功能全在「主题」里。
    [specs addObject:[self tcpGroupWithHeader:@"通用" footer:nil]];
    [specs addObject:[self tcpSwitchNamed:@"启用插件" key:TCPKeyEnabled]];

    // 主题组不再挂任何技术串（用户 2026-10-30 14:5x 要求正式版去掉「已认出：icon{…}」，
    // 15:06 又要求去掉「刷新图标 ref{views=…}：views=找到的图标视图…」这类提示 —— 刷新本身
    // 当场就生效，屏幕上的变化就是反馈，面板里不必再解释一遍）。
    // 素材到底认出了什么，进「运行日志」看；面板正文只留用户看得懂的话。
    [specs addObject:[self tcpGroupWithHeader:@"主题" footer:nil]];
    [specs addObject:[self tcpThemeEntryRow]];
    [specs addObject:[self tcpButtonNamed:@"刷新图标" action:@selector(tcpRefreshIcons)]];

#if TCP_PANEL_LOG_ENTRY
    // 日志入口（用户 2026-10-30 15:27：**放在面板最下方**）：独立一段、一行按钮、不带说明文字。
    // 正式版去掉它：把 ThemeCorePlusVersion.h 的 TCP_PANEL_LOG_ENTRY 改成 0 —— 连这一段空白一起消失。
    [specs addObject:[self tcpGroupWithHeader:nil footer:nil]];
    [specs addObject:[self tcpButtonNamed:@"运行日志" action:@selector(tcpShowLog)]];
#endif

    // 用户 2026-10-31 04:27 要求去掉底部那行「当前：液态玻璃」（加载状态不要再显示），
    // 底栏只留作者与版本。
    [specs addObject:[self tcpGroupWithHeader:nil
                                       footer:[NSString stringWithFormat:@"作者：yangzhou　·　v%@",
                                               TCP_VERSION]]];
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
        // 键不存在 = 没设置过，默认值与 dylib 侧 TCPConfig 保持一致（2026-10-30 15:33 用户要求）：
        // 总开关默认开，四个功能开关默认关 —— 面板显示什么，dylib 就按什么做，不再默认全开。
        if ([key isEqualToString:TCPKeyEnabled]) return @YES;
        return @NO;
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

// 「刷新图标」—— 用户 14:21/14:22 点名要的功能：不注销就让图标生效。
// 动作链：这里广播 Darwin 通知 → SpringBoard 里的插件收到 → TCPReload(YES) → 清掉视图与共用缓存，
// 再叫每个图标视图当场重新出图（-updateImageAnimated:NO，走显示层站拿主题图）。
// 用户 14:49 要求**不要弹窗**（「这个提示没必要，正式版本要去除」）：点下去就静默刷新，
// 只把状态行重算一遍，屏幕上的变化本身就是反馈。
- (void)tcpRefreshIcons {
    TCPPostPreferencesChanged();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self reloadSpecifiers];
    });
}

// 「运行日志」：push 一个纯 UIKit 页面（日志页不经过 Preferences 的 specifier 机制）。
// 万一没有导航栈（正常不会），退化成弹出 + 「完成」按钮，别把用户困在页里。
- (void)tcpShowLog {
    TCPLogViewController *log = [[TCPLogViewController alloc] init];
    log.title = @"运行日志";
    UINavigationController *nav = self.navigationController;
    if (nav != nil) {
        [nav pushViewController:log animated:YES];
        return;
    }
    UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:log];
    log.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(tcpDismissLog)];
    [self presentViewController:wrapper animated:YES completion:nil];
}

- (void)tcpDismissLog {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
