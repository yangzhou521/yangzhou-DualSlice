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

#pragma mark - 显示层站：iOS 16 上真正决定屏幕上那张图的地方

// 打点：显示层有没有被问过、换成功几次、没换成是因为什么。诊断里一眼可见，不用看屏幕。
static NSInteger sDisplayLook = 0;
static NSInteger sDisplayHit = 0;
static NSInteger sDisplayMissNoImage = 0;
static NSInteger sDisplayMissNoIcon = 0;

NSString *TCPDisplayProbeReport(void) {
    return [NSString stringWithFormat:@"disp{look=%ld,hit=%ld,noimg=%ld,noicon=%ld}",
            (long)sDisplayLook, (long)sDisplayHit,
            (long)sDisplayMissNoImage, (long)sDisplayMissNoIcon];
}

// 视图 → 它正在显示的图标对象。SBIconImageView 自己声明了 -icon（普查坐实）。
static id TCPDisplayViewIcon(id view) {
    static SEL sIcon = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sIcon = NSSelectorFromString(@"icon");
    });
    if (![view respondsToSelector:sIcon]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(view, sIcon);
}

// 显示图可能是 UIImage（displayedImage / squareContentsImage），也可能是 CGImage
// （contentsImage 那条路）。两条都要认，尺寸也要按各自的含义折算成点。
static BOOL TCPDisplayIsCGImage(id object) {
    return object != nil && CFGetTypeID((__bridge CFTypeRef)object) == CGImageGetTypeID();
}

id TCPThemedDisplayReplacement(id original, id view) {
    if (original == nil || view == nil) return original;

    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return original;

    sDisplayLook++;

    // 尺寸/缩放：UIImage 自带 scale；CGImage 没有，按屏幕缩放比折成点，
    // 否则 180×180 像素会被当成 180pt 渲染出一张巨图。
    CGSize pointSize = CGSizeZero;
    CGFloat scale = [UIScreen mainScreen].scale;
    if (scale <= 0) scale = 2.0;
    if ([original isKindOfClass:[UIImage class]]) {
        UIImage *image = (UIImage *)original;
        pointSize = image.size;
        if (image.scale > 0) scale = image.scale;
    } else if (TCPDisplayIsCGImage(original)) {
        CGImageRef cg = (__bridge CGImageRef)original;
        pointSize = CGSizeMake(CGImageGetWidth(cg) / scale, CGImageGetHeight(cg) / scale);
    }
    if (pointSize.width < 1.0 || pointSize.height < 1.0) {
        sDisplayMissNoImage++;
        return original;
    }

    // 复用 iconImageWithInfo: 那一站的同一套合成：主题遮罩在 store 里套（素材存在就总套，
    // 与 cornerRadius 无关），所以这里传 0，不会二次套用。
    TCPIconImageInfo info = { .size = pointSize, .scale = scale, .cornerRadius = 0 };
    UIImage *themed = TCPThemedIconImage(TCPDisplayViewIcon(view), info);
    if (themed == nil) {
        sDisplayMissNoIcon++;
        return original;
    }
    sDisplayHit++;

    // 类型严丝合缝地还回去：UIImage 进就 UIImage 出，CGImage 进就 CGImage 出。
    // 拿 UIImage 顶 CGImage 是当场崩溃的路子（角标那次安全模式就是这么来的）。
    if ([original isKindOfClass:[UIImage class]]) return themed;
    if (TCPDisplayIsCGImage(original)) return (__bridge id)themed.CGImage;
    return original;
}

void TCPInstallDisplaySites(void) {
    // 只挂 SBIconImageView（应用图标视图：主屏、Dock、App 库、切换器都用它）。
    // 不挂 SBFolderIconImageView 的 contentsImage：那里是文件夹里小图拼成的大图，
    // 换成主题底板会把里面所有小图标一并抹掉。也不挂时钟视图：时钟要动态指针。
    NSArray<NSString *> *prefixes = @[ @"SBIconImageView" ];
    NSArray<NSString *> *selectors = @[ @"displayedImage", @"contentsImage",
                                        @"squareContentsImage" ];
    NSUInteger installed = TCPInstallSitesForClassPrefixes(prefixes, @[], selectors,
                                                           TCPSiteKindDisplayImage);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_ICON_DISPLAY_SITES +%lu", (unsigned long)installed);
    }
}
