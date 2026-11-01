//
//  ThemeCorePlusMain.m —— 装配、偏好变更、诊断。
//
//  时序是这套东西最容易出错的地方，所以写清楚：
//   1. dyld 调构造函数时，SpringBoardHome 里的类不一定都已经注册完，SBIcon 的老子类更可能
//      还没来；所以挂站不只在构造函数里做一遍，而是 0.0/0.5/2.0/6.0 秒各补一轮。
//      每轮都重扫类表（objc_copyClassList 不缓存），新来的类也能吃到站。
//   2. 每轮结束都重写一次诊断：注入有没有成功、站点挂了几个、主题解析成什么样，看诊断就够。
//   3. 面板改完设置广播 Darwin 通知，这里收到就重读快照、重排桌面。
//
#import "ThemeCorePlusPrivate.h"
#import "ThemeCorePlusHooks.h"
#import "ThemeCorePlusStore.h"
#import "ThemeCorePlusPaths.h"
#import "ThemeCorePlusPreferences.h"
#import "ThemeCorePlusKeys.h"
#import "ThemeCorePlusLog.h"
#import "ThemeCorePlusVersion.h"

// 诊断写到**目标进程自己的**偏好域：沙箱只允许进程写自己的域，SpringBoard 里的诊断在
// com.apple.springboard 域。读法见 AGENTS.md。
static void TCPWriteProcessPreference(NSString *key, id value) {
    if (key.length == 0) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                            (__bridge CFPropertyListRef)value,
                            kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
}

// 普查清单：只在诊断里用，钩子点靠它的结果坐实，不靠猜。
static NSArray<NSString *> *TCPCensusClassNames(void) {
    return @[ @"SBIconBadgeView", @"SBIconAccessoryImage", @"SBIconImageView",
              @"SBFolderIconImageView", @"SBFolderBackgroundView", @"SBFolderIconImageCache",
              @"SBHIconImageCache", @"SBIconImageCrossfadeView", @"SBHClockApplicationIconImageView",
              @"SBIcon", @"SBHIconAccessoryCountedMapImageTuple",
              // 以下三个是「不注销换图」那条路要用到的：视图（info 重设）、应用图标（生图）、
              // 控制器（relayoutIcons）。方法名以普查结果为准，不靠猜。
              @"SBIconView", @"SBApplicationIcon", @"SBIconController" ];
}

static void TCPWriteDiagnostics(void) {
    TCPThemeStore *store = [TCPThemeStore shared];
    NSMutableArray<NSString *> *sites = [NSMutableArray array];
    for (NSString *description in TCPSiteDescriptions()) {
        [sites addObject:description];
        if (sites.count >= 40) break;
    }
    NSString *siteList = sites.count > 0 ? [sites componentsJoinedByString:@","] : @"-";
    if (siteList.length > 700) siteList = [siteList substringToIndex:700];

    NSString *roots = [TCPSourceThemeRoots() componentsJoinedByString:@"|"];
    if (roots.length > 300) roots = [roots substringToIndex:300];

    // 主题列表也写进诊断：装完机不用看屏幕就能知道「这个进程扫到了几个主题、是哪几个」。
    NSArray<NSString *> *themes = [[TCPThemeStore shared] availableThemePaths];
    NSMutableArray<NSString *> *themeNames = [NSMutableArray array];
    for (NSString *path in themes) {
        [themeNames addObject:path.lastPathComponent];
        if (themeNames.count >= 4) break;
    }
    NSString *themeText = themeNames.count > 0 ? [themeNames componentsJoinedByString:@"|"] : @"-";

    // 像素自检（gen{}/pix{}）原来写好了却没接进来，诊断里一直看不到 —— 2026-10-30 15:4x 接上：
    // 「图标没换」到底是①我们合成把图抹透明了、还是②屏幕上挂的压根不是我们那张图，靠这组数区分。
    NSString *text = [NSString stringWithFormat:@"%@;%@;%@;%@;%@;%@;%@;%@;%@;%@;%@;%@;%@;%@;%@;sites=%lu[%@];roots=[%@];%@;themes=%lu[%@];ientry=[%@];centry=[%@]",
                      [store diagnostics], TCPDisplayProbeReport(), TCPRefreshProbeReport(),
                      TCPIconProbeReport(),
                      TCPBadgeProbeReport(), TCPIconPixelProbeReport(),
                      TCPScreenCensusReport(),
                      TCPDynamicProbeReport(), TCPClockViewProbeReport(), TCPFolderProbeReport(),
                      TCPFolderGridCellProbeReport(),
                      TCPFolderMiniGridProbeReport(),
                      TCPFolderNotifyReport(),
                      TCPIconCacheHookReport(), TCPIconCacheClassReport(),
                      (unsigned long)TCPTotalSiteCount(), siteList, roots,
                      TCPSourceThemeRootsReport(), (unsigned long)themes.count, themeText,
                      TCPIconImageEntryCensus(), TCPIconCacheEntryReport()];
    TCPWriteProcessPreference(TCPKeyDiagnostics, text);

    NSString *census = TCPCensusForClasses(TCPCensusClassNames(), 3600);
    TCPWriteProcessPreference(@"ThemeCorePlusCensus", census);

    // 本机装着的 MarkTheme16（com.hmmzzz.marktheme）能正常换图标，ThemeCore 0.5.1 也曾经能。
    // 它们到底挂在哪几个 (类,选择器) 上，直接按 IMP 归属从运行中的 SpringBoard 里读出来：
    // 换过 IMP 的站点，IMP 落在那个插件的 dylib 里。有了这张表就不必再猜站点。
    NSArray<NSString *> *ownerClasses = @[ @"SBIconImageView", @"SBIconImageCrossfadeView",
                                           @"SBIconView", @"SBIcon", @"SBApplicationIcon",
                                           @"SBHIconImageCache", @"SBFolderIconImageView",
                                           @"SBHClockApplicationIconImageView", @"IFImageBag",
                                           @"ISIcon", @"SBIconIconImage" ];
    NSArray<NSString *> *ownerSelectors = @[ @"iconImageWithInfo:", @"unmaskedIconImageWithInfo:",
                                             @"displayedImage", @"contentsImage",
                                             @"squareContentsImage", @"setImage:",
                                             @"updateImageAnimated:", @"setIconImageInfo:",
                                             @"generateIconImageWithInfo:", @"realImageForIcon:",
                                             @"cacheImageForIcon:", @"setImages:",
                                             @"setOriginalImages:", @"loadImageForGeneration:",
                                             @"iconImageFromUnmaskedImage:", @"setCurrentImageSet:",
                                             @"publishImageSet:", @"buildImageSetForSnapshot:",
                                             @"_handleIconImage:", @"updateImageContentsWithImage:",
                                             @"setComposedImage:", @"maskImageForImageSet:",
                                             @"overlayImageForImageSet:", @"iconImageFromImage:",
                                             @"_configureIconImageView:", @"isRealContentsImage" ];
    TCPWriteProcessPreference(@"ThemeCorePlusHookOwners",
                              TCPHookOwnerCensus(ownerClasses, ownerSelectors, 1600));

    // 角标 / 通知的类普查（用户 2026-10-30 15:13 要求「角标开着时锁屏通知也跟着走」）：
    //   ① 角标站实际落在哪些类上（含锁屏通知那套自己声明的类）；
    //   ② 通知列表里有没有自己的图标显示层（有的话锁屏通知的 App 图标也该由它接管）。
    NSArray<NSString *> *badgeSelectorNames = @[ @"_checkoutBackgroundImage",
                                                  @"_checkoutBackgroundImageTuple",
                                                  @"_checkoutImageForText:font:highlighted:" ];
    TCPWriteProcessPreference(@"ThemeCorePlusBadgeCensus",
                              TCPClassCensusForSubstrings(@[ @"Badge", @"Notification" ],
                                                          badgeSelectorNames, 2000));
    TCPWriteProcessPreference(@"ThemeCorePlusNotificationCensus",
                              TCPClassCensusForSubstrings(@[ @"Notification" ],
                                                          @[ @"displayedImage", @"contentsImage",
                                                             @"squareContentsImage", @"iconImageWithInfo:",
                                                             @"setIconImageInfo:" ], 1200));

    // 角标站的「真名」普查（0.9.7）：类名带这些字样的类，各自声明了哪些名字里含
    // image / background / checkout / badge 的方法。本机刚普查到的结果是
    // `SBIconBadgeView=+_checkoutImageForText:font:highlighted:` —— 整个 SpringBoard 进程里
    // 只有这一个类声明了三条候选站里的一条，也就是说 iOS 16.7.16 的角标走的是「合成」那条路，
    // ThemeCore 0.5.1 挂的 _checkoutBackgroundImage 在这里永远轮不到。把方法名清单留在诊断里，
    // 以后换版本先读它、再决定挂哪一站，不靠猜（猜错 = 安全模式）。
    TCPWriteProcessPreference(@"ThemeCorePlusBadgeMethods",
                              TCPClassMethodCensusForSubstrings(@[ @"SBIconBadge",
                                                                   @"SBHIconAccessory",
                                                                   @"SBIconAccessory" ],
                                                                @"(?i)image|background|checkout|badge",
                                                                2500));
}

// 立刻把诊断重写一遍（供「晚一拍」的体检结束后调用）。
void TCPWriteDiagnosticsNow(void) {
    TCPWriteDiagnostics();
}

// 让桌面把图标重新取一遍图。取不到就当没有这一步（有的版本没有这个方法）。
static void TCPRelayoutIcons(void) {
    // 1.0.36（修 1.0.35 安全模式）：TCPReload 在 dyld 构造函数第一轮必走进这里
    // （sLastReloadSites 初始 0 → sitesChanged 恒真），而 +[SBIconController sharedInstance]
    // 内部就是 +[UIScreen mainScreen] → dyld 阶段断言 → SIGABRT → SpringBoard 连崩进安全模式
    // （崩溃栈 TCPReload:180 → TCPRelayoutIcons → +[SBIconController sharedInstance]）。
    // 这就是 0.9.21 那个崩溃模式的翻版。闸门：图片工作未开闸（进程还没起来，+2 秒主队列
    // 才 TCPStoreEnableImageWork）一律不碰共享实例；开闸后由 dyld 补挂轮 / 用户改设置轮再重排。
    if (!TCPStoreImageWorkReady()) return;
    Class controllerClass = objc_getClass("SBIconController");
    if (controllerClass == Nil) return;
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (![controllerClass respondsToSelector:sharedSelector]) return;
    id controller = ((id (*)(id, SEL))objc_msgSend)((id)controllerClass, sharedSelector);
    if (controller == nil) return;
    SEL relayoutSelector = NSSelectorFromString(@"relayoutIcons");
    if ([controller respondsToSelector:relayoutSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(controller, relayoutSelector);
    }
}

static void TCPReload(BOOL refreshImages) {
    [[TCPThemeStore shared] reload];
    TCPInstallIconSites();
    TCPInstallDisplaySites();
    TCPInstallBadgeSites();
    // 时钟图标的视图站（0.9.17 写好、1.0.0 精简时漏了调用）：时钟从不走图标取图那几站，
    // 它自己画表盘和指针，只能挂 SBHClockApplicationIconImageView 的 layoutSubviews。
    // 类还没加载时它自己会返回，下一轮再挂。
    TCPInstallClockViewSite();
    TCPInstallFolderSites();           // 1.0.33：文件夹底板站（ANEMFolderIconBG）—— 之前写好了从没调，外壳透明无背景的根因
    TCPInstallFolderGridCellSites();   // 1.0.12：文件夹收起 mini 拼图的格子图站
    TCPInstallFolderMiniCellSite();    // 1.0.32：mini 拼图真正的入口（SBFolderIcon 自己）

    // 1.0.15：注销后「桌面反复加载」的根因就在这里 —— 启动那 4 轮补挂（0 / 0.5 / 2 / 6 秒）
    // 每一轮都无条件 relayoutIcons + 清文件夹拼图缓存，屏幕上就是桌面图标被反复重排、重画。
    // 现在只在「站点数变了」（晚到的类在这一轮挂上了）或「用户改了设置」时才重排一次。
    // 日志留痕：gen 会照旧涨，但桌面只被重排真正需要的那几次。
    NSUInteger sitesNow = TCPTotalSiteCount();
    static NSUInteger sLastReloadSites = 0;
    BOOL sitesChanged = (sitesNow != sLastReloadSites);
    sLastReloadSites = sitesNow;
    if (refreshImages || sitesChanged) {
        TCPRelayoutIcons();

        // 文件夹预览那张拼图（收起状态的 mini 图标）由 SBFolderIconImageCache 缓存：
        // 主题换上来之后它不会自己重算，于是「打开是主题图标、收起还是原图标」。这里叫它重算一次。
        TCPFolderCacheRefresh();

        // 1.0.22：站点挂齐的那一刻立即强刷（用户：别的主题引擎进桌面秒加载）。
        // 启动轮 refreshImages=NO，原来要等固定 1/2.5 秒的强刷拍；现在晚到的类一挂上
        // （sitesChanged）就当场把已建出来的视图换成主题图，不等定时拍。
        if (!refreshImages) {
            TCPRefreshIconImages();
        }
    }

    // 每次重载记一行「这一轮解析成什么样」，另起一行贴素材快照：面板「运行日志」里看到的就是
    // 这些。出问题时不用看屏幕也能知道插件在干什么、素材认出了几个。
    TCPThemeStore *store = [TCPThemeStore shared];
    TCPLogLine(@"重载 theme=%@ 层=%lu 站点=%lu 功能(图标=%d,文件夹=%d,角标=%d,文件=%d)",
               store.active ? store.themeName : @"（原生外观）",
               (unsigned long)store.themePaths.count,
               (unsigned long)TCPTotalSiteCount(),
               (int)store.iconsEnabled, (int)store.foldersEnabled,
               (int)store.badgesEnabled, (int)store.filesEnabled);
    TCPLogLine(@"快照 %@", [store diagnostics]);
    // refreshImages 只在「用户改了设置」时才为真。
    // 启动时（0/0.5/2/6 秒那几轮）一律不刷：2026-10-30 的安全模式就是启动即强刷视图
    // 与本机别的图标插件重入导致的（crash 栈 TCPReload → TCPRefreshIconImages →
    // clearIconImageInfo → … → tcpIconHook8，consecutiveCrashCount=7）。
    // 启动时挂好站点 + relayoutIcons 就够，下一次布局会自己按新主题取图。
    if (refreshImages) {
        TCPRefreshIconImages();
        // 探针报告是进程内的累计值（活了多久就累多久），注释里写清楚，免得被当成单次结果。
        TCPLogLine(@"刷新图标（累计）%@", TCPRefreshProbeReport());
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            TCPRefreshIconImages();
            TCPLogLine(@"刷新图标第二轮（累计）%@", TCPRefreshProbeReport());
            TCPWriteDiagnostics();
        });
    }
    TCPWriteDiagnostics();
}

// 屏幕归属普查 + 把结果写进诊断。0.9.8：普查独立于「刷新图标」——
// 启动时故意不刷视图（0.6.0 崩过），所以过去的 pix{} 永远是 0，看着像体检没跑。
// 这里在主线程、桌面图标已经建出来之后跑普查，只读不重画，不碰视图状态。
static void TCPRunCensusAndWrite(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ TCPRunCensusAndWrite(); });
        return;
    }
    TCPRunScreenCensus();
    // 文件夹预览取证（只读）：必须和普查一起、在主线程、图标都建好之后跑。
    TCPProbeFolderViews();
    TCPWriteDiagnostics();
    os_log(TCPLogHandle(), "TCPS_CENSUS %{public}@", TCPScreenCensusReport());
}

static void TCPPreferencesChanged(CFNotificationCenterRef center,
                                  void *observer,
                                  CFNotificationName name,
                                  const void *object,
                                  CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TCPLogLine(@"收到面板的刷新请求（Darwin 通知）");
        // 角标各站的计数清零（0.9.4）：诊断里的 bg/tup/txt 就从这次改动之后开始数，
        // 「哪个站在干活、单层闸门开没开」不必看屏幕，改一次设置读一次诊断就知道。
        TCPBadgeResetStations();
        TCPReload(YES);
        os_log(TCPLogHandle(), "TCPS_RELOAD site=%lu", (unsigned long)TCPTotalSiteCount());
    });
}

__attribute__((constructor)) static void TCPInitialize(void) {
    @autoreleasepool {
        // 1.0.33：**先判进程，图标服务进程只取证、什么都不做。**
        // 这个 dylib 现在也注入 com.apple.iconservices.iconservicesagent（见过滤器 plist 的
        // Executables）。那是系统级图标生成服务，一旦崩了全系统图标都不显示，所以：
        // 在这个进程里**连 TCPLogLine（写偏好）都不调**，只 dump 一次方法表就 return —— 
        // 不挂站、不开计时器、不写任何偏好。
        // 目的只有一个：找出它里面真正产出图标图的类+方法，判断要不要走 Mikkyy 那条资源层路线。
        NSString *bundle = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        if (![bundle isEqualToString:@"com.apple.springboard"] &&
            ![bundle isEqualToString:@"com.apple.Preferences"]) {
            TCPRunIconServiceProbe();
            return;
        }

        // TCP_VERSION 是 @"0.6.0"（NSString 字面量），所以这里只能用 %@：写成 %s 会把它当
        // C 字符串读，打出来是内存垃圾。ApelinLoaded 这一行是 apelin_package_confirm_loaded
        // 的标记行，格式不能动。
        os_log(TCPLogHandle(), "ApelinLoaded com.yangzhou.themecoreplus-%{public}@", TCP_VERSION);
        os_log(TCPLogHandle(), "TCPS_START v%{public}@ bundle=%{public}@",
               TCP_VERSION, bundle);
        // 日志从这里开始。重启进程后「运行日志」页最上面那行的 pid 一变，就知道后面的事
        // 都发生在这一次重启之后。
        TCPLogLine(@"启动 v%@ bundle=%@ pid=%d",
                   TCP_VERSION, bundle,
                   (int)[NSProcessInfo processInfo].processIdentifier);

        // 桌面图标布局备份/恢复：注销或 SpringBoard 崩溃后保住之前的图标摆位。
        // 由 ThemeCorePlusLayout.m 实现；只在 SpringBoard 进程里动手（内部有 bundleID 检查）。
        TCPLayoutInstall();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        TCPPreferencesChanged,
                                        (__bridge CFStringRef)TCPPreferencesChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        // 1.0.31：**启动时序重写**（用户 2026-11-01 20:00「这插件从一开始就多次加载才能
        // 进桌面，是不是架构没写好」—— 是架构问题，已按本机五个主题引擎的通行做法改掉）。
        //
        // 原来：构造函数里立刻排 4 轮 TCPReload（0 / 0.3 / 1 / 2 秒），每轮都要
        //   objc_copyClassList 拷全进程类表（挂站 + 角标子串，一轮好几次）并重刷视图。
        //   这四轮全挤在 SpringBoard 刚起来的几秒里，看门狗预算被吃光 → 进程被杀 →
        //   系统拉起 → 又崩 → 用户看到的就是「黑屏反复加载，要好几次才进桌面」。
        //
        // 现在：构造函数里只挂一次（固定类名清单 objc_getClass 直取，零全表拷贝），
        //   等 SpringBoard 窗口建出来之后补挂两轮（那时 SpringBoardHome 一定已 dlopen）。
        TCPReload(NO);

        // 1.0.35（修「构造函数里读图 → +[UIScreen mainScreen] 断言 → SpringBoard 连崩」）：
        // 构造函数阶段只建索引、不读任何图片（见 ThemeCorePlusStore.m 顶部闸门说明）。
        // 2 秒后（main() 早就开跑、UIApplication 已建起来）开闸，顺带补做被推迟的
        // 遮罩体检与图标预热。SpringBoard 与设置面板两个进程各自开自己那道闸。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            TCPStoreEnableImageWork();
        });

        // 1.0.31：**补挂改成 dyld 事件，不再定时扫描**（用户 2026-11-01 20:09 确认这条是最优解）。
        // 本机五个主题引擎里 Mikkyy 用的正是 dyld_register_func_for_add_image：框架一加载就通知，
        // 那时类一定已注册，objc_getClass 直取即可。定时拍只能撞运气，且每拍都拷全表。
        // 回调已在 Hooks.m 里保证只在主队列回调、只做挂站。
        TCPInstallDyldImageObserver(^{
            TCPReload(NO);
        });

        // 1.0.32 取证：只在 SpringBoard 里 dump 一次缓存层方法表（定位秒加载真入口用）。
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
            TCPRunIconCacheProbe();
        }

        // 「注销后自动生效」（精简版 2026-10-31）：图标视图一建好就刷，尽量接近「注销即加载」。
        // 1.0.22 按用户要求第一拍 0 秒（视图还没建好时刷了白刷，但成本极低——遍历窗口树
        // 找不到 SBIconImageView 就返回），2.5 秒兜底拍负责把视图建好后的那次补上。
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                TCPRefreshIconImages();
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                TCPRefreshIconImages();
            });
        }

        // 屏幕归属普查（0.9.8）：跑在「图标已经建出来」之后的几秒，只读不重画。
        for (NSNumber *delay in @[ @1.5, @4.0, @10.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                TCPRunCensusAndWrite();
            });
        }

        // 1.0.7：时钟图标主动刷新。
        // 为什么不能只靠钩子：iOS 16.7 的 SBHClockApplicationIconImageView 从不重新 layout
        // （1.0.6 装机实测 clockv{look=0}），所以挂的 layoutSubviews 钩子一次都没触发。
        // 这里每 30 秒自己去找屏幕上的时钟视图并重画一次 —— 指针按当前时间重画，因此是活的。
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
            for (NSNumber *delay in @[ @3.0, @12.0 ]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    TCPClockTick();
                });
            }
            // 文件级静态持有：dispatch_source_t 在 ARC 下是对象，放局部变量会被释放并取消
            // （0.9.17 那次 tick=0 就是这个原因）。
            static dispatch_source_t sClockTimer = nil;
            if (sClockTimer == nil) {
                sClockTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                    dispatch_get_main_queue());
                if (sClockTimer != nil) {
                    dispatch_source_set_timer(sClockTimer,
                                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)),
                                              (uint64_t)(30.0 * NSEC_PER_SEC),
                                              (uint64_t)(2.0 * NSEC_PER_SEC));
                    dispatch_source_set_event_handler(sClockTimer, ^{ TCPClockTick(); });
                    dispatch_resume(sClockTimer);
                }
            }
        }
    }
}
