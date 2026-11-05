#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "TCXPrivate.h"
#import "TCXStore.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"

// 角标层 —— 逐条对齐 ThemeCorePlus 1.0.7（本机装机实测通过、用户 2026-10-31 目视确认）。
//
// 为什么不能「往系统底板塞素材」：本机（iOS 16）SBIconBadgeView 的底板是 SBDarkeningImageView，
// 系统把红底画在它的 layer.contents 里，我们塞进去的图下一帧就被重写 → 屏幕上「系统红底 + 我们的素材」
// 两层（用户 2026-10-31 17:17）；而底板本身是圆形/圆头素材，用 resizableImageWithCapInsets 横向
// 拉伸又会变成异形（用户 2026-10-31 20:31「圆形素材被拉成异形」）。
//
// 1.0.7 的终局做法（本文件照抄，只有两处站）：
//   ① 成图站 +[SBIconBadgeView _checkoutImageForText:font:highlighted:]
//      —— 返回「主题底板 + 数字」的**一整张图**（圆头胶囊：两端裁素材、中间填素材本色，绝不横向
//         拉伸；单数字时画布正好等于素材本身 25x25，与实测 canvas=25x25 一致）。返回类型绝不改变：
//         原值是 tuple 就重新包 tuple，是裸图就换裸图。
//   ② 呈现站 -[SBIconBadgeView layoutSubviews]
//      —— 从系统底板**子树**里找到我们那张图，把它搬到自己的一层上（overlay），再把底板 hidden。
//         拿不到我们的图就一个字节都不动（绝不把角标弄成空白）。
//
// 底板站（_checkoutBackgroundImage / …Tuple）已删除：底板已合成在整图里，那两站在本机从没被调用
// （诊断 bg{} 恒 0），留着只会在别的系统上再造一次双层。

static id (*orig_textFont)(id, SEL, id, id, BOOL);
static void (*orig_badgeLayout)(id, SEL);

#pragma mark - 我们的图：打标记、认领

static const void *TCXBadgeMarkKey = &TCXBadgeMarkKey;
static const void *TCXBadgeOverlayKey = &TCXBadgeOverlayKey;

static void TCXBadgeMarkImage(UIImage *image) {
    if (image == nil) return;
    objc_setAssociatedObject(image, TCXBadgeMarkKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL TCXBadgeImageIsOurs(UIImage *image) {
    if (![image isKindOfClass:[UIImage class]]) return NO;
    return objc_getAssociatedObject(image, TCXBadgeMarkKey) != nil;
}

// 底板子树里握着我们那张图的最内层视图（找不到返回 nil）。
static UIView *TCXBadgeOurHostInSubtree(UIView *root) {
    if (root == nil) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    NSUInteger guard = 0;
    while (queue.count > 0 && guard++ < 32) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:[UIImageView class]] && TCXBadgeImageIsOurs(((UIImageView *)view).image)) {
            return view;
        }
        if (view.subviews.count > 0) [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

// 系统底板：KVC 的 _backgroundView / backgroundView，退而找类名带 Darkening 的直接子视图。
static UIView *TCXBadgeBackgroundView(UIView *view) {
    if (view == nil) return nil;
    UIView *bg = nil;
    @try { bg = [view valueForKey:@"_backgroundView"]; } @catch (NSException *e) { bg = nil; }
    if ([bg isKindOfClass:[UIView class]] && bg != view) return bg;
    @try { bg = [view valueForKey:@"backgroundView"]; } @catch (NSException *e) { bg = nil; }
    if ([bg isKindOfClass:[UIView class]] && bg != view) return bg;
    for (UIView *sub in view.subviews) {
        if ([NSStringFromClass([sub class]) containsString:@"Darkening"]) return sub;
    }
    return nil;
}

// 图按等比塞进 box（1.0.7 的结论：沿用宿主的 contentMode 会把图拉宽，一律 AspectFit）。
static CGRect TCXBadgeAspectFitRect(UIImage *image, CGRect box) {
    CGSize size = image != nil ? image.size : CGSizeZero;
    if (size.width <= 0 || size.height <= 0 || box.size.width <= 0 || box.size.height <= 0) return box;
    CGFloat ratio = MIN(box.size.width / size.width, box.size.height / size.height);
    CGSize fit = CGSizeMake(size.width * ratio, size.height * ratio);
    return CGRectMake(box.origin.x + (box.size.width - fit.width) / 2.0,
                      box.origin.y + (box.size.height - fit.height) / 2.0,
                      fit.width, fit.height);
}

#pragma mark - 成图

// 主题底板素材（原图，不做 resizable）。theme 里实测是 SBBadgeBG@3x.png（75x75px = 25pt）。
static UIImage *TCXBadgeArt(void) {
    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];
    UIImage *art = [store springboardImageNamed:@"SBBadgeBG" scale:3.0];
    if (!art) art = [store springboardImageNamed:@"SBBadgeBackground" scale:3.0];
    if (!art) return nil;
    if (art.size.width < 4 || art.size.height < 4 || art.CGImage == NULL) return nil;
    return art;
}

// 「底板 + 数字」合成一张整图：素材原样 + 数字居中。
//   用户 2026-11-06 原话「角标只按名字加载 不按形状你去画它！你永远画不对！」——
//   素材（SBBadgeBG@3x.png 等）已由主题作者设计好形状（圆/方/异形），我们绝不裁剪、拼接、拉伸，
//   原样使用；数字画在素材中心，字号自适应不溢出。素材尺寸即 badge 尺寸（@3x 75px = 25pt）。
static UIImage *TCXBadgeCompose(UIImage *art, NSString *text, UIFont *font) {
    if (art == nil || font == nil || [text length] == 0) return nil;

    CGFloat scale = art.scale > 0 ? art.scale : 3.0;
    CGSize size = art.size;   // 素材逻辑尺寸（如 25x25），即 badge 尺寸
    if (size.width < 1.0 || size.height < 1.0) return nil;

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentCenter;
    para.lineBreakMode = NSLineBreakByClipping;

    // 数字字号自适应：从传入字号往下找，直到宽高都放进素材安全区。
    CGFloat maxTextW = size.width * 0.74;
    CGFloat maxTextH = size.height * 0.66;
    UIFont *useFont = font;
    CGFloat start = font.pointSize > 0 ? font.pointSize : 16.0;
    for (CGFloat pt = start; pt >= 6.0; pt -= 1.0) {
        UIFont *cand = [UIFont fontWithDescriptor:font.fontDescriptor size:pt];
        CGSize ts = [text sizeWithAttributes:@{NSFontAttributeName: cand,
                                               NSParagraphStyleAttributeName: para}];
        if (ts.width <= maxTextW && ts.height <= maxTextH) { useFont = cand; break; }
        useFont = cand;
    }

    NSDictionary *attrs = @{ NSFontAttributeName: useFont,
                             NSForegroundColorAttributeName: [UIColor whiteColor],
                             NSParagraphStyleAttributeName: para };
    CGSize textSize = [text sizeWithAttributes:attrs];
    if (textSize.width <= 0 || textSize.height <= 0) return nil;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];

    UIImage *out = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [art drawInRect:CGRectMake(0, 0, size.width, size.height)];   // 素材原样
        [text drawInRect:CGRectMake(0, (size.height - textSize.height) / 2.0,
                                    size.width, textSize.height)
          withAttributes:attrs];
    }];
    return out;
}

// 成图站：返回类型绝不改变（tuple 重新包，裸图换裸图）。
static id repl_textFont(id self, SEL _cmd, id text, id font, BOOL highlighted) {
    id original = orig_textFont ? orig_textFont(self, _cmd, text, font, highlighted) : nil;
    @try {
        if (!TCXPrefBool(@"Enabled", YES)) return original;
        if (![text isKindOfClass:[NSString class]] || [text length] == 0) return original;

        TCXCountBadgeLook();

        UIImage *art = TCXBadgeArt();
        if (art == nil) return original;

        UIFont *useFont = [font isKindOfClass:[UIFont class]] ? font
                       : [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        UIImage *image = TCXBadgeCompose(art, (NSString *)text, useFont);
        if (image == nil) return original;
        TCXBadgeMarkImage(image);

        Class tupleClass = TCXClass(@"SBHIconAccessoryCountedMapImageTuple");
        if (tupleClass && [original isKindOfClass:tupleClass]) {
            SEL initSel = @selector(initWithImage:countedMapKey:);
            if ([tupleClass instancesRespondToSelector:initSel]) {
                TCXStore *store = [TCXStore shared];
                NSString *key = [NSString stringWithFormat:@"appicon-badge-%@-%lu-%@",
                                 store.themeName ?: @"none", (unsigned long)store.generation, text];
                id tuple = ((id (*)(id, SEL, id, id))objc_msgSend)([tupleClass alloc], initSel, image, key);
                if (tuple != nil) return tuple;
            }
            return original;   // 包不上就退回原值，绝不返回类型不对的东西
        }
        if ([original isKindOfClass:[UIImage class]]) return image;

        Class accClass = TCXClass(@"SBIconAccessoryImage");
        if (accClass && [accClass instancesRespondToSelector:@selector(initWithImage:)]) {
            id acc = ((id (*)(id, SEL, id))objc_msgSend)([accClass alloc], @selector(initWithImage:), image);
            if (acc != nil) return acc;
        }
        return original;
    } @catch (NSException *exception) {
        return original;
    }
}

// 呈现站：把我们的整图搬到自己的一层，再把系统底板藏掉（系统每帧重画也露不出来）。
static void repl_badgeLayout(id self, SEL _cmd) {
    if (orig_badgeLayout) orig_badgeLayout(self, _cmd);
    @try {
        if (!TCXPrefBool(@"Enabled", YES)) return;
        UIView *view = (UIView *)self;
        UIView *bgView = TCXBadgeBackgroundView(view);
        if (bgView == nil) return;

        UIImageView *overlay = objc_getAssociatedObject(view, TCXBadgeOverlayKey);
        BOOL haveOverlay = [overlay isKindOfClass:[UIImageView class]] && overlay.superview == view;
        UIView *ourHost = TCXBadgeOurHostInSubtree(bgView);

        if (!haveOverlay && ourHost == nil) return;   // 这一格没我们的图 → 一个字节都不动

        if (!haveOverlay) {
            overlay = [[UIImageView alloc] initWithFrame:bgView.frame];
            overlay.userInteractionEnabled = NO;
            overlay.contentMode = UIViewContentModeScaleAspectFit;
            objc_setAssociatedObject(view, TCXBadgeOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [view addSubview:overlay];
            TCXNoteSite(@"badge:lift");
        }
        UIImage *fresh = [ourHost isKindOfClass:[UIImageView class]] ? ((UIImageView *)ourHost).image : nil;
        if (fresh != nil && fresh != overlay.image) overlay.image = fresh;

        CGRect box = bgView.frame;
        if (ourHost != nil && ourHost.superview != nil) {
            box = [ourHost convertRect:ourHost.bounds toView:view];
        }
        overlay.frame = TCXBadgeAspectFitRect(overlay.image, box);
        if (overlay.hidden) overlay.hidden = NO;
        if (view.subviews.lastObject != overlay) [view bringSubviewToFront:overlay];
        if (!bgView.hidden) bgView.hidden = YES;
    } @catch (NSException *exception) {}
}

void TCXInstallBadgeHooks(void) {
    Class cls = TCXClass(@"SBIconBadgeView");
    if (!cls) {
        TCXNoteSite(@"badge:noclass");
        return;
    }
    Class meta = object_getClass(cls);

    // ① 成图站（类方法）：本机 iOS 16 角标的图与文字都从这出来。
    if ([meta respondsToSelector:@selector(_checkoutImageForText:font:highlighted:)]) {
        MSHookMessageEx(meta, @selector(_checkoutImageForText:font:highlighted:),
                        (IMP)&repl_textFont, (IMP *)&orig_textFont);
        if (orig_textFont) TCXNoteSite(@"SBIconBadgeView:+_checkoutImageForText:font:highlighted:");
    }

    // ② 呈现站：搬图 + 藏底板。
    if ([cls respondsToSelector:@selector(layoutSubviews)]) {
        MSHookMessageEx(cls, @selector(layoutSubviews),
                        (IMP)&repl_badgeLayout, (IMP *)&orig_badgeLayout);
        if (orig_badgeLayout) TCXNoteSite(@"SBIconBadgeView:layoutSubviews");
    }
}
