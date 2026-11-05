#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "../Headers/TCXPrivate.h"
#import "../Sources/TCXPrefs.h"
#import "../Sources/TCXStore.h"

// 文件夹两态：
//   关闭态（桌面上的文件夹图标）底板 = <主题>/Bundles/com.apple.springboard/ANEMFolderIconBG@3x.png
//   打开态（展开后的大背景）       = <主题>/Bundles/com.apple.springboard/ANEMFolderBG@3x.png
// 文件夹里外的 app 图标走 TCXIcons.m 的生图站，这里只管底图。
// 做法：在系统底板视图上叠一层 UIImageView（tag 固定，重复 layout 只复用），主题没有素材就移除。

void TCXNoteSite(NSString *site);

static const NSInteger kTCXFolderTag = 0x7C0F01;

static void TCXApplyBackground(UIView *host, NSString *name) {
    UIImageView *layer = (UIImageView *)[host viewWithTag:kTCXFolderTag];
    UIImage *image = nil;
    if (TCXPrefBool(@"Enabled", YES)) {
        TCXStore *store = [TCXStore shared];
        [store reloadIfNeeded];
        image = [store springboardImageNamed:name scale:3.0];
    }
    if (!image) { [layer removeFromSuperview]; return; }
    if (![layer isKindOfClass:[UIImageView class]]) {
        layer = [[UIImageView alloc] initWithFrame:host.bounds];
        layer.tag = kTCXFolderTag;
        layer.userInteractionEnabled = NO;
        layer.contentMode = UIViewContentModeScaleToFill;
        layer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:layer atIndex:0];
    }
    layer.frame = host.bounds;
    layer.image = image;
    // 主题底板盖住系统毛玻璃
    for (UIView *sub in host.subviews) {
        if (sub != layer && [NSStringFromClass([sub class]) containsString:@"Material"]) sub.alpha = 0.0;
    }
}

static void (*origIconBGLayout)(id, SEL);
static void replIconBGLayout(UIView *self, SEL _cmd) {
    if (origIconBGLayout) origIconBGLayout(self, _cmd);
    @try { TCXApplyBackground(self, @"ANEMFolderIconBG"); } @catch (NSException *e) {}
}

static void (*origFolderBGLayout)(id, SEL);
static void replFolderBGLayout(UIView *self, SEL _cmd) {
    if (origFolderBGLayout) origFolderBGLayout(self, _cmd);
    @try { TCXApplyBackground(self, @"ANEMFolderBG"); } @catch (NSException *e) {}
}

static void (*origFolderIconViewLayout)(id, SEL);
static void (*origFolderIconImageViewLayout)(id, SEL);

static void TCXHookLayout(NSString *className, IMP repl, IMP *slot, NSString *label) {
    Class cls = TCXClass(className);
    if (!cls) return;
    // layoutSubviews 由 UIView 继承、类自己不声明，必须用 respondsToSelector 判断
    // （这个坑在时钟模块踩过：用「类自己声明」判断永远 false，站永远挂不上）。
    if (![cls respondsToSelector:@selector(layoutSubviews)]) return;
    MSHookMessageEx(cls, @selector(layoutSubviews), repl, slot);
    if (*slot) TCXNoteSite(label);
}

void TCXInstallFolderHooks(void) {
    // 一站一槽：每个类各自的原实现槽。
    TCXHookLayout(@"SBFolderIconBackgroundView", (IMP)&replIconBGLayout,
                  (IMP *)&origIconBGLayout, @"folder:closed");
    TCXHookLayout(@"SBFolderBackgroundView", (IMP)&replFolderBGLayout,
                  (IMP *)&origFolderBGLayout, @"folder:open");
    // 关闭态容器：SnowBoard 实测背景也在 SBFolderIconView / SBFolderIconImageView 上，
    // 补挂这两处，保证「未打开时也显示文件夹素材」（用户 2026-11-06 01:50 报的）。
    TCXHookLayout(@"SBFolderIconView", (IMP)&replIconBGLayout,
                  (IMP *)&origFolderIconViewLayout, @"folder:iconview");
    TCXHookLayout(@"SBFolderIconImageView", (IMP)&replIconBGLayout,
                  (IMP *)&origFolderIconImageViewLayout, @"folder:iconimageview");
}
