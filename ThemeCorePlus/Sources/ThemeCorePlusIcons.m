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

// 定义在下面「图标像素自检」那节：把合成的图量一遍像素（C 要求先声明后使用）。
static void TCPNoteComposedImage(UIImage *image, NSString *bundleID);

UIImage *TCPThemedIconImage(id icon, TCPIconImageInfo info) {
    if (icon == nil || info.size.width <= 0 || info.size.height <= 0) return nil;
    NSString *bundleID = TCPIconBundleIdentifier(icon);
    if (bundleID.length == 0) return nil;

    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;

    // 遮罩：优先用主题自带的作者遮罩（store 自己会套）；IconCornerMask 只是没有素材时的兜底。
    CGFloat radius = [store cornerMaskEnabled] ? info.cornerRadius : 0;
    UIImage *image = [store iconImageForBundleID:bundleID
                                           size:info.size
                                          scale:info.scale
                                   cornerRadius:radius];
    TCPNoteComposedImage(image, bundleID);   // 自己的产物也量一遍像素，见「图标像素自检」那节
    return image;
}

void TCPInstallIconSites(void) {
    NSArray<NSString *> *prefixes = @[ @"SBIcon", @"SBLeaf", @"SBApplication", @"SBH",
                                       @"SBFolder", @"SBSearch", @"SBWidget", @"SBNewsstand" ];
    // 视图/缓存/控制器类不吃这一站：它们只是拿图来画，套两次遮罩就糊了。
    NSArray<NSString *> *excluding = @[ @"View", @"Badge", @"Image", @"Cache", @"Controller",
                                        @"List", @"Accessory", @"Animator", @"Crossfade",
                                        @"Transition", @"Drag", @"Drop", @"Page", @"Scroll",
                                        @"Layout", @"Observer", @"Provider", @"Settings" ];
    // generateIconImageWithInfo: 是真正的「生图」入口：本机运行期按 IMP 归属查出来的结果是
    // MarkThemeRuntime.dylib 挂在 SBApplicationIcon:generateIconImageWithInfo:，ThemeCore 0.5.1
    // 的二进制里也有同名方法；而我们原来只挂 getter（iconImageWithInfo:），在这台 16.7.16 上
    // 一次都没被问过（诊断 look=0）。所以把生成站一起挂上：谁生成图标图，谁就被换成主题图。
    NSArray<NSString *> *selectors = @[ @"iconImageWithInfo:",
                                        @"unmaskedIconImageWithInfo:",
                                        @"iconImageWithImageInfo:",
                                        @"generateIconImageWithInfo:" ];
    NSUInteger installed = TCPInstallSitesForClassPrefixes(prefixes, excluding, selectors,
                                                           TCPSiteKindIconImageInfo);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_ICON_SITES +%lu", (unsigned long)installed);
    }
}

#pragma mark - 即时生效：不注销也能换图

// 为什么需要这一站：图标图进了 SBHIconImageCache（按 info 缓存），只换来图函数没用 ——
// 视图手里那张图早就在缓存里了。所以改设置后要做的两件事：清缓存 + 让视图按新 info 重取。
// 打点写进诊断，下一轮不用看屏幕就能知道清缓存那一步到底调到了哪个方法名。
static NSInteger sRefreshViews = 0;
static NSInteger sRefreshPushed = 0;   // 真的被叫去重新出图的视图数（0 = 刷新没落到视图上）
static NSInteger sRefreshModel = 0;
static NSInteger sRefreshCache = 0;
static NSInteger sRefreshCacheMiss = 0;
static NSString *sRefreshPurgeName = nil;

NSString *TCPRefreshProbeReport(void) {
    return [NSString stringWithFormat:@"ref{views=%ld,pushed=%ld,model=%ld,cache=%ld,miss=%ld,purge=%@}",
            (long)sRefreshViews, (long)sRefreshPushed, (long)sRefreshModel, (long)sRefreshCache,
            (long)sRefreshCacheMiss, sRefreshPurgeName ?: @"-"];
}

// SBIconImageView 自己声明的 -iconImageInfo / -setIconImageInfo: 用的就是这个结构。
// 与 ThemeCorePlusHooks.h 的 TCPIconImageInfo 完全同构（4 个 double，按 HFA 走 d0–d3），
// 这里不再另抄一份字段：ABI 关键结构体只能有一个定义，抄两份迟早改一边漏一边。
typedef TCPIconImageInfo TCPIconImageInfoShort;

// 图标图缓存对象上的清空方法：不同版本名字不同，按顺序试第一个存在的。
// 都是无参方法 —— 带参数的那种（purgeCachedImagesForIcons:）要传图标集合，不在刷新路径上冒险。
static void TCPPurgeViewImageCache(id view) {
    static SEL sCacheGetter = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sCacheGetter = NSSelectorFromString(@"iconImageCache");
    });
    if (![view respondsToSelector:sCacheGetter]) return;

    id cache = ((id (*)(id, SEL))objc_msgSend)(view, sCacheGetter);
    if (cache == nil) {
        sRefreshCacheMiss++;
        return;
    }
    for (NSString *name in @[ @"purgeCache", @"purgeAllCaches", @"purgeCaches",
                              @"clearCache", @"removeAllObjects" ]) {
        SEL sel = NSSelectorFromString(name);
        if ([cache respondsToSelector:sel]) {
            ((void (*)(id, SEL))objc_msgSend)(cache, sel);
            sRefreshCache++;
            sRefreshPurgeName = name;
            return;
        }
    }
    sRefreshCacheMiss++;
}

#pragma mark - 图标像素自检：桌面上哪些图标其实是空的 / 屏幕上挂的是不是我们的图

// 用户 2026-10-30 14:42/14:51 两次报「有些是空白图标」「图标目前二个图层」，15:33 又说「图标主题和角标
// 都没正式显示加载」，但 agent 这边看不到屏幕（本机 icli screen ocr / describe 都报 capture failed，
// 我也没有读图能力）。所以让插件自己数像素，一次回答三件事：
//   gen{...}  我们合出来的那张图本身是不是透明的 —— 是的话就是我们把图抹没了；
//   pix{...}  视图交出去的图是不是我们的、**屏幕上那几个 UIImageView 手里攥的是不是我们的** ——
//             「交出去的是主题图、屏幕上是原图」就等于显示层白干，得改走 IconServices 那条路；
//             顺带数一个视图里叠了几张 UIImageView（「两个图层」）。
// 说明：这段以前写好了却**从来没被调用**（15:4x 才发现），所以诊断里一直没有 pix{}。

typedef struct {
    CGFloat coverage;    // 不透明像素占比：1 = 整张都是实的，0 = 全透明
    CGFloat flat;        // 纯白/纯黑且没有细节的比例（发白的空壳）
    CGFloat luminance;   // 实心部分的平均亮度 0~1
    BOOL valid;
} TCPPixelStats;

static TCPPixelStats TCPPixelStatsForImage(UIImage *image) {
    TCPPixelStats stats = { 0, 0, 0, NO };
    if (image == nil || image.CGImage == NULL) return stats;

    const size_t side = 24;   // 24×24 足够分清「透明 / 纯色 / 有内容」，又不会拖慢刷新
    unsigned char buffer[side * side * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buffer, side, side, 8, side * 4, space,
                                             kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (ctx == NULL) return stats;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    CGContextDrawImage(ctx, CGRectMake(0, 0, side, side), image.CGImage);
    CGContextRelease(ctx);

    const size_t total = side * side;
    size_t clear = 0, flat = 0, lumaSum = 0;
    for (size_t i = 0; i < total; i++) {
        const unsigned char *px = buffer + i * 4;
        if (px[3] < 8) { clear++; continue; }
        int lum = (px[0] * 299 + px[1] * 587 + px[2] * 114) / 1000;
        lumaSum += (size_t)lum;
        int dr = (int)px[0] - (int)px[1];
        int dg = (int)px[1] - (int)px[2];
        if (abs(dr) < 8 && abs(dg) < 8 && (lum > 244 || lum < 12)) flat++;
    }
    stats.valid = YES;
    stats.coverage = (CGFloat)(total - clear) / (CGFloat)total;
    stats.flat = (CGFloat)flat / (CGFloat)total;
    size_t solid = total - clear;
    stats.luminance = solid > 0 ? (CGFloat)lumaSum / (CGFloat)(255.0 * (double)solid) : 0;
    return stats;
}

// 显示层站的打点开关：体检自己问 displayedImage 时不要把自己的询问算进 look/hit（会虚高）。
static BOOL sPixelQuietDisplayCounters = NO;
// 定义在文件后面（显示层站那节）：视图 → 它绑定的图标对象。
static id TCPDisplayViewIcon(id view);

// —— 合成站：我们自己的产物 ——
static NSInteger sComposedCount = 0;
static NSInteger sComposedClear = 0;
static CGFloat sComposedMinCoverage = 1.0;
static CGFloat sComposedLuminance = 0;
static NSString *sComposedLast = nil;

// 合完一张主题图立刻量它自己。全透明 = 就是我们把它抹没了，用户看到的就是「空白图标」。
static void TCPNoteComposedImage(UIImage *image, NSString *bundleID) {
    if (image == nil) return;
    sComposedCount++;
    TCPPixelStats stats = TCPPixelStatsForImage(image);
    if (!stats.valid) {
        sComposedLast = [NSString stringWithFormat:@"%@:%.0fx%.0f@%.0f,noCGImage",
                         bundleID ?: @"?", image.size.width, image.size.height, image.scale];
        return;
    }
    if (stats.coverage < sComposedMinCoverage) sComposedMinCoverage = stats.coverage;
    if (stats.coverage < 0.2) sComposedClear++;
    sComposedLuminance = stats.luminance;
    sComposedLast = [NSString stringWithFormat:@"%@:%.0fx%.0f@%.0f,cov=%.2f,lum=%.2f",
                     bundleID ?: @"?", image.size.width, image.size.height, image.scale,
                     (double)stats.coverage, (double)stats.luminance];
}

// —— 视图层：屏幕上到底挂了什么 ——
static NSInteger sPixelViews = 0;
static NSInteger sPixelThemed = 0;        // 视图 displayedImage 交出来的就是我们合的图
static NSInteger sPixelScreenTotal = 0;   // 数过的屏幕 UIImageView 张数
static NSInteger sPixelScreenThemed = 0;  // 屏幕上那张图是我们的
static NSInteger sPixelScreenStock = 0;   // 屏幕上那张图不是我们的（=显示层白干）
static NSInteger sPixelClear = 0;
static NSInteger sPixelFlat = 0;
static NSInteger sPixelNil = 0;
static NSInteger sPixelMaxImageViews = 0;
static CGFloat sPixelMinOpaque = 1.0;
static NSMutableArray<NSString *> *sPixelBlankSamples = nil;

// 一个视图里挂了几张 UIImageView（递归两层）。同一个位置叠两张，屏幕上就是「两个图层」。
static NSInteger TCPCountImageViews(UIView *view) {
    NSInteger count = 0;
    for (UIView *sub in view.subviews) {
        NSString *name = NSStringFromClass([sub class]);
        if ([name containsString:@"ImageView"] && sub.bounds.size.width > 1) count++;
        if (sub.subviews.count > 0 && count > 0) count += TCPCountImageViews(sub);
    }
    return count;
}

// 现场体检一个图标视图。刷新时对每个视图调一次。
static void TCPInspectIconView(id view) {
    if (view == nil || ![view isKindOfClass:[UIView class]]) return;
    if (sPixelBlankSamples == nil) sPixelBlankSamples = [NSMutableArray array];
    sPixelViews++;

    NSString *bundleID = TCPIconBundleIdentifier(TCPDisplayViewIcon(view));

    NSInteger layers = TCPCountImageViews((UIView *)view);
    if (layers > sPixelMaxImageViews) sPixelMaxImageViews = layers;

    // ① 视图交出去的那张图（把打点静音，免得体检把自己的询问算成 look/hit）
    static SEL sDisplayed = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sDisplayed = NSSelectorFromString(@"displayedImage");
    });
    UIImage *displayed = nil;
    if ([view respondsToSelector:sDisplayed]) {
        sPixelQuietDisplayCounters = YES;
        id value = ((id (*)(id, SEL))objc_msgSend)(view, sDisplayed);
        sPixelQuietDisplayCounters = NO;
        if ([value isKindOfClass:[UIImage class]]) displayed = value;
    }
    if (displayed == nil) {
        sPixelNil++;
    } else if ([[TCPThemeStore shared] isRenderedImage:displayed]) {
        sPixelThemed++;
    }

    // ② 屏幕上真正挂着的图：视图里那几张 UIImageView 手里的 image
    TCPThemeStore *store = [TCPThemeStore shared];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:((UIView *)view).subviews];
    NSUInteger guard = 0;
    while (queue.count > 0 && guard++ < 32) {
        UIView *sub = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([sub isKindOfClass:[UIImageView class]] && sub.bounds.size.width > 1) {
            UIImage *image = ((UIImageView *)sub).image;
            sPixelScreenTotal++;
            if (image == nil) {
                sPixelNil++;
            } else {
                if ([store isRenderedImage:image]) sPixelScreenThemed++;
                else sPixelScreenStock++;

                TCPPixelStats stats = TCPPixelStatsForImage(image);
                if (stats.valid) {
                    if (stats.coverage < sPixelMinOpaque) sPixelMinOpaque = stats.coverage;
                    NSString *tag = nil;
                    if (stats.coverage < 0.1) {
                        sPixelClear++;
                        tag = @"(clear)";
                    } else if (stats.flat > 0.9) {
                        sPixelFlat++;
                        tag = @"(flat)";
                    }
                    if (tag && bundleID.length > 0 && sPixelBlankSamples.count < 8 &&
                        ![sPixelBlankSamples containsObject:[bundleID stringByAppendingString:tag]]) {
                        [sPixelBlankSamples addObject:[bundleID stringByAppendingString:tag]];
                    }
                }
            }
        }
        if (sub.subviews.count > 0) [queue addObjectsFromArray:sub.subviews];
    }
}

NSString *TCPIconPixelProbeReport(void) {
    return [NSString stringWithFormat:
            @"gen{n=%ld,clear=%ld,minCov=%.2f,lum=%.2f,last=%@};"
            @"pix{n=%ld,themed=%ld,screen{total=%ld,ours=%ld,stock=%ld},clear=%ld,flat=%ld,nil=%ld,minOpaque=%.2f,maxImgViews=%ld,blank=[%@]}",
            (long)sComposedCount, (long)sComposedClear, (double)sComposedMinCoverage,
            (double)sComposedLuminance, sComposedLast ?: @"-",
            (long)sPixelViews, (long)sPixelThemed, (long)sPixelScreenTotal,
            (long)sPixelScreenThemed, (long)sPixelScreenStock, (long)sPixelClear,
            (long)sPixelFlat, (long)sPixelNil, (double)sPixelMinOpaque,
            (long)sPixelMaxImageViews,
            sPixelBlankSamples.count > 0 ? [sPixelBlankSamples componentsJoinedByString:@","] : @"-"];
}

// 让屏幕当场换图，不注销。2026-10-30 第二版：
//   上一版只清缓存 → 屏幕上纹丝不动（清了缓存没人重新问，视图手里还攥着旧图）。
//   这一版在清完之后**主动叫每个视图重新出图**：-updateImageAnimated:NO 是视图自己的
//   正常重画入口，它会重新走 -contentsImage → 显示层站 → 我们的主题图。
//   特意不再用 clearIconImageInfo + setIconImageInfo: 那条路（0.6.0 就是在那条路上崩的）。
// 时序：必须在主线程（碰视图树 + 重新出图都是 UIKit 的事），非主线程就 hop 过去。
void TCPRefreshIconImages(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            TCPRefreshIconImages();
        });
        return;
    }

    Class baseClass = objc_getClass("SBIconImageView");
    if (baseClass == Nil) return;

    // 不重入：一次刷新会碰到几十个视图，谁在途中又要求刷新就往回走（2026-10-30 崩过一次）。
    static BOOL sRefreshing = NO;
    if (sRefreshing) return;
    sRefreshing = YES;

    SEL clearCached = NSSelectorFromString(@"clearCachedImages");
    SEL updateImage = NSSelectorFromString(@"updateImageAnimated:");
    SEL iconGetter = NSSelectorFromString(@"icon");

    // 桌面上「已经建出来」的图标视图全在这棵树里：主屏、Dock、文件夹里的小格、App 库。
    // 上限只是防呆，正常一屏几十个。用指针去重：同一个视图只会被问一次。
    NSMutableArray *views = [NSMutableArray array];
    NSMutableSet<NSValue *> *seenViews = [NSMutableSet set];
    NSMutableArray *stack = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        [stack addObject:window];
    }
    NSUInteger guard = 0;
    while (stack.count > 0 && guard++ < 6000) {
        UIView *view = [stack lastObject];
        [stack removeLastObject];
        if ([view isKindOfClass:baseClass]) {
            NSValue *key = [NSValue valueWithPointer:(__bridge const void *)view];
            if (![seenViews containsObject:key]) {
                [seenViews addObject:key];
                [views addObject:view];
            }
        }
        [stack addObjectsFromArray:view.subviews];
    }

    // 同一个缓存对象会被很多视图共享：按对象去重，别把整张缓存连清几遍。
    NSMutableSet<NSValue *> *purged = [NSMutableSet set];
    NSUInteger pushed = 0;
    for (id view in views) {
        sRefreshViews++;

        // 1) 清共用缓存（每个缓存对象只清一次）
        id cache = nil;
        SEL cacheGetter = NSSelectorFromString(@"iconImageCache");
        if ([view respondsToSelector:cacheGetter]) {
            cache = ((id (*)(id, SEL))objc_msgSend)(view, cacheGetter);
        }
        NSValue *key = cache ? [NSValue valueWithPointer:(__bridge const void *)cache] : nil;
        if (cache == nil || ![purged containsObject:key]) {
            if (key) [purged addObject:key];
            TCPPurgeViewImageCache(view);
        }

        // 2) 视图自己的图袋
        if ([view respondsToSelector:clearCached]) {
            ((void (*)(id, SEL))objc_msgSend)(view, clearCached);
        }

        // 3) 关键的一步：让视图当场重新出图。没有图标对象的（还没绑定模型的）跳过。
        id icon = nil;
        if ([view respondsToSelector:iconGetter]) {
            icon = ((id (*)(id, SEL))objc_msgSend)(view, iconGetter);
        }
        if (icon == nil || ![view respondsToSelector:updateImage]) continue;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view, updateImage, NO);
        pushed++;

        // 4) 顺手把刚重画完的视图体检一遍：屏幕上那几张 UIImageView 手里到底是我们的图还是原图。
        //    原来这个体检函数写好了却没人调，所以诊断里永远没有 pix{}（2026-10-30 15:5x 接上）。
        TCPInspectIconView(view);
    }

    sRefreshPushed += (NSInteger)pushed;
    os_log(TCPLogHandle(), "TCPS_REFRESH views=%lu pushed=%lu model=%ld cache=%ld purge=%{public}@",
           (unsigned long)views.count, (unsigned long)pushed, (long)sRefreshModel, (long)sRefreshCache,
           sRefreshPurgeName ?: @"-");
    sRefreshing = NO;
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
// 自己身上没有就往上找最多 4 层：图是先被创建、后绑模型的，刚建出来的视图自己还没 icon，
// 但它已经在父视图的图标上下文里了 —— 诊断里 noicon 那一摞大半是这么来的（2026-10-30 15:5x）。
static id TCPDisplayViewIcon(id view) {
    static SEL sIcon = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sIcon = NSSelectorFromString(@"icon");
    });
    id current = view;
    for (NSInteger level = 0; level < 4 && current != nil; level++) {
        if ([current respondsToSelector:sIcon]) {
            id icon = ((id (*)(id, SEL))objc_msgSend)(current, sIcon);
            if (icon != nil) return icon;
        }
        if (![current isKindOfClass:[UIView class]]) break;
        current = ((UIView *)current).superview;
    }
    return nil;
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

    // 上面那一站（iconImageWithInfo:）可能已经换过一次：拿到的是我们自己渲染的图就别再套一遍。
    // 二次合成是「图标发糊 / 发白」的一个来源，且纯属白干。
    if ([original isKindOfClass:[UIImage class]] && [store isRenderedImage:(UIImage *)original]) {
        return original;
    }

    // 体检自己问 displayedImage 时不要把自己的询问算进 look/hit/miss（否则数字虚高）。
    const BOOL quiet = sPixelQuietDisplayCounters;

    if (!quiet) sDisplayLook++;

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
        if (!quiet) sDisplayMissNoImage++;
        return original;
    }

    // 复用 iconImageWithInfo: 那一站的同一套合成：主题遮罩在 store 里套（素材存在就总套，
    // 与 cornerRadius 无关），所以这里传 0，不会二次套用。
    TCPIconImageInfo info = { .size = pointSize, .scale = scale, .cornerRadius = 0 };
    UIImage *themed = TCPThemedIconImage(TCPDisplayViewIcon(view), info);
    if (themed == nil) {
        if (!quiet) sDisplayMissNoIcon++;
        return original;
    }
    if (!quiet) sDisplayHit++;

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
