//
//  ThemeCorePlusFolders.m —— 文件夹底板：主题里的 ANEMFolderIconBG（或同类名）换掉系统底板。
//
//  文件夹底板在 iOS 16 上有好几条入口（SBFolderIconImageView 自绘、SBFolderBackgroundView
//  贴图、SBFolderIcon 合成图），名字随版本变过，所以按「存在就挂」的候选清单挂，
//  主题里没有文件夹素材时站点直接原样转发。哪一条真的生效，看诊断里的普查结果。
//
//  1.0.4：恢复文件夹底板站（1.0.0 精简版误砍）。同时加文件夹预览取证：递归扫子视图 +
//  枚举 SBFolderIconImageView 自己声明的方法，一次装包就能定位该挂哪一层。
//
#import "ThemeCorePlusHooks.h"
#import "ThemeCorePlusStore.h"

UIImage *TCPThemedFolderBackground(CGFloat scale) {
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;
    return [store folderBackgroundImageForScale:scale];
}

// 1.0.4：恢复文件夹底板站。候选方法名按「存在就挂」挂，不同 iOS 版本可能走不同入口。
void TCPInstallFolderSites(void) {
    // 1.0.31：固定类名直取（原来按前缀扫全表；此函数当前未被调用，改掉是防止以后启用时
    // 又把全表拷贝带回启动路径）。
    NSArray<NSString *> *folderClasses = @[ @"SBFolderIconImageView", @"SBFolderBackgroundView" ];
    // 旧版本曾挂过 _folderBackgroundImage / backgroundImage / _backgroundImage；
    // iOS 16.7 实测哪条存在用哪条，不猜。
    NSArray<NSString *> *selectors = @[@"_folderBackgroundImage",
                                        @"backgroundImage",
                                        @"_backgroundImage",
                                        @"folderBackgroundImage"];
    NSUInteger installed = TCPInstallSitesFromClassList(folderClasses, selectors,
                                                        TCPSiteKindFolderBackground, NO);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_FOLDER_SITES +%lu", (unsigned long)installed);
    }
}

// 1.0.12：文件夹收起状态 mini 拼图「每一格图标图」。
// 入口是 SBFolderIconImageCache 的 -gridCellImageOfSize:forIcon:iconImageInfo:（诊断 allm= 坐实，
// /5 = self+SEL+CGSize+icon+info 五个参数）。它参数里直接带那一格的 icon，逐个来问，
// 所以不用拿文件夹 leaf 列表（lv=SBFolderIcon:noleafsel 那条路已证死，别再试）。
// 只挂缓存类这一个前缀：别的 SBFolder* 类不声明这个选择器，R2（类自己声明才挂）会自然跳过。
void TCPInstallFolderGridCellSites(void) {
    // 1.0.31：固定类名直取（原来按 "SBFolderIconImageCache" 前缀扫全表）。
    NSArray<NSString *> *cacheClasses = @[ @"SBFolderIconImageCache" ];
    NSArray<NSString *> *selectors = @[ @"gridCellImageOfSize:forIcon:iconImageInfo:" ];
    // 必须用「只挂实例方法」的入口：SBFolderIconImageCache 的元类上有个同名的 convenience
    // 类方法，通用站「类方法优先」会挂到 + 版本（诊断 sites= 里是 +SBFolderIconImageCache:…
    // 且 grid{look=0}），系统真正调的 - 版本就拦不到。挂实例方法后 grid{look} 才会涨。
    NSUInteger installed = TCPInstallSitesFromClassList(cacheClasses, selectors,
                                                        TCPSiteKindFolderGridCell, YES);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_FOLDER_GRID_SITES +%lu", (unsigned long)installed);
    }

    // 1.0.20 取证：gridCellImageOfSize 本机 look=0（系统不逐格问）。再挂两个候选整图入口，
    // 只计数、原样返回，装完读 minigrid{look} 就知道到底哪个方法在出 mini 拼图。
    NSUInteger mg = TCPInstallSitesFromClassList(cacheClasses,
                                                 @[ @"genericMiniGridImage" ],
                                                 TCPSiteKindFolderMiniGrid, YES);
    if (mg > 0) {
        os_log(TCPLogHandle(), "TCPS_FOLDER_MINIGRID_SITES +%lu", (unsigned long)mg);
    }
}

// 1.0.22：文件夹收起 mini 拼图不重新生成的修法。
// 取证（1.0.20/1.0.21）：gridCellImageOfSize 与 genericMiniGridImage 两个探针 look=0——
// 系统出 mini 图不走 SBFolderIconImageCache 的这两个方法；mini 图是 SBFolderIcon 的
// generateIconImageWithInfo:（已挂在 icon 站）生成后**缓存**的，换主题不会自动重算。
// 修法：找到屏幕上的 SBFolderIcon（视图的 _folderIcon / folderIcon 属性），
// 对缓存类调 -informObserversOfUpdateForFolderIcon:（allm= 坐实该类声明了它，/3 = 一个对象参数），
// 通知「文件夹图更新了」→ 系统重算 mini 图，重算时 leaf 站（SBLeafIcon:generateIconImageWithInfo: 已挂）出主题图。
static NSInteger sFolderNotifyCount = 0;
static NSString *sFolderNotifyLast = @"-";

NSString *TCPFolderNotifyReport(void) {
    return [NSString stringWithFormat:@"foldernotify{n=%ld,last=%@}",
            (long)sFolderNotifyCount, sFolderNotifyLast];
}

void TCPFolderNotifyRecalc(void) {
    if (![NSThread isMainThread]) return;
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active || !store.iconsEnabled) { sFolderNotifyLast = @"inactive"; return; }
    Class cacheClass = NSClassFromString(@"SBFolderIconImageCache");
    Class viewClass = NSClassFromString(@"SBFolderIconImageView");
    if (cacheClass == Nil || viewClass == Nil) { sFolderNotifyLast = @"nocls"; return; }
    SEL informSel = NSSelectorFromString(@"informObserversOfUpdateForFolderIcon:");
    if (![cacheClass instancesRespondToSelector:informSel]) { sFolderNotifyLast = @"nosel"; return; }

    // 拿缓存单例
    id cache = nil;
    for (NSString *name in @[ @"sharedInstance", @"sharedCache", @"defaultCache", @"sharedImageCache" ]) {
        SEL sel = NSSelectorFromString(name);
        if ([cacheClass respondsToSelector:sel]) {
            cache = ((id (*)(id, SEL))objc_msgSend)((id)cacheClass, sel);
            if (cache != nil) break;
        }
    }
    if (cache == nil) { sFolderNotifyLast = @"nocache"; return; }

    // 遍历窗口树找文件夹视图 → 取它的 folderIcon
    NSMutableArray *stack = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows) [stack addObject:window];
    NSUInteger guard = 0;
    NSInteger notified = 0;
    NSMutableSet *seenIcons = [NSMutableSet set];
    while (stack.count > 0 && guard++ < 6000) {
        UIView *view = [stack lastObject];
        [stack removeLastObject];
        if ([view isKindOfClass:viewClass]) {
            id folderIcon = nil;
            @try { folderIcon = [view valueForKey:@"_folderIcon"]; } @catch (NSException *e) { (void)e; }
            if (folderIcon == nil) {
                @try { folderIcon = [view valueForKey:@"folderIcon"]; } @catch (NSException *e) { (void)e; }
            }
            if (folderIcon != nil && ![seenIcons containsObject:folderIcon]) {
                [seenIcons addObject:folderIcon];
                @try {
                    ((void (*)(id, SEL, id))objc_msgSend)(cache, informSel, folderIcon);
                    notified++;
                } @catch (NSException *e) { (void)e; }
            }
        }
        [stack addObjectsFromArray:view.subviews];
    }
    sFolderNotifyCount += notified;
    sFolderNotifyLast = [NSString stringWithFormat:@"ok:%ld", (long)notified];
}
