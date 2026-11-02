#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusThemeStore.h"
#import "YzThemeCorePlusCalendarInk.h"
#import "YzThemeCorePlusPrivate.h"

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
        if (ink) return yz_themecoreplus_composeCalendar(base, ink);
        return base;
    }

    if (!hasThemeIcon) return original(self, _cmd, info);

    UIImage *themed = [store yz_themecoreplus_renderedIconForBundleID:bundleID
                                                                 size:info.size
                                                                scale:info.scale
                                                            applyMask:applyMask];
    return themed ?: original(self, _cmd, info);
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
static Class yz_themecoreplus_declaringClass(Class cls, SEL selector) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(current, &count);
        BOOL found = NO;
        for (unsigned int index = 0; index < count; index++) {
            if (method_getName(methods[index]) == selector) { found = YES; break; }
        }
        if (methods) free(methods);
        if (found) return current;
    }
    return Nil;
}

static void yz_themecoreplus_installIconSite(Class cls, NSString *name,
                                             IMP replacement, IMP *originalSlot) {
    SEL selector = NSSelectorFromString(name);
    Class owner = yz_themecoreplus_declaringClass(cls, selector);
    if (!owner) return;
    MSHookMessageEx(owner, selector, replacement, originalSlot);
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
    }
}