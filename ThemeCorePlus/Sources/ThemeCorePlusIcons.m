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

// 1.0.42 的 Bundles 资源替换站：装配函数 `TCPInstallBundleAssetSites` 定义在本文件末尾，
// 而调用它的装配入口在文件顶部 —— 少了这条前向声明，clang 直接报
// 「call to undeclared function 'TCPInstallBundleAssetSites'」（2026-11-03 CI run 41614741297 失败原因）。
// 同一个函数在 ThemeCorePlusPrivate.h 里也有一份声明，这里补一份是为了让本文件自洽。
void TCPInstallBundleAssetSites(void);

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
    // 1.0.31：改成**固定类名清单直取**（原来按 8 个宽前缀全进程扫类表，见
    // TCPInstallSitesFromClassList 上方的说明）。清单 = 本机诊断 sites= 里实际命中的类
    // + 原前缀覆盖到、但这次可能还没 dlopen 的同族类（取不到就跳过，下一轮再来）。
    NSArray<NSString *> *iconClasses = @[ @"SBIcon",
                                          @"SBLeafIcon",
                                          @"SBApplicationIcon",
                                          @"SBHApplicationIcon",
                                          @"SBHCalendarApplicationIcon",
                                          @"SBCalendarIconImageProvider",
                                          @"SBCalendarApplicationIcon",
                                          @"SBHBookmarkIcon",
                                          @"SBHBookmark",
                                          @"SBPlaceholderIcon",
                                          @"SBInCallPresentationScreenSharingIcon",
                                          @"SBFolderIcon",
                                          @"SBSearchIcon",
                                          @"SBWidgetIcon",
                                          @"SBNewsstandIcon" ];
    // generateIconImageWithInfo: 是真正的「生图」入口：本机运行期按 IMP 归属查出来的结果是
    // MarkThemeRuntime.dylib 挂在 SBApplicationIcon:generateIconImageWithInfo:，ThemeCore 0.5.1
    // 的二进制里也有同名方法；而我们原来只挂 getter（iconImageWithInfo:），在这台 16.7.16 上
    // 一次都没被问过（诊断 look=0）。所以把生成站一起挂上：谁生成图标图，谁就被换成主题图。
    NSArray<NSString *> *selectors = @[ @"iconImageWithInfo:",
                                        @"unmaskedIconImageWithInfo:",
                                        @"iconImageWithImageInfo:",
                                        @"generateIconImageWithInfo:" ];
    NSUInteger installed = TCPInstallSitesFromClassList(iconClasses, selectors,
                                                        TCPSiteKindIconImageInfo, NO);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_ICON_SITES +%lu", (unsigned long)installed);
    }

    // 1.0.23：图标图**缓存层**（MarkTheme16 秒加载的关键，二进制符号取证）。
    // 改为 Forced 挂载（class_getInstanceMethod 含继承），挂上后视图第一次从缓存取图就是主题图。
    NSUInteger cacheSites = TCPInstallIconCacheLayerSites();
    if (cacheSites > 0) {
        os_log(TCPLogHandle(), "TCPS_ICON_CACHE_SITES +%lu", (unsigned long)cacheSites);
    }
    // 1.0.30 的「按选择器名全进程扫一遍」已撤：1.0.30 实测全进程没有任何类声明这三个选择器
    // （诊断里三个 *IconImageCache 全是 nomethod、byname 无输出），空跑一轮白吃启动预算。

    // 1.0.42：Bundles 资源替换（用户点名「设置里的系统小图标」）。这一站在设置进程里才是主角，
    // 图标站对设置没意义，所以它必须单独装，不能藏在图标站的判断里。
    TCPInstallBundleAssetSites();
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
    TCPThemeStore *store = [TCPThemeStore shared];
    return [NSString stringWithFormat:@"ref{views=%ld,pushed=%ld,model=%ld,cache=%ld,miss=%ld,purge=%@%lu}",
            (long)sRefreshViews, (long)sRefreshPushed, (long)sRefreshModel, (long)sRefreshCache,
            (long)sRefreshCacheMiss, store.purgeName ?: @"-",
            (unsigned long)store.purgeCount];
}

// SBIconImageView 自己声明的 -iconImageInfo / -setIconImageInfo: 用的就是这个结构。
// 与 ThemeCorePlusHooks.h 的 TCPIconImageInfo 完全同构（4 个 double，按 HFA 走 d0–d3），
// 这里不再另抄一份字段：ABI 关键结构体只能有一个定义，抄两份迟早改一边漏一边。
typedef TCPIconImageInfo TCPIconImageInfoShort;

// 图标图缓存对象上的清空方法：不同版本名字不同，按顺序试第一个存在的。
// 都是无参方法 —— 带参数的那种（purgeCachedImagesForIcons:）要传图标集合，不在刷新路径上冒险。
// 1.0.38：视图自己身上拿不到缓存（诊断 ref=...cache=0,miss=2 = 16 个视图的 -iconImageCache
// 全是 nil），真正的缓存挂在 SBIconController→iconManager→iconImageCache 上（探针坐实：
// 控制器声明零参 -iconManager，管理器声明零参 -iconImageCache / -folderIconImageCache）。
// 所以先照旧问视图，拿不到就整条链重取一次。这是「秒加载」的关键那一步：
// 系统把原图缓存在这个对象里，不清掉，视图重画时还会把原图贴回来。
// 1.0.38 修正：函数体已搬到 ThemeCorePlusStore.m（2026-11-02）。原因：本文件只进插件本体，
// 而设置面板的源码清单也含 Store.m —— 定义只留在本文件里，面板链接期就报
// 「Undefined symbols _TCPLiveIconImageCache」（云编译 run 41405575029）。
// 本文件照 ThemeCorePlusHooks.h 的 extern 声明调用它即可（同一个 dylib 内解析）。

// 文件夹的图标缓存（同一条链，只是换成 folderIconImageCache）：文件夹收起状态的 mini 拼图
// 存在这个对象里，主题换了它不会自己重算，要靠它重算一次。
id TCPLiveFolderImageCache(void) {
    // 1.0.41（修 1.0.39「注销后进安全模式」）：构造函数阶段一律不走这条路。
    // 崩溃报告 SpringBoard-2026-11-03-040505.ips（注销后首次加载新 dylib）：
    //   TCPInitialize（dyld 构造函数）→ TCPReload(NO) → TCPRefreshIconImages
    //   → TCPFolderNotifyRecalc → TCPLiveFolderImageCache
    //   → +[SBIconController sharedInstance] → -[SBUIController init]
    //   → +[UIScreen mainScreen] → NSAssertionHandler → SIGABRT。
    // 构造函数跑在 main() 之前，UIApplication / UIScreen 都还不存在，
    // +[UIScreen mainScreen] 里那句断言必命中（与 1.0.35、1.0.36、0.9.21 同一个病根）。
    // 1.0.36 只给 TCPRelayoutIcons 上了闸门，1.0.38 新写的这条
    // 「控制器→管理器→folderIconImageCache」链漏在外面，现在这一层也上闸：
    // 闸门没开返回 nil，调用方照旧记 nocache/notready，等 +2 秒开闸后的刷新拍再真拿。
    if (!TCPStoreImageWorkReady()) return nil;
    static SEL managerGetter = NULL, folderCacheGetter = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        managerGetter = NSSelectorFromString(@"iconManager");
        folderCacheGetter = NSSelectorFromString(@"folderIconImageCache");
    });
    Class controllerClass = objc_getClass("SBIconController");
    if (controllerClass == Nil) return nil;
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    if (![controllerClass respondsToSelector:sharedSel]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)((id)controllerClass, sharedSel);
    if (controller == nil || ![controller respondsToSelector:managerGetter]) return nil;
    id manager = ((id (*)(id, SEL))objc_msgSend)(controller, managerGetter);
    if (manager == nil || ![manager respondsToSelector:folderCacheGetter]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(manager, folderCacheGetter);
}

static void TCPPurgeViewImageCache(id view) {
    static SEL sCacheGetter = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sCacheGetter = NSSelectorFromString(@"iconImageCache");
    });

    id cache = nil;
    if (view != nil && [view respondsToSelector:sCacheGetter]) {
        cache = ((id (*)(id, SEL))objc_msgSend)(view, sCacheGetter);
    }
    if (cache == nil) cache = TCPLiveIconImageCache();   // 1.0.38：改从控制器→管理器那条链取
    if (cache == nil) {
        sRefreshCacheMiss++;
        return;
    }
    // 1.0.44：同 Store.m 的 purgeSystemIconCache —— 真正的零参方法叫 purgeAllCachedImages
    // （本机反射探针 TCPCacheProbe.txt 坐实），旧名字一个都不存在，所以这条一直在空转。
    for (NSString *name in @[ @"purgeAllCachedImages",
                              @"purgeCache", @"purgeAllCaches", @"purgeCaches",
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
// 整个时钟图标都交给这套素材：
// 1.0.11 支持按 scale 优先查找（@2x 优先，退回 @3x，退回无后缀），不再硬编码 @3x
static UIImage *TCPClockAssetImageNamed(TCPThemeStore *store, NSString *baseName, CGFloat scale) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSInteger wantScale = (NSInteger)round(scale > 0 ? scale : 2.0);
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (wantScale >= 2) [candidates addObject:[NSString stringWithFormat:@"%@@%ldx.png", baseName, (long)wantScale]];
    if (wantScale != 3) [candidates addObject:[NSString stringWithFormat:@"%@@3x.png", baseName]];
    if (wantScale != 2) [candidates addObject:[NSString stringWithFormat:@"%@@2x.png", baseName]];
    [candidates addObject:[NSString stringWithFormat:@"%@.png", baseName]];

    for (NSString *root in store.themePaths) {
        NSString *dir = [root stringByAppendingPathComponent:@"Bundles/com.apple.springboard"];
        for (NSString *cand in candidates) {
            NSString *p = [dir stringByAppendingPathComponent:cand];
            if ([fm fileExistsAtPath:p]) {
                UIImage *img = [UIImage imageWithContentsOfFile:p];
                if (img) return img;
            }
        }
    }
    return nil;
}

static UIImage *TCPClockAssetImage(TCPThemeStore *store, NSString *name) {
    return TCPClockAssetImageNamed(store, [name stringByDeletingPathExtension], 2.0);
}

// 画一根指针（定义在下面）：素材真实范围的「底边中点」对准表盘中心，按长度缩放后绕中心转 angle。
static void TCPDrawClockHand(CGContextRef ctx, UIImage *hand, CGPoint center,
                             CGFloat angle, CGFloat length,
                             CGFloat *outBoxW, CGFloat *outBoxH);

// 1.0.7：把「主题表盘 + 按当前时间画的指针 + 红点」合成成一张整图。
// 为什么单独合成（而不是拿 Store 的静态表盘）：Store 里 com.apple.mobiletimer 只登记了
// ClockIconBackgroundSquare（表盘），指针素材（ClockIconHourHand / ClockIconMinuteHand /
// ClockIconRedDot）不在图标表里 —— 直接取图只能拿到一块表盘，没有指针。
// 而 iOS 16.7 的 SBHClockApplicationIconImageView 从不重新 layout（诊断 clockv{look=0}），
// 系统那层指针我们接管不了，所以指针只能自己画；自己画就得自己按时间更新 ——
// 这张图每 30 秒重画一次（TCPClockTick），指针就是活的。
static UIImage *TCPClockComposeImage(TCPThemeStore *store, CGFloat side, CGFloat scale) {
    if (store == nil || side <= 0) return nil;
    if (scale <= 0) scale = [UIScreen mainScreen].scale;
    if (scale <= 0) scale = 3.0;

    UIImage *face = TCPClockAssetImage(store, @"ClockIconBackgroundSquare@3x.png");
    if (face == nil) face = TCPClockAssetImage(store, @"ClockIconBackgroundSquare.png");
    if (face == nil) return nil;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx == NULL) { UIGraphicsEndImageContext(); return nil; }

    CGRect rect = CGRectMake(0, 0, side, side);
    [face drawInRect:rect];

    UIImage *minuteHand = TCPClockAssetImage(store, @"ClockIconMinuteHand@3x.png");
    UIImage *hourHand = TCPClockAssetImage(store, @"ClockIconHourHand@3x.png");
    UIImage *redDot = TCPClockAssetImage(store, @"ClockIconRedDot@3x.png");
    if (minuteHand || hourHand || redDot) {
        NSDateComponents *c = [[NSCalendar currentCalendar]
                               components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                 fromDate:[NSDate date]];
        CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
        CGFloat minAngle = (CGFloat)c.minute * 6.0 * M_PI / 180.0;
        CGFloat hourAngle = ((CGFloat)(c.hour % 12) + (CGFloat)c.minute / 60.0) * 30.0 * M_PI / 180.0;
        if (minuteHand) TCPDrawClockHand(ctx, minuteHand, center, minAngle, side * 0.72, NULL, NULL);
        if (hourHand) TCPDrawClockHand(ctx, hourHand, center, hourAngle, side * 0.50, NULL, NULL);
        if (redDot) {
            CGFloat d = side * 0.11;
            [redDot drawInRect:CGRectMake(center.x - d * 0.5, center.y - d * 0.5, d, d)];
        }
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

// 素材实色范围（左上为原点）；量不到返回 CGRectZero。
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
static NSInteger sDynFailNoAsset = 0;   // 1.0.19：细分失败来源（noasset）
static NSInteger sDynFailNoCtx = 0;     // 1.0.19：细分失败来源（noctx）
static NSInteger sDynFailNoImage = 0;   // 1.0.19：细分失败来源（noimage）
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
    return [NSString stringWithFormat:@"dyn{clock=%ld,cal=%ld,fail=%ld(na=%ld,nc=%ld,ni=%ld),seen=%ld,noimg=%ld,last=%@,cls[%@],c[%@]}",
            (long)sDynClock, (long)sDynCalendar, (long)sDynFail,
            (long)sDynFailNoAsset, (long)sDynFailNoCtx, (long)sDynFailNoImage,
            (long)sDynSeen, (long)sDynNotImage, sDynLast ?: @"-", TCPSiteClassSummary(),
            TCPDynamicClassProbe()];
}

// 1.0.31 取证：**iOS 16.7.16 上真正声明了「图标图」方法的类**。
//
// 为什么需要：秒加载要挂的缓存层真入口，1.0.30 已证伪原假设（SBHIconImageCache 三兄弟
// 根本不实现 iconImageWithInfo:）。猜名字的代价是 0.9.21 那种安全模式，所以必须实测。
// icli 之类的外部探针看不到 SpringBoard 私有类（沙箱 + 不在本进程），只有插件自己能在
// SpringBoard 里问 —— 这就是本函数存在的理由。
//
// 只跑一次（静态标志），只读：objc_copyClassList + class_copyMethodList，
// 结果写进诊断的 ientry= 一项。不上任何钩子。
static NSString *sIconEntryReport = nil;

NSString *TCPIconImageEntryCensus(void) {
    if (sIconEntryReport != nil) return sIconEntryReport;

    // 只认「出图」这条路的方法名。
    NSArray<NSString *> *needles = @[ @"iconImageWithInfo", @"unmaskedIconImageWithInfo",
                                      @"generateIconImageWithInfo", @"iconImageForIcon",
                                      @"iconImageWithOptions", @"iconImageWithImageInfo",
                                      @"gridCellImageOfSize", @"imageForIcon" ];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) {
        sIconEntryReport = @"-";
        return sIconEntryReport;
    }
    for (unsigned int i = 0; i < count && parts.count < 12; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        unsigned int mcount = 0;
        Method *methods = class_copyMethodList(cls, &mcount);
        if (methods == NULL) continue;
        NSMutableArray<NSString *> *hits = [NSMutableArray array];
        for (unsigned int j = 0; j < mcount && hits.count < 4; j++) {
            NSString *sel = NSStringFromSelector(method_getName(methods[j]));
            for (NSString *needle in needles) {
                if ([sel hasPrefix:needle]) {
                    if (![hits containsObject:sel]) [hits addObject:sel];
                    break;
                }
            }
        }
        free(methods);
        if (hits.count == 0) continue;
        [parts addObject:[NSString stringWithFormat:@"%@:%@",
                          NSStringFromClass(cls), [hits componentsJoinedByString:@"/"]]];
    }
    if (classes) free(classes);
    sIconEntryReport = parts.count > 0 ? [parts componentsJoinedByString:@";"] : @"none";
    os_log(TCPLogHandle(), "TCPS_IENTRY %{public}@", sIconEntryReport);
    return sIconEntryReport;
}

// 1.0.31 取证：同样的方法名，在**图标缓存类**上再查一遍（含继承）。
// 上一项只列「自己声明」的，缓存类往往是父类/分类声明，所以这里用 class_getInstanceMethod
// 问「实例能不能响应」，这才是能不能挂的判断依据。
NSString *TCPIconCacheEntryReport(void) {
    static NSString *sCacheEntry = nil;
    if (sCacheEntry != nil) return sCacheEntry;
    NSArray<NSString *> *classes = @[ @"SBHIconImageCache", @"SBFolderIconImageCache",
                                      @"SBIconImageCache", @"PKIconImageCache",
                                      @"SBIconModel", @"SBIconController" ];
    NSArray<NSString *> *sels = @[ @"iconImageWithInfo:", @"unmaskedIconImageWithInfo:",
                                   @"generateIconImageWithInfo:", @"iconImageForIcon:" ];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *name in classes) {
        Class cls = NSClassFromString(name);
        if (cls == Nil) { [parts addObject:[name stringByAppendingString:@"=nil"]]; continue; }
        NSMutableArray<NSString *> *has = [NSMutableArray array];
        for (NSString *selName in sels) {
            if (class_getInstanceMethod(cls, NSSelectorFromString(selName)) != NULL) {
                [has addObject:selName];
            }
        }
        [parts addObject:[NSString stringWithFormat:@"%@=%@", name,
                          has.count ? [has componentsJoinedByString:@"/"] : @"none"]];
    }
    sCacheEntry = [parts componentsJoinedByString:@";"];
    os_log(TCPLogHandle(), "TCPS_CACHE_ENTRY %{public}@", sCacheEntry);
    return sCacheEntry;
}

BOOL TCPIconNeedsSystemComposite(id icon) {
    if (icon == nil) return NO;
    return TCPBundleIsDynamic(TCPIconBundleIdentifier(icon));
}

// 1.0.7：日历的「数字层」提取（定义在文件后面）。
static void TCPCompositeCalendarInk(CGContextRef ctx, CGRect rect, UIImage *systemImage, BOOL darkBase);
// 1.0.30：日历墨层筛掉多少（-1 = 一个字没留下已回退旧行为），写进 dyn last 的 inkdrop=。
static double sCalendarInkDrop = 0.0;

#pragma mark - 1.0.43 日历文字：主题参数 + 系统字体（照 ThemeCore / SnowBoard 的做法自己画）

// 为什么改（用户 2026-11-03 12:17 点名「ThemeCore 原插件包只是不支持图标角标阴影等等，
// 桌面图标为什么不直接用它的实现方式」）—— 本机 strings 取证：
//   ThemeCore.dylib 与 SnowBoardBase.dylib 里都带着同一组键：CalendarIconDateSettings /
//   CalendarIconDaySettings / TextYoffset / FontWeight / IconBundles。也就是说主题 Info.plist
//   这两节**本来就是给引擎自己画文字用的参数**，不是给抠像素用的。
//   我们 1.0.7 起走「抠系统图的墨」：代价是永远对不齐，而且 1.0.32 的规则③专门把偏红像素
//   判成「不是墨」，星期文字被整条丢掉 —— 现场就是「日历上只有数字、没有星期」。
// 现在：底图照旧画主题素材，文字用**系统字体**按参数画。跟 ThemeCore / SnowBoard 同路。
//
// 参数语义（与 ThemeCore 对齐）：
//   FontSize   —— 以 60pt 图标盒子标定的点数，图标更大就等比放大（k = 高度/60）。
//   FontWeight —— UltraLight…Black。FontName 给了先按名字找字体；找不到（本机主题写的
//                 "SF-Compact" 在 iOS 上没有这个可用字体名）就退回系统字体 + 这个字重。
//   TextColor / ShadowColor / ShadowBlurRadius / TextYoffset / TextXoffset / ShadowYoffset。
// 位置锚点（无偏移时的基准，占图标高度的比例；要微调只改这三行）：
static const CGFloat kTCPCalDateBaseY = 0.520;   // 日期数字中心
static const CGFloat kTCPCalDayBaseY  = 0.260;   // 星期文字中心
static const CGFloat kTCPCalBaseSize  = 60.0;    // 参数里的点数按 60pt 图标标定

static CGFloat TCPCalFloat(NSDictionary *dict, NSString *key, CGFloat fallback) {
    id value = dict[key];
    if ([value isKindOfClass:[NSNumber class]]) return (CGFloat)[value doubleValue];
    if ([value isKindOfClass:[NSString class]]) return (CGFloat)[(NSString *)value doubleValue];
    return fallback;
}

static NSString *TCPCalString(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) return value;
    return nil;
}

static UIFontWeight TCPCalWeight(NSString *name) {
    if (name.length == 0) return UIFontWeightRegular;
    NSString *n = [name lowercaseString];
    if ([n isEqualToString:@"ultralight"])   return UIFontWeightUltraLight;
    if ([n isEqualToString:@"thin"])         return UIFontWeightThin;
    if ([n isEqualToString:@"light"])        return UIFontWeightLight;
    if ([n isEqualToString:@"medium"])       return UIFontWeightMedium;
    if ([n isEqualToString:@"semibold"])     return UIFontWeightSemibold;
    if ([n isEqualToString:@"bold"])         return UIFontWeightBold;
    if ([n isEqualToString:@"heavy"])        return UIFontWeightHeavy;
    if ([n isEqualToString:@"black"])        return UIFontWeightBlack;
    return UIFontWeightRegular;
}

// "#RRGGBB" / "#AARRGGBB" / @[@(r),@(g),@(b)]（0~255 或 0~1）。认不出就用 fallback。
static UIColor *TCPCalParseColor(id value, UIColor *fallback) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    BOOL ok = NO;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)value stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
        if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
        if (s.length == 6 || s.length == 8) {
            unsigned long long v = strtoull(s.UTF8String, NULL, 16);
            if (s.length == 8) {
                a = ((v >> 24) & 0xFF) / 255.0;
                r = ((v >> 16) & 0xFF) / 255.0;
            } else {
                r = ((v >> 16) & 0xFF) / 255.0;
            }
            g = ((v >> 8) & 0xFF) / 255.0;
            b = (v & 0xFF) / 255.0;
            ok = YES;
        }
    } else if ([value isKindOfClass:[NSArray class]] && [(NSArray *)value count] >= 3) {
        NSArray *arr = value;
        BOOL unit = YES;   // 三个分量都 <= 1 就当作 0~1
        for (NSUInteger i = 0; i < 3; i++) {
            if (![arr[i] isKindOfClass:[NSNumber class]] || [arr[i] doubleValue] > 1.0) unit = NO;
        }
        CGFloat div = unit ? 1.0 : 255.0;
        r = [arr[0] doubleValue] / div;
        g = [arr[1] doubleValue] / div;
        b = [arr[2] doubleValue] / div;
        if (arr.count >= 4 && [arr[3] isKindOfClass:[NSNumber class]]) {
            a = unit ? [arr[3] doubleValue] : [arr[3] doubleValue] / 255.0;
        }
        ok = YES;
    }
    if (!ok) return fallback;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static CGFloat TCPCalColorLuminance(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return 0.0;
    return 0.299 * r + 0.587 * g + 0.114 * b;
}

// 字色兜底（只在极端情况下改主题给的颜色，避免「白底白字看不见」）：
// 底很亮而字也很亮 → 换黑；底很暗而字也很暗 → 换白。其余一律照主题来。
static UIColor *TCPCalVisibleColor(UIColor *wanted, CGFloat baseLum, BOOL *adjusted) {
    CGFloat lum = TCPCalColorLuminance(wanted);
    if (baseLum >= 0.80 && lum >= 0.80) { if (adjusted) *adjusted = YES; return [UIColor blackColor]; }
    if (baseLum <= 0.10 && lum <= 0.12) { if (adjusted) *adjusted = YES; return [UIColor whiteColor]; }
    return wanted;
}

// FontName 优先；找不到（例如主题写的 "SF-Compact"）退回系统字体 + FontWeight。
static UIFont *TCPCalFont(NSDictionary *settings, CGFloat size, BOOL *systemFallback) {
    UIFontWeight weight = TCPCalWeight(TCPCalString(settings, @"FontWeight"));
    NSString *name = TCPCalString(settings, @"FontName");
    UIFont *font = nil;
    if (name.length > 0) font = [UIFont fontWithName:name size:size];
    if (font == nil) {
        if (systemFallback) *systemFallback = (name.length > 0);
        font = [UIFont systemFontOfSize:size weight:weight];
    }
    return font;
}

// 星期文字：系统同一套本地化（中文「周一」、英文「MON」…）。
static NSString *TCPCalWeekdayText(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        NSString *template = [NSDateFormatter dateFormatFromTemplate:@"EEE" options:0
                                                             locale:[NSLocale currentLocale]];
        fmt.dateFormat = template.length > 0 ? template : @"EEE";
    });
    @synchronized (fmt) {
        return [fmt stringFromDate:[NSDate date]];
    }
}

static NSString *TCPCalDayText(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"d";
    });
    @synchronized (fmt) {
        return [fmt stringFromDate:[NSDate date]];
    }
}

// 画一层文字。box/字号/颜色/阴影全按这一节的参数来；没画成返回 NO。
static BOOL TCPCalDrawLayer(CGContextRef ctx, CGRect rect, NSString *text, NSDictionary *settings,
                            CGFloat baseY, CGFloat defaultSize, CGFloat scaleFactor,
                            CGFloat baseLum, NSMutableArray<NSString *> *info) {
    if (ctx == NULL || text.length == 0 || settings == nil) return NO;
    CGFloat size = TCPCalFloat(settings, @"FontSize", defaultSize) * scaleFactor;
    if (!(size > 1.0)) size = defaultSize * scaleFactor;
    if (size > rect.size.height * 0.9) size = rect.size.height * 0.9;

    BOOL systemFallback = NO;
    UIFont *font = TCPCalFont(settings, size, &systemFallback);
    if (font == nil) return NO;

    BOOL adjusted = NO;
    UIColor *color = TCPCalParseColor(settings[@"TextColor"], [UIColor blackColor]);
    color = TCPCalVisibleColor(color, baseLum, &adjusted);

    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[NSFontAttributeName] = font;
    attrs[NSForegroundColorAttributeName] = color;

    CGFloat blur = TCPCalFloat(settings, @"ShadowBlurRadius", 0) * scaleFactor;
    if (blur > 0) {
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = TCPCalParseColor(settings[@"ShadowColor"],
                                             [UIColor colorWithWhite:0.0 alpha:0.5]);
        shadow.shadowBlurRadius = blur;
        shadow.shadowOffset = CGSizeMake(TCPCalFloat(settings, @"ShadowXoffset", 0) * scaleFactor,
                                         TCPCalFloat(settings, @"ShadowYoffset", 0) * scaleFactor);
        attrs[NSShadowAttributeName] = shadow;
    }
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByClipping;
    attrs[NSParagraphStyleAttributeName] = style;

    CGSize textSize = [text sizeWithAttributes:attrs];
    if (textSize.width <= 0 || textSize.height <= 0) return NO;
    CGFloat cx = CGRectGetMidX(rect) + TCPCalFloat(settings, @"TextXoffset", 0) * scaleFactor;
    CGFloat cy = rect.size.height * baseY + TCPCalFloat(settings, @"TextYoffset", 0) * scaleFactor;
    CGRect drawRect = CGRectMake(cx - textSize.width * 0.5, cy - textSize.height * 0.5,
                                 textSize.width, textSize.height);
    [text drawInRect:drawRect withAttributes:attrs];

    [info addObject:[NSString stringWithFormat:@"%@@%.1f,y%.0f,w%.0f%@%@", text, size,
                     drawRect.origin.y, textSize.width,
                     systemFallback ? @",sf" : @"", adjusted ? @",auto" : @""]];
    return YES;
}

// 从系统日历图里量出「星期」「日期」两块文字的中心（比例坐标 0~1，相对整图高度），
// 顺便给出墨占比。**量的只是位置**：文字的颜色/字号/字体一律听主题参数、由系统字体自绘。
//
// 为什么要量：文字该摆在图标哪个高度是系统自己的版式，各 iOS 版本/机型/语言不一样，
// 写死比例迟早对不齐（老路抠墨就是这么一路歪下来的）。
// 判据不依赖「白底 + 黑字」这种假设：先直方图求不透明像素的主色 = 卡片底色，
// 再把「与底色亮度差 > 0.25」的像素当墨，按行投影分成上下两簇（上 = 星期，下 = 日期）。
// 亮色图标（白底黑字）与深色图标（黑底白字）都能量。
// 量不出来（底色不占多数、墨太少、簇分不开）返回 NO，调用方用固定比例兜底。
static BOOL TCPCalendarSystemTextBoxes(UIImage *image, CGFloat *weekdayCenterY,
                                       CGFloat *dateCenterY, double *inkRatio) {
    if (image == nil || image.CGImage == NULL) return NO;
    CGImageRef cg = image.CGImage;
    size_t sw = CGImageGetWidth(cg), sh = CGImageGetHeight(cg);
    if (sw < 16 || sh < 16) return NO;
    size_t dw = MIN(sw, (size_t)96), dh = MIN(sh, (size_t)96);
    unsigned char *buf = calloc(dw * dh, 4);
    if (buf == NULL) return NO;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef tmp = CGBitmapContextCreate(buf, dw, dh, 8, dw * 4, space,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (tmp == NULL) { free(buf); return NO; }
    CGContextDrawImage(tmp, CGRectMake(0, 0, (CGFloat)dw, (CGFloat)dh), cg);
    CGContextRelease(tmp);

    // ① 卡片底色 = 不透明像素直方图里最多的一桶（4bit/通道），再把这桶像素平均一下拿准色。
    unsigned short bins[4096] = {0};   // 8KB 栈上；计数上限 dw*dh≤9216 < 65535
    size_t total = 0;
    for (size_t i = 0; i < dw * dh; i++) {
        if (buf[i * 4 + 3] < 16) continue;
        size_t b = ((size_t)(buf[i * 4] >> 4) << 8) | ((size_t)(buf[i * 4 + 1] >> 4) << 4) |
                   (size_t)(buf[i * 4 + 2] >> 4);
        bins[b]++;
        total++;
    }
    if (total < 64) { free(buf); return NO; }
    size_t best = 0, bestN = 0;
    for (size_t b = 0; b < 4096; b++) if (bins[b] > bestN) { bestN = bins[b]; best = b; }
    if (bestN * 4 < total) { free(buf); return NO; }   // 底色不占多数：不是常规日历图
    double sr = 0, sg = 0, sb = 0;
    size_t sn = 0;
    for (size_t i = 0; i < dw * dh; i++) {
        if (buf[i * 4 + 3] < 16) continue;
        size_t b = ((size_t)(buf[i * 4] >> 4) << 8) | ((size_t)(buf[i * 4 + 1] >> 4) << 4) |
                   (size_t)(buf[i * 4 + 2] >> 4);
        if (b != best) continue;
        sr += buf[i * 4]; sg += buf[i * 4 + 1]; sb += buf[i * 4 + 2];
        sn++;
    }
    if (sn == 0) { free(buf); return NO; }
    double bgLum = (0.299 * (sr / sn) + 0.587 * (sg / sn) + 0.114 * (sb / sn)) / 255.0;

    // ② 行投影：每行「与底色亮度差 > 0.25」的像素数就是这一行的墨。
    unsigned char *rowInk = calloc(dh, 1);
    if (rowInk == NULL) { free(buf); return NO; }
    size_t inkTotal = 0, first = dh, last = 0;
    for (size_t y = 0; y < dh; y++) {
        size_t n = 0;
        for (size_t x = 0; x < dw; x++) {
            size_t i = y * dw + x;
            if (buf[i * 4 + 3] < 16) continue;
            double lum = (0.299 * buf[i * 4] + 0.587 * buf[i * 4 + 1] + 0.114 * buf[i * 4 + 2]) / 255.0;
            if (fabs(lum - bgLum) > 0.25) n++;
        }
        rowInk[y] = (unsigned char)MIN(n, (size_t)255);
        inkTotal += n;
        if (n > 0) { if (y < first) first = y; last = y; }
    }
    free(buf);
    if (first >= last || inkTotal < (size_t)(dw * dh) / 200) { free(rowInk); return NO; }

    // ③ 两簇之间最大的那段空白就是分界；它必须落在中间，否则当成整块图形（退回固定比例）。
    size_t gapStart = 0, gapLen = 0, curStart = 0, curLen = 0;
    for (size_t y = first; y <= last; y++) {
        if (rowInk[y] == 0) {
            if (curLen == 0) curStart = y;
            curLen++;
            if (curLen > gapLen) { gapLen = curLen; gapStart = curStart; }
        } else {
            curLen = 0;
        }
    }
    size_t span = last - first;
    size_t split = first + span / 2;
    if (gapLen >= 2 && gapStart > first + span / 6 && gapStart + gapLen < last - span / 6) {
        split = gapStart + gapLen / 2;
    }

    size_t topSum = 0, topN = 0, botSum = 0, botN = 0;
    for (size_t y = first; y <= last; y++) {
        if (rowInk[y] == 0) continue;
        if (y < split) { topSum += y; topN++; } else { botSum += y; botN++; }
    }
    free(rowInk);
    if (topN == 0 || botN == 0) return NO;

    CGFloat dayY = (CGFloat)(((double)topSum / (double)topN + 0.5) / (double)dh);
    CGFloat dateY = (CGFloat)(((double)botSum / (double)botN + 0.5) / (double)dh);
    // 合理性：上簇在上、下簇在下、两簇拉开一点距离、都在图内。任一条不满足就当没量到。
    if (!(dayY > 0.04 && dateY < 0.96 && dateY - dayY > 0.10)) return NO;
    if (weekdayCenterY) *weekdayCenterY = dayY;
    if (dateCenterY) *dateCenterY = dateY;
    if (inkRatio) *inkRatio = (double)inkTotal / (double)(dw * dh);
    return YES;
}

// 日历合成：主题底图 + 自己画的星期/日期文字。返回写进 dyn last 的描述串。
static NSString *TCPCompositeCalendarText(CGContextRef ctx, CGRect rect, UIImage *base,
                                          UIImage *systemImage,
                                          NSDictionary *dateSettings, NSDictionary *daySettings) {
    if (ctx == NULL || rect.size.height <= 0) return @"base+text(none)";
    CGFloat k = rect.size.height / kTCPCalBaseSize;
    CGFloat baseLum = base != nil ? TCPPixelStatsForImage(base).luminance : 0.5;

    CGFloat dayY = kTCPCalDayBaseY, dateY = kTCPCalDateBaseY;
    double inkRatio = 0.0;
    BOOL measured = TCPCalendarSystemTextBoxes(systemImage, &dayY, &dateY, &inkRatio);

    NSMutableArray<NSString *> *info = [NSMutableArray array];
    BOOL day = TCPCalDrawLayer(ctx, rect, TCPCalWeekdayText(), daySettings,
                               dayY, 9.5, k, baseLum, info);
    BOOL date = TCPCalDrawLayer(ctx, rect, TCPCalDayText(), dateSettings,
                                dateY, 30.0, k, baseLum, info);
    if (!day && !date) return measured ? @"base+text(none,box)" : @"base+text(none)";
    return [NSString stringWithFormat:@"base+text(%@,%@,%.2f/%.2f,ink=%.2f)",
            [info componentsJoinedByString:@","],
            measured ? @"sys" : @"fix", dayY, dateY, inkRatio];
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
        // 1.0.19：noasset 兜底 —— 遮罩/圆角链路出错时，退回「无圆角」再取一次，
        // 仍拿不到才记 fail。日历 8/13 失败回退系统图，先排除这条。
        themed = [store iconImageForBundleID:bundleID
                                       size:info.size
                                      scale:info.scale
                               cornerRadius:0];
    }
    if (themed == nil) {
        __sync_fetch_and_add(&sDynFail, 1);
        __sync_fetch_and_add(&sDynFailNoAsset, 1);
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
        __sync_fetch_and_add(&sDynFailNoCtx, 1);
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
        // 日历（1.0.43 起照 ThemeCore / SnowBoard 的做法：**底图用主题素材，文字自己画**）。
        //
        // 为什么换（用户 2026-11-03 12:17 点名）—— 本机 strings 取证：ThemeCore.dylib 与
        // SnowBoardBase.dylib 里都带着 CalendarIconDateSettings / CalendarIconDaySettings /
        // TextYoffset / FontWeight / IconBundles 同一组键，说明主题 Info.plist 这两节
        // **本来就是给引擎自己用系统字体画文字的参数**。我们 1.0.7 起却拿它去抠系统图的墨：
        // 永远对不齐，而且 1.0.32 的规则③专门把偏红像素判成「不是墨」，星期文字被整条丢掉。
        // 现在：底图照旧画主题素材，星期/日期文字用系统字体按参数画上去。
        // 主题没声明这两节时才退回老路（抠墨），免得别的主题反而变差。
        [themed drawInRect:rect];
        NSDictionary *dateSettings = [store calendarDateSettings];
        NSDictionary *daySettings = [store calendarDaySettings];
        if (dateSettings != nil || daySettings != nil) {
            how = TCPCompositeCalendarText(ctx, rect, themed, systemImage, dateSettings, daySettings);
        } else {
            if (systemImage != nil) {
                TCPPixelStats s = TCPPixelStatsForImage(themed);
                TCPCompositeCalendarInk(ctx, rect, systemImage, s.luminance < 0.5);
            }
            how = @"base+ink(nocfg)";
        }
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (result == nil) {
        __sync_fetch_and_add(&sDynFail, 1);
        __sync_fetch_and_add(&sDynFailNoImage, 1);
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

// 1.0.7：日历的「数字层」提取。
// 为什么不能用混合模式（用户 2026-10-31 20:31「日历和时钟美化素材不加载」、
// 早期版本「日历显示了底图没有显示文字」）：系统日历整图是「白底 + 黑数字」，
// multiply 压在深色主题底上 → 白底变成主题色、黑数字还是黑 → 深底上根本看不见字；
// screen 压在浅底上 → 白字也看不见。混合模式解决不了「墨要跟着底色换颜色」。
// 正确做法：把系统图里「与背景色不同的部分」（也就是日期数字）取出来当**墨**，
// 再按主题底图的明暗选黑/白把它画上去 —— 文字一定可见，底图也保持主题的样子。
static void TCPCompositeCalendarInk(CGContextRef ctx, CGRect rect, UIImage *systemImage, BOOL darkBase) {
    if (ctx == NULL || systemImage == nil || systemImage.CGImage == NULL) return;
    CGImageRef cg = systemImage.CGImage;
    size_t sw = CGImageGetWidth(cg), sh = CGImageGetHeight(cg);
    if (sw == 0 || sh == 0) return;

    size_t cap = 96;
    size_t dw = MIN(sw, cap), dh = MIN(sh, cap);
    unsigned char *buffer = calloc(dw * dh, 4);
    if (buffer == NULL) return;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef tmp = CGBitmapContextCreate(buffer, dw, dh, 8, dw * 4, space,
                                              (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (tmp == NULL) { free(buffer); return; }
    CGContextDrawImage(tmp, CGRectMake(0, 0, (CGFloat)dw, (CGFloat)dh), cg);
    CGContextRelease(tmp);

    // 1.0.32：**改成「近黑选数字」，不再用四角均值当背景。**
    //
    // 为什么换（AI 逆向 + 本机诊断对得上）：
    // 原来用「四角像素平均」当背景色，但图标图带圆角遮罩 —— **四角是透明的（alpha≈0，RGB=0）**，
    // 均值被拖成近黑。于是白底(255,255,255) 与"背景"差异拉满，**整张系统图（含白色底板）都被
    // 判成墨**，盖住主题底图。诊断上表现为 inkdrop=0.00、cov=0.96（整图一个大连通块）。
    //
    // 新判据不依赖背景估计，直接按颜色选：
    //   ① alpha < 16        → 不是墨（圆角透明区）
    //   ② max(R,G,B) >= 140 → 不是墨（白底、灰阴影、浅色装饰）
    //   ③ R - max(G,B) > 30 → 不是墨（红色星期文字，如 "MON"/"TUE"）
    // 剩下三通道都低的，就是黑色的日期数字（含抗锯齿边）。
    // 系统日历图结构（iOS 16.7）= 白底 + 红色星期文字 + 黑色日期数字；红条 iOS 7 起已去掉。
    unsigned char *maskBuffer = calloc(dw * dh, 4);
    if (maskBuffer == NULL) { free(buffer); return; }
    unsigned char *rawAlpha = calloc(dw * dh, 1);      // 0~255 的原始墨强度
    if (rawAlpha == NULL) { free(maskBuffer); free(buffer); return; }
    for (size_t i = 0; i < dw * dh; i++) {
        unsigned char *p = buffer + i * 4;
        unsigned char a = p[3];
        if (a < 16) continue;                       // ① 透明 → 背景
        unsigned char r = p[0], g = p[1], b = p[2];
        unsigned char mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
        if (mx >= 140) continue;                    // ② 亮色（白底/灰阴影）→ 不是墨
        unsigned char gb = g > b ? g : b;
        if ((int)r - (int)gb > 30) continue;        // ③ 偏红（星期文字）→ 不是墨
        // 越黑越实：mx 越小越实，映射到 120~255 的幅度
        rawAlpha[i] = (unsigned char)(mx < 100 ? 255 : 255 - (mx - 100) * 2);
    }
    free(buffer);

    // 腐蚀 1 像素（3×3 取最小）：粗笔画的字留下主干，细线（指针）整条消失。
    unsigned char *eroded = calloc(dw * dh, 1);
    if (eroded != NULL) {
        for (size_t y = 0; y < dh; y++) {
            for (size_t x = 0; x < dw; x++) {
                unsigned char m = rawAlpha[y * dw + x];
                for (int dy = -1; dy <= 1 && m > 0; dy++) {
                    long yy = (long)y + dy;
                    if (yy < 0 || yy >= (long)dh) { m = 0; break; }
                    for (int dx = -1; dx <= 1; dx++) {
                        long xx = (long)x + dx;
                        if (xx < 0 || xx >= (long)dw) { m = 0; break; }
                        unsigned char v = rawAlpha[yy * dw + xx];
                        if (v < m) m = v;
                    }
                }
                eroded[y * dw + x] = m;
            }
        }
    }

    // 连通区域筛：4 连通从粗主干长回原始墨区域，面积太小的整块丢掉（指针常是独立的小块）。
    BOOL *keep = NULL;
    size_t *stack = NULL;
    if (eroded != NULL) {
        keep = calloc(dw * dh, 1);
        unsigned char *visited = calloc(dw * dh, 1);
        stack = calloc(dw * dh, sizeof(size_t));
        if (keep != NULL && visited != NULL && stack != NULL) {
            size_t minArea = MAX((size_t)6, (dw * dh) / 900);   // ≈0.11% 的面积，数字笔画远大于它
            for (size_t i = 0; i < dw * dh; i++) {
                if (visited[i] || rawAlpha[i] == 0) continue;
                size_t top = 0, area = 0;
                BOOL hasCore = NO;
                stack[top++] = i;
                visited[i] = 1;
                while (top > 0) {
                    size_t cur = stack[--top];
                    area++;
                    if (eroded != NULL && eroded[cur] > 0) hasCore = YES;
                    size_t cx = cur % dw, cy = cur / dw;
                    size_t nb[4] = { cur - 1, cur + 1,
                                     (cy > 0 ? cur - dw : cur), (cy + 1 < dh ? cur + dw : cur) };
                    for (int k = 0; k < 4; k++) {
                        size_t n = nb[k];
                        if (k == 0 && cx == 0) continue;
                        if (k == 1 && cx + 1 >= dw) continue;
                        if (visited[n] || rawAlpha[n] == 0) continue;
                        visited[n] = 1;
                        stack[top++] = n;
                    }
                }
                if (hasCore && area >= minArea) {
                    // 回填：整块保留
                    top = 0;
                    stack[top++] = i;
                    keep[i] = 1;
                    while (top > 0) {
                        size_t cur = stack[--top];
                        size_t cx = cur % dw, cy = cur / dw;
                        size_t nb[4] = { cur - 1, cur + 1,
                                         (cy > 0 ? cur - dw : cur), (cy + 1 < dh ? cur + dw : cur) };
                        for (int k = 0; k < 4; k++) {
                            size_t n = nb[k];
                            if (k == 0 && cx == 0) continue;
                            if (k == 1 && cx + 1 >= dw) continue;
                            if (keep[n] || rawAlpha[n] == 0) continue;
                            keep[n] = 1;
                            stack[top++] = n;
                        }
                    }
                }
            }
            free(visited);
        } else {
            free(visited);
            free(keep);
            keep = NULL;
        }
        free(stack);
    }

    size_t keptPixels = 0;
    for (size_t i = 0; i < dw * dh; i++) {
        unsigned char v = rawAlpha[i];
        if (keep != NULL && v > 0 && !keep[i]) v = 0;   // 没通过形状筛选的（指针、装饰线）不画
        if (v > 0) keptPixels++;
        maskBuffer[i * 4 + 0] = v;
        maskBuffer[i * 4 + 1] = v;
        maskBuffer[i * 4 + 2] = v;
        maskBuffer[i * 4 + 3] = 255;
    }
    // 1.0.30 取证：筛掉了多少墨（诊断日历那段的 ink: 后缀会带上 inkdrop=）。
    double dropped = 0.0;
    if (keep != NULL) {
        size_t raw = 0;
        for (size_t i = 0; i < dw * dh; i++) if (rawAlpha[i] > 0) raw++;
        if (raw > 0) dropped = 1.0 - (double)keptPixels / (double)raw;
        // 一个字都没留下 → 说明这版系统图的字也没通过筛选，退回旧行为（宁可多墨，不可空白）
        if (keptPixels < MAX((size_t)4, (dw * dh) / 4000)) {
            for (size_t i = 0; i < dw * dh; i++) {
                unsigned char v = rawAlpha[i];
                maskBuffer[i * 4 + 0] = v;
                maskBuffer[i * 4 + 1] = v;
                maskBuffer[i * 4 + 2] = v;
            }
            dropped = -1.0;
        }
    }
    free(eroded);
    free(keep);
    free(rawAlpha);
    sCalendarInkDrop = dropped;

    CGColorSpaceRef maskSpace = CGColorSpaceCreateDeviceRGB();
    // buffer 是 RGBA 排布（每像素 4 字节），bytesPerRow 必须是 dw*4。
    // kCGImageAlphaNoneSkipLast：ClipToMask 用**亮度**当遮罩强度，最后一个字节被忽略。
    CGContextRef maskCtx = CGBitmapContextCreate(maskBuffer, dw, dh, 8, dw * 4, maskSpace,
                                                  (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(maskSpace);
    if (maskCtx == NULL) { free(maskBuffer); return; }
    CGImageRef maskImage = CGBitmapContextCreateImage(maskCtx);
    CGContextRelease(maskCtx);
    if (maskImage != NULL) {
        CGContextSaveGState(ctx);
        CGContextClipToMask(ctx, rect, maskImage);
        CGContextSetFillColorWithColor(ctx, (darkBase ? [UIColor whiteColor] : [UIColor blackColor]).CGColor);
        CGContextFillRect(ctx, rect);
        CGContextRestoreGState(ctx);
        CGImageRelease(maskImage);
    }
    free(maskBuffer);
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

// 覆盖层的身份标记：我们自己的 UIImageView 用它认领，找「表盘」时要跳过它，
// 否则下一拍会把自己盖上去的图当成系统表盘。
static const NSInteger kTCPClockOverlayTag = 0x7C1C0C4;

// 在视图里找「表盘」：尺寸（点）与本视图大致相等的 UIImageView，或 layer.contents 有图的 CALayer。
// iOS 16.7 的 SBHClockApplicationIconImageView 表盘可能是 CALayer 自绘（不是 UIImageView）。
// 返回一个封装：type="imgv" 时 value 是 UIImageView；type="layer" 时 value 是 CALayer。
static NSDictionary *TCPClockFindFace(UIView *view, NSInteger depth, NSMutableArray<NSString *> *trace) {
    CGSize bounds = view.bounds.size;
    if (bounds.width < 8) return nil;
    for (UIView *sub in view.subviews) {
        if (sub.tag == kTCPClockOverlayTag) continue;   // 我们自己盖上去的那张，不算表盘

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
        // 路径 A：UIImageView（旧版本/iOS 15 及以下）
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImage *image = ((UIImageView *)sub).image;
            CGSize size = image.size;
            if (size.width > 1 && fabs(size.width - bounds.width) <= bounds.width * 0.25) {
                return @{ @"type": @"imgv", @"value": sub };
            }
        }
        // 路径 B：CALayer（iOS 16+ 自绘表盘）
        CALayer *layer = sub.layer;
        if (layer && layer.contents) {
            CGSize layerSize = layer.bounds.size;
            if (layerSize.width > 1 && fabs(layerSize.width - bounds.width) <= bounds.width * 0.25) {
                // 确认 contents 是 CGImage（不是别的类型）
                CFTypeID contentsType = CFGetTypeID((__bridge CFTypeRef)layer.contents);
                if (contentsType == CGImageGetTypeID()) {
                    return @{ @"type": @"layer", @"value": layer, @"host": sub };
                }
            }
        }
        if (depth > 0) {
            NSDictionary *found = TCPClockFindFace(sub, depth - 1, trace);
            if (found != nil) return found;
        }
    }
    return nil;
}

// 旧名保留，供本文件内调用（避免改太多地方）
static UIImageView *TCPClockFindFaceView(UIView *view, NSInteger depth, NSMutableArray<NSString *> *trace) {
    NSDictionary *found = TCPClockFindFace(view, depth, trace);
    if ([@"imgv" isEqualToString:found[@"type"]]) {
        return found[@"value"];
    }
    return nil;
}

static void TCPClockEnsureOverlay(UIView *view, UIImage *themed) {
    // 1.0.11：如果之前有盖过整图 overlay，把它移除掉，不再覆盖整张图
    UIView *old = [view viewWithTag:kTCPClockOverlayTag];
    if (old) [old removeFromSuperview];
    // 1.0.16：这里只画**针帽这一张小图**，不是整图覆盖。
    //   绝不往系统的 10×10 中轴层塞图 —— 1.0.12 的教训：素材（4×4@3x）被 resize
    //   拉伸成「太大的针帽」；也绝不盖整张图 —— 1.0.8 的教训：那是双层来源。
    //   画法：按素材**自身尺寸**居中（contentMode = Center 不缩放、不拉伸）。
    if (themed == nil || view == nil) return;
    UIImageView *iv = [[UIImageView alloc] initWithImage:themed];
    iv.tag = kTCPClockOverlayTag;
    iv.userInteractionEnabled = NO;
    iv.contentMode = UIViewContentModeCenter;
    iv.backgroundColor = [UIColor clearColor];
    iv.frame = view.bounds;
    [view addSubview:iv];
}

static void TCPClockViewApply(UIView *view) {
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active || !store.iconsEnabled) return;
    CGSize size = view.bounds.size;
    if (size.width < 8 || size.height < 8) return;

    // 清理旧版本的整图覆盖层（1.0.8 及以前那种盖一张含指针的整图 = 双层来源，永久废除）
    // 1.0.16：这里先不画 —— 针帽等下面拿到素材后再画（TCPClockEnsureOverlay(view, cap)）。

    CGFloat scale = view.window.screen.scale > 0 ? view.window.screen.scale : 2.0;

    // 1.0.16 针帽：用主题素材 ClockIconRedDot（中央帽），按**原尺寸**画在覆盖层正中；
    //   系统那枚 10×10 中轴帽（系统自画）随后清掉，避免两层叠加。
    //   拿不到素材就什么都不做（系统帽保持原样，绝不让针帽变空白）。
    UIImage *cap = TCPClockAssetImageNamed(store, @"ClockIconRedDot", scale);
    TCPClockEnsureOverlay(view, cap);

    // 1.0.11 逐片换素材（用户已验收）：表盘写视图自己的 layer，指针写系统那 5 个子 layer。
    // 1.0.12 只修针帽：系统结构是
    //     视图自己的 layer.contents = 表盘
    //     + 5 个子 CALayer（10x22 时针 / 10x32 分针 / 10x10 中轴 / 2x28 秒针 / 2x2 秒针帽）
    //   中轴层(l2)与秒针帽层(l4)本来就是系统自画的针帽，把 redDot 素材（4x4 点）整图塞进
    //   10x10 / 2x2 且默认 resize 拉伸 → 中轴被放大成「太大的针帽」。这两层一个字节都不碰，
    //   交还系统，针帽恢复系统原大小。时针 / 分针 / 秒针继续用主题素材。
    UIImage *face = TCPClockAssetImageNamed(store, @"ClockIconBackgroundSquare", scale);
    if (face == nil) {
        face = [store iconImageForBundleID:@"com.apple.mobiletimer"
                                      size:size
                                     scale:scale
                              cornerRadius:0];
    }
    if (face && face.CGImage) {
        if (view.layer.contents != (__bridge id)face.CGImage) {
            view.layer.contents = (__bridge id)face.CGImage;
        }
    }

    NSArray<CALayer *> *sublayers = view.layer.sublayers;
    NSUInteger layerCount = sublayers.count;
    if (layerCount >= 3) {
        UIImage *hourHand = TCPClockAssetImageNamed(store, @"ClockIconHourHand", scale);
        UIImage *minHand = TCPClockAssetImageNamed(store, @"ClockIconMinuteHand", scale);
        UIImage *secHand = TCPClockAssetImageNamed(store, @"ClockIconSecondHand", scale);

        // l0: 时针
        if (hourHand && hourHand.CGImage && sublayers[0].contents != (__bridge id)hourHand.CGImage) {
            sublayers[0].contents = (__bridge id)hourHand.CGImage;
        }
        // l1: 分针
        if (minHand && minHand.CGImage && sublayers[1].contents != (__bridge id)minHand.CGImage) {
            sublayers[1].contents = (__bridge id)minHand.CGImage;
        }
        // l2: 中轴 —— 1.0.16：系统那枚 10×10 的中轴帽清掉（contents 置 nil），
        //     换成我们自己按原尺寸画的 ClockIconRedDot；**只在拿到素材时才清**，
        //     拿不到就保持系统帽，绝不让针帽变空白。系统可能自己重绘，每拍再清一次。
        if (cap && cap.CGImage && sublayers[2].contents != NULL) {
            sublayers[2].contents = nil;
        }
        // l3: 秒针（若存在）
        if (layerCount >= 4 && secHand && secHand.CGImage && sublayers[3].contents != (__bridge id)secHand.CGImage) {
            sublayers[3].contents = (__bridge id)secHand.CGImage;
        }
        // l4: 秒针帽 —— 系统自画，不碰（1.0.12）：素材里没有对应的秒针端点帽，
        //     2×2 层塞 4×4 素材同样会被拉伸。
        __sync_fetch_and_add(&sClockVHit, 1);
        sClockVLast = [NSString stringWithFormat:@"layers:subs=%lu|face=%@|h=%@|m=%@|s=%@|dot=%@",
                       (unsigned long)layerCount,
                       face ? @"y" : @"n",
                       hourHand ? @"y" : @"n",
                       minHand ? @"y" : @"n",
                       secHand ? @"y" : @"n",
                       cap ? @"ours" : @"sys"];
    } else if (face) {
        __sync_fetch_and_add(&sClockVHit, 1);
        sClockVLast = [NSString stringWithFormat:@"face_only|subs=%lu", (unsigned long)layerCount];
    } else {
        __sync_fetch_and_add(&sClockVMiss, 1);
        sClockVLast = @"noasset";
    }
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

// 1.0.32：时钟视图类名 —— iOS 14~16 是 SBClockApplicationIconImageView（**无 H**），
// SBHClockApplicationIconImageView 是 iOS 17+ 才有的名字。我们原来只用后者 → found=0，
// 这台 16.7.16 上从头到尾没碰到过时钟。两个都试，谁在就用谁。
Class TCPClockViewClass(void) {
    Class cls = NSClassFromString(@"SBClockApplicationIconImageView");
    if (cls == Nil) cls = NSClassFromString(@"SBHClockApplicationIconImageView");
    return cls;
}

void TCPInstallClockViewSite(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class cls = TCPClockViewClass();
    if (cls == Nil) return;   // 类还没加载，下一轮 TCPReload 再试
    MSHookMessageEx(cls, @selector(layoutSubviews), (IMP)TCPClockLayoutHook, (IMP *)&sClockLayoutOrig);
    installed = YES;
    os_log(TCPLogHandle(), "TCPS_CLOCK_VIEW hooked");
}

// 1.0.10 取证（只读，不改任何状态）：把时钟视图的完整结构摊开。
// 目的：看清系统把「表盘」和「指针」分别画在哪一层 —— 是子视图、子 layer，还是自己 drawRect。
// 知道之后才能只换表盘、不碰指针（1.0.8 那种"盖一张含指针的整图"必然和系统指针重复）。
static BOOL TCPDisplayIsCGImage(id object);   // 定义在文件后面

static NSString *TCPClockStructureTrace(UIView *view) {
    if (view == nil) return @"nilview";
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    // ① 视图自己的 layer：有没有 contents、几层子 layer。
    NSString *own = [NSString stringWithFormat:@"v=%@|%.0fx%.0f|own=%@|sub=%lu",
                     NSStringFromClass([view class]),
                     view.bounds.size.width, view.bounds.size.height,
                     view.layer.contents ? @"y" : @"n",
                     (unsigned long)view.layer.sublayers.count];
    [lines addObject:own];

    // ② 子视图（最多 6 个）：类名 | 尺寸 | image 或 layer.contents | 是否我们自己盖的。
    NSInteger n = 0;
    for (UIView *sub in view.subviews) {
        if (n++ >= 6) break;
        NSString *tag = (sub.tag == kTCPClockOverlayTag) ? @"OURS" : @"sys";
        NSString *kind = @"-";
        if ([sub isKindOfClass:[UIImageView class]]) {
            UIImage *im = ((UIImageView *)sub).image;
            kind = im ? [NSString stringWithFormat:@"img%.0fx%.0f", im.size.width, im.size.height] : @"noimg";
        } else if (sub.layer.contents != NULL) {
            kind = TCPDisplayIsCGImage(sub.layer.contents) ? @"cgimg" : @"contents";
        }
        [lines addObject:[NSString stringWithFormat:@"s:%@|%.0fx%.0f|%@|%@",
                          NSStringFromClass([sub class]),
                          sub.bounds.size.width, sub.bounds.size.height, kind, tag]];
    }

    // ③ layer 子树（最多 6 层）：类名 | 尺寸 | contents 有没有。
    n = 0;
    for (CALayer *lay in view.layer.sublayers) {
        if (n++ >= 6) break;
        [lines addObject:[NSString stringWithFormat:@"l:%@|%.0fx%.0f|%@",
                          NSStringFromClass([lay class]),
                          lay.bounds.size.width, lay.bounds.size.height,
                          lay.contents ? (TCPDisplayIsCGImage(lay.contents) ? @"cg" : @"obj") : @"nil"]];
    }
    return [lines componentsJoinedByString:@";"];
}

// 1.0.7：主动刷新计数（诊断 clockv{tick=,found=}）。
static NSInteger sClockTickCount = 0;
static NSInteger sClockTickFound = 0;
static NSString *sClockStructure = nil;   // 1.0.10 取证：时钟视图的完整结构（只读）

NSString *TCPClockViewProbeReport(void) {
    return [NSString stringWithFormat:@"clockv{look=%ld,hit=%ld,miss=%ld,tick=%ld,found=%ld,last=%@,st=%@}",
            (long)sClockVLook, (long)sClockVHit, (long)sClockVMiss,
            (long)sClockTickCount, (long)sClockTickFound, sClockVLast,
            sClockStructure ?: @"-"];
}

// 1.0.7：主动找时钟视图并重画。
// 为什么需要它：iOS 16.7 的 SBHClockApplicationIconImageView **从不重新 layout**
// （1.0.6 装机实测 clockv{look=0,hit=0,miss=0,last=-}：挂的 layoutSubviews 钩子一次没触发），
// 所以光挂回调不行 —— 必须自己去找屏幕上的时钟视图。
// 顺带把指针变成活的：每 30 秒重画一次（时针分针精度到分钟，够用）。

void TCPClockTick(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ TCPClockTick(); });
        return;
    }
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active || !store.iconsEnabled) return;
    Class cls = TCPClockViewClass();
    if (cls == Nil) return;

    NSMutableArray *stack = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows) [stack addObject:window];
    NSUInteger guard = 0;
    NSInteger found = 0;
    while (stack.count > 0 && guard++ < 4000) {
        UIView *view = [stack lastObject];
        [stack removeLastObject];
        if ([view isKindOfClass:cls]) {
            found++;
            // 1.0.10：只读记录结构，不碰任何状态。
            @try { sClockStructure = TCPClockStructureTrace(view); } @catch (__unused NSException *e) { }
            @try { TCPClockViewApply(view); } @catch (__unused NSException *e) { }
        }
        [stack addObjectsFromArray:view.subviews];
    }
    sClockTickCount++;
    sClockTickFound = found;
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

// —— 文件夹预览拼图的缓存（收起状态的 mini 图标）——
//
// 收起时那张「3×3 mini 图标」的图不是几个独立的图标视图，而是 SBFolderIconImageCache
// 合出来并缓存的一张图（诊断：_SBIconGridWrapperView 手里 61×61 的图 = stock）。
// 所以「打开文件夹是主题图标、收起还是原图标」最可能的原因不是我们没挂上站，而是这张拼图
// 在我们出图之前就合好并缓存了，之后没人叫它重算。
// 这里做两件事：① 把缓存类自己声明的相关方法名记进诊断（下一版据此写死正确的重算方法）；
// ② 软调用一组常见的「重算/清缓存」零参数方法，主题生效后让拼图重算一次。
// 全是 respondsToSelector + 参数个数检查 + @try：方法名哪个版本变了只是不做事，不会崩。
static NSString *sFolderCacheLast = @"-";

static NSString *TCPFolderCacheMethods(void) {
    Class cls = NSClassFromString(@"SBFolderIconImageCache");
    if (cls == Nil) return @"nocls";
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; methods != NULL && i < count; i++) {
        if (method_getNumberOfArguments(methods[i]) != 2) continue;   // 只关心零参数（self+SEL）
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        if ([name containsString:@"image"] || [name containsString:@"reload"] ||
            [name containsString:@"invalid"] || [name containsString:@"refresh"] ||
            [name containsString:@"update"] || [name containsString:@"purge"]) {
            if (names.count < 12) [names addObject:name];
        }
    }
    if (methods != NULL) free(methods);
    return names.count > 0 ? [names componentsJoinedByString:@","] : @"nohit";
}

// 1.0.7 取证：SBFolderIconImageCache 的**全部**方法名（带参数个数）。
// 1.0.6 只列了零参数方法，结果 cm=nohit —— 拼图方法都是带参数的，
// 于是既不知道该挂哪个方法、也不知道参数长什么样。这一版全列出来，下一版照着写。
static NSString *TCPFolderCacheAllMethods(void) {
    Class cls = NSClassFromString(@"SBFolderIconImageCache");
    if (cls == Nil) return @"nocls";
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (methods == NULL || count == 0) return @"nomethods";
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        NSUInteger args = method_getNumberOfArguments(methods[i]);   // 含 self+SEL
        if (names.count < 24) {
            [names addObject:[NSString stringWithFormat:@"%@/%lu", name, (unsigned long)args]];
        }
    }
    free(methods);
    return names.count > 0 ? [names componentsJoinedByString:@","] : @"nohit";
}

// 1.0.7 取证：文件夹图标对象（SBFolderIcon）与它里面的 leaf 图标。
// 收起时的 mini 预览就是这些 leaf 图标拼出来的；要用主题图重拼，
// 就得先知道每个 mini 对应哪个 bundleID —— 这一版把类名、数量、bundleID 全记进诊断。
// 取法：视图上的 _folderIcon（KVC 读，拿不到就 nil）；leaf 图标用几个候选选择器试。
static NSString *TCPFolderLeavesReport(void) {
    Class viewClass = NSClassFromString(@"SBFolderIconImageView");
    if (viewClass == Nil) return @"nocls";
    __block NSString *result = @"nofolder";
    NSMutableArray *stack = [NSMutableArray array];
    for (UIWindow *window in [UIApplication sharedApplication].windows) [stack addObject:window];
    NSUInteger guard = 0;
    while (stack.count > 0 && guard++ < 4000) {
        UIView *view = [stack lastObject];
        [stack removeLastObject];
        if ([view isKindOfClass:viewClass]) {
            id folderIcon = nil;
            @try { folderIcon = [view valueForKey:@"_folderIcon"]; } @catch (NSException *e) { (void)e; }
            if (folderIcon == nil) {
                @try { folderIcon = [view valueForKey:@"folderIcon"]; } @catch (NSException *e) { (void)e; }
            }
            if (folderIcon == nil) { result = @"noicon"; }
            else {
                NSMutableArray<NSString *> *ids = [NSMutableArray array];
                id leaves = nil;
                for (NSString *sel in @[ @"leafIcons", @"allIcons", @"icons", @"childIcons" ]) {
                    SEL s = NSSelectorFromString(sel);
                    if (![folderIcon respondsToSelector:s]) continue;
                    leaves = ((id (*)(id, SEL))objc_msgSend)(folderIcon, s);
                    if ([leaves isKindOfClass:[NSArray class]] && ((NSArray *)leaves).count > 0) break;
                    leaves = nil;
                }
                if (leaves == nil) {
                    result = [NSString stringWithFormat:@"%@:noleafsel", NSStringFromClass([folderIcon class])];
                } else {
                    for (id leaf in (NSArray *)leaves) {
                        if (ids.count >= 6) break;
                        NSString *bid = TCPIconBundleIdentifier(leaf);
                        [ids addObject:bid ?: @"?"];
                    }
                    result = [NSString stringWithFormat:@"%@:n=%lu[%@]",
                              NSStringFromClass([folderIcon class]),
                              (unsigned long)((NSArray *)leaves).count,
                              [ids componentsJoinedByString:@","]];
                }
            }
            break;
        }
        [stack addObjectsFromArray:view.subviews];
    }
    return result;
}

void TCPFolderCacheRefresh(void) {
    if (![NSThread isMainThread]) return;
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active || !store.iconsEnabled) { sFolderCacheLast = @"inactive"; return; }
    Class cls = NSClassFromString(@"SBFolderIconImageCache");
    if (cls == Nil) { sFolderCacheLast = @"nocls"; return; }
    id cache = nil;
    for (NSString *name in @[ @"sharedInstance", @"sharedCache", @"defaultCache",
                              @"sharedImageCache" ]) {
        SEL sel = NSSelectorFromString(name);
        if (![cls respondsToSelector:sel]) continue;
        cache = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel);
        if (cache != nil) break;
    }
    if (cache == nil) { sFolderCacheLast = @"nocache"; return; }
    NSMutableArray<NSString *> *done = [NSMutableArray array];
    for (NSString *name in @[ @"reloadImagesForAllFolderIcons", @"reloadImagesForAllIcons",
                              @"reloadAllImages", @"invalidateAllImages", @"invalidate",
                              @"removeAllImages", @"purgeCache", @"clearCache" ]) {
        SEL sel = NSSelectorFromString(name);
        Method m = class_getInstanceMethod([cache class], sel);
        if (m == NULL || method_getNumberOfArguments(m) != 2) continue;   // 只调零参数版本
        @try {
            ((void (*)(id, SEL))objc_msgSend)(cache, sel);
            [done addObject:name];
        } @catch (NSException *e) {
            [done addObject:[name stringByAppendingString:@"!ex"]];
        }
    }
    sFolderCacheLast = done.count > 0 ? [done componentsJoinedByString:@","] : @"nomethod";
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
    // 采完样再叫缓存重算：主题刚上来时那张拼图是缓存的旧图，重算之后下一轮普查才看得到变化。
    TCPFolderCacheRefresh();
}

NSString *TCPFolderProbeReport(void) {
    // 1.0.7：加 allm（缓存类全部方法）与 lv（文件夹 leaf 图标取证）两段。
    return [NSString stringWithFormat:@"folderv{n=%ld,s=[%@],m=%@,cache=%@,cm=%@,allm=%@,lv=%@}",
            (long)sFolderViewCount,
            sFolderViewSamples.count > 0
                ? [sFolderViewSamples componentsJoinedByString:@";"] : @"-",
            sFolderMethods, sFolderCacheLast, TCPFolderCacheMethods(),
            TCPFolderCacheAllMethods(), TCPFolderLeavesReport()];
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

// TCPDisplayIsCGImage 的前向声明已在前面（时钟取证那段），这里不用重复。

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
// 1.0.24：从视图取 iconImageInfo（结构体）。视图不响应或值异常时用 bounds 兜底，
// 保证换图 API 拿到的尺寸是合理的（结构体 ABI 铁律，绝不手算寄存器）。
static TCPIconImageInfo TCPViewIconImageInfoValue(id view) {
    TCPIconImageInfo info = { .size = CGSizeZero, .scale = 2.0, .cornerRadius = 0 };
    SEL sel = NSSelectorFromString(@"iconImageInfo");
    if (view != nil && [view respondsToSelector:sel]) {
        @try {
            TCPIconImageInfo got = ((TCPIconImageInfo (*)(id, SEL))objc_msgSend)(view, sel);
            if (got.size.width >= 8 && got.size.height >= 8) return got;
        } @catch (NSException *e) { (void)e; }
    }
    if (view != nil) {
        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"bounds"));
        if (bounds.size.width >= 8 && bounds.size.height >= 8) {
            info.size = bounds.size;
            info.cornerRadius = bounds.size.width * 0.2237;
        }
    }
    return info;
}

void TCPRefreshIconImages(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            TCPRefreshIconImages();
        });
        return;
    }

    // 1.0.41（修「注销后进安全模式」）：构造函数的启动轮会走到这里（TCPReload(NO) →
    // sitesChanged → 本函数），而本函数下面第一件事就是 [UIApplication sharedApplication]、
    // 再往下经 TCPFolderNotifyRecalc 拿 SBIconController 共享实例 —— 构造函数跑在 main()
    // 之前，这两样都不存在（+[UIScreen mainScreen] 断言 → SIGABRT，崩溃报告
    // SpringBoard-2026-11-03-040505.ips）。闸门没开一律返回：+2 秒开闸那一步
    // （ThemeCorePlusMain.m 的 TCPStoreEnableImageWork 之后）与面板刷新请求照旧会刷。
    if (!TCPStoreImageWorkReady()) return;

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
        // 1.0.24（借鉴 MarkTheme16）：优先用 iOS 16 正式的换图 API
        // -updateImageContentsWithImage:imageAppearance:isRealContentsImage:animated:
        // 它带外观参数、无交叉淡化闪烁；拿不到主题图或视图不响应时退回 updateImageAnimated:NO。
        TCPIconImageInfo viewInfo = TCPViewIconImageInfoValue(view);
        UIImage *themedImage = TCPThemedIconImage(icon, viewInfo);
        SEL updateContents = NSSelectorFromString(@"updateImageContentsWithImage:imageAppearance:isRealContentsImage:animated:");
        BOOL done = NO;
        if (themedImage != nil && [view respondsToSelector:updateContents]) {
            @try {
                ((void (*)(id, SEL, id, id, BOOL, BOOL))objc_msgSend)(
                    view, updateContents, themedImage, nil, YES, NO);
                done = YES;
            } @catch (NSException *e) { (void)e; }
        }
        if (!done) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(view, updateImage, NO);
        }
        pushed++;

        // 4) 顺手把刚重画完的视图体检一遍：屏幕上那几张 UIImageView 手里到底是我们的图还是原图。
        //    原来这个体检函数写好了却没人调，所以诊断里永远没有 pix{}（2026-10-30 15:5x 接上）。
        TCPInspectIconView(view);
    }

    sRefreshPushed += (NSInteger)pushed;
    os_log(TCPLogHandle(), "TCPS_REFRESH views=%lu pushed=%lu model=%ld cache=%ld purge=%{public}@",
           (unsigned long)views.count, (unsigned long)pushed, (long)sRefreshModel, (long)sRefreshCache,
           sRefreshPurgeName ?: @"-");
    // 1.0.18：热刷新也收拾角标视图 —— 原来只刷 SBIconImageView，角标还攥着旧图。
    TCPBadgeRefreshVisible();
    // 1.0.18：热刷新也重画时钟视图 —— 时钟视图从不走 layoutSubviews（只靠 30 秒 tick），
    // 点「刷新图标」后要立即重画，否则时钟素材要等 30 秒或注销才换。
    TCPClockTick();
    // 1.0.22：热刷新也通知文件夹 mini 拼图重算（换主题后收起状态才显示主题格子）。
    TCPFolderNotifyRecalc();
    // 1.0.24：每次刷新都再试一次挂缓存层站 —— SBHIconImageCache 属于 SpringBoardHome，
    // 启动早期（0/0.3/1/2 秒补挂轮）可能还没 dlopen，那时候 objc_copyClassList 扫不到它。
    // 刷新拍（0 秒 / 2.5 秒 / 用户点刷新）时重试；函数幂等，已挂过直接跳过。
    TCPInstallIconCacheLayerSites();
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
    // 1.0.31：固定类名直取（原来按 "SBIconImageView" 前缀扫全表）。
    NSArray<NSString *> *viewClasses = @[ @"SBIconImageView" ];
    NSArray<NSString *> *selectors = @[ @"displayedImage", @"contentsImage",
                                        @"squareContentsImage" ];
    NSUInteger installed = TCPInstallSitesFromClassList(viewClasses, selectors,
                                                        TCPSiteKindDisplayImage, NO);
    if (installed > 0) {
        os_log(TCPLogHandle(), "TCPS_ICON_DISPLAY_SITES +%lu", (unsigned long)installed);
    }
}

#pragma mark - 1.0.42：Bundles 资源替换（iOS「设置」里的小图标）

// 主题里的 Bundles/<bundleid>/<图片名>[@2x|@3x].png 直接顶掉那个 bundle 里的同名图。
// 用户点名的用法：iOS「设置」每一行左边的小图标（通用 / 显示与亮度 / Wi-Fi / 蓝牙…）
// 来自 com.apple.preferences-ui-framework，主题给了同名图就该在设置里显示出来。
//
// 挂点：+[UIImage imageNamed:]（走 mainBundle）与
//       +[UIImage imageNamed:inBundle:compatibleWithTraitCollection:]（调用方自己传 framework 的 bundle）。
// 设置走的就是这两条。它们也是全进程最热的图片入口，所以**先**用名字集合 O(1) 排除，
// 名字没在主题里出现过就直接走原实现 —— 绝大多数调用只多一次 NSSet 查询。
//
// 铁律（1.4.0 那次进安全模式的教训）：这里只在「主线程 + UIApplication 已经存在」时读一次
// 屏幕倍率并缓存；构造函数阶段一律用 2，绝不碰 UIScreen。

static NSSet<NSString *> *sBundleAssetNames = nil;
static NSUInteger sBundleAssetNamesGeneration = NSUIntegerMax;
static NSInteger sBundleAssetHitTotal = 0;

static UIImage *(*sBundleAssetImageNamedOrig)(id, SEL, NSString *) = NULL;
static UIImage *(*sBundleAssetImageNamedInBundleOrig)(id, SEL, NSString *, NSBundle *, UITraitCollection *) = NULL;

static NSSet<NSString *> *TCPBundleAssetNames(void) {
    TCPThemeStore *store = [TCPThemeStore shared];
    NSUInteger generation = store.generation;
    if (sBundleAssetNames == nil || sBundleAssetNamesGeneration != generation) {
        sBundleAssetNames = [store bundleAssetNames];
        sBundleAssetNamesGeneration = generation;
    }
    return sBundleAssetNames;
}

static CGFloat TCPBundleAssetScale(void) {
    static CGFloat cached = 0;
    if (cached > 0) return cached;
    if (![NSThread isMainThread]) return 2.0;
    Class appClass = objc_getClass("UIApplication");
    if (appClass == Nil) return 2.0;
    BOOL ready = NO;
    @try {
        id app = ((id (*)(id, SEL))objc_msgSend)(appClass, NSSelectorFromString(@"sharedApplication"));
        ready = (app != nil);
    } @catch (__unused NSException *exception) {
        ready = NO;
    }
    if (!ready) return 2.0;
    @try {
        cached = [UIScreen mainScreen].scale;
    } @catch (__unused NSException *exception) {
        cached = 0;
    }
    return cached > 0 ? cached : 2.0;
}

// 命中就返回主题那张图（imageWithContentsOfFile: 会按文件名里的 @2x/@3x 定 scale）。
static UIImage *TCPBundleAssetReplacement(NSString *name, NSBundle *bundle) {
    if (name.length == 0) return nil;
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;
    if (![TCPBundleAssetNames() containsObject:name.lowercaseString]) return nil;

    NSString *bundleID = nil;
    @try {
        bundleID = bundle.bundleIdentifier;
    } @catch (__unused NSException *exception) {
        bundleID = nil;
    }
    if (bundleID.length == 0) {
        bundleID = [[NSBundle mainBundle] bundleIdentifier];
    }
    CGFloat scale = TCPBundleAssetScale();
    NSString *path = [store bundleAssetPathForBundleID:bundleID name:name scale:scale];
    if (path.length == 0 && [store isPreferencesBundleID:bundleID]) {
        // bundle id 与主题目录名对不上时的兜底：这个名字在主题里只出现一次就用它。
        path = [store bundleAssetPathForUniqueName:name scale:scale];
    }
    if (path.length == 0) return nil;

    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (image == nil) return nil;
    sBundleAssetHitTotal++;
    [store noteBundleAssetHit:[NSString stringWithFormat:@"%@:%@", bundleID ?: @"-", name]];
    return image;
}

static UIImage *TCPBundleAssetImageNamedHook(id self, SEL _cmd, NSString *name) {
    UIImage *replacement = TCPBundleAssetReplacement(name, nil);
    if (replacement != nil) return replacement;
    return sBundleAssetImageNamedOrig ? sBundleAssetImageNamedOrig(self, _cmd, name) : nil;
}

static UIImage *TCPBundleAssetImageNamedInBundleHook(id self, SEL _cmd, NSString *name,
                                                     NSBundle *bundle, UITraitCollection *traits) {
    UIImage *replacement = TCPBundleAssetReplacement(name, bundle);
    if (replacement != nil) return replacement;
    return sBundleAssetImageNamedInBundleOrig
        ? sBundleAssetImageNamedInBundleOrig(self, _cmd, name, bundle, traits)
        : nil;
}

void TCPInstallBundleAssetSites(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class imageClass = [UIImage class];
        MSHookMessageEx(object_getClass(imageClass), @selector(imageNamed:),
                        (IMP)TCPBundleAssetImageNamedHook, (IMP *)&sBundleAssetImageNamedOrig);
        MSHookMessageEx(object_getClass(imageClass),
                        @selector(imageNamed:inBundle:compatibleWithTraitCollection:),
                        (IMP)TCPBundleAssetImageNamedInBundleHook,
                        (IMP *)&sBundleAssetImageNamedInBundleOrig);
        os_log(TCPLogHandle(), "TCPS_BUNDLE_ASSETS names=%lu",
               (unsigned long)TCPBundleAssetNames().count);
    });
}
