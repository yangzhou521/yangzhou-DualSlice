#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../Sources/TCXPrefs.h"
#import "../Sources/TCXStore.h"

// 控制中心图标 / 各系统 bundle 资源：ThemeCore 的路线 = 按 bundle 取图时查主题
//   <主题>/Bundles/<bundle id>/<资源名>@3x.png
// 例：Bundles/com.apple.control-center.FlashlightModule/FlashlightOn@3x.png
// 挂 UIImage 的两个按 bundle 取图类方法，命中就返回主题图，否则原样。

extern void TCXNoteSite(NSString *site);
extern void TCXCountIconHit(NSString *bundleID);

static UIImage *(*origNamedInBundle)(id, SEL, NSString *, NSBundle *, UITraitCollection *);
static UIImage *(*origNamedInBundleConfig)(id, SEL, NSString *, NSBundle *, id);

static UIImage *TCXBundleLookup(NSString *name, NSBundle *bundle) {
    if (![name isKindOfClass:[NSString class]] || !name.length) return nil;
    NSString *bid = bundle.bundleIdentifier;
    if (!bid.length || [bid isEqualToString:@"com.apple.springboard"]) return nil; // 桌面资源走专用站
    if (!TCXPrefBool(@"Enabled", YES)) return nil;
    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];
    if (!store.themePath) return nil;
    NSString *base = [name stringByDeletingPathExtension];
    UIImage *img = [store imageNamed:base inBundle:bid scale:3.0];
    if (img) TCXCountIconHit(bid);
    return img;
}

static UIImage *replNamedInBundle(id self, SEL _cmd, NSString *name, NSBundle *bundle, UITraitCollection *traits) {
    @try { UIImage *t = TCXBundleLookup(name, bundle); if (t) return t; } @catch (NSException *e) {}
    return origNamedInBundle ? origNamedInBundle(self, _cmd, name, bundle, traits) : nil;
}

static UIImage *replNamedInBundleConfig(id self, SEL _cmd, NSString *name, NSBundle *bundle, id config) {
    @try { UIImage *t = TCXBundleLookup(name, bundle); if (t) return t; } @catch (NSException *e) {}
    return origNamedInBundleConfig ? origNamedInBundleConfig(self, _cmd, name, bundle, config) : nil;
}

void TCXInstallBundleImageHooks(void) {
    Class meta = object_getClass([UIImage class]);
    SEL a = @selector(imageNamed:inBundle:compatibleWithTraitCollection:);
    if (class_getClassMethod([UIImage class], a)) {
        MSHookMessageEx(meta, a, (IMP)&replNamedInBundle, (IMP *)&origNamedInBundle);
        if (origNamedInBundle) TCXNoteSite(@"UIImage:imageNamed:inBundle:traits");
    }
    SEL b = @selector(imageNamed:inBundle:withConfiguration:);
    if (class_getClassMethod([UIImage class], b)) {
        MSHookMessageEx(meta, b, (IMP)&replNamedInBundleConfig, (IMP *)&origNamedInBundleConfig);
        if (origNamedInBundleConfig) TCXNoteSite(@"UIImage:imageNamed:inBundle:config");
    }
}
