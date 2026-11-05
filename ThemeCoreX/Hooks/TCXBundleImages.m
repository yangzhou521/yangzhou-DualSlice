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
    if (!bid.length) return nil;
    if (!TCXPrefBool(@"Enabled", YES)) return nil;
    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];
    NSString *base = [name stringByDeletingPathExtension];
    // 通用索引：Bundles/<bid>/ 下所有素材一律生效（含 com.apple.springboard 的
    // 时钟/文件夹/角标素材，以及用户以后新加的任何 bundle 目录）。
    //
    // ⚠️ 绝不再退回 [store imageNamed:inBundle:scale:]。那个方法为了兜住 springboard 素材
    // 会跨目录找「同名」素材（<主题>/Bundles/com.apple.springboard/ → <主题>/IconBundles/
    // → 主题根）；而本站挂在 UIImage imageNamed:inBundle: 上，命中的是**整个 SpringBoard**
    // 里所有按 bundle 取图的地方 —— 任何 App 请求自己叫 icon / Icon 的资源，都会被换成
    // 主题里的同名素材。2026-11-06 实测（B41）：当前主题层第一个是「角标：透明玻璃」，
    // 它的角标底板正好叫 IconBundles/icon.png（裸名 icon），于是没素材的 App
    // （wiki.qaq.irisin 等）桌面图标被换成这张透明玻璃底板，用户看到「原本的图标没了」。
    UIImage *img = [store imageForAsset:base inBundle:bid];
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
