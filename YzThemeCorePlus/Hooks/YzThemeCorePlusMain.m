#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusPreferences.h"
#import "YzThemeCorePlusThemeStore.h"
#import "YzThemeCorePlusPrivate.h"
#import "YzThemeCorePlusVersion.h"

// 偏好变更通知：偏好面板和刷新按钮广播同一个 Darwin 通知，主线程按依赖序刷新。
static void yz_themecoreplus_applyThemeChange(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[YzThemeCorePlusConfig yz_themecoreplus_shared] yz_themecoreplus_reload];
        [[YzThemeCorePlusThemeStore yz_themecoreplus_shared] yz_themecoreplus_reload];
        SBIconController *controller = [SBIconController sharedInstance];
        if (controller && [controller respondsToSelector:@selector(relayoutIcons)]) {
            [controller relayoutIcons];
        }
    });
}

static void yz_themecoreplus_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                                  CFStringRef name, const void *object,
                                                  CFDictionaryRef info) {
    yz_themecoreplus_applyThemeChange();
}

static void (*orig_didFinishLaunching)(id self, SEL _cmd, id application) = NULL;

static void repl_didFinishLaunching(id self, SEL _cmd, id application) {
    orig_didFinishLaunching(self, _cmd, application);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        yz_themecoreplus_preferencesDidChange,
        (__bridge CFStringRef)YzThemeCorePlusPreferencesChanged, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

__attribute__((constructor))
static void yz_main_init(void) {
    @autoreleasepool {
        // 判活的一行：装完注销后在系统日志里看到它，才说明这一版真的被加载了（版本号取自单一来源头）。
        NSLog(@"[YzThemeCorePlus] loaded version=%s", YZ_THEMECOREPLUS_VERSION);

        // Readers load a snapshot; they never write default preferences.
        [YzThemeCorePlusConfig yz_themecoreplus_shared];
        [YzThemeCorePlusThemeStore yz_themecoreplus_shared];

        Class cls = objc_getClass("SpringBoard");
        if (cls) {
            MSHookMessageEx(cls, @selector(applicationDidFinishLaunching:),
                            (IMP)&repl_didFinishLaunching, (IMP*)&orig_didFinishLaunching);
        }
    }
}
