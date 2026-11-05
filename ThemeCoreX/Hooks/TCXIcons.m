#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "TCXPrivate.h"
#import "TCXStore.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"

// 图标层。
//
// 挂钩面按 ThemeCore 0.5.1 逆向出来的选择器清单对齐（证据：ThemeCore.dylib 的
// 选择器字符串全集）。分四组，签名不同就绝不复用同一个函数指针：
//
//   A  info 型（按值传 SBIconImageInfo 结构体，4 个 double）
//        -iconImageWithInfo: / -unmaskedIconImageWithInfo:
//        -generateIconImageWithInfo: / -genericIconImageWithInfo:
//   B  bundle id 型（1 个 NSString，返回类型不保证是 UIImage）
//        -appIconForBundleIdentifier: / -iconForBundleIdentifier:
//   C  bundle id + scale
//        -imageForBundleIdentifier:scale:
//   D  icon 对象型（1 个 id）
//        -cachedImageForIcon: / -imageForIcon:
//   E  format 型（格式参数按 NSInteger 透传，同宽安全）
//        -_applicationIconImageForBundleIdentifier:format:
//        -_applicationIconImageForBundleIdentifier:format:scale:
//
// 组 B/D/E 一律**先拿原值、验类型**：不是 UIImage 就原样返回，一个字节都不换。
// 换类型（CGImageRef / ISImage / 包壳 tuple）会让调用方按错误类型取属性，立刻崩。
//
// 一站一槽：只挂在**自己声明**该选择器的那一层（class_copyMethodList 判定），
// 挂到继承来的实现上会拿到空的原实现指针。

// 日历叠加（TCXCalendar.m）：主题只出底图，星期/日期由我们画。
extern UIImage *TCXCalendarOverlay(UIImage *image, NSString *bundleID, CGSize size, CGFloat scale);

// 该 icon 对象是不是我们自己产出的主题图（视图层防重入用）。
BOOL TCXIsThemedImage(UIImage *image);

#pragma mark - 一站一槽：每个 (类, 选择器) 各存自己的原实现

// 为什么要有这张表：同一个选择器（如 -iconImageWithInfo:）会被**多个类各自声明**，
// 而 repl 函数是所有类共用的一个。若把所有类的原实现都塞进同一个静态变量，
// 后挂的类会覆盖先挂的，先挂的类实例被调用时就调到了**别的类的原实现**。
// 修法：挂站时把 (类, 选择器) → 原实现 记进表；repl 被调用时用 self 的**动态类**
// 沿继承链向上找第一个登记过该选择器的类，取它自己的原实现。
// （ThemeCore 用 Logos 的 %hook，每个类天然生成自己的 orig 槽；我们不用 Logos，
//   所以必须自己实现同等的一站一槽。）
typedef struct {
    Class cls;
    SEL selector;
    IMP original;
} TCXOriginalSlot;

static TCXOriginalSlot gOriginals[512];
static int gOriginalCount = 0;

// 当前线程正在执行的原实现（按「命中的类」记账）。为什么需要：
// 子类 Y 覆写了某选择器、其原实现里又调 [super ...]，而父类 X 也挂了同一选择器时，
// 若只看 self 的动态类，Y 的原实现 -> X 的实现 -> 又找到 Y 的原实现 -> 无限递归。
// 所以记下这一条调用链上已经用过的类，查找时跳过它们，逐层向上。
static __thread Class gInFlight[32];
static __thread int gInFlightCount = 0;

static BOOL TCXInFlightContains(Class cls) {
    for (int i = 0; i < gInFlightCount; i++) {
        if (gInFlight[i] == cls) return YES;
    }
    return NO;
}

static void TCXInFlightPush(Class cls) {
    if (!cls) return;
    if (gInFlightCount < 32) gInFlight[gInFlightCount++] = cls;
}

static void TCXInFlightPop(void) {
    if (gInFlightCount > 0) gInFlightCount--;
}

// 沿 self 的动态类向上找第一个登记过该选择器、且**不在当前调用链上**的类。
static IMP TCXOriginalFor(Class dynamicClass, SEL selector, Class *outHit) {
    if (!dynamicClass || !selector) return NULL;
    for (Class c = dynamicClass; c; c = class_getSuperclass(c)) {
        if (TCXInFlightContains(c)) continue;
        for (int i = 0; i < gOriginalCount; i++) {
            if (gOriginals[i].cls == c && gOriginals[i].selector == selector) {
                if (outHit) *outHit = c;
                return gOriginals[i].original;
            }
        }
    }
    return NULL;
}

// 取原实现并把命中的类压进调用链；配套 TCXEndOriginal 弹出。
static IMP TCXBeginOriginal(id self, SEL selector, Class *outHit) {
    Class hit = NULL;
    IMP imp = TCXOriginalFor(object_getClass(self), selector, &hit);
    if (hit) TCXInFlightPush(hit);
    if (outHit) *outHit = hit;
    return imp;
}

static void TCXEndOriginal(Class hit) {
    if (hit) TCXInFlightPop();
}

static void TCXRegisterOriginal(Class cls, SEL selector, IMP original) {
    if (!cls || !selector || !original) return;
    for (int i = 0; i < gOriginalCount; i++) {
        if (gOriginals[i].cls == cls && gOriginals[i].selector == selector) {
            gOriginals[i].original = original;
            return;
        }
    }
    if (gOriginalCount < 512) {
        gOriginals[gOriginalCount].cls = cls;
        gOriginals[gOriginalCount].selector = selector;
        gOriginals[gOriginalCount].original = original;
        gOriginalCount++;
    }
}

#pragma mark - 组 A：info 型

typedef UIImage *(*TCXInfoImp)(id, SEL, TCXIconImageInfo);

// 从图标对象上取 bundle id：三条都试，全失败就放行。
NSString *TCXBundleIDOfIcon(id icon) {
    @try {
        if (!icon) return nil;
        for (NSString *selectorName in @[@"applicationBundleID", @"bundleIdentifier", @"leafIdentifier"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if (![icon respondsToSelector:selector]) continue;
            id value = ((id (*)(id, SEL))objc_msgSend)(icon, selector);
            if ([value isKindOfClass:[NSString class]] && [value length]) return value;
        }
    } @catch (NSException *exception) {
    }
    return nil;
}

static UIImage *TCXThemedInfoImage(id icon, CGFloat scale, CGSize size) {
    NSString *bundleID = TCXBundleIDOfIcon(icon);
    if (!bundleID) return nil;

    TCXStore *store = [TCXStore shared];
    TCXCountIconLook();
    if (![store hasIconForBundleID:bundleID scale:scale]) return nil;

    UIImage *themed = [store imageForBundleID:bundleID size:size scale:scale];
    if (!themed) return nil;

    // 日历图标：底图来自主题，星期与日期由我们叠上去（见 TCXCalendar.m）。
    // 其它 bundle 原样返回，函数内部第一件事就是判 bundleID。
    themed = TCXCalendarOverlay(themed, bundleID, size, scale);

    TCXCountIconHit(bundleID);
    return themed;
}

static UIImage *TCXThemedImage(id self, SEL _cmd, TCXIconImageInfo info) {
    Class hit = NULL;
    TCXInfoImp original = (TCXInfoImp)TCXBeginOriginal(self, _cmd, &hit);
    if (!original) return nil;
    @try {
        if (!TCXPrefBool(@"Enabled", YES)) return original(self, _cmd, info);

        [[TCXStore shared] reloadIfNeeded];
        UIImage *themed = TCXThemedInfoImage(self, info.scale, info.size);
        return themed ?: original(self, _cmd, info);
    } @finally {
        TCXEndOriginal(hit);
    }
}

#define TCX_INFO_REPL(name) \
    static UIImage *repl_##name(id self, SEL _cmd, TCXIconImageInfo info) { \
        return TCXThemedImage(self, _cmd, info); \
    }

TCX_INFO_REPL(IconImageWithInfo)
TCX_INFO_REPL(UnmaskedIconImageWithInfo)
TCX_INFO_REPL(GenerateIconImageWithInfo)
TCX_INFO_REPL(GenericIconImageWithInfo)

#pragma mark - 组 B / C：bundle id 型

typedef id (*TCXBundleImp)(id, SEL, NSString *);
typedef id (*TCXBundleScaleImp)(id, SEL, NSString *, CGFloat);
typedef id (*TCXIconImp)(id, SEL, id);
typedef id (*TCXFormatImp)(id, SEL, NSString *, NSInteger);
typedef id (*TCXFormatScaleImp)(id, SEL, NSString *, NSInteger, CGFloat);

// 把原值换主题图。原值不是 UIImage（CGImageRef / ISImage / 包壳）就一个字都不动。
static id TCXThemeResult(id result, NSString *bundleID, CGFloat scale) {
    if (![result isKindOfClass:[UIImage class]]) return result;
    if (!bundleID.length) return result;

    UIImage *image = (UIImage *)result;
    if (TCXIsThemedImage(image)) return result;
    if ([image respondsToSelector:@selector(isSymbolImage)] && [image isSymbolImage]) return result;

    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];

    TCXCountIconLook();
    if (![store hasIconForBundleID:bundleID scale:scale]) return result;

    UIImage *themed = [store imageForBundleID:bundleID size:image.size scale:scale];
    if (!themed) return result;

    TCXCountIconHit(bundleID);
    return themed;
}

#define TCX_BUNDLE_REPL(name) \
    static id repl_##name(id self, SEL _cmd, NSString *bundleID) { \
        Class hit = NULL; \
        TCXBundleImp orig = (TCXBundleImp)TCXBeginOriginal(self, _cmd, &hit); \
        @try { \
            id result = orig ? orig(self, _cmd, bundleID) : nil; \
            if (!TCXPrefBool(@"Enabled", YES)) return result; \
            if (![bundleID isKindOfClass:[NSString class]]) return result; \
            @try { \
                return TCXThemeResult(result, bundleID, 2.0); \
            } @catch (NSException *exception) { \
                return result; \
            } \
        } @finally { \
            TCXEndOriginal(hit); \
        } \
    }

TCX_BUNDLE_REPL(AppIconForBundleIdentifier)
TCX_BUNDLE_REPL(IconForBundleIdentifier)

static id repl_ImageForBundleIdentifierScale(id self, SEL _cmd, NSString *bundleID, CGFloat scale) {
    Class hit = NULL;
    TCXBundleScaleImp orig = (TCXBundleScaleImp)TCXBeginOriginal(self, _cmd, &hit);
    @try {
        id result = orig ? orig(self, _cmd, bundleID, scale) : nil;
        if (!TCXPrefBool(@"Enabled", YES)) return result;
        if (![bundleID isKindOfClass:[NSString class]]) return result;
        @try {
            return TCXThemeResult(result, bundleID, scale > 0 ? scale : 2.0);
        } @catch (NSException *exception) {
            return result;
        }
    } @finally {
        TCXEndOriginal(hit);
    }
}

#define TCX_ICON_REPL(name) \
    static id repl_##name(id self, SEL _cmd, id icon) { \
        Class hit = NULL; \
        TCXIconImp orig = (TCXIconImp)TCXBeginOriginal(self, _cmd, &hit); \
        @try { \
            id result = orig ? orig(self, _cmd, icon) : nil; \
            if (!TCXPrefBool(@"Enabled", YES)) return result; \
            @try { \
                UIImage *image = [result isKindOfClass:[UIImage class]] ? (UIImage *)result : nil; \
                CGFloat scale = image ? image.scale : 2.0; \
                return TCXThemeResult(result, TCXBundleIDOfIcon(icon), scale > 0 ? scale : 2.0); \
            } @catch (NSException *exception) { \
                return result; \
            } \
        } @finally { \
            TCXEndOriginal(hit); \
        } \
    }

TCX_ICON_REPL(CachedImageForIcon)
TCX_ICON_REPL(ImageForIcon)

static id repl_ApplicationIconImageForBundleIdentifierFormat(id self, SEL _cmd, NSString *bundleID, NSInteger format) {
    Class hit = NULL;
    TCXFormatImp orig = (TCXFormatImp)TCXBeginOriginal(self, _cmd, &hit);
    @try {
        id result = orig ? orig(self, _cmd, bundleID, format) : nil;
        if (!TCXPrefBool(@"Enabled", YES)) return result;
        if (![bundleID isKindOfClass:[NSString class]]) return result;
        @try {
            return TCXThemeResult(result, bundleID, 2.0);
        } @catch (NSException *exception) {
            return result;
        }
    } @finally {
        TCXEndOriginal(hit);
    }
}

static id repl_ApplicationIconImageForBundleIdentifierFormatScale(id self, SEL _cmd, NSString *bundleID,
                                                                 NSInteger format, CGFloat scale) {
    Class hit = NULL;
    TCXFormatScaleImp orig = (TCXFormatScaleImp)TCXBeginOriginal(self, _cmd, &hit);
    @try {
        id result = orig ? orig(self, _cmd, bundleID, format, scale) : nil;
        if (!TCXPrefBool(@"Enabled", YES)) return result;
        if (![bundleID isKindOfClass:[NSString class]]) return result;
        @try {
            return TCXThemeResult(result, bundleID, scale > 0 ? scale : 2.0);
        } @catch (NSException *exception) {
            return result;
        }
    } @finally {
        TCXEndOriginal(hit);
    }
}

#pragma mark - 组 E：视图层（呈现层最后一道保险）

// SBIconImageView 拿到图之后才上屏。有些路径绕过生图层（缓存命中、图标已渲染过），
// 所以这一层必须也挂：把它要显示的图换掉，是「换图生效」的最后一个可靠落点。
static void replSetImage(id self, SEL _cmd, UIImage *image) {
    Class hit = NULL;
    void (*orig)(id, SEL, UIImage *) =
        (void (*)(id, SEL, UIImage *))TCXBeginOriginal(self, _cmd, &hit);
    if (!orig) return;

    @try {
        UIImage *replacement = image;
        @try {
            if (image && TCXPrefBool(@"Enabled", YES) && !TCXIsThemedImage(image)) {
                id icon = nil;
                if ([self respondsToSelector:@selector(icon)]) {
                    icon = ((id (*)(id, SEL))objc_msgSend)(self, @selector(icon));
                }
                NSString *bundleID = TCXBundleIDOfIcon(icon);
                if (bundleID.length) {
                    TCXStore *store = [TCXStore shared];
                    [store reloadIfNeeded];
                    CGFloat scale = image.scale > 0 ? image.scale : 2.0;
                    if ([store hasIconForBundleID:bundleID scale:scale]) {
                        UIImage *themed = [store imageForBundleID:bundleID size:image.size scale:scale];
                        if (themed) {
                            TCXCountIconHit(bundleID);
                            replacement = themed;
                        }
                    }
                }
            }
        } @catch (NSException *exception) {
            replacement = image;
        }
        orig(self, _cmd, replacement);
    } @finally {
        TCXEndOriginal(hit);
    }
}

#pragma mark - 挂站

static BOOL TCXClassDeclares(Class cls, SEL selector) {
    if (!cls) return NO;
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL declared = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(list[i]) == selector) { declared = YES; break; }
    }
    free(list);
    return declared;
}

// 只挂「自己声明」该选择器的类；挂上后把 (类, 选择器) → 原实现 记进一站一槽表。
static void TCXHookDeclared(Class cls, SEL selector, IMP replacement, NSString *label) {
    if (!TCXClassDeclares(cls, selector)) return;
    IMP original = NULL;
    MSHookMessageEx(cls, selector, replacement, &original);
    if (original) {
        TCXRegisterOriginal(cls, selector, original);
        TCXNoteSite([NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), label]);
    }
}

static void TCXReloadCallback(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    @autoreleasepool {
        [[TCXStore shared] reload];
        Class controller = TCXClass(@"SBIconController");
        if (controller && [controller respondsToSelector:@selector(sharedInstance)]) {
            id instance = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(sharedInstance));
            if ([instance respondsToSelector:@selector(reloadIconImages)]) {
                ((void (*)(id, SEL))objc_msgSend)(instance, @selector(reloadIconImages));
            }
        }
    }
}

void TCXInstallIconHooks(void) {
    // 类清单与 ThemeCore 0.5.1 落在同一批：IconServices 的生图对象 + SpringBoard 的图标对象。
    NSArray<NSString *> *owners = @[
        @"ISBundleIdentifierIcon",
        @"ISIcon",
        @"ISGenerationRequest",
        @"SBApplicationIcon",
        @"SBLeafIcon",
        @"SBIcon",
        @"SBHIconImageCache",
        @"SBFolderIconImageCache",
        @"SBFolderIconImageSharedCache",
        @"SBHCalendarApplicationIcon",
        @"SBCalendarApplicationIcon",
        @"SBWidgetIcon",
        @"SBHLibraryPodCategoryIcon",
        @"SBHLibraryAdditionalItemsIndicatorIcon",
    ];

    for (NSString *name in owners) {
        Class cls = TCXClass(name);
        if (!cls) continue;

        TCXHookDeclared(cls, @selector(iconImageWithInfo:),
                        (IMP)&repl_IconImageWithInfo, @"iconImageWithInfo:");
        TCXHookDeclared(cls, @selector(unmaskedIconImageWithInfo:),
                        (IMP)&repl_UnmaskedIconImageWithInfo, @"unmaskedIconImageWithInfo:");
        TCXHookDeclared(cls, @selector(generateIconImageWithInfo:),
                        (IMP)&repl_GenerateIconImageWithInfo, @"generateIconImageWithInfo:");
        TCXHookDeclared(cls, @selector(genericIconImageWithInfo:),
                        (IMP)&repl_GenericIconImageWithInfo, @"genericIconImageWithInfo:");

        TCXHookDeclared(cls, @selector(appIconForBundleIdentifier:),
                        (IMP)&repl_AppIconForBundleIdentifier, @"appIconForBundleIdentifier:");
        TCXHookDeclared(cls, @selector(iconForBundleIdentifier:),
                        (IMP)&repl_IconForBundleIdentifier, @"iconForBundleIdentifier:");
        TCXHookDeclared(cls, @selector(imageForBundleIdentifier:scale:),
                        (IMP)&repl_ImageForBundleIdentifierScale,
                        @"imageForBundleIdentifier:scale:");

        TCXHookDeclared(cls, @selector(cachedImageForIcon:),
                        (IMP)&repl_CachedImageForIcon, @"cachedImageForIcon:");
        TCXHookDeclared(cls, @selector(imageForIcon:),
                        (IMP)&repl_ImageForIcon, @"imageForIcon:");

        TCXHookDeclared(cls, @selector(_applicationIconImageForBundleIdentifier:format:),
                        (IMP)&repl_ApplicationIconImageForBundleIdentifierFormat,
                        @"_applicationIconImageForBundleIdentifier:format:");
        TCXHookDeclared(cls, @selector(_applicationIconImageForBundleIdentifier:format:scale:),
                        (IMP)&repl_ApplicationIconImageForBundleIdentifierFormatScale,
                        @"_applicationIconImageForBundleIdentifier:format:scale:");
    }

    // 呈现层：只有真实存在 SBIconImageView 的进程（SpringBoard）才挂得上。
    Class imageView = TCXClass(@"SBIconImageView");
    TCXHookDeclared(imageView, @selector(setImage:),
                    (IMP)&replSetImage, @"setImage:");

    // 换主题 → 让系统重取可见图标。Darwin 通知跨进程可靠。
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, TCXReloadCallback,
                                    CFSTR("com.yangzhou.appicon.reload"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
