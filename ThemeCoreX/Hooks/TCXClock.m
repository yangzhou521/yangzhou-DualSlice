#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "TCXPrivate.h"
#import "TCXStore.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"

// 时钟图标 —— 主题表盘 + 自绘指针。
//
// 素材（本机 /Library/Themes 实测，两个主题都有）：
//   ClockIconBackgroundSquare  表盘（Smartisan 192×192、带 @3x~iphone；液态玻璃 250×250、裸名）
//   ClockIconHourHand 8×96 / ClockIconMinuteHand 8×144 / ClockIconSecondHand 20×450（Smartisan）
//   ClockIconRedDot 12×12 / ClockIconBlackDot（ThemeCore 证据里有这两个名字）
//   老命名 ClockIconBackground / ClockIconFace 作兜底（ThemeCore 证据里 `clock.background`）。
//
// 指针尺寸怎么换算（这里有个真实结论，别改回去）：
//   **按像素比例算，不看各自的 @x 后缀。** Smartisan 的表盘 4 个后缀（@2x/@3x × iphone/ipad）
//   全是 192×192 像素 —— 说明作者把「像素」当设计基准，后缀只是给系统的门面。若按各自
//   的 UIImage.scale 换算成点再对齐，时针会变成表盘半径的 75%、分针超过半径（明显不对）；
//   按像素对齐则：时针半长 = 半径 50%、分针 75%、秒针 233%（长出图标外）—— 与 iOS 时钟
//   图标的观感完全吻合。所以：k = 画布宽 / 表盘像素宽，指针按「像素 × k」画。
//
// 指针绕哪里转（这是唯一没取证到的一点）：
//   Anemone 系约定是「绕指针图的几何中心转，图的中心对齐表盘中心」，Smartisan 的尺寸与它
//   自洽；液态玻璃的指针图用哪种解释都不自洽（那是一套杂素材）。所以做成可切：
//   偏好 ClockHandAnchor = center（默认）/ bottom。上机先看默认，不对再切，不在代码里赌。
//
// 红点（ClockIconRedDot）：位置推断不出来（不在图里，也不在主题 plist 里），画错比不画更糟，
//   所以默认不画；黑点（时分针轴心）画在正中心，这个没歧义。

static NSCache<NSString *, UIImage *> *sClockCache = nil;
static NSString *const kTCXClockHandAnchorPref = @"ClockHandAnchor";

#pragma mark - 合成

// 画一根指针：把画布原点移到中心、按角度旋转，再按锚点把指针图摆正。
static void TCXDrawHand(UIImage *hand, CGFloat pixelScale, BOOL bottomAnchor, CGFloat angle) {
    if (!hand) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;

    CGSize size = CGSizeMake(hand.size.width * pixelScale, hand.size.height * pixelScale);
    CGContextSaveGState(context);
    CGContextRotateCTM(context, (CGFloat)(angle * M_PI / 180.0));   // y 轴朝下，正角即视觉顺时针
    CGFloat x = -size.width / 2.0;
    CGFloat y = bottomAnchor ? -size.height : -size.height / 2.0;
    [hand drawInRect:CGRectMake(x, y, size.width, size.height)];
    CGContextRestoreGState(context);
}

// 像素宽（不是点宽）：素材之间只有像素可比。
static CGFloat TCXPixelWidth(UIImage *image) {
    if (image.CGImage) return (CGFloat)CGImageGetWidth(image.CGImage);
    return image.size.width * (image.scale > 0 ? image.scale : 1.0);
}

// 组装「当前时刻」的时钟图。表盘取不到就返回 nil（调用方放行系统图）。
UIImage *TCXClockImage(CGSize canvas, CGFloat scale) {
    if (canvas.width < 8.0) return nil;

    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];

    UIImage *face = [store springboardImageNamed:@"ClockIconBackgroundSquare" scale:scale];
    if (!face) face = [store springboardImageNamed:@"ClockIconBackground" scale:scale];
    if (!face) face = [store springboardImageNamed:@"ClockIconFace" scale:scale];
    if (!face) return nil;

    UIImage *hourHand = [store springboardImageNamed:@"ClockIconHourHand" scale:scale];
    UIImage *minuteHand = [store springboardImageNamed:@"ClockIconMinuteHand" scale:scale];
    UIImage *secondHand = [store springboardImageNamed:@"ClockIconSecondHand" scale:scale];
    UIImage *blackDot = [store springboardImageNamed:@"ClockIconBlackDot" scale:scale];

    NSDateComponents *parts = [[NSCalendar currentCalendar]
                               components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                               fromDate:[NSDate date]];
    NSInteger hour = parts.hour, minute = parts.minute, second = parts.second;
    CGFloat hourAngle = (CGFloat)((hour % 12) * 30.0) + minute * 0.5f;
    CGFloat minuteAngle = (CGFloat)(minute * 6.0) + second * 0.1f;
    CGFloat secondAngle = (CGFloat)(second * 6.0);

    // 有秒针就按秒缓存，没有就按分钟（少合成，少开销）。
    NSString *key = [NSString stringWithFormat:@"clk|%@|%.0fx%.0f|%ld|%ld|%ld",
                     store.themeName ?: @"none", canvas.width, canvas.height,
                     (long)hour, (long)minute, secondHand ? (long)second : 0];
    if (!sClockCache) {
        sClockCache = [[NSCache alloc] init];
        sClockCache.countLimit = 8;
    }
    UIImage *cached = [sClockCache objectForKey:key];
    if (cached) return cached;

    BOOL bottomAnchor = [TCXPrefString(kTCXClockHandAnchorPref) isEqualToString:@"bottom"];
    CGFloat pixelScale = canvas.width / MAX(TCXPixelWidth(face), 1.0);

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = scale > 0 ? scale : 2.0;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:canvas format:format];

    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [face drawInRect:CGRectMake(0, 0, canvas.width, canvas.height)];

        CGContextRef ctx = context.CGContext;
        CGContextTranslateCTM(ctx, canvas.width / 2.0, canvas.height / 2.0);

        TCXDrawHand(hourHand, pixelScale, bottomAnchor, hourAngle);
        TCXDrawHand(minuteHand, pixelScale, bottomAnchor, minuteAngle);

        if (blackDot) {
            CGSize dot = CGSizeMake(blackDot.size.width * pixelScale,
                                    blackDot.size.height * pixelScale);
            [blackDot drawInRect:CGRectMake(-dot.width / 2.0, -dot.height / 2.0,
                                            dot.width, dot.height)];
        }
        TCXDrawHand(secondHand, pixelScale, bottomAnchor, secondAngle);

        CGContextTranslateCTM(ctx, -canvas.width / 2.0, -canvas.height / 2.0);
    }];

    if (result) [sClockCache setObject:result forKey:key];
    return result;
}

void TCXClockInvalidate(void) {
    [sClockCache removeAllObjects];
}

#pragma mark - 挂站

static UIImage *(*orig_clockContents_SBH)(id, SEL);
static UIImage *(*orig_clockContents_SB)(id, SEL);

static UIImage *TCXClockResolved(UIImage *original) {
    @try {
        // 时钟常开（面板已无开关），只受总开关控制。
        if (!TCXPrefBool(@"Enabled", YES)) return original;
        CGSize canvas = original.size;
        CGFloat scale = original.scale;
        if (canvas.width < 8.0 || canvas.height < 8.0) return original;
        UIImage *composed = TCXClockImage(canvas, scale);
        return composed ?: original;
    } @catch (NSException *exception) {
        return original;
    }
}

static UIImage *repl_clockContents_SBH(id self, SEL _cmd) {
    UIImage *original = orig_clockContents_SBH ? orig_clockContents_SBH(self, _cmd) : nil;
    return TCXClockResolved(original);
}

static UIImage *repl_clockContents_SB(id self, SEL _cmd) {
    UIImage *original = orig_clockContents_SB ? orig_clockContents_SB(self, _cmd) : nil;
    return TCXClockResolved(original);
}

// 一站一槽：SBH*/SB* 两个类各自的原实现槽（iOS 16 上是 SBH 那个）。
static void TCXHookClockClass(NSString *name, IMP repl, IMP *slot) {
    Class cls = TCXClass(name);
    if (!cls) return;
    if (!TCXClassDeclaresSelector(cls, @selector(contentsImage))) {
        TCXNoteSite([name stringByAppendingString:@":nodecl"]);
        return;
    }
    IMP original = NULL;
    MSHookMessageEx(cls, @selector(contentsImage), repl, &original);
    if (original) {
        *slot = original;
        TCXNoteSite([name stringByAppendingString:@":contentsImage"]);
    }
}

void TCXInstallClockHooks(void) {
    TCXHookClockClass(@"SBHClockApplicationIconImageView",
                      (IMP)&repl_clockContents_SBH, (IMP *)&orig_clockContents_SBH);
    TCXHookClockClass(@"SBClockApplicationIconImageView",
                      (IMP)&repl_clockContents_SB, (IMP *)&orig_clockContents_SB);
}
