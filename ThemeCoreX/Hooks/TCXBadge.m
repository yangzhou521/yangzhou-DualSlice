#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "TCXPrivate.h"
#import "TCXStore.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"

// 角标层。
//
// iOS 16 的 SBIconBadgeView 不给「设置一张图」的入口，它从缓存里结账式取图：
//   +[SBIconBadgeView _checkoutBackgroundImage]              （类方法，一次取一张底板）
//   -[SBIconBadgeView _checkoutBackgroundImage]              （实例方法）
// 返回值可能是 UIImage，也可能是 SBHIconAccessoryCountedMapImageTuple 包着 UIImage ——
// 所以**绝不改变返回类型**：是 tuple 就用 tuple 重新包一层，是 image 就直接换。
// 换了类型会让调用方按错误类型取属性，立刻崩，这是 1.0.x 最贵的一课。
//
// 主题素材（按顺序找）：
//   <主题>/Bundles/com.apple.springboard/SBBadgeBackground@2x.png
//   <主题>/SBBadgeBackground@2x.png

static id (*orig_bgInstance)(id, SEL);
static id (*orig_bgClass)(id, SEL);
static id (*orig_bgTuple)(id, SEL);
static id (*orig_textFont)(id, SEL, id, id, BOOL);
static void (*orig_badgeLayout)(id, SEL);

// 角标底板素材名：主题里实测是 **SBBadgeBG@3x.png**（在 Bundles/com.apple.springboard/ 下），
// 有的主题叫 SBBadgeBackground，两个都试。
// 底板要用 resizableImageWithCapInsets 拉伸：系统底板会随文字变宽，
// 直接 drawInRect 拉伸会把圆角拉成方的（宽角标「99+」尤其明显）。
static UIImage *TCXBadgeArt(void) {
    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];
    UIImage *art = [store springboardImageNamed:@"SBBadgeBG" scale:3.0];
    if (!art) art = [store springboardImageNamed:@"SBBadgeBackground" scale:3.0];
    if (!art) return nil;
    CGSize pixels = CGSizeMake(art.size.width * art.scale, art.size.height * art.scale);
    if (pixels.width < 8 || pixels.height < 8) return art;
    UIEdgeInsets cap = UIEdgeInsetsMake(pixels.height * 0.4, pixels.width * 0.4,
                                        pixels.height * 0.4, pixels.width * 0.4);
    return [art resizableImageWithCapInsets:cap resizingMode:UIImageResizingModeStretch];
}

// iOS 16 的角标底板**不是图**：SBIconBadgeView 内部有个 _backgroundView，
// 系统给它设 systemRed + 圆角。所以底板只能走 layoutSubviews：
// 把主题图塞进 _backgroundView 并把 backgroundColor 清成透明。
// layoutSubviews 由 UIView 继承而来，类自己不声明 —— 判断要用 respondsToSelector。
static void repl_badgeLayout(id self, SEL _cmd) {
    if (orig_badgeLayout) orig_badgeLayout(self, _cmd);
    @try {
        if (!TCXPrefBool(@"Enabled", YES)) return;
        UIImage *bg = TCXBadgeArt();
        if (!bg) return;
        UIView *bgView = nil;
        @try { bgView = [self valueForKey:@"_backgroundView"]; } @catch (NSException *e) { bgView = nil; }
        if ([bgView isKindOfClass:[UIImageView class]]) {
            [(UIImageView *)bgView setImage:bg];
            [bgView setBackgroundColor:[UIColor clearColor]];
            TCXCountBadgeLook();
        }
    } @catch (NSException *exception) {}
}

// 角标文字图：iOS 16 的文字仍然走 +_checkoutImageForText:font:highlighted:。
// 主题没给字体/颜色设置时，用系统字体与白色画一张透明底文字图。
static id repl_textFont(id self, SEL _cmd, id text, id font, BOOL highlighted) {
    id original = orig_textFont ? orig_textFont(self, _cmd, text, font, highlighted) : nil;
    @try {
        if (!TCXPrefBool(@"Enabled", YES)) return original;
        if (![text isKindOfClass:[NSString class]] || [text length] == 0) return original;

        TCXCountBadgeLook();

        UIFont *useFont = [font isKindOfClass:[UIFont class]] ? font
                       : [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        CGSize textSize = [text sizeWithAttributes:@{NSFontAttributeName: useFont}];
        if (textSize.width <= 0 || textSize.height <= 0) return original;

        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 3.0;
        format.opaque = NO;
        UIGraphicsImageRenderer *renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:textSize format:format];
        UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [text drawAtPoint:CGPointZero withAttributes:@{NSFontAttributeName: useFont,
                                                           NSForegroundColorAttributeName: [UIColor whiteColor]}];
        }];
        if (!img) return original;

        // 用 tuple 包一层：调用方期待的是 SBHIconAccessoryCountedMapImageTuple
        // 或 SBIconAccessoryImage，直接返回裸 UIImage 会被按错误类型取属性。
        Class tupleClass = TCXClass(@"SBHIconAccessoryCountedMapImageTuple");
        if (tupleClass) {
            SEL initSel = @selector(initWithImage:countedMapKey:);
            if ([tupleClass instancesRespondToSelector:initSel]) {
                TCXStore *store = [TCXStore shared];
                NSString *key = [NSString stringWithFormat:@"appicon-badge-%@-%lu",
                                 store.themeName ?: @"none", (unsigned long)store.generation];
                id tuple = ((id (*)(id, SEL, id, id))objc_msgSend)([tupleClass alloc], initSel, img, key);
                if (tuple) return tuple;
            }
        }
        Class accClass = TCXClass(@"SBIconAccessoryImage");
        if (accClass && [accClass instancesRespondToSelector:@selector(initWithImage:)]) {
            id acc = ((id (*)(id, SEL, id))objc_msgSend)([accClass alloc], @selector(initWithImage:), img);
            if (acc) return acc;
        }
        return original;
    } @catch (NSException *exception) {
        return original;
    }
}

static id TCXBadgeBackground(id self, SEL _cmd, id original) {
    if (!original) return nil;
    if (!TCXPrefBool(@"Enabled", YES)) return original;
    // 角标常开（面板已无开关），不再读 BadgeEnabled。

    TCXCountBadgeLook();

    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];

    UIImage *art = [store springboardImageNamed:@"SBBadgeBackground" scale:2.0];
    if (!art) return original;

    Class tupleClass = TCXClass(@"SBHIconAccessoryCountedMapImageTuple");
    if (tupleClass && [original isKindOfClass:tupleClass]) {
        SEL initSel = @selector(initWithImage:countedMapKey:);
        if ([tupleClass instancesRespondToSelector:initSel]) {
            NSString *key = [NSString stringWithFormat:@"appicon-%@-%lu",
                             store.themeName ?: @"none", (unsigned long)store.generation];
            id tuple = ((id (*)(id, SEL, id, id))objc_msgSend)([tupleClass alloc], initSel, art, key);
            if (tuple) return tuple;
        }
        return original;   // 包不上就退回原值，绝不返回类型不对的东西
    }

    if ([original isKindOfClass:[UIImage class]]) return art;
    return original;
}

static id repl_bgInstance(id self, SEL _cmd) {
    id original = orig_bgInstance ? orig_bgInstance(self, _cmd) : nil;
    @try {
        return TCXBadgeBackground(self, _cmd, original);
    } @catch (NSException *exception) {
        return original;
    }
}

static id repl_bgClass(id self, SEL _cmd) {
    id original = orig_bgClass ? orig_bgClass(self, _cmd) : nil;
    @try {
        return TCXBadgeBackground(self, _cmd, original);
    } @catch (NSException *exception) {
        return original;
    }
}

// iOS 13-15 的 tuple 版底板（本次只做兼容，挂上了才走）。
static id repl_bgTuple(id self, SEL _cmd) {
    id original = orig_bgTuple ? orig_bgTuple(self, _cmd) : nil;
    @try {
        return TCXBadgeBackground(self, _cmd, original);
    } @catch (NSException *exception) {
        return original;
    }
}

void TCXInstallBadgeHooks(void) {
    Class cls = TCXClass(@"SBIconBadgeView");
    if (!cls) {
        TCXNoteSite(@"badge:noclass");
        return;
    }

    // iOS 16 的真实结构（第三方 ThemeCorePlus 在本机抓到的，ThemeCore 0.5.1 无角标功能，
    // 这里只能借它对 iOS 16 的实证）：
    //   · 底板**不是图** —— SBIconBadgeView 内部 _backgroundView，系统设 systemRed + 圆角；
    //     所以底板走 layoutSubviews：塞主题图 + 把 backgroundColor 清透明。
    //   · 文字仍然是图 —— 走 +_checkoutImageForText:font:highlighted:。
    //   · 另有 _checkoutBackgroundImageTuple（iOS 13-15 那套的 tuple 版本）。
    // 之前挂 _checkoutBackgroundImage 且用「类自己声明」判断，两分支都不命中 → bdg=0。

    Class meta = object_getClass(cls);

    // ① 文字图（类方法）
    if ([meta respondsToSelector:@selector(_checkoutImageForText:font:highlighted:)]) {
        MSHookMessageEx(meta, @selector(_checkoutImageForText:font:highlighted:),
                        (IMP)&repl_textFont, (IMP *)&orig_textFont);
        if (orig_textFont) TCXNoteSite(@"SBIconBadgeView:+_checkoutImageForText:font:highlighted:");
    }

    // ② 底板（呈现层 layoutSubviews）
    if ([cls respondsToSelector:@selector(layoutSubviews)]) {
        MSHookMessageEx(cls, @selector(layoutSubviews),
                        (IMP)&repl_badgeLayout, (IMP *)&orig_badgeLayout);
        if (orig_badgeLayout) TCXNoteSite(@"SBIconBadgeView:layoutSubviews");
    }

    // ③ tuple 版本（老系统路径，命中就挂）
    unsigned int count0 = 0;
    Method *list0 = class_copyMethodList(cls, &count0);
    BOOL hasTuple = NO;
    for (unsigned int i = 0; i < count0; i++) {
        if (method_getName(list0[i]) == @selector(_checkoutBackgroundImageTuple)) { hasTuple = YES; break; }
    }
    free(list0);
    if (hasTuple) {
        MSHookMessageEx(cls, @selector(_checkoutBackgroundImageTuple),
                        (IMP)&repl_bgTuple, (IMP *)&orig_bgTuple);
        if (orig_bgTuple) TCXNoteSite(@"SBIconBadgeView:-_checkoutBackgroundImageTuple");
    }

    // 老系统（iOS 13-15 那套）：实例与类方法各一个 _checkoutBackgroundImage。
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL hasInstanceBg = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(list[i]) == @selector(_checkoutBackgroundImage)) { hasInstanceBg = YES; break; }
    }
    free(list);

    if (hasInstanceBg) {
        MSHookMessageEx(cls, @selector(_checkoutBackgroundImage),
                        (IMP)&repl_bgInstance, (IMP *)&orig_bgInstance);
        if (orig_bgInstance) TCXNoteSite(@"SBIconBadgeView:-_checkoutBackgroundImage");
    }

    unsigned int classCount2 = 0;
    Method *classList2 = class_copyMethodList(meta, &classCount2);
    BOOL hasClassBg = NO;
    for (unsigned int i = 0; i < classCount2; i++) {
        if (method_getName(classList2[i]) == @selector(_checkoutBackgroundImage)) { hasClassBg = YES; break; }
    }
    free(classList2);

    if (hasClassBg) {
        MSHookMessageEx(meta, @selector(_checkoutBackgroundImage),
                        (IMP)&repl_bgClass, (IMP *)&orig_bgClass);
        if (orig_bgClass) TCXNoteSite(@"SBIconBadgeView:+_checkoutBackgroundImage");
    }
}