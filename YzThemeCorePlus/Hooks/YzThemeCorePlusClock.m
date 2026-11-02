#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusThemeStore.h"
#import "YzThemeCorePlusPrivate.h"

// 时钟主题化：换表盘 + 换指针，指针保持走时。
// 关键：iOS 14-16 类名是 SBClockApplicationIconImageView（无 "H"）。
// 走时靠 CALayer 指针 _hours/_minutes/_seconds/_redDot/_blackDot。
// 主题资源放 <主题>/Bundles/com.apple.springboard/：ClockIconBackgroundSquare / ClockIcon{Hour,Minute,Second}Hand / ClockIcon{Black,Red}Dot。

static BOOL yz_clockEnabled(void) {
    return [[YzThemeCorePlusConfig yz_themecoreplus_shared] yz_themecoreplus_isEnabled];
}

static void yz_applyClockHands(SBClockApplicationIconImageView *view) {
    YzThemeCorePlusThemeStore *store = [YzThemeCorePlusThemeStore yz_themecoreplus_shared];
    CGFloat scale = [UIScreen mainScreen].scale;
    NSDictionary *map = @{
        @"_hours":     @"ClockIconHourHand",
        @"_minutes":   @"ClockIconMinuteHand",
        @"_seconds":   @"ClockIconSecondHand",
        @"_redDot":    @"ClockIconRedDot",
        @"_blackDot":  @"ClockIconBlackDot",
    };
    for (NSString *ivar in map) {
        UIImage *img = [store yz_themecoreplus_springboardImageNamed:map[ivar] scale:scale];
        if (!img) continue;
        id layer = [view valueForKey:ivar];
        if ([layer isKindOfClass:[CALayer class]]) {
            [(CALayer *)layer setContents:(id)img.CGImage];
            [(CALayer *)layer setBackgroundColor:[UIColor clearColor].CGColor];
        }
    }
}

static UIImage *(*orig_contentsImage)(id self, SEL _cmd) = NULL;
static id (*orig_initWithFrame)(id self, SEL _cmd, CGRect frame) = NULL;
static void (*orig_updateAnimatingState)(id self, SEL _cmd) = NULL;
static BOOL (*orig_isAnimationAllowed)(id self, SEL _cmd) = NULL;

static UIImage *repl_contentsImage(id self, SEL _cmd) {
    if (!yz_clockEnabled()) return orig_contentsImage(self, _cmd);
    YzThemeCorePlusThemeStore *store = [YzThemeCorePlusThemeStore yz_themecoreplus_shared];
    UIImage *face = [store yz_themecoreplus_springboardImageNamed:@"ClockIconBackgroundSquare"
                                                             scale:[UIScreen mainScreen].scale];
    return face ?: orig_contentsImage(self, _cmd);
}

static id repl_initWithFrame(id self, SEL _cmd, CGRect frame) {
    id view = orig_initWithFrame(self, _cmd, frame);
    if (view && yz_clockEnabled()) yz_applyClockHands(view);
    return view;
}

static void repl_updateAnimatingState(id self, SEL _cmd) {
    orig_updateAnimatingState(self, _cmd);
    if (yz_clockEnabled()) yz_applyClockHands(self);
}

static BOOL repl_isAnimationAllowed(id self, SEL _cmd) {
    return yz_clockEnabled() ? YES : orig_isAnimationAllowed(self, _cmd);
}

__attribute__((constructor))
static void yz_clock_init(void) {
    @autoreleasepool {
        Class cls = objc_getClass("SBClockApplicationIconImageView");
        if (!cls) return;
        MSHookMessageEx(cls, @selector(contentsImage), (IMP)&repl_contentsImage, (IMP*)&orig_contentsImage);
        MSHookMessageEx(cls, @selector(initWithFrame:), (IMP)&repl_initWithFrame, (IMP*)&orig_initWithFrame);
        MSHookMessageEx(cls, @selector(updateAnimatingState), (IMP)&repl_updateAnimatingState, (IMP*)&orig_updateAnimatingState);
        MSHookMessageEx(cls, @selector(isAnimationAllowed), (IMP)&repl_isAnimationAllowed, (IMP*)&orig_isAnimationAllowed);
    }
}
