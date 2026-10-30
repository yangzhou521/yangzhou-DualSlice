//
// CountdownHUD.m —— SpringBoard 侧的自绘倒计时胶囊（「倒计时上岛」）
//
// 为什么要它：Apelin 的本地通知在发送瞬间会把 App 拉回前台，横幅被它自己的
// UNUserNotificationCenterDelegate 吞掉，既看不到、也进不了 DynamicX 的灵动岛
// （详见 AGENTS.md 与技能 respring-notify-countdown）。所以注销 / 装包前的 5 秒，
// 由这个插件自己画在屏幕上，不依赖任何通知。
//
// 触发方式（故意不用 Darwin 通知：本机没有 notifyutil，icli 也不发通知）：
//   脚本把请求写进 /var/mobile/Library/Preferences/.countdownhud-request，
//   格式 `<epoch>|<秒数>|<标签>`；插件每 0.5 秒读一次这个文件，内容变了就倒数。
//   读失败 / 文件不存在都只是什么都不做。
//
// 规矩（AGENTS.md 硬规矩）：
//   - 不用私有类发消息：这里只用公开的 UIWindow / UIView / UILabel / NSTimer。
//   - 没有 MSHookMessageEx，连 substrate 都不链，全部逻辑在 constructor 里起一个轮询。
//   - 诊断写进目标进程自己的偏好域（kCFPreferencesCurrentApplication = com.apple.springboard）：
//     `icli prefs read com.apple.springboard CountdownHUDDiagnostics`
//   - 日志走 os_log，subsystem 是包名，格式化符带 %{public}。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <os/log.h>

static NSString *const CHVersion = @"1.0.0";
static NSString *const CHRequestPath = @"/var/mobile/Library/Preferences/.countdownhud-request";
static const NSTimeInterval CHPollInterval = 0.5;
static const CGFloat CHPillWidth = 190.0;
static const CGFloat CHPillHeight = 44.0;

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

static UIWindowScene *CHActiveScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (app == nil) {
        return nil;
    }
    NSSet<UIScene *> *scenes = app.connectedScenes;
    for (UIScene *scene in scenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    for (UIScene *scene in scenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static void CHWriteDiagnostics(void) {
    NSString *summary = [NSString stringWithFormat:@"v%@;shows=%lu;last=%lus;label=%@",
                         CHVersion, gShows, gLastSeconds,
                         gLabelText.length ? gLabelText : @"-"];
    CFPreferencesSetAppValue(CFSTR("CountdownHUDDiagnostics"),
                             (__bridge CFStringRef)summary,
                             kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
}

static void CHLayOut(void) {
    CGRect bounds = gWindow.bounds;
    CGFloat top = gWindow.safeAreaInsets.top;
    if (top <= 0.0) {
        top = 20.0;
    }
    gPill.frame = CGRectMake((bounds.size.width - CHPillWidth) / 2.0,
                             top + 6.0, CHPillWidth, CHPillHeight);
}

static void CHBuildIfNeeded(void) {
    if (gWindow != nil) {
        return;
    }
    UIWindowScene *scene = CHActiveScene();
    if (scene != nil) {
        gWindow = [[CHWindow alloc] initWithWindowScene:scene];
    } else {
        gWindow = [[CHWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    gWindow.windowLevel = 10000000.0;
    gWindow.backgroundColor = [UIColor clearColor];
    gWindow.userInteractionEnabled = NO;
    gWindow.hidden = YES;

    gPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CHPillWidth, CHPillHeight)];
    gPill.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.86];
    gPill.layer.cornerRadius = CHPillHeight / 2.0;
    gPill.layer.masksToBounds = YES;
    gPill.userInteractionEnabled = NO;

    gLabel = [[UILabel alloc] initWithFrame:gPill.bounds];
    gLabel.textAlignment = NSTextAlignmentCenter;
    gLabel.textColor = [UIColor whiteColor];
    gLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightSemibold];
    gLabel.adjustsFontSizeToFitWidth = YES;
    gLabel.minimumScaleFactor = 0.7;
    gLabel.userInteractionEnabled = NO;

    [gPill addSubview:gLabel];
    [gWindow addSubview:gPill];
}

static void CHPaint(void) {
    UIColor *tint = [UIColor whiteColor];
    if (gRemaining <= 2) {
        tint = [UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1.0];
    } else if (gRemaining <= 3) {
        tint = [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1.0];
    }
    gLabel.textColor = tint;
    gLabel.text = [NSString stringWithFormat:@"%lu 秒后%@", (unsigned long)gRemaining, gLabelText];

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

static void CHStartCountdown(NSUInteger seconds, NSString *label) {
    if (seconds == 0 || seconds > 600) {
        seconds = 5;
    }
    if (label.length == 0) {
        label = @"注销";
    }
    CHBuildIfNeeded();
    if (gWindow == nil) {
        os_log(CHLog(), "no window scene, HUD skipped");
        return;
    }
    if (gTimer != nil) {
        [gTimer invalidate];
        gTimer = nil;
    }
    gRemaining = seconds;
    gLastSeconds = (unsigned long)seconds;
    gLabelText = [label copy];
    gShows += 1;

    CHLayOut();
    gPill.alpha = 1.0;
    gWindow.hidden = NO;
    [gWindow bringSubviewToFront:gPill];
    CHPaint();
    CHWriteDiagnostics();
    os_log(CHLog(), "HUD show secs=%lu label=%{public}@", (unsigned long)seconds, gLabelText);

    gTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                             repeats:YES
                                               block:^(NSTimer *timer) {
        if (gRemaining > 1) {
            gRemaining -= 1;
            CHPaint();
            os_log(CHLog(), "HUD tick %lu", (unsigned long)gRemaining);
        } else {
            [timer invalidate];
            gTimer = nil;
            gLabel.textColor = [UIColor colorWithRed:1.0 green:0.27 blue:0.23 alpha:1.0];
            gLabel.text = [NSString stringWithFormat:@"现在%@", gLabelText];
            os_log(CHLog(), "HUD finish");
            CHHide();
            CHWriteDiagnostics();
        }
    }];
}

#pragma mark - 轮询请求文件

static NSString *gLastToken = nil;

static void CHHandleRequest(NSString *content) {
    NSArray<NSString *> *parts = [content componentsSeparatedByString:@"|"];
    NSUInteger seconds = 5;
    NSString *label = @"注销";
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
    dispatch_async(dispatch_get_main_queue(), ^{
        CHStartCountdown(seconds, label);
    });
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
    BOOL firstSeen = (gLastToken == nil);
    gLastToken = content;
    if (firstSeen) {
        // 插件刚加载时文件里可能还留着上一次的请求：记下来但不触发。
        return;
    }
    CHHandleRequest(content);
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