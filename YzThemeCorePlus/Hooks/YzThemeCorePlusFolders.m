#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusThemeStore.h"
#import "YzThemeCorePlusPrivate.h"

// 文件夹收起状态的 mini 拼图主题化。
// 每格 mini 图入口 = -[SBFolderIcon miniGridCellImageForIcon:]（在图标类上，不在 SBFolderIconImageCache）。
// 对每格：有主题图就用主题图（按系统 mini 图尺寸渲染、不圆角），否则系统原样。

static id (*orig_miniGrid)(id self, SEL _cmd, id icon) = NULL;

static id repl_miniGrid(id self, SEL _cmd, id icon) {
    if (![[YzThemeCorePlusConfig yz_themecoreplus_shared] yz_themecoreplus_isEnabled]) {
        return orig_miniGrid(self, _cmd, icon);
    }
    NSString *bundleID = nil;
    if ([icon respondsToSelector:@selector(applicationBundleID)]) {
        bundleID = [icon applicationBundleID];
    }
    YzThemeCorePlusThemeStore *store = [YzThemeCorePlusThemeStore yz_themecoreplus_shared];
    if (bundleID.length == 0 || ![store yz_themecoreplus_iconPathForBundleID:bundleID scale:0]) {
        return orig_miniGrid(self, _cmd, icon);
    }
    UIImage *stock = (UIImage *)orig_miniGrid(self, _cmd, icon);
    if (![stock isKindOfClass:[UIImage class]]) return stock;

    UIImage *themed = [store yz_themecoreplus_renderedIconForBundleID:bundleID
                                                                 size:stock.size
                                                                scale:stock.scale
                                                            applyMask:NO];
    return themed ?: stock;
}

__attribute__((constructor))
static void yz_folders_init(void) {
    @autoreleasepool {
        Class cls = objc_getClass("SBFolderIcon");
        if (cls) {
            MSHookMessageEx(cls, @selector(miniGridCellImageForIcon:),
                            (IMP)&repl_miniGrid, (IMP*)&orig_miniGrid);
        }
    }
}
