//
//  ThemeCorePlusFolders.m —— 文件夹底板：主题里的 ANEMFolderIconBG（或同类名）换掉系统底板。
//
//  文件夹底板在 iOS 16 上有好几条入口（SBFolderIconImageView 自绘、SBFolderBackgroundView
//  贴图、SBFolderIcon 合成图），名字随版本变过，所以按「存在就挂」的候选清单挂，
//  主题里没有文件夹素材时站点直接原样转发。哪一条真的生效，看诊断里的普查结果。
//
#import "ThemeCorePlusHooks.h"
#import "ThemeCorePlusStore.h"

UIImage *TCPThemedFolderBackground(CGFloat scale) {
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;
    return [store folderBackgroundImageForScale:scale];
}

void TCPInstallFolderSites(void) {
    NSArray<NSString *> *prefixes = @[ @"SBFolderIcon", @"SBFolderBackground", @"SBFolderView",
                                       @"SBFolderScroll", @"SBFolderPage" ];
    NSArray<NSString *> *excluding = @[ @"Cache", @"Snapshot", @"Animator", @"Transition" ];
    NSArray<NSString *> *selectors = @[ @"_folderBackgroundImage", @"folderBackgroundImage",
                                        @"backgroundImage", @"_backgroundImage" ];
    NSUInteger installed = TCPInstallSitesForClassPrefixes(prefixes, excluding, selectors,
                                                           TCPSiteKindFolderBackground);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_FOLDER_SITES +%lu", (unsigned long)installed);
    }
}
