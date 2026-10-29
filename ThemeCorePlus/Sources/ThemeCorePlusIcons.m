//
//  ThemeCorePlusIcons.m —— 主屏 / Dock / 搜索图标：把系统要的图换成主题素材合成的图。
//
//  挂点选择（全部按「类自己声明了才挂」的规矩，见 ThemeCorePlusHooks.h 的 R1/R2）：
//   · 最上游是 SBIcon 的 -iconImageWithInfo: (SBIconImageInfo)。主屏、Dock、App 库、
//     搜索、切换器都是从它拿图的，挂在这里一处顶多处。
//   · unmaskedIconImageWithInfo: 是 SBIconView 走「不要遮罩」路径时用的，一起挂。
//   · iconImageWithImageInfo: 是少数版本的选择器名，存在就挂。
//  视图类一律排除：SBIconView / SBIconImageView / SBIconImageCrossfadeView 都是拿图来画，
//  在它们身上再套一层只会二次套用遮罩。
//
#import "ThemeCorePlusHooks.h"
#import "ThemeCorePlusStore.h"

// 从 icon 对象身上问出 bundle id。SBIcon 的子类各有各的写法，按可靠性依次问。
// 全部用 objc_msgSend 直接发消息，绝不写 [SBApplicationIcon xxx]：那会让链接期多出一个
// 私有类符号（SDK 里没有），构建就会失败。
static NSString *TCPIconBundleIdentifier(id icon) {
    if (icon == nil) return nil;

    static SEL sApplicationBundleID = NULL;
    static SEL sApplication = NULL;
    static SEL sBundleIdentifier = NULL;
    static SEL sLeafIdentifier = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sApplicationBundleID = NSSelectorFromString(@"applicationBundleID");
        sApplication = NSSelectorFromString(@"application");
        sBundleIdentifier = NSSelectorFromString(@"bundleIdentifier");
        sLeafIdentifier = NSSelectorFromString(@"leafIdentifier");
    });

    if ([icon respondsToSelector:sApplicationBundleID]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(icon, sApplicationBundleID);
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    if ([icon respondsToSelector:sApplication]) {
        id application = ((id (*)(id, SEL))objc_msgSend)(icon, sApplication);
        if (application && [application respondsToSelector:sBundleIdentifier]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(application, sBundleIdentifier);
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
        }
    }
    if ([icon respondsToSelector:sLeafIdentifier]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(icon, sLeafIdentifier);
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

UIImage *TCPThemedIconImage(id icon, TCPIconImageInfo info) {
    if (icon == nil || info.size.width <= 0 || info.size.height <= 0) return nil;
    NSString *bundleID = TCPIconBundleIdentifier(icon);
    if (bundleID.length == 0) return nil;

    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;

    // 遮罩：优先用主题自带的作者遮罩（store 自己会套）；IconCornerMask 只是没有素材时的兜底。
    CGFloat radius = [store cornerMaskEnabled] ? info.cornerRadius : 0;
    return [store iconImageForBundleID:bundleID
                                 size:info.size
                                scale:info.scale
                         cornerRadius:radius];
}

void TCPInstallIconSites(void) {
    NSArray<NSString *> *prefixes = @[ @"SBIcon", @"SBLeaf", @"SBApplication", @"SBH",
                                       @"SBFolder", @"SBSearch", @"SBWidget", @"SBNewsstand" ];
    // 视图/缓存/控制器类不吃这一站：它们只是拿图来画，套两次遮罩就糊了。
    NSArray<NSString *> *excluding = @[ @"View", @"Badge", @"Image", @"Cache", @"Controller",
                                        @"List", @"Accessory", @"Animator", @"Crossfade",
                                        @"Transition", @"Drag", @"Drop", @"Page", @"Scroll",
                                        @"Layout", @"Observer", @"Provider", @"Settings" ];
    NSArray<NSString *> *selectors = @[ @"iconImageWithInfo:",
                                        @"unmaskedIconImageWithInfo:",
                                        @"iconImageWithImageInfo:" ];
    NSUInteger installed = TCPInstallSitesForClassPrefixes(prefixes, excluding, selectors,
                                                           TCPSiteKindIconImageInfo);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_ICON_SITES +%lu", (unsigned long)installed);
    }
}
