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
    NSArray<NSString *> *prefixes = @[ @"SBFolderIconImageView", @"SBFolderBackgroundView" ];
    // 旧版本曾挂过 _folderBackgroundImage / backgroundImage / _backgroundImage；
    // iOS 16.7 实测哪条存在用哪条，不猜。
    NSArray<NSString *> *selectors = @[@"_folderBackgroundImage",
                                        @"backgroundImage",
                                        @"_backgroundImage",
                                        @"folderBackgroundImage"];
    NSUInteger installed = TCPInstallSitesForClassPrefixes(prefixes, @[], selectors,
                                                           TCPSiteKindFolderBackground);
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
    NSArray<NSString *> *prefixes = @[ @"SBFolderIconImageCache" ];
    NSArray<NSString *> *selectors = @[ @"gridCellImageOfSize:forIcon:iconImageInfo:" ];
    NSUInteger installed = TCPInstallSitesForClassPrefixes(prefixes, @[], selectors,
                                                           TCPSiteKindFolderGridCell);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_FOLDER_GRID_SITES +%lu", (unsigned long)installed);
    }
}
