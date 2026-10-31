//
// CountdownHUD.m —— SpringBoard 侧的自绘胶囊（「倒计时上岛」+ 纯文案提醒）+ 注销确认弹窗
//
// v1.5.0（用户 2026-10-31 05:33 / 05:35 原话：「以后注销事件给我一个警告⚠️弹窗 让我决定
//   要不注销！」「和 ios 系统桌面弹窗一样的弹窗！无论在任何界面有注销事件发生它就给我一个弹窗！」）：
//   请求标签以 `?` 开头时**不画胶囊**，改为在 SpringBoard 里弹一个**真正的系统对话框**
//   （UIAlertController：和桌面、设置里那种完全同款 —— 圆角面板 + 毛玻璃 + 两颗按钮），
//   标题「⚠️ 即将注销」，按钮「取消」/「立即注销」。窗口层级 CHAlertWindowLevel 高过
//   一切 App 与灵动岛，所以任何界面（桌面、别的 App、锁屏之上）都会盖上去。
//   用户点完把结果写进 .countdownhud-answer：`confirm|…` / `cancel|…` / `timeout|…`，
//   脚本读到 confirm 才继续倒计时 + 注销；cancel / timeout 一律什么都不做。
//   **超时绝不自动注销** —— 这是用户「让我决定」的底线。
//   铁律不变：dyld 构造函数里绝不碰 UIKit（见 v1.4.1 / v1.4.2 的安全模式事故）。
//
// v1.4.0：注销 / 装包这类「要动设备」的倒计时，在**画胶囊之前**先打一下最弱的震动
//   （`UISelectionFeedbackGenerator` ＝ 系统里点选 / 滚轮那一下，全系统最弱的一档）：
//   用户 2026-10-31 要求「有注销的打算时第一时间来个最弱的震动，震动要早于倒计时」。
//   触发点＝请求被读到的那一拍，且同一请求只震一次（没拿到 windowScene 的重试不再震）；
//   纯文案提醒（`!` 开头）不震。诊断串末尾多了 `haptic=N`（累计震了几次）。
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
// v1.6.1：确认后由插件自己执行注销用
#include <dlfcn.h>
#include <spawn.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
extern char **environ;

static NSString *const CHVersion = @"1.6.1";
static NSString *const CHRequestPath = @"/var/mobile/Library/Preferences/.countdownhud-request";
static NSString *const CHAnswerPath  = @"/var/mobile/Library/Preferences/.countdownhud-answer";
// v1.6.1：这个文件存在时，弹窗点了「立即注销」只写答案、不真注销 —— 给测试与「只倒计时」场景用。
static NSString *const CHNoRespringMarker = @"/var/mobile/Library/Preferences/.countdownhud-no-respring";
static const NSTimeInterval CHPollInterval = 0.5;

// 胶囊窗口的层级：既要盖在灵动岛（SystemAperture 那套）之上，也要盖在任何 App 之上。
static const CGFloat CHWindowLevel = 20000000.0;

// v1.5.0：注销确认弹窗要盖在胶囊（20000000）和系统 alert（2000）之上，任何界面都压得住。
static const CGFloat CHAlertWindowLevel = 30000000.0;

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

// v1.6.0：这两个提前声明 —— CHWindow 的 hitTest 要用 gPill 的矩形和 gLinkSession。
// gLinkSession 为空 = 这条请求没有点击目标，hitTest 一律返回 nil（与 1.5.0 行为一致）。
static UIView *gPill;
static NSString *gLinkSession;

// 高于系统 alert（2000），保证盖在 App 与灵动岛之上；并且不吃触摸。
@interface CHWindow : UIWindow
@end

@implementation CHWindow
// v1.6.0：胶囊上挂了一个「跳到发消息的对话」的点击目标时，**只在胶囊那块矩形里**吃触摸，
// 其余地方照旧返回 nil 穿透（胶囊之外整个屏幕都不受影响）。没有链接目标的老请求
// （脚本不带 sid）行为与 1.5.0 完全一致：任何地方都不吃触摸。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (gLinkSession.length == 0 || self.hidden || gPill == nil) {
        return nil;
    }
    if (!CGRectContainsPoint(gPill.frame, point)) {
        return nil;
    }
    return gPill;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (gLinkSession.length == 0 || self.hidden || gPill == nil) {
        return NO;
    }
    return CGRectContainsPoint(gPill.frame, point);
}
@end

// v1.5.0：注销确认弹窗的窗口。和胶囊窗口相反，这一层**必须吃触摸**（要能点「取消 / 立即注销」）。
// 但它铺满全屏，所以点在弹窗面板之外时返回 nil —— 触摸照常落到下面的 App，
// 不许因为弹了个窗就把整个屏幕锁死。
@interface CHAlertWindow : UIWindow
@end

@implementation CHAlertWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == nil || hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}
@end

static CHWindow *gWindow = nil;
static UILabel *gLabel = nil;
static NSTimer *gTimer = nil;
static NSUInteger gRemaining = 0;
static NSString *gLabelText = @"";
static unsigned long gShows = 0;
static unsigned long gLastSeconds = 0;
static BOOL gPlainNotice = NO;   // v1.2.0：「!」开头的标签＝纯文案，不显示「N 秒后」，不跳数字
static NSUInteger gHaptics = 0;      // v1.4.0：累计震了几次（诊断串 haptic=）
static NSString *gHapticToken = nil; // v1.4.0：已经为哪条请求震过（同一请求只震一次）
static unsigned long gTaps = 0;      // v1.6.0：胶囊被点了几次（诊断串 taps=）

// v1.5.0：注销确认弹窗的状态（诊断串里要报，所以和别的 static 放一起）。
static BOOL gAskMode = NO;              // 这次是弹窗而不是胶囊 → mode=alert
static unsigned long gAlerts = 0;       // 累计弹过几次
static NSString *gAnswerDetail = @"-";  // 最近一次答复 confirm|cancel|timeout|-
static NSString *gExecDetail = @"-";    // v1.6.1：点了「立即注销」之后插件实际做了什么（诊断 exec=spawned|skip-marker|term|fail|-）

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
    NSString *summary = [NSString stringWithFormat:@"v%@;shows=%lu;last=%lus;label=%@;font=%.1f;island=%@;src=%@;cand=%lu;mode=%@;win=%@;islandWin=%@;haptic=%lu;alerts=%lu;ans=%@;exec=%@;link=%@;taps=%lu",
                         CHVersion, gShows, gLastSeconds,
                         gLabelText.length ? gLabelText : @"-",
                         gFontSize,
                         gIslandDetail, gIslandSource,
                         (unsigned long)gIslandCandidates,
                         gAskMode ? @"alert" : (gPlainNotice ? @"plain" : @"count"),
                         gSelfWindowDetail, gIslandWindowDetail,
                         (unsigned long)gHaptics,
                         (unsigned long)gAlerts, gAnswerDetail, gExecDetail,
                         gLinkSession.length ? gLinkSession : @"none",
                         (unsigned long)gTaps];
    CFPreferencesSetAppValue(CFSTR("CountdownHUDDiagnostics"),
                             (__bridge CFStringRef)summary,
                             kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
}

#pragma mark - 点击胶囊：跳到发消息的那个对话（v1.6.0）

// 手势的 target 必须是对象，所以借一个小类把点击转给 C 函数。
static void CHHandlePillTap(void);

@interface CHTapTarget : NSObject
- (void)chTap:(UITapGestureRecognizer *)recognizer;
@end

@implementation CHTapTarget
- (void)chTap:(UITapGestureRecognizer *)recognizer {
    CHHandlePillTap();
}
@end

static CHTapTarget *gTapTarget = nil;

static void CHHandlePillTap(void) {
    if (gLinkSession.length == 0) {
        return;
    }
    NSString *urlString = [NSString stringWithFormat:@"apelin://conversation/%@", gLinkSession];
    NSURL *url = [NSURL URLWithString:urlString];
    gTaps += 1;
    os_log(CHLog(), "pill tapped -> %{public}@ (taps=%lu)",
           urlString, (unsigned long)gTaps);

    // 先收胶囊再去跳转：HUD 窗口层级 20000000，比任何 App 都高，
    // 不收起就会一直压在刚打开的 Apelin 上面，直到倒计时自己淡出。
    if (gTimer != nil) {
        [gTimer invalidate];
        gTimer = nil;
    }
    if (gWindow != nil) {
        gWindow.hidden = YES;
    }
    gPill.alpha = 1.0;
    CHWriteDiagnostics();

    if (url != nil) {
        [[UIApplication sharedApplication] openURL:url
                                           options:@{}
                                 completionHandler:^(BOOL success) {
            os_log(CHLog(), "open %{public}@ -> %d", urlString, (int)success);
        }];
    }
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
    // v1.6.0：窗口本身开着交互，但 hitTest 里只在「有链接目标 + 点在胶囊里」时返回胶囊，
    // 其余一律 nil 穿透 —— 所以不会因为这一改就吃掉屏幕上的触摸。
    w.userInteractionEnabled = YES;
    w.hidden = YES;

    // 带 rootViewController 的窗口才是「完整」窗口：胶囊加在它内容层之上。
    UIViewController *host = [[UIViewController alloc] init];
    host.view.backgroundColor = [UIColor clearColor];
    host.view.userInteractionEnabled = YES;
    w.rootViewController = host;

    if (gPill == nil) {
        gPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CHFallbackPillWidth, CHFallbackPillHeight)];
        gPill.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.86];
        gPill.layer.cornerRadius = CHFallbackPillHeight / 2.0;
        gPill.layer.masksToBounds = YES;
        gPill.userInteractionEnabled = YES; // v1.6.0：要能点（真正吃不吃由 CHWindow 的 hitTest 决定）

        if (gTapTarget == nil) {
            gTapTarget = [[CHTapTarget alloc] init];
        }
        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:gTapTarget action:@selector(chTap:)];
        tap.cancelsTouchesInView = NO;
        [gPill addGestureRecognizer:tap];

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

static BOOL CHStartCountdown(NSUInteger seconds, NSString *label, BOOL plain, NSString *link) {
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
    gAskMode = NO;   // v1.5.0：走胶囊就不是弹窗了（诊断串 mode= 要跟着变回来）
    gLinkSession = [link copy]; // v1.6.0：点胶囊跳到这个对话（空 = 不可点）
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

#pragma mark - 注销确认弹窗（v1.5.0）

// 用户 2026-10-31 05:33 / 05:35：「以后注销事件给我一个警告⚠️弹窗 让我决定要不注销！」
// 「和 ios 系统桌面弹窗一样的弹窗！无论在任何界面有注销事件发生它就给我一个弹窗！」
//
// 请求标签以 `?` 开头就走这条路：**不画胶囊**，直接在 SpringBoard 里 present 一个
// UIAlertController（和桌面、设置里弹的完全同款：圆角面板 + 两颗按钮），
// 标题「⚠️ 即将注销」，按钮「取消」/「立即注销」。
// 窗口层级 CHAlertWindowLevel 高过一切 App 与灵动岛，所以任何界面都会盖上来。
//
// 用户点完把结果写进 CHAnswerPath：`<epoch>|confirm|cancel|timeout`，
// 脚本读这一行才决定要不要真的往下走。**超时绝不自动注销** —— 这是「让我决定」的底线。
static CHAlertWindow *gAlertWindow = nil;
static UIAlertController *gAlert = nil;
static NSTimer *gAlertTimeout = nil;

static void CHWriteAnswer(NSString *verdict) {
    // 带 epoch：脚本先记下自己写请求那一刻的时间，只认比它新的答复，不会被上一次的旧答案骗到。
    NSString *line = [NSString stringWithFormat:@"%ld|%@\n",
                      (long)[[NSDate date] timeIntervalSince1970], verdict];
    NSError *err = nil;
    BOOL ok = [line writeToFile:CHAnswerPath atomically:YES
                       encoding:NSUTF8StringEncoding error:&err];
    if (!ok) {
        os_log(CHLog(), "answer write failed: %{public}@", err.localizedDescription);
    }
    gAnswerDetail = verdict;
    os_log(CHLog(), "answer %{public}@ written=%d", verdict, ok ? 1 : 0);
}

// v1.6.1：点了「立即注销」不能只把 confirm 写进文件就完事 —— 那条路要求
// `respring-guard.sh --ask` 那一刻还在前台轮询，脚本一结束（回合结束/超时/被打断），
// 用户点下去就只剩一个文件、屏幕毫无反应。所以改成：插件自己执行注销。
//
// 做法：从自己这个 dylib 的真实路径推出引导根（<jbroot>/usr/lib/TweakInject/CountdownHUD.dylib），
// 再 spawn <jbroot>/usr/bin/sbreload；找不到就试 /usr/bin/sbreload、/var/jb/usr/bin/sbreload。
// 都起不来才退化成给 SpringBoard 自己发 SIGTERM（launchd 会原样把它拉起来，效果等同注销）。
// `CHNoRespringMarker` 存在时只写答案、不注销 —— 给「只倒计时」测试用。
static NSString *CHBootstrapRoot(void) {
    Dl_info info;
    if (dladdr((const void *)&CHBootstrapRoot, &info) == 0 || info.dli_fname == NULL) {
        return nil;
    }
    NSString *self = [NSString stringWithUTF8String:info.dli_fname];
    NSRange r = [self rangeOfString:@"/usr/lib/TweakInject/"];
    if (r.location == NSNotFound) {
        return nil;
    }
    return [self substringToIndex:r.location];
}

static void CHRespringSelf(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:CHNoRespringMarker]) {
        gExecDetail = @"skip-marker";
        os_log(CHLog(), "respring skipped (marker present)");
        CHWriteDiagnostics();
        return;
    }

    NSMutableArray<NSString *> *cands = [NSMutableArray array];
    NSString *root = CHBootstrapRoot();
    if (root.length > 0) {
        [cands addObject:[root stringByAppendingString:@"/usr/bin/sbreload"]];
    }
    [cands addObject:@"/usr/bin/sbreload"];
    [cands addObject:@"/var/jb/usr/bin/sbreload"];

    for (NSString *path in cands) {
        if (![fm isExecutableFileAtPath:path]) {
            continue;
        }
        pid_t pid = 0;
        const char *cpath = path.fileSystemRepresentation;
        char *argv[] = { (char *)cpath, NULL };
        int rc = posix_spawn(&pid, cpath, NULL, NULL, argv, environ);
        os_log(CHLog(), "respring spawn %{public}@ rc=%d pid=%d", path, rc, (int)pid);
        if (rc == 0) {
            gExecDetail = @"spawned";
            CHWriteDiagnostics();
            return;
        }
    }

    // 起不了 sbreload：让 SpringBoard 自己退出，launchd 会立刻重新拉起（用户看到的就是注销）。
    gExecDetail = @"term";
    os_log(CHLog(), "sbreload unavailable, sending SIGTERM to SpringBoard");
    CHWriteDiagnostics();
    kill(getpid(), SIGTERM);
}

// 只在真有 windowScene 时才建弹窗窗口（和胶囊同一个铁律：没挂 scene 的窗口不渲染）。
static BOOL CHEnsureAlertWindow(void) {
    UIWindowScene *scene = CHPickScene();
    if (scene == nil) {
        return NO;
    }
    if (gAlertWindow != nil && gAlertWindow.windowScene == scene) {
        return YES;
    }
    if (gAlertWindow != nil) {
        gAlertWindow.hidden = YES;
        gAlertWindow = nil;
        gAlert = nil;
    }

    CHAlertWindow *w = [[CHAlertWindow alloc] initWithWindowScene:scene];
    w.windowLevel = CHAlertWindowLevel;
    w.backgroundColor = [UIColor clearColor];
    w.hidden = NO;

    UIViewController *host = [[UIViewController alloc] init];
    host.view.backgroundColor = [UIColor clearColor];
    w.rootViewController = host;

    gAlertWindow = w;
    os_log(CHLog(), "alert window ready on %{public}@ (level=%.0f)",
           CHClassNameOf(scene), w.windowLevel);
    return YES;
}

static void CHDismissAlert(void) {
    if (gAlertTimeout != nil) {
        [gAlertTimeout invalidate];
        gAlertTimeout = nil;
    }
    UIAlertController *a = gAlert;
    gAlert = nil;
    if (a != nil) {
        [a dismissViewControllerAnimated:YES completion:^{
            gAlertWindow.hidden = YES;
        }];
    } else if (gAlertWindow != nil) {
        gAlertWindow.hidden = YES;
    }
}

// 返回 NO ＝ 现在还没有 windowScene，这次没弹，请求留着下一拍再来（不算消费掉）。
static BOOL CHShowAlert(NSUInteger seconds, NSString *label) {
    if (!CHEnsureAlertWindow()) {
        os_log(CHLog(), "no window scene yet, alert deferred");
        return NO;
    }
    // 同一时刻只留一个弹窗：上一条还没收就先收掉。
    if (gAlert != nil) {
        if (gAlertTimeout != nil) {
            [gAlertTimeout invalidate];
            gAlertTimeout = nil;
        }
        [gAlert dismissViewControllerAnimated:NO completion:nil];
        gAlert = nil;
    }

    gAskMode = YES;
    gPlainNotice = NO;
    gLabelText = [label copy];
    gLastSeconds = (unsigned long)seconds;
    gShows += 1;
    gAlerts += 1;

    UIAlertController *a =
        [UIAlertController alertControllerWithTitle:@"⚠️ 即将注销"
                                           message:label
                                    preferredStyle:UIAlertControllerStyleAlert];
    // 取消：什么都不做，只把 cancel 写回去。
    [a addAction:[UIAlertAction actionWithTitle:@"取消"
                                          style:UIAlertActionStyleCancel
                                        handler:^(UIAlertAction *action) {
        CHWriteAnswer(@"cancel");
        CHDismissAlert();
        CHWriteDiagnostics();
    }]];
    // 立即注销：写 confirm（脚本端仍能据此记录），**然后由插件自己真的注销**（v1.6.1）——
    // 不再依赖脚本那一刻是否还在前台轮询。
    [a addAction:[UIAlertAction actionWithTitle:@"立即注销"
                                          style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *action) {
        CHWriteAnswer(@"confirm");
        CHDismissAlert();
        CHWriteDiagnostics();
        // 留 1 秒：让答案文件落盘、诊断写完，再结束这个进程。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CHRespringSelf();
        });
    }]];

    gAlert = a;
    gAlertWindow.hidden = NO;
    [gAlertWindow.rootViewController presentViewController:a animated:YES completion:nil];

    // 超时：写 timeout，收掉弹窗，**绝不自动注销**。
    if (seconds > 0) {
        gAlertTimeout = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)seconds
                                                        repeats:NO
                                                          block:^(NSTimer *timer) {
            gAlertTimeout = nil;
            CHWriteAnswer(@"timeout");
            CHDismissAlert();
            CHWriteDiagnostics();
            os_log(CHLog(), "alert timed out, nothing done");
        }];
    }

    CHWriteDiagnostics();
    os_log(CHLog(), "alert shown secs=%lu label=%{public}@", (unsigned long)seconds, gLabelText);
    return YES;
}

#pragma mark - 轮询请求文件

static NSString *gLastToken = nil;
static BOOL gPrimed = NO;   // 首次读到的内容只记不触发（多半是上一次留下的旧请求）

#pragma mark - 弱震动（要动设备之前先震一下）

// v1.4.0：用户要求「有注销的打算时第一时间来个最弱的震动，而且震动要早于倒计时」。
// 用 UISelectionFeedbackGenerator：系统里点选 / 滚轮那一下，是全系统最弱的一档触感
// （比 light impact 轻，比 AudioServicesPlaySystemSound 那类「震一下」温和得多）。
// 只在真的要动设备的倒计时上震（纯文案提醒不震），而且**同一请求只震一次**：
// 没拿到 windowScene 时那一拍只是重试，不重复震。设备侧：iPhone 8 有 Taptic Engine，
// 在 SpringBoard 里调它会真的震；万一某个机型没有，也只是安静地什么都不发生。
//
// v1.4.1 修复：生成器**绝不在构造函数里创建**。
// 1.4.0 在 CHInitialize（SpringBoard 启动的 dyld 构造函数）里就预热震动生成器，
// 那时 UIKit 还没初始化完：UISelectionFeedbackGenerator init → _defaultCoordinateSpace
// → +[UIScreen mainScreen] 触发 NSAssertionHandler 抛异常 → SIGABRT，
// SpringBoard 崩溃循环 → 设备进安全模式（案例：docs/cases/countdownhud-safe-mode.md）。
// 现在改成：第一次真要震的时候（主线程、已经有 windowScene、UIKit 完全活着）才惰性创建，
// 创建失败就静默跳过，绝不让震动功能把桌面搞崩。
static UISelectionFeedbackGenerator *gHapticGenerator = nil;

// v1.4.2：预热函数整体删除 —— 构造函数阶段连「碰一下已存在的生成器」都不做。
// 震动生成器只在消费请求、拿到 windowScene 之后才惰性创建。

// 返回 NO 表示这台设备/这一刻用不了震动（安静跳过，不崩）。
static BOOL CHFireWeakHaptic(void) {
    @try {
        if (gHapticGenerator == nil) {
            // 惰性创建：只在主线程、UIKit 已就绪的时刻做。
            if (![NSThread isMainThread]) {
                return NO;
            }
            gHapticGenerator = [[UISelectionFeedbackGenerator alloc] init];
        }
        [gHapticGenerator selectionChanged];
        gHaptics += 1;
        os_log(CHLog(), "weak haptic fired (#%lu)", (unsigned long)gHaptics);
        [gHapticGenerator prepare];   // 给下一次（下一条请求）重新上电
        return YES;
    } @catch (NSException *e) {
        // 理论上走不到（生成器只在 UIKit 就绪后创建），但万一系统抛异常也不能带崩 SpringBoard。
        os_log(CHLog(), "weak haptic failed: %{public}@", e.name);
        gHapticGenerator = nil;
        return NO;
    }
}

// v1.6.0：第 4 段是可选的对话 session id（Apelin 的 UUID 形如 8-4-4-4-12 的十六进制）。
// 只认这个形状，别的乱内容一律当「没有链接」，免得拼出奇怪的 URL。
static BOOL CHLooksLikeSessionID(NSString *text) {
    if (text.length < 8 || text.length > 64) {
        return NO;
    }
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF-"];
    return [text rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

static BOOL CHHandleRequest(NSString *content) {
    NSArray<NSString *> *parts = [content componentsSeparatedByString:@"|"];
    NSUInteger seconds = 5;
    NSString *label = @"注销";
    BOOL plain = NO;
    BOOL ask = NO;
    BOOL hasSeconds = NO;
    if (parts.count >= 2) {
        NSInteger value = [parts[1] integerValue];
        if (value > 0 && value <= 600) {
            seconds = (NSUInteger)value;
            hasSeconds = YES;
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
    // v1.5.0：标签以「?」开头＝**注销确认弹窗**（系统样式，任何界面都盖上来）。
    // 这一条里的「秒数」不是倒计时，而是「弹窗挂多久没人理就自己收掉」（默认 60 秒），
    // 超时写 timeout，**绝不自动注销**。
    if ([label hasPrefix:@"?"]) {
        ask = YES;
        label = [label substringFromIndex:1];
        label = [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (label.length == 0) {
            label = @"注销";
        }
        // 弹窗正文单行显示，太长就截断。
        if (label.length > 48) {
            label = [[label substringToIndex:47] stringByAppendingString:@"…"];
        }
        if (!hasSeconds) {
            seconds = 60;
        }
    }
    // v1.6.0：第 4 段 = 发这条消息的对话 session id。有它，胶囊就是可点的：
    // 点一下跳进那个对话（apelin://conversation/<sid>）。没有就维持 1.5.0 的老样子（不吃触摸）。
    // 弹窗（`?`）模式下不挂链接 —— 那一层是全屏窗口，挂上去只会多出误触。
    NSString *link = nil;
    if (!ask && parts.count >= 4) {
        NSString *candidate =
            [parts[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (CHLooksLikeSessionID(candidate)) {
            link = candidate;
        }
    }
    // v1.4.0：要动设备的动作（注销 / 装包 / 杀进程，也就是非 `!` 的倒计时）先把最弱的震动
    // 打出去 —— 而且是**同一请求只震一次**（同一个 content 在重试时不再震），然后才画胶囊：
    // 先震，屏幕上再出现「N 秒后…」。
    // 同一请求只震一次：**在真的震成功之后**才记 token。
    // v1.4.2 修：原来是在「准备震」时就记 token，若那一刻 UIKit 还没就绪（拿不到 windowScene）
    // 就跳过了震动，但 token 已经写上 → 后续重试不会再震（用户要求的「震动早于胶囊」就丢了）。
    BOOL needsHaptic = (!plain && ![content isEqualToString:gHapticToken]);

    // 显示一律在主线程做，并且要等它给出结果：只有真的显示出来了，这一条请求才算消费掉
    // （没有 windowScene 不算，轮询下一拍会重试）。
    // v1.4.2 修复：**震动必须排在「UIKit 完全就绪」之后**。
    // 1.4.1 把生成器的创建从构造函数挪到了「第一次要震时惰性创建」，但那一次恰恰发生在
    // SpringBoard 刚起来、windowScene 还没拿到的时候 —— UISelectionFeedbackGenerator init
    // 会走到 +[UIScreen mainScreen]，那时 UIKit 还没初始化完 → NSAssertionHandler → SIGABRT，
    // SpringBoard 崩溃循环 → 安全模式（真机实测：SpringBoard 启动 0.67 秒后崩）。
    // 现在的规矩：**先 CHEnsureWindow()（拿到真实 windowScene = UIKit 已经活着），再打震动**，
    // 然后才画胶囊。既保住「震动早于倒计时」的次序，又绝不在 UIKit 未就绪时碰它。
    __block BOOL shown = NO;
    void (^run)(void) = ^{
        if (needsHaptic) {
            // 只有真的能拿到 windowScene 才敢震；拿不到就安静跳过（不崩、不消费请求）。
            // 震成功之后才记 token：这样「第一次没震成」不会把这一条请求永久变成「不震」。
            if (CHEnsureWindow() && CHFireWeakHaptic()) {
                gHapticToken = [content copy];
            }
        }
        if (ask) {
            gLinkSession = nil; // v1.6.0：弹窗模式不挂点击目标
        }
        shown = ask ? CHShowAlert(seconds, label) : CHStartCountdown(seconds, label, plain, link);
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

    // v1.4.2：**构造函数里彻底不碰 UIKit**。
    // v1.4.0 在这里创建震动生成器 → +[UIScreen mainScreen] 断言 → SIGABRT → 安全模式；
    // v1.4.1 改成只预热一只已存在的生成器（此刻没有，等于什么都不做）；
    // v1.4.2 直接删掉这次预热：震动生成器只在消费请求、拿到 windowScene 之后才惰性创建。
    // 铁律：注入 SpringBoard 的插件，dyld 构造函数阶段禁止调用任何 UIKit API。

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
