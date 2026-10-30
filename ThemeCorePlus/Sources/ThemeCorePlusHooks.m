//
//  ThemeCorePlusHooks.m —— 「一站一槽」站点框架（见头文件里的 R1/R2）。
//
#import "ThemeCorePlusHooks.h"
#import <substrate.h>
#import <dlfcn.h>   // dladdr：反查某个 IMP 属于哪个镜像（见文末「谁 hook 了它」）

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
    return ((TCPIconImageInfoFn)original)(self, _cmd, info);
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

static id TCPBadgeTextHandle(IMP *slot, id self, SEL _cmd, NSString *text, UIFont *font, BOOL highlighted) {
    IMP original = *slot;
    if (original == NULL) return nil;
    id result = ((TCPBadgeTextFn)original)(self, _cmd, text, font, highlighted);
    // 角标盒子的高度就是屏幕上角标的高：一个字时宽也取这个值 → 正圆；
    // 两个以上再按文字宽度加宽成圆头胶囊。盒子拿不到才退回素材自己的点数。
    CGSize box = TCPBadgeSystemBoxSize(result);
    // 单层闸门（0.9.4）：底板站这一轮已经换过底板了，这里就只交数字（透明底）——
    // 两站都画底板的话屏幕上就是同一张底板叠两层（用户说的「二个图层」）。
    UIImage *themed = TCPBadgeBackgroundServed()
        ? TCPThemedBadgeTextOnlyImage(text, font, TCPUIScale(), box)
        : TCPThemedBadgeTextImage(text, font, TCPUIScale(), box);
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
};

#pragma mark - 挂站

static BOOL TCPInstallOneSite(Class cls, SEL sel, TCPSiteKind kind) {
    if (cls == Nil || sel == NULL || kind >= TCPSiteKindCount) return NO;

    // R2：类自己声明了才挂（类方法与实例方法分别判断；两者都声明时优先类方法）。
    BOOL asClassMethod = TCPClassDeclaresMethod(object_getClass(cls), sel);
    BOOL asInstanceMethod = !asClassMethod && TCPClassDeclaresMethod(cls, sel);
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

// 类名匹配：byPrefix = YES 按前缀，NO 按「包含」。
static NSUInteger TCPInstallSitesMatching(NSArray<NSString *> *patterns,
                                          BOOL byPrefix,
                                          NSArray<NSString *> *excludingSubstrings,
                                          NSArray<NSString *> *selectors,
                                          TCPSiteKind kind) {
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
            if (TCPInstallOneSite(cls, NSSelectorFromString(selectorName), kind)) installed++;
        }
    }
    if (classes) free(classes);
    return installed;
}

NSUInteger TCPInstallSitesForClassPrefixes(NSArray<NSString *> *prefixes,
                                           NSArray<NSString *> *excludingSubstrings,
                                           NSArray<NSString *> *selectors,
                                           TCPSiteKind kind) {
    return TCPInstallSitesMatching(prefixes, YES, excludingSubstrings, selectors, kind);
}

NSUInteger TCPInstallSitesForClassSubstrings(NSArray<NSString *> *substrings,
                                             NSArray<NSString *> *excludingSubstrings,
                                             NSArray<NSString *> *selectors,
                                             TCPSiteKind kind) {
    return TCPInstallSitesMatching(substrings, NO, excludingSubstrings, selectors, kind);
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
