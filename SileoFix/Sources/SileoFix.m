// SileoFix —— 修 SileoWallpaper 让 Sileo 输入框点不进去、键盘打不开的问题。
//
// 症状：任意软件源页里的「搜索软件包」输入框点了没反应（键盘不弹、打字不进）。
// 成因：壁纸插件的装饰视图（SW* / UIVisualEffectView / _UIBackdropView）盖在输入框上面
//       并吃掉了触摸。本插件不改壁纸，只做一件事：
//       在 Sileo 里按输入框的真实中心点做 hitTest，如果命中的视图既不是输入框的祖先、
//       也不是它的子孙（＝有个盖板挡住了），就把这个装饰盖板设成 userInteractionEnabled=NO，
//       触摸于是自然落到下面的输入框上。
//
// 只动「装饰层」：类名以 SW 开头、名字含 Backdrop、或者是 UIVisualEffectView。
// 遇到说不清来源的盖板只记日志、不动它，避免把 Sileo 自己的控件弄坏。
//
// 诊断日志：os_log subsystem com.yangzhou.sileofix，category fix
//   icli log syslog --subsystem com.yangzhou.sileofix
//
// 版本：1.0.0

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <substrate.h>

#define SW_VERSION "1.0.0"

static os_log_t SWLogHandle(void) {
    static os_log_t handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = os_log_create("com.yangzhou.sileofix", "fix");
    });
    return handle;
}

#define SWLOGF(fmt, ...) os_log_info(SWLogHandle(), fmt, ##__VA_ARGS__)

#pragma mark - 工具

// 装饰层判定：只对这类视图动手。
static BOOL SWIsDecorative(UIView *v) {
    if (!v) return NO;
    NSString *cn = NSStringFromClass([v class]);
    if (!cn) return NO;
    if ([cn hasPrefix:@"SW"]) return YES;
    if ([cn rangeOfString:@"Backdrop"].location != NSNotFound) return YES;
    Class effect = NSClassFromString(@"UIVisualEffectView");
    if (effect && [v isKindOfClass:effect]) return YES;
    return NO;
}

// a 是否为 v 的祖先（含自身）
static BOOL SWIsAncestorOf(UIView *a, UIView *v) {
    for (UIView *p = v; p; p = p.superview) {
        if (p == a) return YES;
    }
    return NO;
}

static NSString *SWChainDescription(UIView *v) {
    NSMutableString *s = [NSMutableString string];
    int depth = 0;
    for (UIView *p = v; p && depth < 8; p = p.superview, depth++) {
        [s appendFormat:@"%@<%.0f,%.0f %.0fx%.0f>%@ ", NSStringFromClass([p class]),
            p.frame.origin.x, p.frame.origin.y, p.frame.size.width, p.frame.size.height,
            p.userInteractionEnabled ? @"" : @"(noUI)"];
    }
    return s;
}

static UIWindow *SWMainWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIWindow *w in app.windows) {
        if (w.isKeyWindow) return w;
    }
    return app.windows.firstObject;
}

#pragma mark - 核心修复

// 对一个输入框做「谁吃掉了触摸」检查，必要时关掉盖板的交互。
static void SWFixField(UIView *field) {
    if (!field) return;
    UIWindow *win = field.window;
    if (!win) return;

    CGPoint p = [field convertPoint:CGPointMake(CGRectGetMidX(field.bounds),
                                                CGRectGetMidY(field.bounds))
                             toView:win];
    NSString *fname = NSStringFromClass([field class]);

    for (int i = 0; i < 4; i++) {
        UIView *hit = [win hitTest:p withEvent:nil];
        if (!hit) {
            SWLOGF("field=%{public}@ hit=nil", fname);
            return;
        }
        BOOL reached = (hit == field) || SWIsAncestorOf(hit, field) || SWIsAncestorOf(field, hit);
        if (reached) {
            SWLOGF("OK field=%{public}@ hit=%{public}@ step=%d", fname,
                   NSStringFromClass([hit class]), i);
            return;
        }
        SWLOGF("BLOCKED field=%{public}@ hit=%{public}@ decorative=%d chain=%{public}@",
               fname, NSStringFromClass([hit class]), SWIsDecorative(hit) ? 1 : 0,
               SWChainDescription(hit));
        if (!SWIsDecorative(hit)) {
            // 来源不明：只记录，不下手。
            return;
        }
        hit.userInteractionEnabled = NO;
        SWLOGF("disabled %{public}@", NSStringFromClass([hit class]));
    }
}

static void SWFixTree(UIView *v) {
    if (!v) return;
    BOOL interesting = [v isKindOfClass:[UIControl class]];
    Class barClass = NSClassFromString(@"UISearchBar");
    if (barClass && [v isKindOfClass:barClass]) interesting = YES;
    if (interesting && v.bounds.size.width > 1 && v.bounds.size.height > 1) {
        SWFixField(v);
    }
    for (UIView *sub in v.subviews) {
        SWFixTree(sub);
    }
}

static void SWFixAllFields(void) {
    UIWindow *win = SWMainWindow();
    if (win) SWFixTree(win);
}

// 布局是异步的：输入框刚进窗口时盖板可能还没摆好，稍后补几刀。
static void SWFixFieldWithRetries(UIView *field) {
    SWFixField(field);
    __weak UIView *weakField = field;
    for (int i = 1; i <= 3; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * i * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView *f = weakField;
            if (f) SWFixField(f);
        });
    }
}

#pragma mark - 钩子

static void (*sw_orig_viewDidAppear)(id, SEL, BOOL);
static void sw_hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    sw_orig_viewDidAppear(self, _cmd, animated);
    SWFixAllFields();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SWFixAllFields();
    });
}

static void (*sw_orig_tf_didMoveToWindow)(id, SEL);
static void sw_hook_tf_didMoveToWindow(id self, SEL _cmd) {
    sw_orig_tf_didMoveToWindow(self, _cmd);
    if ([(UIView *)self window]) SWFixFieldWithRetries((UIView *)self);
}

static void (*sw_orig_sb_didMoveToWindow)(id, SEL);
static void sw_hook_sb_didMoveToWindow(id self, SEL _cmd) {
    sw_orig_sb_didMoveToWindow(self, _cmd);
    if ([(UIView *)self window]) SWFixFieldWithRetries((UIView *)self);
}

static void SWStartSweeper(void) {
    __block int ticks = 0;
    [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *timer) {
        if (++ticks > 20) {
            [timer invalidate];
            return;
        }
        SWFixAllFields();
    }];
}

__attribute__((constructor)) static void SileoFixInit(void) {
    @autoreleasepool {
        Class vc = objc_getClass("UIViewController");
        if (vc) {
            MSHookMessageEx(vc, @selector(viewDidAppear:),
                            (IMP)&sw_hook_viewDidAppear, (IMP *)&sw_orig_viewDidAppear);
        }
        Class tf = objc_getClass("UITextField");
        if (tf) {
            MSHookMessageEx(tf, @selector(didMoveToWindow),
                            (IMP)&sw_hook_tf_didMoveToWindow, (IMP *)&sw_orig_tf_didMoveToWindow);
        }
        Class sb = objc_getClass("UISearchBar");
        if (sb) {
            MSHookMessageEx(sb, @selector(didMoveToWindow),
                            (IMP)&sw_hook_sb_didMoveToWindow, (IMP *)&sw_orig_sb_didMoveToWindow);
        }
        SWLOGF("SileoFix loaded v" SW_VERSION);
        dispatch_async(dispatch_get_main_queue(), ^{
            SWStartSweeper();
        });
    }
}