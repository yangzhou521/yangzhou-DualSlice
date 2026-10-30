// SileoFix —— 修 SileoWallpaper 让 Sileo 输入框点不进去、键盘打不开的问题。
//
// 症状：任意软件源页里的「搜索软件包」输入框点了没反应（键盘不弹、打字不进）。
// 成因：壁纸插件的装饰视图（SW* / UIVisualEffectView / _UIBackdropView 等）盖在
//       输入框上面并吃掉了触摸。本插件不改壁纸，只做两件事：
//       ① 在 Sileo 里按控件的真实中心点做 hitTest，若命中的视图既不是它的祖先、
//          也不是它的子孙（＝有盖板），就把盖板设成 userInteractionEnabled=NO；
//       ② 兜底：窗口收到「手指按下」时若命中的不是控件、而底下其实有控件，
//          直接把焦点交给下面的输入框（或触发那个按钮），这样即使盖板类名不认识也能用。
//
// 诊断日志：os_log（默认级别，统一日志可见）subsystem com.yangzhou.sileofix
//   icli log syslog --subsystem com.yangzhou.sileofix
//
// 版本：1.0.1

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <substrate.h>

#define SW_VERSION "1.0.1"

static os_log_t SWLogHandle(void) {
    static os_log_t handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = os_log_create("com.yangzhou.sileofix", "fix");
    });
    return handle;
}

// 用默认级别（os_log 而不是 os_log_info）：info 级默认不进统一日志，诊断会瞎。
#define SWLOGF(fmt, ...) os_log(SWLogHandle(), fmt, ##__VA_ARGS__)

// 落地标记：本机读日志不可靠时，直接看文件就知道插件有没有注入、拦到了谁。
// 路径是 jbroot 里的 /var/mobile/Library/Preferences/.sileofix.log（mobile 可写）。
static void SWMarker(NSString *line) {
    if (!line) return;
    NSString *path = @"/var/mobile/Library/Preferences/.sileofix.log";
    NSString *old = [NSString stringWithContentsOfFile:path
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    if (!old) old = @"";
    if (old.length > 6000) old = [old substringFromIndex:old.length - 4000];
    NSString *now = [NSString stringWithFormat:@"%@\n", line];
    [[old stringByAppendingString:now] writeToFile:path
                                        atomically:YES
                                          encoding:NSUTF8StringEncoding
                                             error:NULL];
}

/// 状态变化事件：既进统一日志，也追加到标记文件。
static void SWNote(NSString *line) {
    if (!line) return;
    os_log(SWLogHandle(), "%{public}@", line);
    SWMarker(line);
}

#pragma mark - 工具

// 装饰层判定：壁纸插件的视图优先被认定。
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

static BOOL SWIsControl(UIView *v) {
    if ([v isKindOfClass:[UIControl class]]) return YES;
    Class barClass = NSClassFromString(@"UISearchBar");
    if (barClass && [v isKindOfClass:barClass]) return YES;
    return NO;
}

// 在窗口里找「点 p（窗口坐标）下面最深的那个控件」，跳过隐藏/不可交互的。
static UIView *SWFindControlAt(UIView *v, CGPoint pInV) {
    if (!v || v.hidden || v.alpha < 0.01 || !v.userInteractionEnabled) return nil;
    if (!CGRectContainsPoint(v.bounds, pInV)) return nil;
    for (UIView *sub in [v.subviews reverseObjectEnumerator]) {
        CGPoint q = [sub convertPoint:pInV fromView:v];
        UIView *r = SWFindControlAt(sub, q);
        if (r) return r;
    }
    if (SWIsControl(v)) return v;
    return nil;
}

#pragma mark - 核心修复

// 对一个控件做「谁吃掉了触摸」检查，必要时关掉盖板的交互。
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
            // 正常：控件自己就是命中目标，不用管（不打日志，免得刷屏）。
            return;
        }
        SWNote([NSString stringWithFormat:@"BLOCKED field=%@ hit=%@ decorative=%d chain=%@",
                fname, NSStringFromClass([hit class]), SWIsDecorative(hit) ? 1 : 0,
                SWChainDescription(hit)]);
        if (SWIsControl(hit)) {
            // 命中的是另一个控件：那是 Sileo 自己的东西，不动。
            return;
        }
        hit.userInteractionEnabled = NO;
        SWNote([NSString stringWithFormat:@"disabled %@", NSStringFromClass([hit class])]);
    }
}

static void SWFixTree(UIView *v) {
    if (!v) return;
    if (SWIsControl(v) && v.bounds.size.width > 1 && v.bounds.size.height > 1) {
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

// 布局是异步的：控件刚进窗口时盖板可能还没摆好，稍后补几刀。
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

static void (*sw_orig_didMoveToWindow)(id, SEL);
static void sw_hook_didMoveToWindow(id self, SEL _cmd) {
    sw_orig_didMoveToWindow(self, _cmd);
    UIView *v = (UIView *)self;
    if (v.window && SWIsControl(v)) SWFixFieldWithRetries(v);
}

// ① 把命中盖板关掉；② 盖板已经被关掉也仍然没拿到焦点时，直接替它把焦点/点击交下去。
static void (*sw_orig_sendEvent)(id, SEL, UIEvent *);
static void sw_hook_sendEvent(id self, SEL _cmd, UIEvent *event) {
    sw_orig_sendEvent(self, _cmd, event);

    UIWindow *win = (UIWindow *)self;
    if (!win.isKeyWindow) return;
    if (!event || event.type != UIEventTypeTouches) return;

    for (UITouch *t in [event allTouches]) {
        if (t.phase != UITouchPhaseBegan) continue;
        CGPoint p = [t locationInWindow];

        UIView *hit = [win hitTest:p withEvent:event];
        if (!hit) continue;
        if (SWIsControl(hit)) continue;          // 正常命中控件，交给系统

        UIView *target = SWFindControlAt(win, p);
        if (!target) continue;
        if (SWIsAncestorOf(hit, target)) continue;  // 命中的是目标自己的祖先，按原样来

        if (!SWIsControl(hit)) {
            hit.userInteractionEnabled = NO;
            SWNote([NSString stringWithFormat:@"sendEvent: disabled %@ eating %@ at <%.0f,%.0f>",
                    NSStringFromClass([hit class]), NSStringFromClass([target class]), p.x, p.y]);
        }
        UIView *t2 = target;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([t2 isKindOfClass:[UITextField class]]) {
                SWNote([NSString stringWithFormat:@"sendEvent: focus %@", NSStringFromClass([t2 class])]);
                [(UITextField *)t2 becomeFirstResponder];
            } else if ([t2 isKindOfClass:[UIControl class]]) {
                SWNote([NSString stringWithFormat:@"sendEvent: tap %@", NSStringFromClass([t2 class])]);
                [(UIControl *)t2 sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        });
    }
}

static void SWStartSweeper(void) {
    __block int ticks = 0;
    [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *timer) {
        if (++ticks > 40) {
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
                            (IMP)&sw_hook_didMoveToWindow, (IMP *)&sw_orig_didMoveToWindow);
        }
        Class sb = objc_getClass("UISearchBar");
        if (sb) {
            MSHookMessageEx(sb, @selector(didMoveToWindow),
                            (IMP)&sw_hook_didMoveToWindow, (IMP *)&sw_orig_didMoveToWindow);
        }
        Class win = objc_getClass("UIWindow");
        if (win) {
            MSHookMessageEx(win, @selector(sendEvent:),
                            (IMP)&sw_hook_sendEvent, (IMP *)&sw_orig_sendEvent);
        }
        SWNote(@"loaded v" SW_VERSION);
        // 也记一份窗口/类清单，方便判断注入成功但没命中。
        dispatch_async(dispatch_get_main_queue(), ^{
            SWStartSweeper();
        });
    }
}