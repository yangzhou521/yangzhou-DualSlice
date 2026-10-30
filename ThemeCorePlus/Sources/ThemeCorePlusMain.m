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

    NSString *text = [NSString stringWithFormat:@"%@;%@;%@;%@;%@;sites=%lu[%@];roots=[%@];%@;themes=%lu[%@]",
                      [store diagnostics], TCPDisplayProbeReport(), TCPRefreshProbeReport(),
                      TCPIconProbeReport(), TCPBadgeProbeReport(),
                      (unsigned long)TCPTotalSiteCount(), siteList, roots,
                      TCPSourceThemeRootsReport(), (unsigned long)themes.count, themeText];
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
}

// 让桌面把图标重新取一遍图。取不到就当没有这一步（有的版本没有这个方法）。
static void TCPRelayoutIcons(void) {
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
    TCPInstallFolderSites();
    TCPInstallFileSites();
    TCPRelayoutIcons();
    // refreshImages 只在「用户改了设置」时才为真。
    // 启动时（0/0.5/2/6 秒那几轮）一律不刷：2026-10-30 的安全模式就是启动即强刷视图
    // 与本机别的图标插件重入导致的（crash 栈 TCPReload → TCPRefreshIconImages →
    // clearIconImageInfo → … → tcpIconHook8，consecutiveCrashCount=7）。
    // 启动时挂好站点 + relayoutIcons 就够，下一次布局会自己按新主题取图。
    if (refreshImages) {
        TCPRefreshIconImages();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            TCPRefreshIconImages();
            TCPWriteDiagnostics();
        });
    }
    TCPWriteDiagnostics();
}

static void TCPPreferencesChanged(CFNotificationCenterRef center,
                                  void *observer,
                                  CFNotificationName name,
                                  const void *object,
                                  CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TCPReload(YES);
        os_log(TCPLogHandle(), "TCPS_RELOAD site=%lu", (unsigned long)TCPTotalSiteCount());
    });
}

__attribute__((constructor)) static void TCPInitialize(void) {
    @autoreleasepool {
        // TCP_VERSION 是 @"0.6.0"（NSString 字面量），所以这里只能用 %@：写成 %s 会把它当
        // C 字符串读，打出来是内存垃圾。ApelinLoaded 这一行是 apelin_package_confirm_loaded
        // 的标记行，格式不能动。
        os_log(TCPLogHandle(), "ApelinLoaded com.yangzhou.themecoreplus-%{public}@", TCP_VERSION);
        os_log(TCPLogHandle(), "TCPS_START v%{public}@ bundle=%{public}@",
               TCP_VERSION, [[NSBundle mainBundle] bundleIdentifier] ?: @"?");

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        TCPPreferencesChanged,
                                        (__bridge CFStringRef)TCPPreferencesChangedNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        // 补挂几轮：SpringBoardHome 的类按需加载，晚到的类只有下一轮才扫得到。
        for (NSNumber *delay in @[ @0.0, @0.5, @2.0, @6.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                TCPReload(NO);
            });
        }
    }
}
