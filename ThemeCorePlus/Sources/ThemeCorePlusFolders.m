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
