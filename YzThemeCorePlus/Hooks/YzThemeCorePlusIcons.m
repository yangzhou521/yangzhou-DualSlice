#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusThemeStore.h"
#import "YzThemeCorePlusCalendarInk.h"
#import "YzThemeCorePlusPrivate.h"
#import "YzThemeCorePlusVersion.h"

// 图标替换：hook SBIcon 家族的取图/生图站（实例方法，签名统一是 SBIconImageInfo → UIImage *）。
// 日历特殊：主题给了底图 → 底图 + 系统实时日期数字（近黑提取 + 按底图明暗填黑/白字）。
//
// 5.3.0 为什么从「一站」扩到「四站」：用户 2026-11-02 报「图标没 hook 到 / 不生效」。
// 自研线 1.0.x 在本机（iPhone10,1 / 16.7.16）实测过同一件事 —— 只挂 iconImageWithInfo:
// 时它一次都没被问过（诊断 look=0），真正生图的是 generateIconImageWithInfo:。
// 所以四个站都挂：谁把图标图交出去，谁就被换成主题图。缺哪个选择器就跳过，不猜。
typedef UIImage *(*YzThemeCorePlusIconImageImp)(id, SEL, SBIconImageInfo);

static YzThemeCorePlusIconImageImp orig_iconImageWithInfo = NULL;
static YzThemeCorePlusIconImageImp orig_unmaskedIconImageWithInfo = NULL;
static YzThemeCorePlusIconImageImp orig_iconImageWithImageInfo = NULL;
static YzThemeCorePlusIconImageImp orig_generateIconImageWithInfo = NULL;

// —— 诊断（本机取证用，插件只写这一个文件）——
// 用户报「图标没生效」时，光看图看不出「是没挂上站」还是「挂上了没被问」与「问到了没换成图」，
// 所以把挂站结果与命中次数写进 /var/mobile/Library/YzThemeCorePlus/icon-diag.txt：
//   v=<版本>;look=<取图站被问次数>;hit=<真换成主题图次数>;last=<最后一次的 bundleID>;sites=<站->声明类>
static NSUInteger sIconLook = 0;
static NSUInteger sIconHit = 0;
static NSString *sIconLastBundle = nil;
static NSString *sIconSites = @"-";
static NSTimeInterval sDiagWrittenAt = 0;

static void yz_themecoreplus_writeIconDiag(BOOL force) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!force && now - sDiagWrittenAt < 20.0) return;
    sDiagWrittenAt = now;
    NSString *directory = @"/var/mobile/Library/YzThemeCorePlus";
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
    });
    NSString *text = [NSString stringWithFormat:@"v=%s;look=%lu;hit=%lu;last=%@;sites=%@\n",
        YZ_THEMECOREPLUS_VERSION, (unsigned long)sIconLook, (unsigned long)sIconHit,
        sIconLastBundle ?: @"-", sIconSites ?: @"-"];
    [text writeToFile:[directory stringByAppendingPathComponent:@"icon-diag.txt"]
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void yz_themecoreplus_markIconHit(NSString *bundleID) {
    if (sIconHit++ == 0 || ![sIconLastBundle isEqualToString:bundleID]) {
        sIconLastBundle = bundleID;
    }
    yz_themecoreplus_writeIconDiag(NO);
}

static UIImage *yz_themecoreplus_themedIcon(id self, SEL _cmd, SBIconImageInfo info,
                                            YzThemeCorePlusIconImageImp original) {
    if (!original) return nil;
    if (![[YzThemeCorePlusConfig yz_themecoreplus_shared] yz_themecoreplus_isEnabled]) {
        return original(self, _cmd, info);
    }
    // 挂到继承来的实现上时，self 也可能是文件夹/小组件图标：没有 applicationBundleID 就放原图。
    if (![self respondsToSelector:@selector(applicationBundleID)]) return original(self, _cmd, info);
    NSString *bundleID = [self applicationBundleID];
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
        return original(self, _cmd, info);
    }

    YzThemeCorePlusThemeStore *store = [YzThemeCorePlusThemeStore yz_themecoreplus_shared];
    BOOL hasThemeIcon = [store yz_themecoreplus_iconPathForBundleID:bundleID scale:info.scale] != nil;
    sIconLook++;
    yz_themecoreplus_writeIconDiag(NO);

    BOOL themeMask = [store yz_themecoreplus_themeFlagForKey:@"IconCornerMask" defaultValue:YES];
    id configMask = [[YzThemeCorePlusConfig yz_themecoreplus_shared]
        yz_themecoreplus_valueForKey:@"IconCornerMask" defaultValue:@(YES)];
    BOOL applyMask = [configMask isKindOfClass:[NSNumber class]]
        ? ([configMask boolValue] && themeMask) : themeMask;

    // 日历
    if ([bundleID isEqualToString:@"com.apple.mobilecal"] && hasThemeIcon) {
        UIImage *base = [store yz_themecoreplus_renderedIconForBundleID:bundleID
                                                                 size:info.size
                                                                scale:info.scale
                                                            applyMask:applyMask];
        if (!base) return original(self, _cmd, info);
        if (![store yz_themecoreplus_themeFlagForKey:@"CalendarLiveDate" defaultValue:YES]) return base;
        UIImage *systemImage = original(self, _cmd, info);
        if (!systemImage) return base;
        CGFloat lum = yz_themecoreplus_averageLuminance(base);
        UIColor *inkColor = (lum < 0.5f) ? [UIColor whiteColor] : [UIColor blackColor];
        UIImage *ink = yz_themecoreplus_calendarInkImage(systemImage, inkColor, NULL);
        if (ink) { yz_themecoreplus_markIconHit(bundleID); return yz_themecoreplus_composeCalendar(base, ink); }
        yz_themecoreplus_markIconHit(bundleID);
        return base;
    }

    if (!hasThemeIcon) return original(self, _cmd, info);

    UIImage *themed = [store yz_themecoreplus_renderedIconForBundleID:bundleID
                                                                 size:info.size
                                                                scale:info.scale
                                                            applyMask:applyMask];
    if (themed) { yz_themecoreplus_markIconHit(bundleID); return themed; }
    return original(self, _cmd, info);
}

static UIImage *repl_iconImageWithInfo(id self, SEL _cmd, SBIconImageInfo info) {
    return yz_themecoreplus_themedIcon(self, _cmd, info, orig_iconImageWithInfo);
}

static UIImage *repl_unmaskedIconImageWithInfo(id self, SEL _cmd, SBIconImageInfo info) {
    return yz_themecoreplus_themedIcon(self, _cmd, info, orig_unmaskedIconImageWithInfo);
}

static UIImage *repl_iconImageWithImageInfo(id self, SEL _cmd, SBIconImageInfo info) {
    return yz_themecoreplus_themedIcon(self, _cmd, info, orig_iconImageWithImageInfo);
}

static UIImage *repl_generateIconImageWithInfo(id self, SEL _cmd, SBIconImageInfo info) {
    return yz_themecoreplus_themedIcon(self, _cmd, info, orig_generateIconImageWithInfo);
}

// 找**真正声明**该选择器的那一层：MSHookMessageEx 挂到「继承来的实现」上会拿到空的原实现指针，
// 接着 original 一调就是崩；所以从 SBApplicationIcon 往父类走，第一个声明它的类才算挂点（一站一槽）。
// 还要签名对得上：只认「一个结构体参数」（self/_cmd/arg 三参、第 2 个参数类型编码 '{' 打头），
// 挂到指针版或零参版上会把参数解释错，一调原实现就崩 —— 签名不符一律不挂。
static BOOL yz_themecoreplus_signatureMatches(Method method) {
    if (!method) return NO;
    if (method_getNumberOfArguments(method) != 3) return NO;
    char *encoding = method_copyArgumentType(method, 2);
    BOOL matches = (encoding != NULL && encoding[0] == '{');
    if (encoding) free(encoding);
    return matches;
}

static Class yz_themecoreplus_declaringClass(Class cls, SEL selector) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(current, &count);
        Method match = NULL;
        for (unsigned int index = 0; index < count; index++) {
            if (method_getName(methods[index]) == selector) { match = methods[index]; break; }
        }
        if (methods) free(methods);
        if (match) return yz_themecoreplus_signatureMatches(match) ? current : Nil;
    }
    return Nil;
}

// —— 挂站 ——
static void yz_themecoreplus_installIconSite(Class cls, NSString *name,
                                             IMP replacement, IMP *originalSlot) {
    SEL selector = NSSelectorFromString(name);
    Class owner = yz_themecoreplus_declaringClass(cls, selector);
    if (!owner) return;
    MSHookMessageEx(owner, selector, replacement, originalSlot);
    NSString *entry = [NSString stringWithFormat:@"%@->%@", name, NSStringFromClass(owner)];
    sIconSites = [sIconSites isEqualToString:@"-"] ? entry : [sIconSites stringByAppendingFormat:@",%@", entry];
}

__attribute__((constructor))
static void yz_icons_init(void) {
    @autoreleasepool {
        Class cls = objc_getClass("SBApplicationIcon");
        if (!cls) return;
        yz_themecoreplus_installIconSite(cls, @"iconImageWithInfo:",
            (IMP)&repl_iconImageWithInfo, (IMP*)&orig_iconImageWithInfo);
        yz_themecoreplus_installIconSite(cls, @"unmaskedIconImageWithInfo:",
            (IMP)&repl_unmaskedIconImageWithInfo, (IMP*)&orig_unmaskedIconImageWithInfo);
        yz_themecoreplus_installIconSite(cls, @"iconImageWithImageInfo:",
            (IMP)&repl_iconImageWithImageInfo, (IMP*)&orig_iconImageWithImageInfo);
        yz_themecoreplus_installIconSite(cls, @"generateIconImageWithInfo:",
            (IMP)&repl_generateIconImageWithInfo, (IMP*)&orig_generateIconImageWithInfo);
        NSLog(@"[YzThemeCorePlus] icon sites=%s", sIconSites.UTF8String);
        yz_themecoreplus_writeIconDiag(YES);
    }
}