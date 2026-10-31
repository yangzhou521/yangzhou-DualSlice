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
#include <stdlib.h>

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

// 时钟 / 日历是系统动态图标（实时指针 / 当天日期）：主题素材只有静态底图，整幅替换必然丢内容。
// 处理方式见 TCPThemedIconImage 的「交给合成站」那一段 + 下面 TCPCompositeDynamicIcon()。
static BOOL TCPBundleIsDynamic(NSString *bundleID) {
    return [bundleID isEqualToString:@"com.apple.mobiletimer"] ||
           [bundleID isEqualToString:@"com.apple.mobilecal"];
}

UIImage *TCPThemedIconImage(id icon, TCPIconImageInfo info) {
    if (icon == nil || info.size.width <= 0 || info.size.height <= 0) return nil;
    NSString *bundleID = TCPIconBundleIdentifier(icon);
    if (bundleID.length == 0) return nil;

    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;

    // 时钟 / 日历：不在这里整幅替换（0.9.11 实测「时钟空白、日历只有底图没有日期」），
    // 交给站点：先让系统照常出图，再由 TCPCompositeDynamicIcon() 叠「主题底 + 系统动态层」。
    if (TCPBundleIsDynamic(bundleID)) return nil;

    // 遮罩：优先用主题自带的作者遮罩（store 自己会套）；IconCornerMask 只是没有素材时的兜底。
    CGFloat radius = [store cornerMaskEnabled] ? info.cornerRadius : 0;
    UIImage *image = [store iconImageForBundleID:bundleID
                                           size:info.size
                                          scale:info.scale
                                   cornerRadius:radius];
    TCPNoteComposedImage(image, bundleID);   // 自己的产物也量一遍像素，见「图标像素自检」那节
    return image;
}

// 给打点用：站点里记「哪个类、解析出什么 bundle id」，一眼看出是没被问还是没认出 id。
NSString *TCPIconIdentifierOf(id icon) {
    return TCPIconBundleIdentifier(icon);
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

    // 0.9.29：原来固定按 24×24 拉平整张图（CGContextDrawImage 的默认插值会把细节糊掉），
    // 现在按原图**像素**尺寸等比缩到最长边 ≤256 再统计 —— 仍只是一两百次像素循环，开销可忽略，
    // 但「透明」判定不再被 24×24 的糊化误导（一张只剩细描边的图在 24×24 里会被糊成半透明）。
    const size_t cap = 256;
    size_t pw = (size_t)CGImageGetWidth(image.CGImage);
    size_t ph = (size_t)CGImageGetHeight(image.CGImage);
    if (pw == 0 || ph == 0) return stats;
    size_t side = MAX(pw, ph);
    size_t w = pw, h = ph;
    if (side > cap) {
        w = MAX((size_t)1, (size_t)llround((double)pw * (double)cap / (double)side));
        h = MAX((size_t)1, (size_t)llround((double)ph * (double)cap / (double)side));
    }
    size_t bytes = w * h * 4;
    if (bytes > 4u * 1024u * 1024u) return stats;
    unsigned char *buffer = (unsigned char *)calloc(bytes, 1);
    if (buffer == NULL) return stats;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buffer, w, h, 8, w * 4, space,
                                             kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (ctx == NULL) { free(buffer); return stats; }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), image.CGImage);
    CGContextRelease(ctx);

    const size_t total = w * h;
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
    free(buffer);
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
// 0.9.27：同一张 UIImage 只统计一次（指针作 key），避免每次取图都跑 24×24 像素统计（卡顿发热主嫌疑）。
// 指针复用冲突概率极低（UIImage 生命周期短），NSCache 自动淘汰兜底；只影响「是否重复统计」，不影响行为。
static NSCache<NSValue *, NSNumber *> *sComposedMemo = nil;
static dispatch_once_t sComposedMemoOnce;
// 0.9.29：「主屏图标不显示、文件夹里有」的取证。上面那份 gen{last=} 只记**最后一张**，
// 而最后被合成的那张往往恰是正常的（gen 一直是 cov=0.84），于是「某一批 App 合成出来是透明的」
// 这件事从没被记下来。这里把凡是 cov<0.10（几乎全透明 = 用户看到的就是空白）的合成结果
// 按 bundleID 去重记下来，诊断里 pix 段以 blank=[bundleID:cov…] 的形式出现。
static NSMutableArray<NSString *> *sTransparentSamples = nil;
static NSInteger sTransparentCount = 0;
static void TCPNoteComposedImage(UIImage *image, NSString *bundleID) {
    if (image == nil) return;
    dispatch_once(&sComposedMemoOnce, ^{
        sComposedMemo = [[NSCache alloc] init];
        sComposedMemo.countLimit = 1024;
        sTransparentSamples = [NSMutableArray array];
    });
    NSValue *memoKey = [NSValue valueWithPointer:(__bridge const void *)image];
    if ([sComposedMemo objectForKey:memoKey] != nil) return;
    [sComposedMemo setObject:@1 forKey:memoKey];
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
    // 透明样本（只记小样本，限 10 条；同一 App 只记一次，免得一张图在四个站点各记一遍）
    if (stats.coverage < 0.10) {
        sTransparentCount++;
        NSString *sample = [NSString stringWithFormat:@"%@:%.2f", bundleID ?: @"?",
                            (double)stats.coverage];
        NSString *prefix = [NSString stringWithFormat:@"%@:", bundleID ?: @"?"];
        BOOL seen = NO;
        for (NSString *old in sTransparentSamples) {
            if ([old hasPrefix:prefix]) { seen = YES; break; }
        }
        if (!seen && sTransparentSamples.count < 10) [sTransparentSamples addObject:sample];
    }
    sComposedLast = [NSString stringWithFormat:@"%@:%.0fx%.0f@%.0f,cov=%.2f,lum=%.2f",
                     bundleID ?: @"?", image.size.width, image.size.height, image.scale,
                     (double)stats.coverage, (double)stats.luminance];
}


#pragma mark - 时钟 / 日历：主题底 + 系统动态层

// 这两样系统图标自带动态内容（实时指针 / 当天日期），主题素材只有静态底图：
//   · 整幅替换 → 指针、日期全没（0.9.11 用户实测「时钟空白、日历只有底图没有日期」）；
//   · 全交给系统 → 主题素材根本没加载（用户 2026-10-31 04:58 实测）。
// 所以站点先把系统那张图（表盘+指针 / 底图+日期）要回来，再由这里叠一张：
//   时钟：系统表盘垫底（不透明的白/黑脸），主题表盘叠在上面 —— 指针仍由
//         SBHClockApplicationIconImageView 自己实时画在最上层，所以还是活的。
//   日历：主题底图垫底，系统那张图按亮度选混合模式压上去 —— 白底取「正片叠底」
//         （白 = 不改变底图，只留下数字的墨），深底取「滤色」（深色不改变底图，只留浅色字）。
// ── 时钟整套素材（用户 2026-10-31 05:15 给的路径）────────────────────────────
// <主题>.theme/Bundles/com.apple.springboard/ 下有：ClockIconBackgroundSquare（表盘）、
// ClockIconHourHand（时针）、ClockIconMinuteHand（分针）、ClockIconRedDot（针帽）。
// 整个时钟图标都交给这套素材：系统表盘、系统指针一层都不画。
static UIImage *TCPClockAssetImage(TCPThemeStore *store, NSString *name) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in store.themePaths) {
        NSString *p = [[root stringByAppendingPathComponent:@"Bundles/com.apple.springboard"]
                       stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:p]) {
            UIImage *img = [UIImage imageWithContentsOfFile:p];
            if (img) return img;
        }
    }
    return nil;
}

// 素材里真正有内容的范围（左上为原点）；量不到返回 CGRectZero。
// 指针图的画布比指针本身大得多（本机 248x547 里指针只是一根细针），
// 不裁出真实范围就会按整张画布缩放，针会细到看不见。
static CGRect TCPAlphaBounds(CGImageRef cg) {
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (w == 0 || h == 0) return CGRectZero;
    uint8_t *buf = calloc(h * w, 1);
    if (!buf) return CGRectZero;
    CGContextRef c = CGBitmapContextCreate(buf, w, h, 8, w, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!c) { free(buf); return CGRectZero; }
    CGContextDrawImage(c, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(c);

    size_t x0 = w, x1 = 0, y0 = h, y1 = 0;
    for (size_t y = 0; y < h; y++) {
        const uint8_t *row = buf + y * w;
        for (size_t x = 0; x < w; x++) {
            if (row[x] > 8) {
                if (x < x0) x0 = x;
                if (x > x1) x1 = x;
                if (y < y0) y0 = y;
                if (y > y1) y1 = y;
            }
        }
    }
    free(buf);
    if (x0 > x1 || y0 > y1) return CGRectZero;
    // bitmap context 的 y=0 是图像底部，翻成「左上为原点」。
    return CGRectMake((CGFloat)x0, (CGFloat)(h - 1 - y1),
                      (CGFloat)(x1 - x0 + 1), (CGFloat)(y1 - y0 + 1));
}

// 画一根指针：素材真实范围的「底边中点」对准表盘中心，按长度缩放后绕中心转 angle。
static void TCPDrawClockHand(CGContextRef ctx, UIImage *hand, CGPoint center,
                             CGFloat angle, CGFloat length,
                             CGFloat *outBoxW, CGFloat *outBoxH) {
    CGImageRef cg = hand.CGImage;
    if (!cg) return;
    CGRect box = TCPAlphaBounds(cg);
    if (CGRectIsEmpty(box) || box.size.height <= 0) return;
    CGFloat k = length / box.size.height;
    CGFloat w = CGImageGetWidth(cg) * k;
    CGFloat h = CGImageGetHeight(cg) * k;
    CGFloat ox = -(box.origin.x + box.size.width * 0.5) * k;
    CGFloat oy = -(box.origin.y + box.size.height) * k;
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, center.x, center.y);
    CGContextRotateCTM(ctx, angle);
    [hand drawInRect:CGRectMake(ox, oy, w, h)];
    CGContextRestoreGState(ctx);
    if (outBoxW) *outBoxW = box.size.width;
    if (outBoxH) *outBoxH = box.size.height;
}

static NSInteger sDynClock = 0;
static NSInteger sDynCalendar = 0;
static NSInteger sDynFail = 0;
static NSInteger sDynSeen = 0;       // 站点摸到动态图标几次（0 = 根本没走到这条路）
static NSInteger sDynNotImage = 0;   // 系统那张图不是 UIImage（没法叠）
static NSString *sDynLast = nil;

// 站点到底被哪些图标类问过（前几名）：时钟/日历走不到这里时，靠它定位是「没被问」
// 还是「被问了但没认出 bundle id」。0.9.14 诊断里 dyn 全是 0，就是靠这一栏分辨的。
static NSMutableDictionary<NSString *, NSNumber *> *sSiteClasses = nil;

static id TCPSiteClassLock(void) {
    static id lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

void TCPNoteIconSiteClass(NSString *className) {
    if (className.length == 0) return;
    @synchronized (TCPSiteClassLock()) {
        if (sSiteClasses == nil) sSiteClasses = [NSMutableDictionary dictionary];
        NSNumber *count = [sSiteClasses objectForKey:className];
        [sSiteClasses setObject:@(count.integerValue + 1) forKey:className];
    }
}

void TCPNoteDynamicSeen(void) { __sync_fetch_and_add(&sDynSeen, 1); }
void TCPNoteDynamicNotImage(void) { __sync_fetch_and_add(&sDynNotImage, 1); }

static NSString *TCPSiteClassSummary(void) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    @synchronized (TCPSiteClassLock()) {
        NSArray *keys = [sSiteClasses keysSortedByValueUsingComparator:^NSComparisonResult(id a, id b) {
            return [(NSNumber *)b compare:(NSNumber *)a];
        }];
        for (NSString *key in keys) {
            if (parts.count >= 6) break;
            NSNumber *count = [sSiteClasses objectForKey:key];
            [parts addObject:[NSString stringWithFormat:@"%@=%ld", key, (long)count.integerValue]];
        }
    }
    return parts.count > 0 ? [parts componentsJoinedByString:@","] : @"-";
}

// 0.9.31：时钟/日历取证 —— 它们各自的类在**本进程**里到底有没有。
// icli 之类的外部探针看不到 SpringBoard 私有类，只有插件自己能在 SpringBoard 里问。
// （时钟钩子的 look 计数由 clockv{} 单独报，这里只报类存在性，避免跨节引用。）
static NSString *TCPDynamicClassProbe(void) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSArray<NSString *> *names = @[ @"SBHClockApplicationIconImageView",
                                    @"SBHClockApplicationIcon",
                                    @"SBHCalendarApplicationIcon",
                                    @"SBIconImageView" ];
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        [parts addObject:[NSString stringWithFormat:@"%@%@", name, cls ? @"+" : @"-"]];
    }
    return [parts componentsJoinedByString:@","];
}

NSString *TCPDynamicProbeReport(void) {
    return [NSString stringWithFormat:@"dyn{clock=%ld,cal=%ld,fail=%ld,seen=%ld,noimg=%ld,last=%@,cls[%@],c[%@]}",
            (long)sDynClock, (long)sDynCalendar, (long)sDynFail,
            (long)sDynSeen, (long)sDynNotImage, sDynLast ?: @"-", TCPSiteClassSummary(),
            TCPDynamicClassProbe()];
}

BOOL TCPIconNeedsSystemComposite(id icon) {
    if (icon == nil) return NO;
    return TCPBundleIsDynamic(TCPIconBundleIdentifier(icon));
}

UIImage *TCPCompositeDynamicIcon(id icon, TCPIconImageInfo info, UIImage *systemImage) {
    if (icon == nil || info.size.width <= 0 || info.size.height <= 0) return nil;
    NSString *bundleID = TCPIconBundleIdentifier(icon);
    if (!TCPBundleIsDynamic(bundleID)) return nil;

    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;

    CGFloat radius = [store cornerMaskEnabled] ? info.cornerRadius : 0;
    UIImage *themed = [store iconImageForBundleID:bundleID
                                             size:info.size
                                            scale:info.scale
                                     cornerRadius:radius];
    if (themed == nil) {
        __sync_fetch_and_add(&sDynFail, 1);
        sDynLast = [NSString stringWithFormat:@"%@:noasset", bundleID];
        return nil;
    }

    BOOL clock = [bundleID isEqualToString:@"com.apple.mobiletimer"];
    CGFloat scale = info.scale > 0 ? info.scale : 1.0;
    CGRect rect = CGRectMake(0, 0, info.size.width, info.size.height);

    UIGraphicsBeginImageContextWithOptions(info.size, NO, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        __sync_fetch_and_add(&sDynFail, 1);
        sDynLast = [NSString stringWithFormat:@"%@:noctx", bundleID];
        return nil;
    }

    NSString *how = @"-";
    if (clock) {
        // 整个时钟图标交给主题素材（用户 2026-10-31 05:15）：表盘 + 时针 + 分针 + 红点，
        // 系统表盘与系统指针一层都不画。指针角度取当前时间（图标重画时才更新）。
        [themed drawInRect:rect];
        NSDateComponents *c = [[NSCalendar currentCalendar]
                               components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                 fromDate:[NSDate date]];
        CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
        CGFloat minAngle = (CGFloat)c.minute * 6.0 * M_PI / 180.0;
        CGFloat hourAngle = ((CGFloat)(c.hour % 12) + (CGFloat)c.minute / 60.0) * 30.0 * M_PI / 180.0;
        CGFloat hw = 0, hh = 0, mw = 0, mh = 0;
        UIImage *minuteHand = TCPClockAssetImage(store, @"ClockIconMinuteHand@3x.png");
        UIImage *hourHand = TCPClockAssetImage(store, @"ClockIconHourHand@3x.png");
        UIImage *redDot = TCPClockAssetImage(store, @"ClockIconRedDot@3x.png");
        if (minuteHand) TCPDrawClockHand(ctx, minuteHand, center, minAngle, info.size.height * 0.72, &mw, &mh);
        if (hourHand) TCPDrawClockHand(ctx, hourHand, center, hourAngle, info.size.height * 0.50, &hw, &hh);
        if (redDot) {
            CGFloat d = info.size.height * 0.11;
            [redDot drawInRect:CGRectMake(center.x - d * 0.5, center.y - d * 0.5, d, d)];
        }
        how = [NSString stringWithFormat:@"face+h%.0fx%.0f+m%.0fx%.0f", hw, hh, mw, mh];
    } else {
        [themed drawInRect:rect];
        if (systemImage) {
            TCPPixelStats stats = TCPPixelStatsForImage(systemImage);
            BOOL light = !stats.valid || stats.luminance > 0.5;
            CGContextSaveGState(ctx);
            CGContextSetBlendMode(ctx, light ? kCGBlendModeMultiply : kCGBlendModeScreen);
            [systemImage drawInRect:rect];
            CGContextRestoreGState(ctx);
            how = light ? @"mul" : @"scr";
        }
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (result == nil) {
        __sync_fetch_and_add(&sDynFail, 1);
        sDynLast = [NSString stringWithFormat:@"%@:noimage", bundleID];
        return nil;
    }

    if (clock) __sync_fetch_and_add(&sDynClock, 1);
    else __sync_fetch_and_add(&sDynCalendar, 1);
    TCPPixelStats out = TCPPixelStatsForImage(result);
    sDynLast = [NSString stringWithFormat:@"%@:%.0fx%.0f@%.0f,%@,cov=%.2f",
                bundleID, info.size.width, info.size.height, scale, how, (double)out.coverage];
    TCPNoteComposedImage(result, bundleID);
    return result;
}

// —— 时钟图标的视图层（0.9.17）——
//
// 为什么非要在视图上动手：诊断里 dyn{clock=0,seen=16} 说明 SBHClockApplicationIconImageView
// 从来不走 iconImageWithInfo: / generateIconImageWithInfo: 那几站（它自己画表盘和指针），
// 所以「表盘 + 按当前时间画的指针」那个合成站一次都没为时钟跑过 —— 主题素材当然永远不出现。
// 这里挂它的 layoutSubviews：系统排完版之后，把它自己那张「表盘」图换成主题表盘。
// 只换一张图的 image，不删子视图、不加子视图、不动指针层（指针是系统另外画的，继续走时间）。
static void (*sClockLayoutOrig)(id, SEL) = NULL;
static NSInteger sClockVLook = 0, sClockVHit = 0, sClockVMiss = 0;
static NSString *sClockVLast = @"-";

// 在视图里找「表盘」那张图：尺寸（点）与本视图大致相等的 UIImageView。
// 只往下一层（系统把表盘放在自己的 imageView 里），找不到就什么都不做。
// 0.9.31：加了 trace —— noface 时把看到的子视图树一并记进诊断，下次装包就知道表盘到底在哪一层、
// 是不是根本不是 UIImageView（iOS 16.7 很可能是 CALayer / 自绘）。
static UIImageView *TCPClockFindFaceView(UIView *view, NSInteger depth, NSMutableArray<NSString *> *trace) {
    CGSize bounds = view.bounds.size;
    if (bounds.width < 8) return nil;
    for (UIView *sub in view.subviews) {
        if (trace != nil && trace.count < 8) {
            NSString *line = [NSString stringWithFormat:@"%@|%.0fx%.0f",
                              NSStringFromClass([sub class]), sub.bounds.size.width, sub.bounds.size.height];
            if ([sub isKindOfClass:[UIImageView class]]) {
                UIImage *im = ((UIImageView *)sub).image;
                if (im) line = [line stringByAppendingFormat:@"|img%.0fx%.0f", im.size.width, im.size.height];
                else line = [line stringByAppendingString:@"|noimg"];
            }
            [trace addObject:line];
        }
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImage *image = ((UIImageView *)sub).image;
            CGSize size = image.size;
            if (size.width > 1 && fabs(size.width - bounds.width) <= bounds.width * 0.25) {
                return (UIImageView *)sub;
            }
        }
        if (depth > 0) {
            UIImageView *found = TCPClockFindFaceView(sub, depth - 1, trace);
            if (found != nil) return found;
        }
    }
    return nil;
}

static void TCPClockViewApply(UIView *view) {
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active || !store.iconsEnabled) return;
    CGSize size = view.bounds.size;
    if (size.width < 8 || size.height < 8) return;

    NSMutableArray<NSString *> *trace = [NSMutableArray array];
    UIImageView *face = TCPClockFindFaceView(view, 1, trace);
    if (face == nil) {
        __sync_fetch_and_add(&sClockVMiss, 1);
        // 0.9.31：noface 时把子视图树记下来（最多 8 条），一次装包就能定位表盘在哪。
        sClockVLast = [NSString stringWithFormat:@"noface|%.0fx%.0f[%@]",
                       size.width, size.height,
                       trace.count > 0 ? [trace componentsJoinedByString:@";"] : @"nosub"];
        return;
    }
    CGFloat scale = view.window.screen.scale > 0 ? view.window.screen.scale : 2.0;
    UIImage *themed = [store iconImageForBundleID:@"com.apple.mobiletimer"
                                             size:size
                                            scale:scale
                                     cornerRadius:0];
    if (themed == nil) {
        __sync_fetch_and_add(&sClockVMiss, 1);
        sClockVLast = @"noasset";
        return;
    }
    if (face.image == themed) return;
    face.image = themed;
    __sync_fetch_and_add(&sClockVHit, 1);
    sClockVLast = [NSString stringWithFormat:@"%@|%.0fx%.0f@%.0f",
                   NSStringFromClass([face class]), themed.size.width, themed.size.height, scale];
}

static void TCPClockLayoutHook(id self, SEL _cmd) {
    if (sClockLayoutOrig != NULL) sClockLayoutOrig(self, _cmd);
    __sync_fetch_and_add(&sClockVLook, 1);
    @try {
        TCPClockViewApply((UIView *)self);
    } @catch (__unused NSException *e) {
        sClockVLast = @"throw";
    }
}

void TCPInstallClockViewSite(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class cls = NSClassFromString(@"SBHClockApplicationIconImageView");
    if (cls == Nil) return;   // 类还没加载，下一轮 TCPReload 再试
    MSHookMessageEx(cls, @selector(layoutSubviews), (IMP)TCPClockLayoutHook, (IMP *)&sClockLayoutOrig);
    installed = YES;
    os_log(TCPLogHandle(), "TCPS_CLOCK_VIEW hooked");
}

NSString *TCPClockViewProbeReport(void) {
    return [NSString stringWithFormat:@"clockv{look=%ld,hit=%ld,miss=%ld,last=%@}",
            (long)sClockVLook, (long)sClockVHit, (long)sClockVMiss, sClockVLast];
}

// —— 文件夹预览（收起状态）取证 ——
//
// 用户 2026-10-31 17:09：「文件夹里的图标打开时是正常显示，文件夹不点开时是原图标」。
// 打开后看到的是独立的 SBIconImageView（显示层站管得到）；收起时那张预览图是
// SBFolderIconImageView 自己把 mini 图标拼成的一张图，mini 图标是不是独立的
// SBIconImageView 实例决定了显示层站能不能摸到它。
// 这里只读地扫一遍窗口树：数出文件夹视图几个、它们直接子视图的类名/尺寸/手里那张图归谁。
// 不碰任何视图状态，一次装包就能判定该挂哪一层。
// 1.0.4：递归深入两层 + 记录 SBFolderIconImageView 自己声明的方法名（定位该挂哪一站）。
static NSInteger sFolderViewCount = 0;
static NSMutableArray<NSString *> *sFolderViewSamples = nil;
static NSString *sFolderMethods = @"-";

// 递归扫一个文件夹视图内部，最多深入两层。
static void TCPProbeFolderViewRecursive(UIView *view, NSInteger depth,
                                         NSMutableArray<NSString *> *outLines,
                                         TCPThemeStore *store) {
    if (depth < 0 || outLines.count >= 12) return;
    for (UIView *sub in view.subviews) {
        NSString *line = [NSString stringWithFormat:@"%@|%.0fx%.0f",
                          NSStringFromClass([sub class]),
                          sub.bounds.size.width, sub.bounds.size.height];
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImage *image = ((UIImageView *)sub).image;
            line = [line stringByAppendingFormat:@"|%@",
                    image == nil ? @"nil"
                                 : ([store isRenderedImage:image] ? @"ours" : @"stock")];
        }
        [outLines addObject:line];
        if (depth > 0) TCPProbeFolderViewRecursive(sub, depth - 1, outLines, store);
    }
}

// 枚举一个类自己声明的方法名（只取含 image/background/folder / icon 字样的），用于定位挂点。
static NSString *TCPFolderIconImageViewMethods(void) {
    Class cls = NSClassFromString(@"SBFolderIconImageView");
    if (cls == Nil) return @"nocls";
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (methods == NULL || count == 0) return @"nomethods";
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        if ([name containsString:@"image"] || [name containsString:@"background"] ||
            [name containsString:@"folder"] || [name containsString:@"icon"]) {
            [names addObject:name];
        }
    }
    free(methods);
    return names.count > 0 ? [names componentsJoinedByString:@","] : @"nohit";
}

void TCPProbeFolderViews(void) {
    if (![NSThread isMainThread]) return;
    Class folderClass = NSClassFromString(@"SBFolderIconImageView");
    if (folderClass == Nil) return;
    if (sFolderViewSamples == nil) sFolderViewSamples = [NSMutableArray array];
    [sFolderViewSamples removeAllObjects];
    sFolderViewCount = 0;
    sFolderMethods = TCPFolderIconImageViewMethods();

    TCPThemeStore *store = [TCPThemeStore shared];
    NSMutableArray *stack = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows) [stack addObject:window];
    NSUInteger guard = 0;
    while (stack.count > 0 && guard++ < 6000) {
        UIView *view = [stack lastObject];
        [stack removeLastObject];
        if ([view isKindOfClass:folderClass]) {
            sFolderViewCount++;
            if (sFolderViewSamples.count < 4) {
                NSMutableArray<NSString *> *kids = [NSMutableArray array];
                // 1.0.4：直接子视图（一层）+ 递归深入两层（看 mini 图标层）。
                for (UIView *sub in view.subviews) {
                    NSString *line = [NSString stringWithFormat:@"%@|%.0fx%.0f",
                                      NSStringFromClass([sub class]),
                                      sub.bounds.size.width, sub.bounds.size.height];
                    if ([sub isKindOfClass:[UIImageView class]]) {
                        UIImage *image = ((UIImageView *)sub).image;
                        line = [line stringByAppendingFormat:@"|%@",
                                image == nil ? @"nil"
                                             : ([store isRenderedImage:image] ? @"ours" : @"stock")];
                    }
                    [kids addObject:line];
                    // 再往下两层
                    TCPProbeFolderViewRecursive(sub, 1, kids, store);
                }
                [sFolderViewSamples addObject:[NSString stringWithFormat:@"%.0fx%.0f[%@]",
                                               view.bounds.size.width, view.bounds.size.height,
                                               [kids componentsJoinedByString:@";"]]];
            }
        }
        [stack addObjectsFromArray:view.subviews];
    }
}

NSString *TCPFolderProbeReport(void) {
    return [NSString stringWithFormat:@"folderv{n=%ld,s=[%@],m=%@}", (long)sFolderViewCount,
            sFolderViewSamples.count > 0
                ? [sFolderViewSamples componentsJoinedByString:@";"] : @"-",
            sFolderMethods];
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
// 0.9.5：「一个图标视图里到底叠了哪几层图、每层归谁」逐层记下来（最多 6 条）。
// 光数张数说明不了问题 —— 得知道那张 stock 图是叠在我们的图下面（重影），还是另一处子视图。
static NSMutableArray<NSString *> *sPixelLayerSamples = nil;
static NSInteger sPixelStackDup = 0;   // 同一视图里「尺寸相同」的图叠在一起的对数

// 一个视图里挂了几张 UIImageView（递归到底）。同一个位置叠两张，屏幕上就是「两个图层」。
// 0.9.5 修：原来写成 `if (sub.subviews.count > 0 && count > 0)` —— 本级一张都没数到时
// 就不往下走了，嵌套两层以上的图（SBIconImageView 的真实形状）永远数成 0：
// 诊断里 maxImgViews 一直是 0，「叠了几层」这条线索被彻底废掉。
static NSInteger TCPCountImageViews(UIView *view) {
    NSInteger count = 0;
    for (UIView *sub in view.subviews) {
        NSString *name = NSStringFromClass([sub class]);
        if ([name containsString:@"ImageView"] && sub.bounds.size.width > 1) count++;
        if (sub.subviews.count > 0) count += TCPCountImageViews(sub);
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
    NSMutableSet<NSString *> *stackedSizes = [NSMutableSet set];
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
                BOOL ours = [store isRenderedImage:image];
                if (ours) sPixelScreenThemed++;
                else sPixelScreenStock++;

                // 0.9.5：逐层记样本。优先记「不是我们的」那一层 —— 那才是我们没盖住的图。
                if (sPixelLayerSamples == nil) sPixelLayerSamples = [NSMutableArray array];
                if (sPixelLayerSamples.count < 6 && !ours) {
                    [sPixelLayerSamples addObject:
                        [NSString stringWithFormat:@"%@|%@|%.0fx%.0f|%.0f,%.0f",
                         (bundleID.length > 0 ? bundleID : @"?"),
                         NSStringFromClass([sub class]),
                         image.size.width, image.size.height,
                         sub.frame.origin.x, sub.frame.origin.y]];
                }
                // 同一视图里尺寸一样的图叠了两张 = 屏幕上就是一个带重影的图标。
                // 同一个尺寸第二次出现就记一对（不区分归属，归属已经在上面记过了）。
                {
                    NSString *sizeKey = [NSString stringWithFormat:@"%.0fx%.0f",
                                         image.size.width, image.size.height];
                    if (![stackedSizes containsObject:sizeKey]) {
                        [stackedSizes addObject:sizeKey];
                    } else {
                        sPixelStackDup++;
                    }
                }

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

// 屏幕归属普查（0.9.8）：主动把当前屏幕上真正画着的图过一遍，数出
//   ours  = 屏幕上挂着的图是我们合成的（主题真的上屏了）
//   stock = 屏幕上挂着的图不是我们的（显示层白干，用户看到的是原图）
//   layer = layer.contents 里放的是 CGImage —— 显示层走的就是这条路，
//           所以必须单独看它，只看 UIImageView.image 会漏掉一半。
// 之前 pix{} 只在「刷新」路径上跑，而启动时不刷（0.6.0 崩过），于是诊断里 pix{n=0}，
// 看上去像「体检根本没执行」。现在普查独立于刷新，主线程定时跑，结果写进诊断。
static NSInteger sCensusRan = 0;          // 普查跑过几次
static NSInteger sCensusViews = 0;        // 数过的图标视图
static NSInteger sCensusOurs = 0;         // 屏幕上是我们合成的图
static NSInteger sCensusStock = 0;        // 屏幕上不是我们的图
static NSInteger sCensusLayerOurs = 0;    // layer.contents 是我们合成的 CGImage
static NSInteger sCensusLayerStock = 0;   // layer.contents 是别的 CGImage
static NSInteger sCensusLayerTotal = 0;
static NSInteger sCensusDisplayedOurs = 0; // displayedImage 交出来的是我们的
static NSInteger sCensusDisplayedTotal = 0;
static NSMutableArray<NSString *> *sCensusSamples = nil;
static NSInteger sCensusIconViews = 0;      // 图标视图数（私有类 SBIconImageView 等）
static NSInteger sCensusIconOurs = 0;       // 其中交出的是我们的图
static NSInteger sCensusIconStock = 0;
static NSMutableArray<NSString *> *sCensusIconSamples = nil;
static NSMutableArray<NSString *> *sCensusBadgeTree = nil;
static BOOL sCensusRunning = NO;

// 定义在文件后面的显示层小工具，这里先声明。
static BOOL TCPDisplayIsCGImage(id object);

static void TCPCensusClassifyUIImage(UIImage *image) {
    if (image == nil) return;
    if ([[TCPThemeStore shared] isRenderedImage:image]) {
        sCensusOurs++;
    } else {
        sCensusStock++;
    }
}

// 普查一个视图（一个图标视图）。只读，不触发任何重画。
static void TCPCensusInspectView(UIView *view, NSUInteger depth) {
    if (view == nil || depth > 8) return;
    if (sCensusViews > 4000) return;

    NSString *className = NSStringFromClass([view class]);

    // ① UIImageView.image —— 图层视图
    if ([view isKindOfClass:[UIImageView class]]) {
        sCensusViews++;
        UIImage *image = ((UIImageView *)view).image;
        TCPCensusClassifyUIImage(image);
        if (image && sCensusSamples.count < 8) {
            BOOL ours = [[TCPThemeStore shared] isRenderedImage:image];
            if (sCensusSamples == nil) sCensusSamples = [NSMutableArray array];
            [sCensusSamples addObject:
                [NSString stringWithFormat:@"%@|%@|%.0fx%.0f|%@",
                 className, ours ? @"ours" : @"stock",
                 image.size.width, image.size.height,
                 TCPDisplayViewIcon(view) ? @"icon" : @"-"]];
        }
    }

    // ①b 真正的图标视图不是 UIImageView（是私有类 SBIconImageView），
    //     它用 displayedImage 交出画进屏幕的那张图 —— 计数在下面那段专门的遍历里做，
    //     这里只做识别，不重复计数。

    // ② layer.contents —— 显示层真正画进屏幕的那张（可能是 CGImage，也可能是 UIImage）
    id contents = view.layer.contents;
    if (contents != nil) {
        sCensusLayerTotal++;
        if (TCPDisplayIsCGImage(contents)) {
            if ([[TCPThemeStore shared] isRenderedCGImagePointer:(__bridge const void *)contents]) {
                sCensusLayerOurs++;
            } else {
                sCensusLayerStock++;
            }
        } else if ([contents isKindOfClass:[UIImage class]]) {
            TCPCensusClassifyUIImage((UIImage *)contents);
        }
    }

    for (UIView *sub in view.subviews) {
        TCPCensusInspectView(sub, depth + 1);
    }
}

void TCPRunScreenCensus(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ TCPRunScreenCensus(); });
        return;
    }
    if (sCensusRunning) return;
    sCensusRunning = YES;

    sCensusViews = 0; sCensusOurs = 0; sCensusStock = 0;
    // 0.9.29：像素自检也挂在这轮普查里跑，计数器每轮归零（否则会一直累加到看不出这一轮的实况）。
    sPixelViews = 0; sPixelThemed = 0; sPixelNil = 0; sPixelClear = 0; sPixelFlat = 0;
    sPixelScreenTotal = 0; sPixelScreenThemed = 0; sPixelScreenStock = 0;
    sPixelMinOpaque = 1.0; sPixelMaxImageViews = 0; sPixelStackDup = 0;
    sPixelBlankSamples = [NSMutableArray array];
    sPixelLayerSamples = [NSMutableArray array];
    sCensusLayerOurs = 0; sCensusLayerStock = 0; sCensusLayerTotal = 0;
    sCensusDisplayedOurs = 0; sCensusDisplayedTotal = 0;
    sCensusSamples = [NSMutableArray array];
    sCensusIconViews = 0; sCensusIconOurs = 0; sCensusIconStock = 0;
    sCensusIconSamples = [NSMutableArray array];
    sCensusBadgeTree = [NSMutableArray array];

    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    // 用 windowScene 拿窗口（UIApplication.windows 在 iOS 15+ 已废弃）。
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            [windows addObject:window];
        }
    }
    if (windows.count == 0) {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            [windows addObject:window];
        }
    }
    for (UIWindow *window in windows) {
        for (UIView *sub in window.subviews) {
            TCPCensusInspectView(sub, 0);
        }
    }

    // displayedImage：视图交出去的那张图是谁的（静默打点，别把自己的询问算进 look/hit）
    SEL displayed = NSSelectorFromString(@"displayedImage");
    // 图标视图不止 SBIconImageView：文件夹是 SBFolderIconImageView，名字里都带 IconImageView。
    NSArray<Class> *iconViewClasses = nil;
    NSMutableArray *wanted = [NSMutableArray array];
    unsigned int count = 0;
    Class *all = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromClass(all[i]);
        if ([name hasPrefix:@"SB"] && [name hasSuffix:@"IconImageView"]) {
            [wanted addObject:all[i]];
        }
    }
    free(all);
    iconViewClasses = wanted;

    if (iconViewClasses.count > 0) {
        for (UIWindow *window in windows) {
            NSMutableArray *stack = [NSMutableArray arrayWithArray:window.subviews];
            NSUInteger guard = 0;
            while (stack.count > 0 && guard++ < 3000) {
                UIView *view = stack.lastObject;
                [stack removeLastObject];
                BOOL isIconView = NO;
                for (Class cls in iconViewClasses) {
                    if ([view isKindOfClass:cls]) { isIconView = YES; break; }
                }
                if (isIconView && [view respondsToSelector:displayed]) {
                    sPixelQuietDisplayCounters = YES;
                    id value = ((id (*)(id, SEL))objc_msgSend)(view, displayed);
                    sPixelQuietDisplayCounters = NO;
                    BOOL ours = NO;   // 0.9.29：提到这一层，像素自检（在原 if 之外）也要用它
                    if ([value isKindOfClass:[UIImage class]]) {
                        sCensusDisplayedTotal++;
                        sCensusIconViews++;
                        ours = [[TCPThemeStore shared] isRenderedImage:(UIImage *)value];
                        if (ours) {
                            sCensusDisplayedOurs++;
                            sCensusIconOurs++;
                        } else {
                            sCensusIconStock++;
                        }
                        if (sCensusIconSamples.count < 12) {
                            [sCensusIconSamples addObject:
                                [NSString stringWithFormat:@"%@|%@|%.0fx%.0f",
                                 NSStringFromClass([view class]), ours ? @"ours" : @"stock",
                                 ((UIImage *)value).size.width, ((UIImage *)value).size.height]];
                        }
                    }
                    // 0.9.29：普查时顺手做一次像素自检（每轮视图只做一次）。
                    // 以前 TCPInspectIconView 只在「改设置刷新」那条路上调，注销后启动一次都不跑，
                    // 于是诊断里 pix{n=0} —— 「图标到底是不是透明白」这件事从来没被量过。
                    if (ours) TCPInspectIconView(view);
                    // 图标视图自己 layer.contents 里画进屏幕的那张图是谁的
                    id contents = view.layer.contents;
                    if (contents != nil) {
                        sCensusLayerTotal++;
                        if (TCPDisplayIsCGImage(contents)) {
                            if ([[TCPThemeStore shared] isRenderedCGImagePointer:(__bridge const void *)contents]) {
                                sCensusLayerOurs++;
                            } else {
                                sCensusLayerStock++;
                            }
                        } else if ([contents isKindOfClass:[UIImage class]]) {
                            TCPCensusClassifyUIImage((UIImage *)contents);
                        }
                    }
                    // 真正的绘制往往在内部子层上：view.layer.contents 是空的，
                    // 图片挂在某个 sublayer 的 contents 里 —— 逐个子层看。
                    for (CALayer *sub in view.layer.sublayers) {
                        id subContents = sub.contents;
                        if (subContents == nil) continue;
                        sCensusLayerTotal++;
                        if (TCPDisplayIsCGImage(subContents)) {
                            if ([[TCPThemeStore shared] isRenderedCGImagePointer:(__bridge const void *)subContents]) {
                                sCensusLayerOurs++;
                            } else {
                                sCensusLayerStock++;
                            }
                        } else if ([subContents isKindOfClass:[UIImage class]]) {
                            TCPCensusClassifyUIImage((UIImage *)subContents);
                        }
                    }
                }
                [stack addObjectsFromArray:view.subviews];
            }
        }
    }

    // 角标子树（0.9.17）：用户报「角标二层」，光看 sys{hid=} 分不清屏幕上到底还留着哪一层。
    // 这里把每个角标视图的子视图摊开：类名、尺寸、有没有被藏、图多大、那张图是不是我们的。
    NSMutableArray<NSString *> *badgeTree = [NSMutableArray array];
    for (UIWindow *window in windows) {
        NSMutableArray *stack = [NSMutableArray arrayWithArray:window.subviews];
        NSUInteger guard = 0;
        while (stack.count > 0 && guard++ < 3000 && badgeTree.count < 6) {
            UIView *view = stack.lastObject;
            [stack removeLastObject];
            if ([NSStringFromClass([view class]) containsString:@"Badge"]) {
                NSMutableArray<NSString *> *kids = [NSMutableArray array];
                for (UIView *sub in view.subviews) {
                    if (kids.count >= 8) break;
                    NSString *k = [NSString stringWithFormat:@"%@|%.0fx%.0f%@",
                                   NSStringFromClass([sub class]),
                                   sub.bounds.size.width, sub.bounds.size.height,
                                   sub.hidden ? @"|hid" : @""];
                    if ([sub isKindOfClass:[UIImageView class]] && ((UIImageView *)sub).image != nil) {
                        UIImage *img = ((UIImageView *)sub).image;
                        k = [k stringByAppendingFormat:@"|img%.0fx%.0f%@",
                             img.size.width, img.size.height,
                             TCPBadgeIsOurImage(img) ? @"*" : @""];
                    }
                    [kids addObject:k];
                }
                [badgeTree addObject:[NSString stringWithFormat:@"%@|%.0fx%.0f|%lu:[%@]",
                                      NSStringFromClass([view class]),
                                      view.bounds.size.width, view.bounds.size.height,
                                      (unsigned long)view.subviews.count,
                                      kids.count > 0 ? [kids componentsJoinedByString:@","] : @"-"]];
            }
            [stack addObjectsFromArray:view.subviews];
        }
    }
    [sCensusBadgeTree removeAllObjects];
    [sCensusBadgeTree addObjectsFromArray:badgeTree];

    sCensusRan++;
    sCensusRunning = NO;
}

NSString *TCPScreenCensusReport(void) {
    return [NSString stringWithFormat:
            @"census{ran=%ld,views=%ld,ours=%ld,stock=%ld,layer{total=%ld,ours=%ld,stock=%ld},disp{total=%ld,ours=%ld},icon{views=%ld,ours=%ld,stock=%ld},is=[%@],s=[%@],badge=[%@]}",
            (long)sCensusRan, (long)sCensusViews, (long)sCensusOurs, (long)sCensusStock,
            (long)sCensusLayerTotal, (long)sCensusLayerOurs, (long)sCensusLayerStock,
            (long)sCensusDisplayedTotal, (long)sCensusDisplayedOurs,
            (long)sCensusIconViews, (long)sCensusIconOurs, (long)sCensusIconStock,
            sCensusIconSamples.count > 0 ? [sCensusIconSamples componentsJoinedByString:@";"] : @"-",
            sCensusSamples.count > 0 ? [sCensusSamples componentsJoinedByString:@";"] : @"-",
            sCensusBadgeTree.count > 0 ? [sCensusBadgeTree componentsJoinedByString:@";"] : @"-"];
}

NSString *TCPIconPixelProbeReport(void) {
    return [NSString stringWithFormat:
            @"gen{n=%ld,clear=%ld,minCov=%.2f,lum=%.2f,last=%@};"
            @"pix{n=%ld,themed=%ld,screen{total=%ld,ours=%ld,stock=%ld},clear=%ld,flat=%ld,nil=%ld,minOpaque=%.2f,maxImgViews=%ld,dup=%ld,blank=[%@],lay=[%@]};"
            @"tclear{n=%ld,blank=[%@]}",
            (long)sComposedCount, (long)sComposedClear, (double)sComposedMinCoverage,
            (double)sComposedLuminance, sComposedLast ?: @"-",
            (long)sPixelViews, (long)sPixelThemed, (long)sPixelScreenTotal,
            (long)sPixelScreenThemed, (long)sPixelScreenStock, (long)sPixelClear,
            (long)sPixelFlat, (long)sPixelNil, (double)sPixelMinOpaque,
            (long)sPixelMaxImageViews,
            (long)sPixelStackDup,
            sPixelBlankSamples.count > 0 ? [sPixelBlankSamples componentsJoinedByString:@","] : @"-",
            sPixelLayerSamples.count > 0 ? [sPixelLayerSamples componentsJoinedByString:@";"] : @"-",
            (long)sTransparentCount,
            sTransparentSamples.count > 0 ? [sTransparentSamples componentsJoinedByString:@","] : @"-"];
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
