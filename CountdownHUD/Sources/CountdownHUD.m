//
// CountdownHUD.m —— SpringBoard 侧的自绘胶囊（「倒计时上岛」+ 纯文案提醒）
//
// v1.2.0：同一个胶囊多了一种「纯文案」用法 —— 标签以 `!` 开头时，屏幕上是这句话本身
//   （不显示「N 秒后」前缀、不跳数字、不做绿→橙→红的倒计时升级），显示 N 秒后淡出。
//   用途：任务做完 / 阶段完成 / 工作进度，用户去了别的对话、桌面或别的 App 时也能在岛上看到。
//   例：`<epoch>|8|!完成：ThemeControl 设置面板`。诊断串因此多了 `mode=plain|count`。
//
// v1.1.1：文字压到原来的 2/3（位置系数「高度 × 0.5」→「高度 ÷ 3」，本机 125×37 的岛上
//   约 12.3pt），并换成等宽数字 + Medium 字重 —— 用户 2026-10-30 反馈「字体太大、不够精致」。
//   同一版里常规字色由白改成系统绿 #34C759，仍是「绿 → 橙（剩 3 秒）→ 红（剩 ≤2 秒）」。
// v1.1.0：胶囊不再用写死的 190×44，而是**量着岛画**。
//   本机的「灵动岛」不是硬件自带的（iPhone10,1 = iPhone 8），是 DynamicX 用系统那套
//   SBSystemAperture* 造出来的假岛；外观还被 IslandGlass 换肤、位置由 VisibleIsland 的
//   yPos 调。所以启动时（以及显示期间每秒）我们在 SpringBoard 自己的窗口里找那只横向
//   胶囊 —— 优先 SystemAperture 窗口里的容器视图 —— 把它的 frame 原样拿来当胶囊的 frame：
//   尺寸、位置自然和岛一致，岛一动（被 VisibleIsland 挪、DynamicX 换布局）也跟着动。
//   找不到（没装岛类插件）才退回写死的 190×44 / 安全区顶 +6。
//
//   量到了什么，写在诊断里：
//     icli prefs read com.apple.springboard CountdownHUDDiagnostics
//     → v1.1.1;shows=N;last=5s;label=注销;font=12.3;island=<类名>|x,y,w,h;src=aperture;cand=N
//   候选清单另写一条 CountdownHUDIslandCandidates（最多 8 行：`A|<类名>|x,y,w,h`，
//   前缀 A = 该候选在 SystemAperture 窗口里），量错了好回头核对。
//
// 触发方式（故意不用 Darwin 通知：本机没有 notifyutil，icli 也不发通知）：
//   脚本把请求写进 /var/mobile/Library/Preferences/.countdownhud-request，
//   格式 `<epoch>|<秒数>|<标签>`；插件每 0.5 秒读一次这个文件，内容变了就倒数。
//   读失败 / 文件不存在都只是什么都不做。
//
// 规矩（AGENTS.md 硬规矩）：
//   - 不用私有类发消息：只用公开的 UIWindow / UIView / UILabel / NSTimer，
//     岛是「按类名认出来的」，不是拿私有类去调的。
//   - 没有 MSHookMessageEx，连 substrate 都不链，全部逻辑在 constructor 里起一个轮询。
//   - 诊断写进目标进程自己的偏好域（kCFPreferencesCurrentApplication = com.apple.springboard）。
//   - 日志走 os_log，subsystem 是包名，格式化符带 %{public}。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <os/log.h>

static NSString *const CHVersion = @"1.3.0";
static NSString *const CHRequestPath = @"/var/mobile/Library/Preferences/.countdownhud-request";
static const NSTimeInterval CHPollInterval = 0.5;

// 胶囊窗口的层级：既要盖在灵动岛（SystemAperture 那套）之上，也要盖在任何 App 之上。
static const CGFloat CHWindowLevel = 20000000.0;

// 兜底尺寸：找不到岛的时候才用。
static const CGFloat CHFallbackPillWidth = 190.0;
static const CGFloat CHFallbackPillHeight = 44.0;

// 岛胶囊的「理想」尺寸（真机灵动岛紧凑态），只用于在多个候选里排序。
static const CGFloat CHIdealIslandWidth = 126.0;
static const CGFloat CHIdealIslandHeight = 37.0;

static os_log_t CHLog(void) {
    static os_log_t log = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.yangzhou.countdownhud", "hud");
    });
    return log;
}

#pragma mark - HUD 窗口

// 高于系统 alert（2000），保证盖在 App 与灵动岛之上；并且不吃触摸。
@interface CHWindow : UIWindow
@end

@implementation CHWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}
@end

static CHWindow *gWindow = nil;
static UIView *gPill = nil;
static UILabel *gLabel = nil;
static NSTimer *gTimer = nil;
static NSUInteger gRemaining = 0;
static NSString *gLabelText = @"";
static unsigned long gShows = 0;
static unsigned long gLastSeconds = 0;
static BOOL gPlainNotice = NO;   // v1.2.0：「!」开头的标签＝纯文案，不显示「N 秒后」，不跳数字

// 量岛的结果
static BOOL gFollowIsland = YES;          // 量到岛就跟着岛走
static NSString *gIslandDetail = @"-";    // 诊断串：<类名>|x,y,w,h
static NSString *gIslandSource = @"none"; // aperture / classname / none
static NSUInteger gIslandCandidates = 0;
static NSString *gIslandWindowDetail = @"-"; // v1.3.0 诊断：岛所在的那个窗口 <类名>|lvl=…
static NSString *gSelfWindowDetail = @"-";   // v1.3.0 诊断：我们自己的窗口有没有 scene / 层级
static CGFloat gFontSize = 12.5;         // v1.1.1：诊断串里报出来，省得靠眼睛量字号

// v1.3.0：窗口必须挂在一块真实的 windowScene 上，否则 iOS 13+ 根本不渲染它。
// 老写法在量不到 scene 时退回 `[[UIWindow alloc] initWithFrame:]`，那种窗口有 window、
// 有 subview、isHidden=NO、诊断计数照涨，**屏幕上永远看不见** —— 这就是「注销前用户
// 毫不知情」的根因。现在量不到 scene 就什么都不建，把请求留到下一次轮询重试。
static UIWindowScene *CHPickScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (app == nil) {
        return nil;
    }
    UIWindowScene *fallback = nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState == UISceneActivationStateForegroundActive) {
            return ws;
        }
        if (fallback == nil) {
            fallback = ws;
        }
    }
    return fallback;
}

static NSString *CHClassNameOf(id obj) {
    return obj != nil ? NSStringFromClass([obj class]) : @"nil";
}

#pragma mark - 量岛：在 SpringBoard 自己的窗口里找岛的胶囊矩形

static BOOL CHHasIslandWord(NSString *name) {
    if (name.length == 0) {
        return NO;
    }
    if ([name rangeOfString:@"Island" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }
    return [name rangeOfString:@"Aperture" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// 把 view 的 frame 换到本插件窗口（gWindow）的坐标系。
// 窗口都是贴着屏幕的，跨窗口换算用窗口原点补差就够了。
static CGRect CHRectInHUDWindow(UIView *view) {
    CGRect rect = [view convertRect:view.bounds toView:nil]; // toView:nil = 该 view 所在窗口的坐标系
    UIWindow *w = view.window;
    if (w != nil) {
        rect.origin.x += w.frame.origin.x;
        rect.origin.y += w.frame.origin.y;
    }
    if (gWindow != nil) {
        rect.origin.x -= gWindow.frame.origin.x;
        rect.origin.y -= gWindow.frame.origin.y;
    }
    return rect;
}

static BOOL CHLooksLikeIslandPill(CGRect r, CGFloat screenWidth) {
    if (!isfinite(r.origin.x) || !isfinite(r.origin.y) ||
        !isfinite(r.size.width) || !isfinite(r.size.height)) {
        return NO;
    }
    if (r.size.width < 70.0 || r.size.width > 260.0) {
        return NO;
    }
    if (r.size.height < 20.0 || r.size.height > 70.0) {
        return NO;
    }
    if (r.size.width < r.size.height * 1.2) { // 横向胶囊，不是方块
        return NO;
    }
    if (r.origin.y < -4.0 || CGRectGetMaxY(r) > 120.0) { // 只在屏幕顶上
        return NO;
    }
    if (r.origin.x < 0.0 || CGRectGetMaxX(r) > screenWidth + 0.5) {
        return NO;
    }
    return YES;
}

static void CHCollectPills(UIView *view, NSMutableArray *out, int depth) {
    if (view == nil || depth > 12) {
        return;
    }
    if (gWindow != nil && (view == gWindow || [view isDescendantOfView:gWindow])) {
        return; // 别把自己的胶囊当成岛
    }
    if (view.hidden || view.alpha < 0.05) {
        return;
    }
    CGRect r = CHRectInHUDWindow(view);
    if (CHLooksLikeIslandPill(r, gWindow.bounds.size.width)) {
        [out addObject:@[ CHClassNameOf(view), [NSValue valueWithCGRect:r] ]];
    }
    NSArray<UIView *> *subs = view.subviews;
    for (NSUInteger i = 0; i < subs.count; i++) {
        CHCollectPills(subs[i], out, depth + 1);
    }
}

// 候选打分：SystemAperture 窗口里的、名字像岛本体的、尺寸最接近真机岛的赢。
static double CHPillScore(NSString *cls, CGRect r, BOOL inApertureWindow) {
    double score = 0.0;
    if (inApertureWindow) {
        score += 5.0;
    }
    if ([cls rangeOfString:@"Aperture" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        score += 1.0;
    }
    if ([cls rangeOfString:@"Container" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        score += 0.6;
    }
    if ([cls rangeOfString:@"Background" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        score += 0.4;
    }
    if ([cls rangeOfString:@"Label" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        score -= 0.8;
    }
    score -= fabs(r.size.width - CHIdealIslandWidth) / CHIdealIslandWidth;
    score -= fabs(r.size.height - CHIdealIslandHeight) / CHIdealIslandHeight;
    return score;
}

static NSArray<UIWindow *> *CHWindows(void) {
    NSMutableArray<UIWindow *> *list = [NSMutableArray array];
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (![list containsObject:w]) {
                [list addObject:w];
            }
        }
    }
    return list;
}

// 量岛。成功返回 YES 并把矩形写进 *outRect。
static BOOL CHMeasureIsland(CGRect *outRect) {
    if (gWindow == nil) {
        return NO;
    }
    NSArray<UIWindow *> *windows = CHWindows();
    if (windows.count == 0) {
        return NO;
    }

    NSString *bestClass = nil;
    CGRect bestRect = CGRectZero;
    BOOL bestInAperture = NO;
    UIWindow *bestWindow = nil;
    double bestScore = -1.0e9;
    NSUInteger candidates = 0;
    NSMutableArray<NSString *> *dump = [NSMutableArray array];

    for (UIWindow *w in windows) {
        if (w == gWindow) {
            continue;
        }
        BOOL inAperture = CHHasIslandWord(CHClassNameOf(w));
        NSMutableArray *pills = [NSMutableArray array];
        CHCollectPills(w, pills, 0);
        for (NSArray *entry in pills) {
            NSString *cls = entry[0];
            CGRect r = [entry[1] CGRectValue];
            candidates += 1;
            NSString *line = [NSString stringWithFormat:@"%@|%@|%.0f,%.0f,%.0f,%.0f",
                              inAperture ? @"A" : @"-", cls,
                              r.origin.x, r.origin.y, r.size.width, r.size.height];
            if (dump.count < 8) {
                [dump addObject:line];
            }
        }
    }

    // 第一轮：只看 SystemAperture 窗口里的候选。
    for (UIWindow *w in windows) {
        if (w == gWindow) {
            continue;
        }
        BOOL inAperture = CHHasIslandWord(CHClassNameOf(w));
        if (!inAperture) {
            continue;
        }
        NSMutableArray *pills = [NSMutableArray array];
        CHCollectPills(w, pills, 0);
        for (NSArray *entry in pills) {
            NSString *cls = entry[0];
            CGRect r = [entry[1] CGRectValue];
            double score = CHPillScore(cls, r, YES);
            if (score > bestScore) {
                bestScore = score;
                bestClass = cls;
                bestRect = r;
                bestInAperture = YES;
                bestWindow = w;
            }
        }
    }

    // 第二轮：没有 Aperture 窗口，才退而认「类名里带 Island/Aperture」的视图。
    if (bestClass == nil) {
        for (UIWindow *w in windows) {
            if (w == gWindow) {
                continue;
            }
            NSMutableArray *pills = [NSMutableArray array];
            CHCollectPills(w, pills, 0);
            for (NSArray *entry in pills) {
                NSString *cls = entry[0];
                CGRect r = [entry[1] CGRectValue];
                if (!CHHasIslandWord(cls)) {
                    continue;
                }
                double score = CHPillScore(cls, r, NO);
                if (score > bestScore) {
                    bestScore = score;
                    bestClass = cls;
                    bestRect = r;
                    bestInAperture = NO;
                    bestWindow = w;
                }
            }
        }
    }

    gIslandCandidates = candidates;
    NSString *dumpText = (dump.count > 0) ? [dump componentsJoinedByString:@"\n"] : @"-";
    CFPreferencesSetAppValue(CFSTR("CountdownHUDIslandCandidates"),
                             (__bridge CFStringRef)dumpText,
                             kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);

    if (bestClass == nil || CGRectIsEmpty(bestRect)) {
        gIslandSource = @"none";
        gIslandDetail = @"-";
        gIslandWindowDetail = @"-";
        os_log(CHLog(), "no island pill found (candidates=%lu)", (unsigned long)candidates);
        return NO;
    }

    // 岛所在的那只窗口与它的层级（v1.3.0 诊断）：胶囊的窗口层级必须高过它，否则被岛盖住。
    gIslandWindowDetail = bestWindow
        ? [NSString stringWithFormat:@"%@|lvl=%.0f", CHClassNameOf(bestWindow), bestWindow.windowLevel]
        : @"-";

    NSString *cls = bestClass.length > 48 ? [bestClass substringToIndex:48] : bestClass;
    gIslandSource = bestInAperture ? @"aperture" : @"classname";
    gIslandDetail = [NSString stringWithFormat:@"%@|%.0f,%.0f,%.0f,%.0f",
                     cls, bestRect.origin.x, bestRect.origin.y,
                     bestRect.size.width, bestRect.size.height];
    if (outRect != NULL) {
        *outRect = bestRect;
    }
    os_log(CHLog(), "island pill %{public}@ src=%{public}@ cand=%lu",
           gIslandDetail, gIslandSource, (unsigned long)candidates);
    return YES;
}

static void CHWriteDiagnostics(void) {
    NSString *summary = [NSString stringWithFormat:@"v%@;shows=%lu;last=%lus;label=%@;font=%.1f;island=%@;src=%@;cand=%lu;mode=%@;win=%@;islandWin=%@",
                         CHVersion, gShows, gLastSeconds,
                         gLabelText.length ? gLabelText : @"-",
                         gFontSize,
                         gIslandDetail, gIslandSource,
                         (unsigned long)gIslandCandidates,
                         gPlainNotice ? @"plain" : @"count",
                         gSelfWindowDetail, gIslandWindowDetail];
    CFPreferencesSetAppValue(CFSTR("CountdownHUDDiagnostics"),
                             (__bridge CFStringRef)summary,
                             kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
}

#pragma mark - 摆放与绘制

// 把胶囊摆到给定矩形上：圆角取半高（岛的胶囊形），字号跟着高度走，宽了自动缩。
static void CHApplyPillRect(CGRect rect) {
    gPill.frame = rect;
    gPill.layer.cornerRadius = MIN(rect.size.height, rect.size.width) / 2.0;
    gLabel.frame = gPill.bounds;
    // v1.1.1：原先取高度的一半（125×37 的岛＝18.5pt），用户嫌大；压到 2/3 → 高度 ÷ 3。
    CGFloat size = rect.size.height / 3.0;
    size = MAX(9.0, MIN(size, 16.0));
    // 等宽数字：每秒跳动的数字不会左右抖；Medium 比 Semibold 细一号，更像系统岛的观感。
    gFontSize = size;
    gLabel.font = [UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightMedium];
}

static void CHLayOut(void) {
    CGRect island = CGRectZero;
    if (gFollowIsland && CHMeasureIsland(&island)) {
        CHApplyPillRect(island);
        return;
    }
    CGRect bounds = gWindow.bounds;
    CGFloat top = gWindow.safeAreaInsets.top;
    if (top <= 0.0) {
        top = 20.0; // iPhone 8 这类无刘海机型的状态栏高度
    }
    CHApplyPillRect(CGRectMake((bounds.size.width - CHFallbackPillWidth) / 2.0,
                               top + 6.0,
                               CHFallbackPillWidth,
                               CHFallbackPillHeight));
}

// v1.3.0：只在真的有 windowScene 时才建窗口；场景换了（换屏 / SpringBoard 重排）就重建，
// 并把胶囊重新挂上去。返回 NO 表示「现在还没法显示」，调用方要留着请求下次再来。
static BOOL CHEnsureWindow(void) {
    UIWindowScene *scene = CHPickScene();
    if (scene == nil) {
        return NO;
    }
    if (gWindow != nil && gWindow.windowScene == scene) {
        return YES;
    }
    if (gWindow != nil) {
        [gPill removeFromSuperview];
        gWindow.hidden = YES;
        gWindow = nil;
    }

    CHWindow *w = [[CHWindow alloc] initWithWindowScene:scene];
    w.windowLevel = CHWindowLevel;
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = NO;
    w.hidden = YES;

    // 带 rootViewController 的窗口才是「完整」窗口：胶囊加在它内容层之上，
    // 而且这一层不吃触摸（hitTest 在 CHWindow 里就返回 nil 了）。
    UIViewController *host = [[UIViewController alloc] init];
    host.view.backgroundColor = [UIColor clearColor];
    host.view.userInteractionEnabled = NO;
    w.rootViewController = host;

    if (gPill == nil) {
        gPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CHFallbackPillWidth, CHFallbackPillHeight)];
        gPill.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.86];
        gPill.layer.cornerRadius = CHFallbackPillHeight / 2.0;
        gPill.layer.masksToBounds = YES;
        gPill.userInteractionEnabled = NO;

        gLabel = [[UILabel alloc] initWithFrame:gPill.bounds];
        gLabel.textAlignment = NSTextAlignmentCenter;
        gLabel.textColor = [UIColor systemGreenColor];
        gLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightMedium];
        gLabel.adjustsFontSizeToFitWidth = YES;
        gLabel.minimumScaleFactor = 0.55;
        gLabel.userInteractionEnabled = NO;

        [gPill addSubview:gLabel];
    }
    gWindow = w;
    [host.view addSubview:gPill];

    gSelfWindowDetail = [NSString stringWithFormat:@"%@|scene=%@|lvl=%.0f|bounds=%.0fx%.0f",
                         CHClassNameOf(w), CHClassNameOf(scene), w.windowLevel,
                         w.bounds.size.width, w.bounds.size.height];
    os_log(CHLog(), "HUD window ready on %{public}@ (level=%.0f)",
           CHClassNameOf(scene), w.windowLevel);
    return YES;
}

static void CHPaint(void) {
    if (gPlainNotice) {
        // v1.2.0：纯文案（任务完成 / 进度提醒）——不是倒计时，所以不做绿→橙→红的升级，
        // 也不带「N 秒后」前缀，屏幕上就是这句话本身。
        gLabel.textColor = [UIColor systemGreenColor];
        gLabel.text = gLabelText;
    } else {
        // v1.1.1：常规色由白改绿（系统绿 #34C759）——用户要求；绿 → 橙 → 红 就是「还有 / 快到了 / 马上」。
        UIColor *tint = [UIColor systemGreenColor];
        if (gRemaining <= 2) {
            tint = [UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1.0];
        } else if (gRemaining <= 3) {
            tint = [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1.0];
        }
        gLabel.textColor = tint;
        gLabel.text = [NSString stringWithFormat:@"%lu 秒后%@", (unsigned long)gRemaining, gLabelText];
    }

    gPill.transform = CGAffineTransformMakeScale(1.08, 1.08);
    [UIView animateWithDuration:0.28
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         gPill.transform = CGAffineTransformIdentity;
                     }
                     completion:nil];
}

static void CHHide(void) {
    [UIView animateWithDuration:0.45
                          delay:0.35
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
                         gPill.alpha = 0.0;
                     }
                     completion:^(BOOL finished) {
                         gPill.alpha = 1.0;
                         gWindow.hidden = YES;
                     }];
}

static BOOL CHStartCountdown(NSUInteger seconds, NSString *label, BOOL plain) {
    if (seconds == 0 || seconds > 600) {
        seconds = plain ? 8 : 5;
    }
    if (label.length == 0) {
        label = plain ? @"完成" : @"注销";
    }
    if (!CHEnsureWindow()) {
        // 还没有 windowScene（SpringBoard 刚起来的那一小会儿）：这次不显示，
        // 也**不算显示过** —— 轮询下一拍会拿着同一条请求再来一次。
        os_log(CHLog(), "no window scene yet, HUD deferred");
        return NO;
    }
    if (gTimer != nil) {
        [gTimer invalidate];
        gTimer = nil;
    }
    gRemaining = seconds;
    gLastSeconds = (unsigned long)seconds;
    gLabelText = [label copy];
    gPlainNotice = plain;
    gShows += 1;

    CHLayOut();
    gPill.alpha = 1.0;
    gWindow.hidden = NO;
    [gWindow bringSubviewToFront:gPill];
    CHPaint();
    CHWriteDiagnostics();
    os_log(CHLog(), "HUD show secs=%lu label=%{public}@ mode=%{public}@",
           (unsigned long)seconds, gLabelText, plain ? @"plain" : @"count");

    gTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                             repeats:YES
                                               block:^(NSTimer *timer) {
        if (gRemaining > 1) {
            gRemaining -= 1;
            // 岛可能被 VisibleIsland / DynamicX 挪了或换了布局：每秒重新量一次。
            CHLayOut();
            if (!gPlainNotice) {
                CHPaint(); // 纯文案不跳数字，不必每秒重画
            }
            os_log(CHLog(), "HUD tick %lu", (unsigned long)gRemaining);
        } else {
            [timer invalidate];
            gTimer = nil;
            if (!gPlainNotice) {
                gLabel.textColor = [UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1.0];
                gLabel.text = [NSString stringWithFormat:@"现在%@", gLabelText];
            }
            os_log(CHLog(), "HUD finish");
            CHHide();
            CHWriteDiagnostics();
        }
    }];
    return YES;
}

#pragma mark - 轮询请求文件

static NSString *gLastToken = nil;
static BOOL gPrimed = NO;   // 首次读到的内容只记不触发（多半是上一次留下的旧请求）

static BOOL CHHandleRequest(NSString *content) {
    NSArray<NSString *> *parts = [content componentsSeparatedByString:@"|"];
    NSUInteger seconds = 5;
    NSString *label = @"注销";
    BOOL plain = NO;
    if (parts.count >= 2) {
        NSInteger value = [parts[1] integerValue];
        if (value > 0 && value <= 600) {
            seconds = (NSUInteger)value;
        }
    }
    if (parts.count >= 3) {
        NSString *candidate =
            [parts[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (candidate.length > 0) {
            label = candidate;
        }
    }
    // v1.2.0：标签以「!」开头＝纯文案提醒（任务完成 / 进度），屏幕上就是这句话本身。
    if ([label hasPrefix:@"!"]) {
        plain = YES;
        label = [label substringFromIndex:1];
        label = [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (label.length == 0) {
            label = @"完成";
        }
        // 单行显示，太长会被缩到看不清：留前 32 个字。
        if (label.length > 32) {
            label = [[label substringToIndex:31] stringByAppendingString:@"…"];
        }
    }
    // 显示一律在主线程做，并且要等它给出结果：只有真的显示出来了，这一条请求才算消费掉
    // （没有 windowScene 不算，轮询下一拍会重试）。
    __block BOOL shown = NO;
    void (^run)(void) = ^{
        shown = CHStartCountdown(seconds, label, plain);
    };
    if ([NSThread isMainThread]) {
        run();
    } else {
        dispatch_sync(dispatch_get_main_queue(), run);
    }
    return shown;
}

static void CHPollOnce(void) {
    NSString *content = [NSString stringWithContentsOfFile:CHRequestPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
    if (content == nil) {
        return;
    }
    content = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (content.length == 0) {
        return;
    }
    if (gLastToken != nil && [content isEqualToString:gLastToken]) {
        return;
    }
    if (!gPrimed) {
        // 插件刚加载时文件里可能还留着上一次的请求：记下来但不触发。
        gPrimed = YES;
        gLastToken = content;
        return;
    }
    // 显示成功才把这条请求记成「已消费」；没显示出来（比如还没有 windowScene）就留着，
    // 0.5 秒后的下一拍接着试。
    if (CHHandleRequest(content)) {
        gLastToken = content;
    }
}

#pragma mark - 入口（没有 hook，纯 constructor）

__attribute__((constructor)) static void CHInitialize(void) {
    os_log(CHLog(), "v%{public}@ loaded; watching %{public}@", CHVersion, CHRequestPath);

    dispatch_queue_t queue = dispatch_queue_create("com.yangzhou.countdownhud.poll", DISPATCH_QUEUE_SERIAL);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    if (source == NULL) {
        os_log(CHLog(), "timer source failed");
        return;
    }
    uint64_t interval = (uint64_t)(CHPollInterval * (double)NSEC_PER_SEC);
    uint64_t leeway = (uint64_t)(0.1 * (double)NSEC_PER_SEC);
    dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, (int64_t)interval), interval, leeway);
    dispatch_source_set_event_handler(source, ^{
        CHPollOnce();
    });

    static dispatch_source_t keepAlive;
    keepAlive = source;
    dispatch_resume(source);
}
