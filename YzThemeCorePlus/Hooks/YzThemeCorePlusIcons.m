#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusThemeStore.h"
#import "YzThemeCorePlusCalendarInk.h"
#import "YzThemeCorePlusPrivate.h"

// 图标替换：hook SBApplicationIcon 的 -iconImageWithInfo:（实例方法）。
// 日历特殊：主题给了底图 → 底图 + 系统实时日期数字（近黑提取 + 按底图明暗填黑/白字）。

static UIImage *(*orig_iconImageWithInfo)(id self, SEL _cmd, SBIconImageInfo info) = NULL;

static UIImage *repl_iconImageWithInfo(id self, SEL _cmd, SBIconImageInfo info) {
    if (![[YzThemeCorePlusConfig yz_themecoreplus_shared] yz_themecoreplus_isEnabled]) {
        return orig_iconImageWithInfo(self, _cmd, info);
    }
    NSString *bundleID = [self applicationBundleID];
    if (bundleID.length == 0) return orig_iconImageWithInfo(self, _cmd, info);

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
        if (!base) return orig_iconImageWithInfo(self, _cmd, info);
        if (![store yz_themecoreplus_themeFlagForKey:@"CalendarLiveDate" defaultValue:YES]) return base;
        UIImage *systemImage = orig_iconImageWithInfo(self, _cmd, info);
        if (!systemImage) return base;
        CGFloat lum = yz_themecoreplus_averageLuminance(base);
        UIColor *inkColor = (lum < 0.5f) ? [UIColor whiteColor] : [UIColor blackColor];
        UIImage *ink = yz_themecoreplus_calendarInkImage(systemImage, inkColor, NULL);
        if (ink) return yz_themecoreplus_composeCalendar(base, ink);
        return base;
    }

    if (!hasThemeIcon) return orig_iconImageWithInfo(self, _cmd, info);

    UIImage *themed = [store yz_themecoreplus_renderedIconForBundleID:bundleID
                                                                 size:info.size
                                                                scale:info.scale
                                                            applyMask:applyMask];
    return themed ?: orig_iconImageWithInfo(self, _cmd, info);
}

__attribute__((constructor))
static void yz_icons_init(void) {
    @autoreleasepool {
        Class cls = objc_getClass("SBApplicationIcon");
        if (cls) {
            MSHookMessageEx(cls, @selector(iconImageWithInfo:),
                            (IMP)&repl_iconImageWithInfo, (IMP*)&orig_iconImageWithInfo);
        }
    }
}
