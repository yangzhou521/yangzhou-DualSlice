// SileoFix —— 修 SileoWallpaper 让 Sileo 输入框点不进去、键盘打不开的问题。
//
// 症状：任意软件源页里的「搜索软件包」输入框点了没反应（键盘不弹、打字不进）。
// 成因：SileoWallpaper 在 Sileo 的导航栏/页面里插 UIBackdropView / UIVisualEffectView
//       盖板（类名 SW*），盖在搜索栏上并吃掉了触摸。本插件不改壁纸、不碰
//       SileoWallpaper 的文件，只做两件事：
//       ① 对每个输入控件按真实中心点做 hitTest，命中的若是「装饰盖板」而它既不是
//          控件的祖先也不是子孙，就把盖板设成 userInteractionEnabled = NO；
//       ② 兜底：窗口收到「手指按下」时若命中的是装饰盖板、而底下有控件，
//          直接把焦点交给下面的输入框（或触发那个按钮）。
//
// 诊断：
//   os_log  subsystem com.yangzhou.sileofix → icli log syslog --subsystem com.yangzhou.sileofix
//   文件日志（Sileo 沙盒内的 Caches/sileofix.log，App 外部可读）：
//     icli fs ls /var/mobile/Containers/Data/Application | grep -i sileo
//
// 版本：1.0.3
//   1.0.3：取证版。1.0.2 的日志证明源内页「搜索软件包」的中心点 hitTest 命中的
//          就是 UISearchBarTextField 自己，所以「装饰盖板吃触摸」不是病因——命中
//          之后就 return 了，等于没查。本版补三处量：① 全部 UIWindow（壁纸若自建
//          独立窗口并设 windowLevel，主窗口 hitTest 根本看不见它）；② 搜索栏与
//          文本框各自的 delegate、能否成为第一响应者；③ 真实点击（TouchBegan）
//          落在搜索栏区域内时的命中链，以及键盘窗口是否已出现。
//   1.0.2：修 1.0.1 的致命崩溃 —— UITextField 与 UISearchBar 的 didMoveToWindow
//          共用一个原 IMP 槽，第二站把槽覆盖成自己的原实现，文本框移动窗口时
//          执行 search bar 的实现而崩（KERN_INVALID_ADDRESS，objc_msgSend
//          searchDisplayController）。现在一站一槽（AGENTS.md「一站一槽」规矩）。
//          日志改写到 App 沙盒（原来写 /var/mobile/Library/Preferences 被沙盒拒，
//          一个字都没落下）；新增自动诊断，无需用户点击就能抓到搜索栏现场。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <substrate.h>

#define SW_VERSION "1.0.3"

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

// 落地标记：本机读统一日志不可靠时，直接看文件就知道插件拦到了谁。
// 必须写在 App 自己的沙盒里 —— Sileo 无权写 /var/mobile/Library/Preferences。
static NSString *SWLogFilePath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                              NSUserDomainMask, YES);
        NSString *dir = caches.firstObject;
        if (dir.length) path = [dir stringByAppendingPathComponent:@"sileofix.log"];
        if (!path) path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sileofix.log"];
    });
    return path;
}

static void SWMarker(NSString *line) {
    if (!line) return;
    NSString *path = SWLogFilePath();
    if (!path) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:nil attributes:nil];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) return;
    @try {
        [fh seekToEndOfFile];
        // 文件太大就重开，别让它无限长。
        if ([fh offsetInFile] > 200 * 1024) {
            [fh truncateFileAtOffset:0];
        }
        NSData *data = [[line stringByAppendingString:@"\n"]
                        dataUsingEncoding:NSUTF8StringEncoding];
        [fh writeData:data];
        [fh closeFile];
    } @catch (__unused NSException *e) {
    }
}

/// 状态变化事件：既进统一日志，也追加到标记文件。
static void SWNote(NSString *line) {
    if (!line) return;
    os_log(SWLogHandle(), "%{public}@", line);
    SWMarker(line);
}

#pragma mark - 工具

// 装饰层判定：SileoWallpaper 的视图优先被认定。
static BOOL SWIsDecorative(UIView *v) {
    if (!v) return NO;
    NSString *cn = NSStringFromClass([v class]);
    if (!cn) return NO;
    if ([cn hasPrefix:@"SW"]) return YES;
    if ([cn rangeOfString:@"Backdrop"].location != NSNotFound) return YES;
    if ([cn rangeOfString:@"Effect"].location != NSNotFound &&
        [cn rangeOfString:@"Search"].location == NSNotFound) return YES;
    Class effect = NSClassFromString(@"UIVisualEffectView");
    if (effect && [v isKindOfClass:effect]) return YES;
    Class backdrop = NSClassFromString(@"_UIBackdropView");
    if (backdrop && [v isKindOfClass:backdrop]) return YES;
    return NO;
}

// a 是否为 v 的祖先（含自身）
static BOOL SWIsAncestorOf(UIView *a, UIView *v) {
    for (UIView *p = v; p; p = p.superview) {
        if (p == a) return YES;
    }
    return NO;
}

static NSString *SWDescribe(UIView *v) {
    if (!v) return @"nil";
    return [NSString stringWithFormat:@"%@<%.0f,%.0f %.0fx%.0f>%@",
            NSStringFromClass([v class]),
            v.frame.origin.x, v.frame.origin.y,
            v.frame.size.width, v.frame.size.height,
            v.userInteractionEnabled ? @"" : @"(noUI)"];
}

static NSString *SWChainDescription(UIView *v) {
    NSMutableString *s = [NSMutableString string];
    int depth = 0;
    for (UIView *p = v; p && depth < 8; p = p.superview, depth++) {
        [s appendString:SWDescribe(p)];
        [s appendString:@" "];
    }
    return s;
}

static UIWindow *SWMainWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *fallback = nil;
    for (UIWindow *w in app.windows) {
        if (w.isHidden || w.alpha < 0.01) continue;
        if (!fallback) fallback = w;
        if (w.isKeyWindow) return w;
    }
    return fallback ?: app.windows.firstObject;
}

static BOOL SWIsControl(UIView *v) {
    if ([v isKindOfClass:[UIControl class]]) return YES;
    Class barClass = NSClassFromString(@"UISearchBar");
    if (barClass && [v isKindOfClass:barClass]) return YES;
    return NO;
}

// 全部窗口一览。壁纸可能自建独立 UIWindow（层级更高），主窗口的 hitTest 看不见它，
// 但系统派发触摸时它排在最前面——这是「主窗口命中控件、用户却点不进去」的唯一解释通道。
static NSString *SWWindowsDescription(void) {
    NSMutableString *s = [NSMutableString stringWithFormat:@"wins=%lu",
                          (unsigned long)[UIApplication sharedApplication].windows.count];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        [s appendFormat:@" [%@ lvl=%.0f hid=%d a=%.2f key=%d]",
         SWDescribe(w), w.windowLevel, w.isHidden ? 1 : 0, w.alpha,
         w.isKeyWindow ? 1 : 0];
    }
    return s;
}

static NSString *SWClassNameOf(id obj) {
    if (!obj || obj == [NSNull null]) return @"nil";
    Class c = [obj class];
    return c ? NSStringFromClass(c) : @"?";
}

// 在视图里找「点 p（v 的坐标）下面最深的那个控件」，跳过隐藏/不可交互的。
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

// 收集某一类视图（限深度，免得撞见巨型树）。
static void SWCollect(UIView *v, Class cls, NSMutableArray<UIView *> *out, int depth) {
    if (!v || depth > 40 || out.count > 40) return;
    if ([v isKindOfClass:cls]) [out addObject:v];
    for (UIView *sub in v.subviews) {
        SWCollect(sub, cls, out, depth + 1);
    }
}

#pragma mark - 核心修复

// 对一个控件做「谁吃掉了触摸」检查，必要时关掉装饰盖板的交互。
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
        SWNote([NSString stringWithFormat:@"BLOCKED field=%@ hit=%@ chain=%@",
                fname, SWDescribe(hit), SWChainDescription(hit)]);
        if (SWIsControl(hit)) {
            // 命中的是另一个控件：那是 Sileo 自己的东西，不动。
            return;
        }
        if (!SWIsDecorative(hit)) {
            // 只动装饰盖板。别的视图是 Sileo 自己的，禁掉只会把它弄坏。
            SWNote([NSString stringWithFormat:@"left-alone %@", SWDescribe(hit)]);
            return;
        }
        hit.userInteractionEnabled = NO;
        SWNote([NSString stringWithFormat:@"disabled %@", SWDescribe(hit)]);
    }
}

static void SWFixTree(UIView *v, int depth) {
    if (!v || depth > 40) return;
    if (SWIsControl(v) && v.bounds.size.width > 1 && v.bounds.size.height > 1) {
        SWFixField(v);
    }
    for (UIView *sub in v.subviews) {
        SWFixTree(sub, depth + 1);
    }
}

static void SWFixAllFields(void) {
    UIWindow *win = SWMainWindow();
    if (win) SWFixTree(win, 0);
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

#pragma mark - 诊断

// 一次性把「搜索栏现在什么样、谁盖着它」写进日志，不需要用户去点。
static void SWDiagSearchBars(NSString *tag) {
    @autoreleasepool {
        UIWindow *win = SWMainWindow();
        if (!win) {
            SWNote([NSString stringWithFormat:@"DIAG(%@) no-window", tag]);
            return;
        }
        Class barCls = NSClassFromString(@"UISearchBar");
        if (!barCls) return;
        NSMutableArray<UIView *> *bars = [NSMutableArray array];
        SWCollect(win, barCls, bars, 0);

        NSMutableString *head = [NSMutableString stringWithFormat:
            @"DIAG(%@) window=%@ bars=%lu wallpaper=%d %@",
            tag, SWDescribe(win), (unsigned long)bars.count,
            NSClassFromString(@"SWPage") ? 1 : 0,
            SWWindowsDescription()];
        // 也把导航栏的图层列一下：盖板通常就贴在 nav bar 上。
        Class navCls = NSClassFromString(@"UINavigationBar");
        if (navCls) {
            NSMutableArray<UIView *> *navs = [NSMutableArray array];
            SWCollect(win, navCls, navs, 0);
            for (UIView *nav in navs) {
                [head appendFormat:@" | nav=%@ subs=%lu", SWDescribe(nav),
                 (unsigned long)nav.subviews.count];
                for (UIView *sub in nav.subviews) {
                    [head appendFormat:@" [%@]", SWDescribe(sub)];
                }
            }
        }
        SWNote(head);

        for (UIView *bar in bars) {
            NSMutableString *line = [NSMutableString stringWithFormat:@"  BAR %@ inWin=%@",
                                     SWDescribe(bar), bar.window ? @"yes" : @"no"];
            if (bar.window) {
                CGPoint p = [bar convertPoint:CGPointMake(CGRectGetMidX(bar.bounds),
                                                          CGRectGetMidY(bar.bounds))
                                       toView:win];
                UIView *hit = [win hitTest:p withEvent:nil];
                [line appendFormat:@" hit=%@", SWDescribe(hit)];
                [line appendFormat:@" chain=%@", SWChainDescription(hit)];
            }
            id tf = nil;
            @try {
                tf = [bar valueForKey:@"_searchField"];
            } @catch (__unused NSException *e) {
                tf = nil;
            }
            if (![tf isKindOfClass:[UIView class]]) {
                NSMutableArray<UIView *> *tfs = [NSMutableArray array];
                Class tfCls = NSClassFromString(@"UITextField");
                if (tfCls) SWCollect(bar, tfCls, tfs, 0);
                tf = tfs.firstObject;
            }
            if ([tf isKindOfClass:[UIView class]]) {
                UIView *t = (UIView *)tf;
                id barDelegate = nil, fieldDelegate = nil;
                @try { barDelegate = [bar valueForKey:@"delegate"]; } @catch (__unused NSException *e) {}
                @try { fieldDelegate = [t valueForKey:@"delegate"]; } @catch (__unused NSException *e) {}
                [line appendFormat:@" | field=%@ enabled=%d first=%d editable=%d canBecome=%d barD=%@ fieldD=%@",
                 SWDescribe(t),
                 [t isKindOfClass:[UIControl class]] ? [(UIControl *)t isEnabled] : -1,
                 [t isFirstResponder] ? 1 : 0,
                 [[t valueForKey:@"isEditable"] boolValue],
                 [t canBecomeFirstResponder] ? 1 : 0,
                 SWClassNameOf(barDelegate), SWClassNameOf(fieldDelegate)];
                [line appendFormat:@" fchain=%@", SWChainDescription(t)];
            } else {
                [line appendString:@" | field=<none>"];
            }
            SWNote(line);
        }
    }
}

// 真实点击落在搜索栏区域内时，把「谁接到了这一下」原样记下来。这是唯一能证明
// 「系统把触摸派给谁」的证据：主窗口 hitTest 命中控件、用户却点不进去时，答案要么在
// 另一只窗口，要么在这条链的某个 delegate 上。
static void SWNoteClickInSearchBar(UIWindow *win, CGPoint p, UIView *hit) {
    Class barCls = NSClassFromString(@"UISearchBar");
    if (!barCls) return;
    NSMutableArray<UIView *> *bars = [NSMutableArray array];
    SWCollect(win, barCls, bars, 0);
    for (UIView *bar in bars) {
        CGRect r = [bar convertRect:bar.bounds toView:win];
        if (!CGRectContainsPoint(r, p)) continue;
        SWNote([NSString stringWithFormat:@"CLICK <%.0f,%.0f> inBar=%@ hit=%@ chain=%@ | %@",
                p.x, p.y, SWDescribe(bar), SWDescribe(hit),
                SWChainDescription(hit), SWWindowsDescription()]);
        return;
    }
}

#pragma mark - 钩子（每一站一个静态原 IMP 槽：AGENTS.md「一站一槽」）

static void (*sw_orig_viewDidAppear)(id, SEL, BOOL);
static void sw_hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    sw_orig_viewDidAppear(self, _cmd, animated);
    SWFixAllFields();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SWFixAllFields();
    });
}

// UITextField 自己的一站。
static void (*sw_orig_tf_didMoveToWindow)(id, SEL);
static void sw_hook_tf_didMoveToWindow(id self, SEL _cmd) {
    sw_orig_tf_didMoveToWindow(self, _cmd);
    UIView *v = (UIView *)self;
    if (v.window && SWIsControl(v)) SWFixFieldWithRetries(v);
}

// UISearchBar 是另一站，必须是另一个槽 —— 1.0.1 就是这里共用槽把 Sileo 打崩的。
static void (*sw_orig_sb_didMoveToWindow)(id, SEL);
static void sw_hook_sb_didMoveToWindow(id self, SEL _cmd) {
    sw_orig_sb_didMoveToWindow(self, _cmd);
    UIView *v = (UIView *)self;
    if (!v.window) return;
    SWFixFieldWithRetries(v);
    SWDiagSearchBars(@"sb-didMove");
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
        CGPoint p = [t locationInView:win];

        UIView *hit = [win hitTest:p withEvent:event];
        SWNoteClickInSearchBar(win, p, hit);
        if (!hit) continue;
        if (SWIsControl(hit)) continue;          // 正常命中控件，交给系统

        UIView *target = SWFindControlAt(win, p);
        if (!target) continue;
        if (SWIsAncestorOf(hit, target)) continue;  // 命中的是目标自己的祖先，按原样来
        if (!SWIsDecorative(hit)) continue;         // 只处理装饰盖板

        hit.userInteractionEnabled = NO;
        SWNote([NSString stringWithFormat:@"sendEvent: disabled %@ eating %@ at <%.0f,%.0f>",
                SWDescribe(hit), SWDescribe(target), p.x, p.y]);
        UIView *t2 = target;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([t2 isKindOfClass:[UITextField class]]) {
                SWNote([NSString stringWithFormat:@"sendEvent: focus %@", SWDescribe(t2)]);
                [(UITextField *)t2 becomeFirstResponder];
            } else if ([t2 isKindOfClass:[UIControl class]]) {
                SWNote([NSString stringWithFormat:@"sendEvent: tap %@", SWDescribe(t2)]);
                [(UIControl *)t2 sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        });
    }
}

// 焦点链取证：搜索栏的文本框到底有没有被要求成为第一响应者，返回的是 YES 还是 NO。
// 返回 NO 说明被 delegate 的 textFieldShouldBeginEditing 之类拦了；压根没被调用，
// 说明触摸根本没走到文本框（或点击被别的窗口/视图吃掉）。
static void SWLogBecomeFirstResponder(UIView *v, BOOL result) {
    NSString *cn = NSStringFromClass([v class]);
    if (!cn) return;
    if ([cn rangeOfString:@"Search" options:NSCaseInsensitiveSearch].location == NSNotFound) return;
    SWNote([NSString stringWithFormat:@"becomeFirstResponder %@ -> %d first=%d",
            SWDescribe(v), result ? 1 : 0, [v isFirstResponder] ? 1 : 0]);
}

// UITextField 一站。
static BOOL (*sw_orig_tf_become)(id, SEL);
static BOOL sw_hook_tf_become(id self, SEL _cmd) {
    BOOL r = sw_orig_tf_become(self, _cmd);
    SWLogBecomeFirstResponder((UIView *)self, r);
    return r;
}

// UISearchBarTextField 自己的一站（若它自己重写了该方法，走这里；槽必须独立）。
static BOOL (*sw_orig_sbtf_become)(id, SEL);
static BOOL sw_hook_sbtf_become(id self, SEL _cmd) {
    BOOL r = sw_orig_sbtf_become(self, _cmd);
    SWLogBecomeFirstResponder((UIView *)self, r);
    return r;
}

static void SWStartSweeper(void) {
    __block int ticks = 0;
    [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *timer) {
        if (++ticks > 40) {
            [timer invalidate];
            return;
        }
        SWFixAllFields();
        if (ticks <= 4) SWDiagSearchBars([NSString stringWithFormat:@"tick%d", ticks]);
    }];
}

// 只在类自己声明了该选择器时才 hook，避免把父类的实现挂到子类头上（配「一站一槽」）。
static BOOL SWClassDeclares(Class cls, SEL sel) {
    if (!cls) return NO;
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    BOOL found = NO;
    for (unsigned int i = 0; i < n; i++) {
        if (method_getName(list[i]) == sel) {
            found = YES;
            break;
        }
    }
    if (list) free(list);
    return found;
}

__attribute__((constructor)) static void SileoFixInit(void) {
    @autoreleasepool {
        Class vc = objc_getClass("UIViewController");
        if (vc && SWClassDeclares(vc, @selector(viewDidAppear:))) {
            MSHookMessageEx(vc, @selector(viewDidAppear:),
                            (IMP)&sw_hook_viewDidAppear, (IMP *)&sw_orig_viewDidAppear);
        }
        Class tf = objc_getClass("UITextField");
        if (tf && SWClassDeclares(tf, @selector(didMoveToWindow))) {
            MSHookMessageEx(tf, @selector(didMoveToWindow),
                            (IMP)&sw_hook_tf_didMoveToWindow, (IMP *)&sw_orig_tf_didMoveToWindow);
        }
        Class sb = objc_getClass("UISearchBar");
        if (sb && SWClassDeclares(sb, @selector(didMoveToWindow))) {
            MSHookMessageEx(sb, @selector(didMoveToWindow),
                            (IMP)&sw_hook_sb_didMoveToWindow, (IMP *)&sw_orig_sb_didMoveToWindow);
        }
        Class win = objc_getClass("UIWindow");
        if (win && SWClassDeclares(win, @selector(sendEvent:))) {
            MSHookMessageEx(win, @selector(sendEvent:),
                            (IMP)&sw_hook_sendEvent, (IMP *)&sw_orig_sendEvent);
        }
        Class sbtf = objc_getClass("UISearchBarTextField");
        if (sbtf && SWClassDeclares(sbtf, @selector(becomeFirstResponder))) {
            MSHookMessageEx(sbtf, @selector(becomeFirstResponder),
                            (IMP)&sw_hook_sbtf_become, (IMP *)&sw_orig_sbtf_become);
        }
        if (tf && SWClassDeclares(tf, @selector(becomeFirstResponder))) {
            MSHookMessageEx(tf, @selector(becomeFirstResponder),
                            (IMP)&sw_hook_tf_become, (IMP *)&sw_orig_tf_become);
        }
        // 每次加载清空上一次的日志：只留下一轮的现场，读起来才不混。
        NSString *logPath = SWLogFilePath();
        if (logPath) [[NSFileManager defaultManager] removeItemAtPath:logPath error:NULL];
        SWNote([NSString stringWithFormat:@"loaded v%s log=%@", SW_VERSION, SWLogFilePath()]);
        dispatch_async(dispatch_get_main_queue(), ^{
            SWStartSweeper();
        });
    }
}