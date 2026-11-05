#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "TCXPrivate.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"
#import "TCXStore.h"

// 图标阴影层。
//
// 两条路，按主题有没有素材自动选：
//   ① 主题给了阴影位图（<主题>/Bundles/AnemoneEffects|Iconomatic|Effects/*shadow*.png，
//      见 TCXStore 的 shadowImage）→ 在图标视图最底层垫一个 UIImageView，Iconomatic 那套做法；
//      位图自带外扩透明边距，按图标 bounds 铺满就是主题作者想要的效果。
//   ② 主题没给 → 退回纯矢量阴影（shadowPath 圆角矩形 + 可配置颜色/透明度/模糊/偏移），
//      零素材也有克制的立体感。
//
// 为什么不再无条件用 CALayer 阴影：Iconomatic 类主题的阴影是画好的 PNG（含底部渐变与边距），
// 用矢量阴影盖上去会与主题作者的设计打架，看着脏。
//
// 注意：签名（上次下发的参数）挂在**视图自己**身上，不能用全局变量 —— 桌面上图标尺寸各异，
// 共用一个全局签名会让第二个图标误判「已经设过了」而跳过，也会让 A 的设置被 B 的判断顶掉。

void TCXCountShadow(void);
void TCXNoteSite(NSString *site);

static const NSInteger kTCXShadowTag = 0x7C0F02;
static char kTCXShadowSignatureKey;

static UIImageView *TCXShadowSubview(UIView *view) {
    for (UIView *sub in view.subviews) {
        if (sub.tag == kTCXShadowTag) return (UIImageView *)sub;
    }
    return nil;
}

static void TCXClearVectorShadow(CALayer *layer) {
    if (layer.shadowOpacity != 0.0f || layer.shadowPath != NULL) {
        layer.shadowOpacity = 0.0f;
        layer.shadowPath = NULL;
    }
}

static void TCXApplyShadow(UIView *view) {
    if (!TCXPrefBool(@"Enabled", YES)) return;

    CALayer *layer = view.layer;
    CGRect bounds = view.bounds;
    if (bounds.size.width < 8.0 || bounds.size.height < 8.0) return;

    NSString *previous = objc_getAssociatedObject(view, &kTCXShadowSignatureKey);

    // 关掉时要有一次清理，否则关开关后旧阴影会一直挂在已经布局过的图标上。
    if (NO) {   // 阴影常开（面板已无开关）
        if (![previous isEqualToString:@"off"]) {
            [TCXShadowSubview(view) removeFromSuperview];
            TCXClearVectorShadow(layer);
            objc_setAssociatedObject(view, &kTCXShadowSignatureKey, @"off",
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];
    UIImage *bitmap = store.shadowImage;

    CGFloat radius = TCXPrefDouble(@"ShadowRadius", 4.0);
    CGFloat opacity = TCXPrefDouble(@"ShadowOpacity", 0.24);
    CGFloat offsetY = TCXPrefDouble(@"ShadowOffsetY", 1.0);
    CGFloat corner = bounds.size.width * 0.2237f;

    NSString *signature = [NSString stringWithFormat:@"%.1f|%.0f|%.2f|%.2f|%.2f|%@",
                           bounds.size.width, bounds.size.height, radius, opacity, offsetY,
                           bitmap ? (store.themeName ?: @"bitmap") : @"vector"];
    if (previous && [previous isEqualToString:signature]) return;   // 滚动时 layoutSubviews 会被狂调
    objc_setAssociatedObject(view, &kTCXShadowSignatureKey, signature,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (bitmap) {
        // ① 位图阴影：垫在图标内容下面。
        // 主题的 iPhoneShadow 素材**自带外扩边距**（比图标本体大一圈），
        // 之前用 ScaleToFill 把阴影图硬拉到图标大小，边距被压掉 → 阴影整体上移、
        // 压到图标中间（用户 2026-11-06 01:50 报的）。
        // 正确做法：保持原始宽高比、按比例放大到「图标 + 四周外扩」，再居中。
        UIImageView *shadowView = TCXShadowSubview(view);
        if (![shadowView isKindOfClass:[UIImageView class]]) {
            shadowView = [[UIImageView alloc] initWithFrame:bounds];
            shadowView.tag = kTCXShadowTag;
            shadowView.userInteractionEnabled = NO;
            shadowView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [view insertSubview:shadowView atIndex:0];
        }
        shadowView.contentMode = UIViewContentModeScaleAspectFit;
        // 阴影外扩与偏移：主题阴影素材设计用于置于图标下方（带有底部投影光晕），
        // 保持水平居中，并在 Y 轴施加向下微移（+grow*0.5），避免阴影反向溢出到图标上方。
        CGFloat side = MAX(bounds.size.width, bounds.size.height);
        CGFloat grow = side * 0.18;          // 四周各外扩
        CGRect shadowRect = CGRectInset(bounds, -grow, -grow);
        shadowRect.origin.y += (grow * 0.5); // 向下偏移，使阴影重心完全落在图标下方
        shadowView.frame = shadowRect;
        shadowView.image = bitmap;
        // 两条路不能同时出现，否则主题位图下面又叠一层矢量暗角。
        TCXClearVectorShadow(layer);
        layer.masksToBounds = NO;
    } else {
        // ② 无素材：矢量阴影直接改本层，零额外图层。
        [TCXShadowSubview(view) removeFromSuperview];
        layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds
                                                      cornerRadius:corner].CGPath;
        layer.shadowColor = [UIColor blackColor].CGColor;
        layer.shadowOpacity = (float)opacity;
        layer.shadowRadius = radius;
        layer.shadowOffset = CGSizeMake(0, offsetY);
        // 图标视图本身不该裁掉阴影。
        layer.masksToBounds = NO;
    }

    TCXCountShadow();
}

static void (*orig_layoutSubviews)(id, SEL);

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