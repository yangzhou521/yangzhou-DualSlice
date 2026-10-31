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
    // 精简版（2026-10-31）：只加载图标 + 角标，文件夹底板不接管。
    // 保留本文件编译是因为 Hooks.m 的文件夹槽位仍引用 TCPThemedFolderBackground，
    // 但这里不再挂任何文件夹站。
}
