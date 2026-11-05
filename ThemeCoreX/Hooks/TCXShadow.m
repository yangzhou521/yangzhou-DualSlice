#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "TCXPrivate.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"

// 图标阴影层。
//
// 做法：挂 SBIconImageView 的 layoutSubviews，在原实现跑完之后给自己的 layer 装
// shadowPath（圆角矩形，半径与图标一致）+ 可配置的颜色/透明度/模糊/偏移。
//
// 为什么不用「再加一个 CALayer 影子层」：
//   多一层就多一次布局与合成，图标数量一多就掉帧；直接改本层阴影是零成本。
//   代价是会与系统自带阴影叠加（系统那层很淡），所以参数默认走克制值，
//   并且 ShadowEnabled 可以一键关掉做 A/B 对比。
//
// 与 ThemeCore 的关系：它操心的是 Iconomatic 位图阴影（主题包里的 shadow png）；
// 我们这条是纯矢量阴影，不读素材也能出效果，两者可以同时存在。

static void (*orig_layoutSubviews)(id, SEL);

static NSString *sLastShadowSignature = nil;

static void TCXApplyShadow(UIView *view) {
    if (!TCXPrefBool(@"Enabled", YES)) return;
    if (!TCXPrefBool(@"ShadowEnabled", YES)) return;

    CALayer *layer = view.layer;
    CGRect bounds = view.bounds;
    if (bounds.size.width < 8.0 || bounds.size.height < 8.0) return;

    CGFloat radius = TCXPrefDouble(@"ShadowRadius", 4.0);
    CGFloat opacity = TCXPrefDouble(@"ShadowOpacity", 0.24);
    CGFloat offsetY = TCXPrefDouble(@"ShadowOffsetY", 1.0);
    CGFloat corner = bounds.size.width * 0.2237f;

    // 同一尺寸不重复下发（图标滚动时 layoutSubviews 会被狂调，每帧重设阴影很浪费）。
    NSString *signature = [NSString stringWithFormat:@"%.0f|%.2f|%.2f|%.2f",
                           bounds.size.width, radius, opacity, offsetY];
    CGPathRef existing = layer.shadowPath;
    if (existing && sLastShadowSignature && [sLastShadowSignature isEqualToString:signature]) {
        return;
    }
    sLastShadowSignature = signature;

    layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds
                                                 cornerRadius:corner].CGPath;
    layer.shadowColor = [UIColor blackColor].CGColor;
    layer.shadowOpacity = (float)opacity;
    layer.shadowRadius = radius;
    layer.shadowOffset = CGSizeMake(0, offsetY);
    // 图标视图本身不该裁掉阴影。
    layer.masksToBounds = NO;

    TCXCountShadow();
}

static void repl_layoutSubviews(id self, SEL _cmd) {
    if (orig_layoutSubviews) orig_layoutSubviews(self, _cmd);
    @try {
        if ([self isKindOfClass:[UIView class]]) TCXApplyShadow((UIView *)self);
    } @catch (NSException *exception) {
        // 阴影是视觉增强，任何异常都不能让 SpringBoard 受影响。
    }
}

void TCXInstallShadowHooks(void) {
    Class cls = TCXClass(@"SBIconImageView");
    if (!cls) {
        // iOS 17+ 可能改名，先记一笔；0.0.1 不猜类名。
        TCXNoteSite(@"shadow:noclass");
        return;
    }
    MSHookMessageEx(cls, @selector(layoutSubviews),
                    (IMP)&repl_layoutSubviews, (IMP *)&orig_layoutSubviews);
    if (orig_layoutSubviews) TCXNoteSite(@"SBIconImageView:layoutSubviews");
}