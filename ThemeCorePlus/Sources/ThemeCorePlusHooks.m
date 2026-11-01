//
//  ThemeCorePlusHooks.m —— 「一站一槽」站点框架（见头文件里的 R1/R2）。
//
#import "ThemeCorePlusHooks.h"
#import <substrate.h>
#import <dlfcn.h>   // dladdr：反查某个 IMP 属于哪个镜像（见文末「谁 hook 了它」）
#import <mach-o/dyld.h>   // 1.0.31：dyld_register_func_for_add_image（框架加载回调，替代定时全表扫描）

#define TCP_SLOT_COUNT 24

#define TCP_SLOT_INDEX_LIST(X) \
    X(0)  X(1)  X(2)  X(3)  X(4)  X(5)  X(6)  X(7) \
    X(8)  X(9)  X(10) X(11) X(12) X(13) X(14) X(15) \
    X(16) X(17) X(18) X(19) X(20) X(21) X(22) X(23)

#pragma mark - 站点账本

static NSMutableArray<NSString *> *sSiteDescriptions = nil;
static NSMutableSet<NSString *> *sInstalledKeys = nil;
static NSUInteger sSlotsUsed[TCPSiteKindCount];
static NSLock *sSiteLock = nil;

static void TCPSiteBook(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sSiteDescriptions = [NSMutableArray array];
        sInstalledKeys = [NSMutableSet set];
        sSiteLock = [[NSLock alloc] init];
    });
}

BOOL TCPClassDeclaresMethod(Class cls, SEL sel) {
    if (cls == Nil || sel == NULL) return NO;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) {
            found = YES;
            break;
        }
    }
    if (methods) free(methods);
    return found;
}

NSUInteger TCPTotalSiteCount(void) {
    TCPSiteBook();
    [sSiteLock lock];
    NSUInteger total = sSiteDescriptions.count;
    [sSiteLock unlock];
    return total;
}

NSArray<NSString *> *TCPSiteDescriptions(void) {
    TCPSiteBook();
    [sSiteLock lock];
    NSArray *copy = [sSiteDescriptions copy];
    [sSiteLock unlock];
    return copy;
}

static CGFloat TCPUIScale(void) {
    static CGFloat scale = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat s = [UIScreen mainScreen].scale;
        scale = (s >= 1.0) ? s : 3.0;
    });
    return scale;
}

#pragma mark - 图标站：结构体进、UIImage 出

typedef UIImage *(*TCPIconImageInfoFn)(id, SEL, TCPIconImageInfo);

// 重入保护（2026-10-30 安全模式崩溃后加）：本机 SpringBoard 里还有别的插件用 Logos
// 挂在同一条链上（崩溃栈里是 $SHARED_HOOKS$+SBLeafIcon$iconImageWithInfo$ 与
// SearchUIHooks$SBIconImageView$contentsImage），我们取主题图这件事一旦绕回同一条
// 取图链，就会自己套自己，一路重入到栈上的指针全废（EXC_BAD_ACCESS at 0x1f，
// consecutiveCrashCount=7 → 每次都进安全模式）。所以同一线程内只要还在我们自己的
// 取图流程里，就直接把调用交给原实现：宁可这一张图不主题化，也不能再重入。
static __thread int tcpIconDepth = 0;

// 打点：装完机读诊断就知道「图标站到底有没有被问、跳过几张、换成几张」，
// 不必再靠反复注销看屏幕。old 版本的诊断串里没有 icon{，所以它也是「新代码跑起来了」的标记。
static long sIconLook = 0, sIconSkip = 0, sIconMiss = 0, sIconHit = 0;

NSString *TCPIconProbeReport(void) {
    return [NSString stringWithFormat:@"icon{look=%ld,skip=%ld,miss=%ld,hit=%ld}",
            sIconLook, sIconSkip, sIconMiss, sIconHit];
}

// 参数可信吗：结构体是 4 个 double、按 HFA 走 d0–d3 进来，尺寸/缩放不可能是 0 或 NaN。
// 不像人样的参数就当自己没被问过，原样转发（绝不在自己这里崩）。
static BOOL TCPIconInfoUsable(TCPIconImageInfo info) {
    CGFloat widths[2] = { info.size.width, info.size.height };
    for (int i = 0; i < 2; i++) {
        if (!(widths[i] > 0.0) || widths[i] > 8192.0) return NO;
    }
    if (!(info.scale > 0.0) || info.scale > 16.0) return NO;
    return YES;
}

static UIImage *TCPIconHandle(IMP *slot, id self, SEL _cmd, TCPIconImageInfo info) {
    IMP original = *slot;
    if (original == NULL) return nil;
    __sync_fetch_and_add(&sIconLook, 1);
    if (!TCPIconInfoUsable(info)) {
        __sync_fetch_and_add(&sIconSkip, 1);
        return ((TCPIconImageInfoFn)original)(self, _cmd, info);
    }
    if (tcpIconDepth > 0) {
        return ((TCPIconImageInfoFn)original)(self, _cmd, info);
    }
    tcpIconDepth++;
    UIImage *themed = TCPThemedIconImage(self, info);
    tcpIconDepth--;
    if (themed != nil) {
        __sync_fetch_and_add(&sIconHit, 1);
        return themed;
    }
    __sync_fetch_and_add(&sIconMiss, 1);
    TCPNoteIconSiteClass([NSString stringWithFormat:@"%@:%@", NSStringFromClass([self class]),
                          TCPIconIdentifierOf(self) ?: @"?"]);
    UIImage *originalImage = ((TCPIconImageInfoFn)original)(self, _cmd, info);
    // 时钟 / 日历：系统那张图（表盘+指针 / 底图+日期）拿到手，再和主题素材叠成一张。
    // 别的图标不走这里，原样返回系统图。
    if (TCPIconNeedsSystemComposite(self)) {
        TCPNoteDynamicSeen();
        if ([originalImage isKindOfClass:[UIImage class]]) {
            UIImage *composed = TCPCompositeDynamicIcon(self, info, originalImage);
            if (composed != nil) {
                __sync_fetch_and_add(&sIconHit, 1);
                return composed;
            }
        } else {
            TCPNoteDynamicNotImage();
        }
    }
    return originalImage;
}

#define TCP_DEFINE_ICON_SLOT(n)                                                \
    static IMP tcpIconOrig##n = NULL;                                          \
    static UIImage *tcpIconHook##n(id self, SEL _cmd, TCPIconImageInfo info) {  \
        return TCPIconHandle(&tcpIconOrig##n, self, _cmd, info);                \
    }
TCP_SLOT_INDEX_LIST(TCP_DEFINE_ICON_SLOT)

#define TCP_SLOT_PTR_ICON(n) &tcpIconOrig##n,
#define TCP_FN_PTR_ICON(n) (IMP)tcpIconHook##n,
static IMP *const kIconSlotStorage[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_SLOT_PTR_ICON) };
static const IMP kIconHookFns[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_FN_PTR_ICON) };

#pragma mark - 类型安全替换：原返回什么类型，就还什么类型

// iOS 16.7 实测（icli probe，2026-10-30）：
//   +[SBIconBadgeView _checkoutImageForText:font:highlighted:] 返回的是
//   SBHIconAccessoryCountedMapImageTuple —— 「一张图 + 一个计数键」的元组，不是 UIImage。
//   计数键不是方法（respondsToSelector 为假）而是 KVC 属性，值形如 "3:.SFUI-Semibold:12.0:0"；
//   图可以用 setValue:forKey:@"image" 就地换掉。
// 拿 UIImage 顶替元组 = 调用方向 UIImage 发它不认识的选择器 = unrecognized selector →
// abort → SpringBoard 安全模式（2026-10-30 反复崩就是这么来的，崩点
// -[SBIconBadgeView _configureAnimatedForText:highlighted:animator:] 的 +240）。
// 所以每个包装函数一律：先跑原实现拿到真正的返回对象，再只把里面的图换掉，绝不换类型。
static BOOL TCPIsCountedMapImageTuple(id object) {
    if (object == nil) return NO;
    Class cls = object_getClass(object);
    if (cls == Nil) return NO;
    const char *name = class_getName(cls);
    if (name == NULL) return NO;
    if (![@(name) containsString:@"CountedMapImageTuple"]) return NO;
    return [object respondsToSelector:NSSelectorFromString(@"image")];
}

id TCPThemedImageReplacement(id original, UIImage *themed) {
    if (themed == nil || original == nil) return original;
    if ([original isKindOfClass:[UIImage class]]) return themed;
    if (TCPIsCountedMapImageTuple(original)) {
        @try {
            [original setValue:themed forKey:@"image"];
        } @catch (NSException *exception) {
            (void)exception;
        }
        return original;
    }
    return original;
}

// 系统为这段文本准备的角标图尺寸 = 屏幕上角标该占多大。取回来当「盒子」交给角标合成，
// 这样素材（@3x 补倍率后 25 点）与系统盒子（26 点上下）对得上，圆还是圆。
// result 可能是 UIImage，也可能是 SBHIconAccessoryCountedMapImageTuple（它的 image 是 KVC 属性）。
static CGSize TCPBadgeSystemBoxSize(id result) {
    id image = nil;
    if ([result isKindOfClass:[UIImage class]]) {
        image = result;
    } else if (TCPIsCountedMapImageTuple(result)) {
        @try {
            image = [result valueForKey:@"image"];
        } @catch (NSException *exception) {
            (void)exception;
        }
    }
    if (![image isKindOfClass:[UIImage class]]) return CGSizeZero;
    return ((UIImage *)image).size;
}

#pragma mark - 角标底板图站：无参

static id TCPBadgeBackHandle(IMP *slot, id self, SEL _cmd) {
    IMP original = *slot;
    if (original == NULL) return nil;
    id result = ((id (*)(id, SEL))original)(self, _cmd);
    UIImage *themed = TCPThemedBadgeBackgroundInBox(TCPUIScale(), TCPBadgeSystemBoxSize(result));
    TCPBadgeNoteStation(TCPSiteKindBadgeBackground, themed != nil);
    return TCPThemedImageReplacement(result, themed);
}

#define TCP_DEFINE_BADGEBACK_SLOT(n)                                          \
    static IMP tcpBadgeBackOrig##n = NULL;                                    \
    static id tcpBadgeBackHook##n(id self, SEL _cmd) {                        \
        return TCPBadgeBackHandle(&tcpBadgeBackOrig##n, self, _cmd);          \
    }
TCP_SLOT_INDEX_LIST(TCP_DEFINE_BADGEBACK_SLOT)

#define TCP_SLOT_PTR_BADGEBACK(n) &tcpBadgeBackOrig##n,
#define TCP_FN_PTR_BADGEBACK(n) (IMP)tcpBadgeBackHook##n,
static IMP *const kBadgeBackSlotStorage[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_SLOT_PTR_BADGEBACK) };
static const IMP kBadgeBackHookFns[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_FN_PTR_BADGEBACK) };

#pragma mark - 角标 tuple 站：无参

static id TCPBadgeTupleHandle(IMP *slot, id self, SEL _cmd) {
    IMP original = *slot;
    if (original == NULL) return nil;
    id result = ((id (*)(id, SEL))original)(self, _cmd);
    UIImage *themed = TCPThemedBadgeBackgroundInBox(TCPUIScale(), TCPBadgeSystemBoxSize(result));
    TCPBadgeNoteStation(TCPSiteKindBadgeTuple, themed != nil);
    return TCPThemedImageReplacement(result, themed);
}

#define TCP_DEFINE_BADGETUPLE_SLOT(n)                                         \
    static IMP tcpBadgeTupleOrig##n = NULL;                                   \
    static id tcpBadgeTupleHook##n(id self, SEL _cmd) {                       \
        return TCPBadgeTupleHandle(&tcpBadgeTupleOrig##n, self, _cmd);        \
    }
TCP_SLOT_INDEX_LIST(TCP_DEFINE_BADGETUPLE_SLOT)

#define TCP_SLOT_PTR_BADGETUPLE(n) &tcpBadgeTupleOrig##n,
#define TCP_FN_PTR_BADGETUPLE(n) (IMP)tcpBadgeTupleHook##n,
static IMP *const kBadgeTupleSlotStorage[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_SLOT_PTR_BADGETUPLE) };
static const IMP kBadgeTupleHookFns[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_FN_PTR_BADGETUPLE) };

#pragma mark - 角标成图站：(文字, 字体, 高亮) 进

typedef id (*TCPBadgeTextFn)(id, SEL, NSString *, UIFont *, BOOL);

// —— 0.9.18 卡顿/发热：角标成图缓存 ——
// 这个站每被问一次就重新 UIGraphics 合成一张**新** UIImage，而系统是按「图对象变了没」决定
// 要不要重画角标：每次都给新对象，它就一直重画、一直再回来问，主线程被锁在
// 「合成 → 重画 → 再问」的环里（用户 2026-10-31 09:13「应用图标主题和角标素材 手机特别卡」
// 「发热烫手」）。同样的（主题代 / 文字 / 字体 / 倍率 / 盒子 / 单层闸门）只合成一次，
// 之后原样交回**同一张**图 —— 图没变，系统就不重画，环断掉。
static NSCache<NSString *, UIImage *> *sBadgeTextImageCache = nil;

static NSCache<NSString *, UIImage *> *TCPBadgeTextCache(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sBadgeTextImageCache = [NSCache new];
        sBadgeTextImageCache.countLimit = 128;
    });
    return sBadgeTextImageCache;
}

static NSString *TCPBadgeTextCacheKey(NSString *text, UIFont *font, CGFloat scale,
                                      CGSize box, BOOL backgroundServed) {
    TCPThemeStore *store = [TCPThemeStore shared];
    return [NSString stringWithFormat:@"%lu|%@|%@|%.1f|%.2fx%.2f|%d|%d|%.1f",
            (unsigned long)store.generation, text ?: @"-",
            font.fontName ?: @"-", (double)font.pointSize,
            (double)box.width, (double)box.height,
            (int)backgroundServed, store.active ? 1 : 0, (double)scale];
}

static id TCPBadgeTextHandle(IMP *slot, id self, SEL _cmd, NSString *text, UIFont *font, BOOL highlighted) {
    IMP original = *slot;
    if (original == NULL) return nil;
    id result = ((TCPBadgeTextFn)original)(self, _cmd, text, font, highlighted);
    // 角标盒子的高度就是屏幕上角标的高：一个字时宽也取这个值 → 正圆；
    // 两个以上再按文字宽度加宽成圆头胶囊。盒子拿不到才退回素材自己的点数。
    CGSize box = TCPBadgeSystemBoxSize(result);
    // 单层闸门（0.9.4）：底板站这一轮已经换过底板了，这里就只交数字（透明底）——
    // 两站都画底板的话屏幕上就是同一张底板叠两层（用户说的「二个图层」）。
    BOOL backgroundServed = TCPBadgeBackgroundServed();
    CGFloat scale = TCPUIScale();
    NSString *key = text.length > 0 ? TCPBadgeTextCacheKey(text, font, scale, box, backgroundServed) : nil;
    UIImage *themed = key != nil ? [TCPBadgeTextCache() objectForKey:key] : nil;
    if (themed == nil) {
        themed = backgroundServed
            ? TCPThemedBadgeTextOnlyImage(text, font, scale, box)
            : TCPThemedBadgeTextImage(text, font, scale, box);
        if (themed != nil && key != nil) [TCPBadgeTextCache() setObject:themed forKey:key];
    }
    // 0.9.11：交出去的是「底板 + 数字」整图时，角标视图侧要把系统自己那层底板藏掉，
    // 否则屏幕上就是「系统底板 + 主题底板」两层（本机 iOS 16.7 底板站根本不存在，
    // 永远是这条路：诊断 gate=composed）。
    if (!backgroundServed && themed != nil) TCPBadgeNoteComposedServed();
    TCPBadgeNoteStation(TCPSiteKindBadgeTextImage, themed != nil);
    return TCPThemedImageReplacement(result, themed);
}

#define TCP_DEFINE_BADGETEXT_SLOT(n)                                          \
    static IMP tcpBadgeTextOrig##n = NULL;                                    \
    static id tcpBadgeTextHook##n(id self, SEL _cmd, NSString *text,          \
                                        UIFont *font, BOOL highlighted) {      \
        return TCPBadgeTextHandle(&tcpBadgeTextOrig##n, self, _cmd, text, font, highlighted); \
    }
TCP_SLOT_INDEX_LIST(TCP_DEFINE_BADGETEXT_SLOT)

#define TCP_SLOT_PTR_BADGETEXT(n) &tcpBadgeTextOrig##n,
#define TCP_FN_PTR_BADGETEXT(n) (IMP)tcpBadgeTextHook##n,
static IMP *const kBadgeTextSlotStorage[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_SLOT_PTR_BADGETEXT) };
static const IMP kBadgeTextHookFns[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_FN_PTR_BADGETEXT) };

#pragma mark - 文件夹底板站：无参

static id TCPFolderBackHandle(IMP *slot, id self, SEL _cmd) {
    IMP original = *slot;
    if (original == NULL) return nil;
    id result = ((id (*)(id, SEL))original)(self, _cmd);
    return TCPThemedImageReplacement(result, TCPThemedFolderBackground(TCPUIScale()));
}

#define TCP_DEFINE_FOLDERBACK_SLOT(n)                                         \
    static IMP tcpFolderBackOrig##n = NULL;                                   \
    static id tcpFolderBackHook##n(id self, SEL _cmd) {                       \
        return TCPFolderBackHandle(&tcpFolderBackOrig##n, self, _cmd);        \
    }
TCP_SLOT_INDEX_LIST(TCP_DEFINE_FOLDERBACK_SLOT)

#define TCP_SLOT_PTR_FOLDERBACK(n) &tcpFolderBackOrig##n,
#define TCP_FN_PTR_FOLDERBACK(n) (IMP)tcpFolderBackHook##n,
static IMP *const kFolderBackSlotStorage[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_SLOT_PTR_FOLDERBACK) };
static const IMP kFolderBackHookFns[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_FN_PTR_FOLDERBACK) };

#pragma mark - 显示层站：无参、出显示图（UIImage / CGImage）

// 包装函数只做两件事：跑原实现拿到真正的返回对象，再交给 TCPThemedDisplayReplacement
// 按类型严丝合缝地换。绝不把 UIImage 硬塞给一个要 CGImage 的调用方。
static id TCPDisplayHandle(IMP *slot, id self, SEL _cmd) {
    IMP original = *slot;
    if (original == NULL) return nil;
    id result = ((id (*)(id, SEL))original)(self, _cmd);
    return TCPThemedDisplayReplacement(result, self);
}

#define TCP_DEFINE_DISPLAY_SLOT(n)                                            \
    static IMP tcpDisplayOrig##n = NULL;                                      \
    static id tcpDisplayHook##n(id self, SEL _cmd) {                          \
        return TCPDisplayHandle(&tcpDisplayOrig##n, self, _cmd);              \
    }
TCP_SLOT_INDEX_LIST(TCP_DEFINE_DISPLAY_SLOT)

#define TCP_SLOT_PTR_DISPLAY(n) &tcpDisplayOrig##n,
#define TCP_FN_PTR_DISPLAY(n) (IMP)tcpDisplayHook##n,
static IMP *const kDisplaySlotStorage[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_SLOT_PTR_DISPLAY) };
static const IMP kDisplayHookFns[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_FN_PTR_DISPLAY) };

#pragma mark - 文件夹 mini 格子站：(CGSize, icon, SBIconImageInfo) 进、UIImage 出

// SBFolderIconImageCache 的 -gridCellImageOfSize:forIcon:iconImageInfo:
// 签名 (id, SEL, CGSize, id, SBIconImageInfo) → UIImage。第三个结构体 SBIconImageInfo 与
// TCPIconImageInfo 完全同构（4 double HFA，_Static_assert 锁死），所以 C 原型直接写
// TCPIconImageInfo —— 编译器按正确 ABI 生成调用，绝不手算寄存器（0.6.0 / 1.0.8 都是
// 手算/抄错结构体崩进安全模式）。
typedef UIImage *(*TCPFolderGridCellFn)(id, SEL, CGSize, id, TCPIconImageInfo);

static long sFolderGridLook = 0, sFolderGridHit = 0, sFolderGridMiss = 0;

NSString *TCPFolderGridCellProbeReport(void) {
    return [NSString stringWithFormat:@"grid{look=%ld,hit=%ld,miss=%ld}",
            sFolderGridLook, sFolderGridHit, sFolderGridMiss];
}

static UIImage *TCPFolderGridHandle(IMP *slot, id self, SEL _cmd, CGSize size,
                                    id icon, TCPIconImageInfo info) {
    IMP original = *slot;
    if (original == NULL) return nil;
    __sync_fetch_and_add(&sFolderGridLook, 1);
    // 先跑原实现拿系统那张格子图：参数可信时用它做尺寸/占位参考，参数不可信则原样退回。
    UIImage *originalImage = ((TCPFolderGridCellFn)original)(self, _cmd, size, icon, info);
    if (!TCPIconInfoUsable(info)) {
        return originalImage;   // 结构体读坏了（size/scale 是垃圾值），绝不在自己这里崩
    }
    // 参数里直接带着「这一格是哪个 App」，直接按 bundleID 出主题图。
    UIImage *themed = TCPThemedIconImage(icon, info);
    if (themed == nil) {
        __sync_fetch_and_add(&sFolderGridMiss, 1);
        return originalImage;
    }
    __sync_fetch_and_add(&sFolderGridHit, 1);
    return themed;
}

#define TCP_DEFINE_FOLDERGRID_SLOT(n)                                          \
    static IMP tcpFolderGridOrig##n = NULL;                                    \
    static UIImage *tcpFolderGridHook##n(id self, SEL _cmd, CGSize size,       \
                                          id icon, TCPIconImageInfo info) {     \
        return TCPFolderGridHandle(&tcpFolderGridOrig##n, self, _cmd, size, icon, info); \
    }
TCP_SLOT_INDEX_LIST(TCP_DEFINE_FOLDERGRID_SLOT)

#define TCP_SLOT_PTR_FOLDERGRID(n) &tcpFolderGridOrig##n,
#define TCP_FN_PTR_FOLDERGRID(n) (IMP)tcpFolderGridHook##n,
static IMP *const kFolderGridSlotStorage[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_SLOT_PTR_FOLDERGRID) };
static const IMP kFolderGridHookFns[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_FN_PTR_FOLDERGRID) };

// SBFolderIconImageCache 的 -genericMiniGridImage：零参数，返回文件夹收起状态那张 2×2 拼图。
typedef UIImage *(*TCPFolderMiniGridFn)(id, SEL);

static long sFolderMiniGridLook = 0, sFolderMiniGridHit = 0;

NSString *TCPFolderMiniGridProbeReport(void) {
    return [NSString stringWithFormat:@"minigrid{look=%ld,hit=%ld}",
            sFolderMiniGridLook, sFolderMiniGridHit];
}

static UIImage *TCPFolderMiniGridHandle(IMP *slot, id self, SEL _cmd) {
    IMP original = *slot;
    if (original == NULL) return nil;
    __sync_fetch_and_add(&sFolderMiniGridLook, 1);
    // 1.0.20 纯探针：只计数，原样返回系统图。装完看 minigrid{look} 是否 >0，
    // 坐实 genericMiniGridImage 是不是 mini 拼图的真入口，下一版再精准叠主题图。
    UIImage *originalImage = ((TCPFolderMiniGridFn)original)(self, _cmd);
    return originalImage;
}

#define TCP_DEFINE_FOLDERMINI_SLOT(n)                                          \
    static IMP tcpFolderMiniOrig##n = NULL;                                    \
    static UIImage *tcpFolderMiniHook##n(id self, SEL _cmd) {                  \
        return TCPFolderMiniGridHandle(&tcpFolderMiniOrig##n, self, _cmd);     \
    }
TCP_SLOT_INDEX_LIST(TCP_DEFINE_FOLDERMINI_SLOT)

#define TCP_SLOT_PTR_FOLDERMINI(n) &tcpFolderMiniOrig##n,
#define TCP_FN_PTR_FOLDERMINI(n) (IMP)tcpFolderMiniHook##n,
static IMP *const kFolderMiniSlotStorage[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_SLOT_PTR_FOLDERMINI) };
static const IMP kFolderMiniHookFns[TCP_SLOT_COUNT] = { TCP_SLOT_INDEX_LIST(TCP_FN_PTR_FOLDERMINI) };

#pragma mark - 槽位表

typedef struct {
    IMP *const *storage;
    const IMP *hooks;
} TCPSlotGroup;

static const TCPSlotGroup kSlotGroups[TCPSiteKindCount] = {
    { kIconSlotStorage,        kIconHookFns },        // TCPSiteKindIconImageInfo
    { kBadgeBackSlotStorage,   kBadgeBackHookFns },   // TCPSiteKindBadgeBackground
    { kBadgeTupleSlotStorage,  kBadgeTupleHookFns },  // TCPSiteKindBadgeTuple
    { kBadgeTextSlotStorage,   kBadgeTextHookFns },   // TCPSiteKindBadgeTextImage
    { kFolderBackSlotStorage,  kFolderBackHookFns },  // TCPSiteKindFolderBackground
    { kDisplaySlotStorage,     kDisplayHookFns },     // TCPSiteKindDisplayImage
    { kFolderGridSlotStorage,  kFolderGridHookFns },  // TCPSiteKindFolderGridCell
    { kFolderMiniSlotStorage,  kFolderMiniHookFns },  // TCPSiteKindFolderMiniGrid
};

#pragma mark - 挂站

static BOOL TCPInstallOneSiteKind(Class cls, SEL sel, TCPSiteKind kind, BOOL instanceOnly) {
    if (cls == Nil || sel == NULL || kind >= TCPSiteKindCount) return NO;

    // R2：类自己声明了才挂。默认类方法优先；instanceOnly=YES 时只认实例方法
    // （SBFolderIconImageCache 这类类/实例同名选择器，系统走实例方法，挂到类方法上等于白挂）。
    BOOL asClassMethod = !instanceOnly && TCPClassDeclaresMethod(object_getClass(cls), sel);
    BOOL asInstanceMethod = TCPClassDeclaresMethod(cls, sel);
    if (instanceOnly) {
        asClassMethod = NO;
    }
    if (!asClassMethod && !asInstanceMethod) return NO;
    Class target = asClassMethod ? object_getClass(cls) : cls;
    NSString *key = [NSString stringWithFormat:@"%@%@:%@",
                     asClassMethod ? @"+" : @"-", NSStringFromClass(cls), NSStringFromSelector(sel)];

    TCPSiteBook();
    [sSiteLock lock];
    BOOL already = [sInstalledKeys containsObject:key];
    NSUInteger index = sSlotsUsed[kind];
    BOOL exhausted = (index >= TCP_SLOT_COUNT);
    [sSiteLock unlock];
    if (already || exhausted) return NO;

    IMP *slot = kSlotGroups[kind].storage[index];
    IMP hook = kSlotGroups[kind].hooks[index];
    IMP original = NULL;
    MSHookMessageEx(target, sel, hook, &original);
    if (original == NULL) return NO;
    *slot = original;

    [sSiteLock lock];
    sSlotsUsed[kind] = index + 1;
    [sInstalledKeys addObject:key];
    [sSiteDescriptions addObject:key];
    [sSiteLock unlock];
    return YES;
}

// 1.0.23：绕过 R2（「类自己声明才挂」）的强制实例方法挂载。
// 用途：SBHIconImageCache 这类缓存类，iconImageWithInfo: 可能是父类/分类声明的，
// class_copyMethodList（R2 用的）列不出它 → 挂不上（1.0.22 实测 sites 里没有缓存层站）。
// 这里改用 class_getInstanceMethod（含继承），只要实例能响应该方法就挂，签名仍走槽位表。
static BOOL TCPInstallOneSiteKindForced(Class cls, SEL sel, TCPSiteKind kind) {
    if (cls == Nil || sel == NULL || kind >= TCPSiteKindCount) return NO;
    if (class_getInstanceMethod(cls, sel) == NULL) return NO;   // 含继承

    NSString *key = [NSString stringWithFormat:@"-%@:%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
    TCPSiteBook();
    [sSiteLock lock];
    BOOL already = [sInstalledKeys containsObject:key];
    NSUInteger index = sSlotsUsed[kind];
    BOOL exhausted = (index >= TCP_SLOT_COUNT);
    [sSiteLock unlock];
    if (already || exhausted) return NO;

    IMP *slot = kSlotGroups[kind].storage[index];
    IMP hook = kSlotGroups[kind].hooks[index];
    IMP original = NULL;
    MSHookMessageEx(cls, sel, hook, &original);
    if (original == NULL) return NO;
    *slot = original;

    [sSiteLock lock];
    sSlotsUsed[kind] = index + 1;
    [sInstalledKeys addObject:key];
    [sSiteDescriptions addObject:key];
    [sSiteLock unlock];
    return YES;
}

// 1.0.31：固定类名清单直取（**不扫类表**）。
//
// 为什么改（用户 2026-11-01 20:00「这插件从一开始就多次加载才能进桌面，是不是架构没写好」）：
// 原来每轮挂站都走 objc_copyClassList 把全进程几千个类拷出来，再对每个类做字符串前缀比对
// （前缀里还有 "SBH"、"SBIcon" 这种命中整个 SpringBoardHome 的宽前缀），命中后还要试 4 个
// 选择器。启动时主线程连做 4 轮（0 / 0.3 / 1 / 2 秒），SpringBoard 的看门狗预算被吃光 →
// 进程被杀 → 系统拉起 → 再崩 → 用户看到的就是「黑屏反复加载，要好几次才进桌面」。
//
// 对照参考（2026-11-01 20:0x 实地扫描本机五个主题引擎，全部零扫描）：
//   MarkTheme 0.2.0/0.3.3、ThemeCore 0.5.1、SnowBoard、Mikkyy 1.0.2
//   —— 它们的 objc_getClassList / objc_copyClassList / class_copyMethodList 全为 0，
//      类名写死、只用 MSHookMessageEx（Mikkyy 用自研 hook）静态挂。
//   ThemeCorePlus 自己是唯一按前缀反复全表扫描的。
//
// 现在改成：要挂的类写成固定清单，用 objc_getClass 直接取（一次哈希查找），取不到就跳过。
// 类还没 dlopen 时返回 Nil，由窗口出现后的补挂轮再取一次即可，不必为此扫全表。
NSUInteger TCPInstallSitesFromClassList(NSArray<NSString *> *classNames,
                                        NSArray<NSString *> *selectors,
                                        TCPSiteKind kind,
                                        BOOL instanceOnly) {
    if (classNames.count == 0 || selectors.count == 0) return 0;
    NSUInteger installed = 0;
    for (NSString *name in classNames) {
        if (name.length == 0) continue;
        Class cls = objc_getClass(name.UTF8String);   // 没 dlopen 就是 Nil，直接跳过
        if (cls == Nil) continue;
        for (NSString *selectorName in selectors) {
            if (TCPInstallOneSiteKind(cls, NSSelectorFromString(selectorName), kind, instanceOnly)) {
                installed++;
            }
        }
    }
    return installed;
}

// 类名匹配：byPrefix = YES 按前缀，NO 按「包含」。
// instanceOnly = YES 时只挂实例方法（见 TCPInstallOneSiteKind 的注释）。
static NSUInteger TCPInstallSitesMatching(NSArray<NSString *> *patterns,
                                          BOOL byPrefix,
                                          NSArray<NSString *> *excludingSubstrings,
                                          NSArray<NSString *> *selectors,
                                          TCPSiteKind kind,
                                          BOOL instanceOnly) {
    if (patterns.count == 0 || selectors.count == 0) return 0;
    // 不缓存类表：类是按需加载的，晚一轮再扫才能把 SpringBoardHome 的类带进来。
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return 0;

    NSUInteger installed = 0;
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        const char *raw = class_getName(cls);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        BOOL wanted = NO;
        for (NSString *pattern in patterns) {
            BOOL hit = byPrefix ? [name hasPrefix:pattern] : [name containsString:pattern];
            if (hit) { wanted = YES; break; }
        }
        if (!wanted) continue;
        BOOL skipped = NO;
        for (NSString *bad in excludingSubstrings) {
            if (bad.length > 0 && [name containsString:bad]) { skipped = YES; break; }
        }
        if (skipped) continue;
        for (NSString *selectorName in selectors) {
            if (TCPInstallOneSiteKind(cls, NSSelectorFromString(selectorName), kind, instanceOnly)) installed++;
        }
    }
    if (classes) free(classes);
    return installed;
}

NSUInteger TCPInstallSitesForClassPrefixes(NSArray<NSString *> *prefixes,
                                           NSArray<NSString *> *excludingSubstrings,
                                           NSArray<NSString *> *selectors,
                                           TCPSiteKind kind) {
    return TCPInstallSitesMatching(prefixes, YES, excludingSubstrings, selectors, kind, NO);
}

NSUInteger TCPInstallInstanceSitesForClassPrefixes(NSArray<NSString *> *prefixes,
                                                   NSArray<NSString *> *excludingSubstrings,
                                                   NSArray<NSString *> *selectors,
                                                   TCPSiteKind kind) {
    return TCPInstallSitesMatching(prefixes, YES, excludingSubstrings, selectors, kind, YES);
}

NSUInteger TCPInstallSitesForClassSubstrings(NSArray<NSString *> *substrings,
                                             NSArray<NSString *> *excludingSubstrings,
                                             NSArray<NSString *> *selectors,
                                             TCPSiteKind kind) {
    return TCPInstallSitesMatching(substrings, NO, excludingSubstrings, selectors, kind, NO);
}

// 1.0.31：锁屏角标的子串兜底 —— **整轮只扫一次类表**。
//
// 原来 ThemeCorePlusBadges.m 对 3 个选择器各调一次 TCPInstallSitesForClassSubstrings，
// 等于一轮 3 次 objc_copyClassList（拷全进程几千个类）。启动时 4 轮补挂 = 12 次全表拷贝，
// 这是启动重的第二大来源。现在合成一个函数：拷一次类表，对命中的类连挂 3 个选择器，
// 并且用静态标志保证整个进程生命周期只跑一次。
static BOOL sBadgeSubstringScanned = NO;

NSUInteger TCPInstallBadgeSubstringSitesOnce(void) {
    if (sBadgeSubstringScanned) return 0;
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return 0;
    sBadgeSubstringScanned = YES;   // 拿到了类表才算跑过，下次不再拷

    NSUInteger installed = 0;
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        const char *raw = class_getName(cls);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        if (![name containsString:@"Badge"]) continue;
        if ([name containsString:@"Accessibility"]) continue;
        if (TCPInstallOneSiteKind(cls, NSSelectorFromString(@"_checkoutBackgroundImage"),
                                  TCPSiteKindBadgeBackground, NO)) installed++;
        if (TCPInstallOneSiteKind(cls, NSSelectorFromString(@"_checkoutBackgroundImageTuple"),
                                  TCPSiteKindBadgeTuple, NO)) installed++;
        if (TCPInstallOneSiteKind(cls,
                                  NSSelectorFromString(@"_checkoutImageForText:font:highlighted:"),
                                  TCPSiteKindBadgeTextImage, NO)) installed++;
    }
    free(classes);
    return installed;
}

// 1.0.25 取证：缓存层挂载实况（诊断 cache=）。写清挂到哪个类的哪个方法，没挂上也写原因。
static NSString *sCacheHookReport = @"-";
NSString *TCPIconCacheHookReport(void) { return sCacheHookReport; }

// 1.0.25：按「声明者」挂缓存层。
// 1.0.24 的教训：cachecls= 证明 SBHIconImageCache 存在，但 cache=nocache —— iconImageWithInfo:
// 不是它自己声明的（R2 列不出），而 forced 版对每个候选类都挂一遍，第一个没声明该方法的类
// 拿到的是转发 IMP/空，占掉槽位后 MSHookMessageEx 返回空就 return NO，永远挂不上。
// 改法：对每个类用 class_getInstanceMethod 拿到 Method，再看 method_getName 所属的声明者
// （method 有 description 里的类名；用 class_copyMethodList 逐级向上找到真正声明的类），
// 只对「自己声明了该方法」的类挂一次，挂成功立刻记下类名。
static Class TCPDeclaringClass(Class cls, SEL sel) {
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Method *ms = class_copyMethodList(c, &n);
        BOOL found = NO;
        if (ms) {
            for (unsigned int i = 0; i < n; i++) {
                if (method_getName(ms[i]) == sel) { found = YES; break; }
            }
            free(ms);
        }
        if (found) return c;
    }
    return Nil;
}

NSUInteger TCPInstallIconCacheLayerSitesV2(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return 0;
    NSUInteger installed = 0;
    NSMutableArray<NSString *> *log = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        const char *raw = class_getName(cls);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        if (![name containsString:@"IconImageCache"]) continue;
        for (NSString *selName in @[ @"iconImageWithInfo:",
                                     @"unmaskedIconImageWithInfo:",
                                     @"generateIconImageWithInfo:" ]) {
            SEL sel = NSSelectorFromString(selName);
            Method direct = class_getInstanceMethod(cls, sel);
            if (direct == NULL) {
                if (log.count < 8) [log addObject:[NSString stringWithFormat:@"%@:%@=nomethod", name, selName]];
                continue;
            }
            Class owner = TCPDeclaringClass(cls, sel);
            if (owner == Nil) {
                if (log.count < 8) [log addObject:[NSString stringWithFormat:@"%@:%@=noowner", name, selName]];
                continue;
            }
            // 1.0.29：不再要求声明者类名含 IconImageCache——真入口可能在 SBIcon 等基类上，
            // 旧的那条过滤会把唯一能挂的站整条漏掉。改成：先试声明者，失败再试本类。
            NSString *ownerName = NSStringFromClass(owner);
            BOOL ok = TCPInstallOneSiteKindForced(owner, sel, TCPSiteKindIconImageInfo);
            if (!ok && owner != cls) {
                ok = TCPInstallOneSiteKindForced(cls, sel, TCPSiteKindIconImageInfo);
                if (ok) ownerName = [ownerName stringByAppendingString:@"->cls"];
            }
            if (ok) {
                installed++;
                if (log.count < 8) [log addObject:[NSString stringWithFormat:@"-%@:%@", ownerName, selName]];
            } else if (log.count < 8) {
                [log addObject:[NSString stringWithFormat:@"%@:%@=hookfail", ownerName, selName]];
            }
        }
    }
    if (classes) free(classes);
    if (log.count > 0) sCacheHookReport = [log componentsJoinedByString:@","];
    else if ([sCacheHookReport isEqualToString:@"-"]) sCacheHookReport = @"nohook";
    return installed;
}

// 1.0.30：按**选择器名**找缓存层真入口，不再靠「类名含 IconImageCache」。
// 1.0.29 的实测（cache=nohook，诊断逐类写着 PKIconImageCache/SBFolderIconImageCache/
// SBHIconImageCache 三个类的 iconImageWithInfo: 全是 nomethod）：这台 16.7.16 上，
// 「图标图缓存」的实现不吃这三个名字 —— 真正声明 iconImageWithInfo: 的类名里没有
// IconImageCache 这串字，被旧过滤整条漏掉（1.0.29 只在「已命中含字类」里放宽了声明者，
// 候选类集合本身还是空的，所以等于没改到）。
// 改法：对全进程每个类，用 class_copyMethodList 逐级向上找「自己声明了
// iconImageWithInfo: / unmaskedIconImageWithInfo: / generateIconImageWithInfo: 的类」，
// 只对声明者强制挂一次。缓存层一命中，桌面第一次取图就是主题图（MarkTheme 式秒加载）。
NSUInteger TCPInstallIconCacheByNameSites(void) {
    static NSArray<NSString *> *sels = nil;
    if (sels == nil) {
        sels = @[ @"iconImageWithInfo:", @"unmaskedIconImageWithInfo:", @"generateIconImageWithInfo:" ];
    }
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return 0;
    NSUInteger installed = 0;
    NSMutableArray<NSString *> *log = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        for (NSString *selName in sels) {
            SEL sel = NSSelectorFromString(selName);
            Class owner = TCPDeclaringClass(cls, sel);
            if (owner == Nil || owner != cls) continue;   // 只由声明它的那个类挂一次（子类走继承）
            if (TCPInstallOneSiteKindForced(cls, sel, TCPSiteKindIconImageInfo)) {
                installed++;
                if (log.count < 10) [log addObject:[NSString stringWithFormat:@"-%@:%@", NSStringFromClass(cls), selName]];
            }
        }
    }
    if (classes) free(classes);
    if (installed > 0) {
        NSString *line = [NSString stringWithFormat:@"byname:%lu[%@]", (unsigned long)installed,
                          [log componentsJoinedByString:@","]];
        sCacheHookReport = ([sCacheHookReport isEqualToString:@"-"] ? line
                            : [NSString stringWithFormat:@"%@;%@", sCacheHookReport, line]);
    }
    return installed;
}

// 1.0.23：图标图缓存层强制挂载（绕过 R2，含继承方法）。
// 遍历类名含 "IconImageCache" 的类（SBHIconImageCache 属于 SpringBoardHome，晚加载才出现），
// 用 TCPInstallOneSiteKindForced 挂 iconImageWithInfo:/unmaskedIconImageWithInfo:/generateIconImageWithInfo:。
// 1.0.22 用 R2 挂没挂上（sites 里没有缓存层站），因为缓存类自己不声明这些方法（父类/分类声明）。
NSUInteger TCPInstallIconCacheLayerSites(void) {
    // 1.0.25：先走按声明者挂的新路径，成功了就不再走旧的遍历强制挂。
    if (TCPInstallIconCacheLayerSitesV2() > 0) return 1;
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return 0;
    NSUInteger installed = 0;
    static NSMutableArray<NSString *> *sCacheClassSeen = nil;
    if (sCacheClassSeen == nil) sCacheClassSeen = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        const char *raw = class_getName(cls);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        // 1.0.24 取证：把类名含 IconImageCache 的都记下来（前 8 个），装完读诊断就知道真名。
        if ([name containsString:@"IconImageCache"] && sCacheClassSeen.count < 8 &&
            ![sCacheClassSeen containsObject:name]) {
            [sCacheClassSeen addObject:name];
        }
        if (![name containsString:@"IconImageCache"]) continue;
        for (NSString *selName in @[ @"iconImageWithInfo:",
                                     @"unmaskedIconImageWithInfo:",
                                     @"generateIconImageWithInfo:" ]) {
            if (TCPInstallOneSiteKindForced(cls, NSSelectorFromString(selName), TCPSiteKindIconImageInfo)) {
                installed++;
            }
        }
    }
    if (classes) free(classes);
    return installed;
}

// 1.0.24 取证：缓存层类名扫描结果（诊断 cachecls=）。
NSString *TCPIconCacheClassReport(void) {
    static NSMutableArray<NSString *> *sSeen = nil;
    if (sSeen == nil) sSeen = [NSMutableArray array];
    // 重新扫一遍当前进程里含 IconImageCache 的类名（最多 8 个）
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return @"cachecls=-";
    [sSeen removeAllObjects];
    for (unsigned int i = 0; i < count && sSeen.count < 8; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        const char *raw = class_getName(cls);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        if ([name containsString:@"IconImageCache"]) [sSeen addObject:name];
    }
    free(classes);
    return [NSString stringWithFormat:@"cachecls=%@",
            sSeen.count > 0 ? [sSeen componentsJoinedByString:@","] : @"none"];
}

#pragma mark - 运行期普查

NSString *TCPCensusForClasses(NSArray<NSString *> *classNames, NSUInteger limit) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger used = 0;
    for (NSString *name in classNames) {
        if (used >= limit) break;
        Class cls = objc_getClass(name.UTF8String);
        if (cls == Nil) {
            [parts addObject:[name stringByAppendingString:@"=absent"]];
            used += name.length + 8;
            continue;
        }
        NSMutableArray<NSString *> *methods = [NSMutableArray array];
        for (int pass = 0; pass < 2; pass++) {
            Class owner = (pass == 0) ? cls : object_getClass(cls);
            unsigned int count = 0;
            Method *list = class_copyMethodList(owner, &count);
            for (unsigned int i = 0; i < count; i++) {
                NSString *selectorName = NSStringFromSelector(method_getName(list[i]));
                if (selectorName.length == 0) continue;
                [methods addObject:(pass == 0 ? selectorName : [@"+" stringByAppendingString:selectorName])];
            }
            if (list) free(list);
        }
        NSString *joined = [methods componentsJoinedByString:@" "];
        NSUInteger room = (limit > used) ? (limit - used) : 0;
        if (joined.length > room) {
            joined = room > 1 ? [joined substringToIndex:room - 1] : @"";
        }
        [parts addObject:[NSString stringWithFormat:@"%@=%@", name, joined]];
        used += joined.length + name.length + 2;
    }
    return [parts componentsJoinedByString:@"\n"];
}

// 角标类普查：类名带 Badge / Notification 的类里，谁自己声明了角标那三个站。
// 用它坐实「锁屏通知的角标是哪个类画的」，不必猜类名（猜测的代价是 SpringBoard 安全模式）。
NSString *TCPClassCensusForSubstrings(NSArray<NSString *> *substrings,
                                      NSArray<NSString *> *selectors,
                                      NSUInteger limit) {
    if (substrings.count == 0 || selectors.count == 0) return @"-";
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return @"-";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger used = 0;
    for (unsigned int i = 0; i < count && used < limit; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        const char *raw = class_getName(cls);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        BOOL wanted = NO;
        for (NSString *part in substrings) {
            if ([name containsString:part]) { wanted = YES; break; }
        }
        if (!wanted) continue;

        NSMutableArray<NSString *> *methods = [NSMutableArray array];
        for (NSString *selectorName in selectors) {
            SEL sel = NSSelectorFromString(selectorName);
            if (sel == NULL) continue;
            if (TCPClassDeclaresMethod(cls, sel)) {
                [methods addObject:selectorName];
            } else if (TCPClassDeclaresMethod(object_getClass(cls), sel)) {
                [methods addObject:[@"+" stringByAppendingString:selectorName]];
            }
        }
        if (methods.count == 0) continue;   // 只有真实现了角标站的类才配占一行
        NSString *line = [NSString stringWithFormat:@"%@=%@", name, [methods componentsJoinedByString:@" "]];
        [parts addObject:line];
        used += line.length + 1;
    }
    if (classes) free(classes);
    return parts.count > 0 ? [parts componentsJoinedByString:@"\n"] : @"-";
}

// 方法名普查（0.9.7）：类名含 substrings 的类，各自把「自己声明的、方法名匹配正则」的方法列出来。
// 与 TCPClassCensusForSubstrings 的区别：那个是「你猜的选择器在不在」，这个是「这个类到底声明了
// 哪些方法」—— 角标站的入口名在 iOS 版本间来回搬，靠猜会挂错地方（代价是安全模式），
// 所以把真名读回诊断里。行格式 类名:父类=方法 方法 …，父类名也在，家族关系一眼看得出。
NSString *TCPClassMethodCensusForSubstrings(NSArray<NSString *> *substrings,
                                            NSString *methodPattern,
                                            NSUInteger limit) {
    if (substrings.count == 0) return @"-";
    NSRegularExpression *pattern = nil;
    if (methodPattern.length > 0) {
        pattern = [NSRegularExpression regularExpressionWithPattern:methodPattern
                                                           options:0
                                                             error:NULL];
    }
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes == NULL) return @"-";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger used = 0;
    for (unsigned int i = 0; i < count && used < limit; i++) {
        Class cls = classes[i];
        if (cls == Nil) continue;
        const char *raw = class_getName(cls);
        if (raw == NULL) continue;
        NSString *name = @(raw);
        BOOL wanted = NO;
        for (NSString *part in substrings) {
            if ([name containsString:part]) { wanted = YES; break; }
        }
        if (!wanted) continue;

        // pass 0 = 实例方法，pass 1 = 类方法（名字前加 + 区分）。
        NSMutableArray<NSString *> *methods = [NSMutableArray array];
        for (int pass = 0; pass < 2; pass++) {
            Class owner = (pass == 0) ? cls : object_getClass(cls);
            unsigned int methodCount = 0;
            Method *list = class_copyMethodList(owner, &methodCount);
            for (unsigned int k = 0; k < methodCount; k++) {
                NSString *selectorName = NSStringFromSelector(method_getName(list[k]));
                if (selectorName.length == 0) continue;
                if (pattern != nil &&
                    [pattern firstMatchInString:selectorName
                                        options:0
                                          range:NSMakeRange(0, selectorName.length)] == nil) {
                    continue;
                }
                [methods addObject:(pass == 0 ? selectorName
                                              : [@"+" stringByAppendingString:selectorName])];
            }
            if (list) free(list);
        }
        if (methods.count == 0) continue;

        Class superClass = class_getSuperclass(cls);
        NSString *superName = (superClass != Nil) ? NSStringFromClass(superClass) : @"-";
        NSString *joined = [methods componentsJoinedByString:@" "];
        NSUInteger room = (limit > used) ? (limit - used) : 0;
        NSString *head = [NSString stringWithFormat:@"%@:%@=", name, superName];
        if (head.length + joined.length > room) {
            NSInteger keep = (NSInteger)room - (NSInteger)head.length - 1;
            joined = (keep > 0) ? [joined substringToIndex:(NSUInteger)keep] : @"";
        }
        NSString *line = [head stringByAppendingString:joined];
        [parts addObject:line];
        used += line.length + 1;
    }
    if (classes) free(classes);
    return parts.count > 0 ? [parts componentsJoinedByString:@"\n"] : @"-";
}

#pragma mark - 「谁 hook 了它」

// dladdr 给出 IMP 所在的镜像。MSHookMessageEx 换上的 IMP 落在插件自己的 dylib 里，
// 所以「这个 (类,选择器) 现在的 IMP 在谁的地盘」= 谁在这个站点上做了手脚。
// 这样就能直接从运行中的 SpringBoard 读出 MarkTheme16（本机能正常换图标）与 ThemeCore
// 的站点清单，不必反汇编、不必猜。
static NSString *TCPImageBasenameOfIMP(IMP imp) {
    if (imp == NULL) return nil;
    Dl_info info;
    if (dladdr((void *)imp, &info) == 0 || info.dli_fname == NULL) return nil;
    return [@(info.dli_fname) lastPathComponent];
}

NSString *TCPHookOwnerCensus(NSArray<NSString *> *classNames,
                             NSArray<NSString *> *selectorNames,
                             NSUInteger limit) {
    // 系统自己的镜像：IMP 落在这里说明这个站点没人动过。
    NSSet<NSString *> *systemImages = [NSSet setWithArray:@[
        @"SpringBoardHome", @"SpringBoard", @"IconServices", @"UIKitCore",
        @"SpringBoardFoundation", @"IconFoundation", @"BaseBoard", @"Foundation",
        @"CoreFoundation", @"libobjc.A.dylib", @"libsystem_kernel.dylib"
    ]];

    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (NSString *className in classNames) {
        Class cls = objc_getClass(className.UTF8String);
        if (cls == Nil) continue;
        for (NSString *selectorName in selectorNames) {
            SEL sel = NSSelectorFromString(selectorName);
            if (sel == NULL) continue;
            // 同 R2：只认类自己声明的方法（实例方法优先，其次类方法）。
            Class owner = TCPClassDeclaresMethod(cls, sel) ? cls : object_getClass(cls);
            if (!TCPClassDeclaresMethod(owner, sel)) continue;
            IMP imp = class_getMethodImplementation(owner, sel);
            NSString *image = TCPImageBasenameOfIMP(imp);
            if (image.length == 0 || [systemImages containsObject:image]) continue;
            [hits addObject:[NSString stringWithFormat:@"%@:%@=%@", className, selectorName, image]];
        }
    }
    if (hits.count == 0) return @"-";
    NSString *text = [hits componentsJoinedByString:@","];
    if (limit > 4 && text.length > limit) text = [text substringToIndex:limit];
    return text;
}

#pragma mark - 1.0.31：dyld 镜像加载回调（替代定时全表扫描补挂）

// 为什么用这个（用户 2026-11-01 20:09「这是不是目前最优解」→ 是）：
// 本机五个主题引擎里 Mikkyy 1.0.2 的做法是 objc_getClass 按名字直取 + 注册
// dyld_register_func_for_add_image 在框架真正加载时补挂，实测 objc_getClassList /
// objc_copyClassList / class_copyMethodList 全为 0 次。
//
// 我们的问题一直是「SpringBoardHome 的类晚到，所以只能定时反复扫全表」。
// dyld 回调把这个「猜时间」换成「等事件」：框架一加载就通知我们，那时类一定已经注册好，
// 用 objc_getClass 直取即可 —— 零全表拷贝，也不会漏。
//
// 线程规则（血的教训 0.9.21）：回调可能在任意线程、且在 dyld 早期触发。所以这里
// **只置标志 + 往主队列丢一次**，绝不在回调里做挂站以外的重活（不改界面、不写偏好）。
static BOOL sDyldPending = NO;          // 有新框架加载过、还没处理
static void (^sDyldHandler)(void) = nil; // 由 Main.m 注入「该补挂了」

static void TCPDyldImageAdded(const struct mach_header *mh, intptr_t slide) {
    // 只看类名直取能得到的东西，不做任何扫描。
    // SpringBoardHome / SpringBoard 一到就把标志立起来，主队列下一拍再挂。
    static BOOL sbhLoaded = NO;
    if (sbhLoaded) return;
    if (objc_getClass("SBIcon") == Nil && objc_getClass("SBIconView") == Nil) {
        return;   // 这两个类还没来，说明来的不是我们要的框架
    }
    sbhLoaded = YES;
    sDyldPending = YES;
    void (^handler)(void) = sDyldHandler;
    if (handler != nil) {
        dispatch_async(dispatch_get_main_queue(), handler);
    }
    os_log(TCPLogHandle(), "TCPS_DYLD SpringBoardHome ready, schedule reload");
}

void TCPInstallDyldImageObserver(void (^handler)(void)) {
    static dispatch_once_t once;
    sDyldHandler = [handler copy];
    dispatch_once(&once, ^{
        dyld_register_func_for_add_image(TCPDyldImageAdded);
        os_log(TCPLogHandle(), "TCPS_DYLD observer registered");
    });
}

BOOL TCPDyldPendingReload(void) {
    BOOL p = sDyldPending;
    sDyldPending = NO;
    return p;
}
