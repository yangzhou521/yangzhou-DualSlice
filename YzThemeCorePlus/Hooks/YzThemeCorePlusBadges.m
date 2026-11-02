#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusThemeStore.h"
#import "YzThemeCorePlusPrivate.h"

// 角标主题化。
// iOS 16 底板不再是图片：SBIconBadgeView 的 _backgroundView.backgroundColor = systemRed + 圆角，
// 不调用 _checkoutBackgroundImage/_checkoutBackgroundImageTuple（那是 iOS 13-15 路径）。
// 所以：文字走 _checkoutImageForText:（iOS 16 仍用图）；底板走 layoutSubviews 清红底 + 塞主题图。

static BOOL yz_themecoreplus_badgeActive(void) {
    if (![[YzThemeCorePlusConfig yz_themecoreplus_shared] yz_themecoreplus_isEnabled]) return NO;
    id badgeEnabled = [[YzThemeCorePlusConfig yz_themecoreplus_shared]
        yz_themecoreplus_valueForKey:@"BadgeEnabled" defaultValue:@(YES)];
    if ([badgeEnabled isKindOfClass:[NSNumber class]] && ![badgeEnabled boolValue]) return NO;
    return [[YzThemeCorePlusThemeStore yz_themecoreplus_shared] yz_themecoreplus_hasBadgeConfiguration];
}

static id yz_themecoreplus_wrapAccessoryImage(UIImage *image, NSString *cacheKey) {
    if (!image) return nil;
    if (kCFCoreFoundationVersionNumber >= 1740.0) {
        Class tupleClass = objc_getClass("SBHIconAccessoryCountedMapImageTuple");
        if (tupleClass) return [[tupleClass alloc] initWithImage:image countedMapKey:cacheKey];
    }
    Class accessoryClass = objc_getClass("SBIconAccessoryImage");
    if (accessoryClass) return [[accessoryClass alloc] initWithImage:image];
    return nil;
}

static id yz_themecoreplus_badgeBackground(void) {
    if (!yz_themecoreplus_badgeActive()) return nil;
    YzThemeCorePlusThemeStore *store = [YzThemeCorePlusThemeStore yz_themecoreplus_shared];
    CGFloat scale = [UIScreen mainScreen].scale;
    UIImage *image = [store yz_themecoreplus_badgeBackgroundImageForScale:scale];
    if (!image) return nil;
    NSString *key = [NSString stringWithFormat:@"YzTCPlus.BadgeBG|%lu|%.0fx%.0f",
        (unsigned long)store.yz_themecoreplus_generation,
        image.size.width * image.scale, image.size.height * image.scale];
    return yz_themecoreplus_wrapAccessoryImage(image, key);
}

static id yz_themecoreplus_textImage(NSString *text, UIFont *fallbackFont, BOOL highlighted) {
    if (!yz_themecoreplus_badgeActive()) return nil;
    if (text.length == 0) return nil;

    YzThemeCorePlusThemeStore *store = [YzThemeCorePlusThemeStore yz_themecoreplus_shared];
    NSDictionary *settings = [store yz_themecoreplus_badgeSettings];

    id fontNameValue = settings[@"FontName"];
    id fontSizeValue = settings[@"FontSize"];
    CGFloat fontSize = [fontSizeValue isKindOfClass:[NSNumber class]]
        ? [fontSizeValue floatValue]
        : (fallbackFont.pointSize > 0 ? fallbackFont.pointSize : 16.0);
    UIFont *font = nil;
    if ([fontNameValue isKindOfClass:[NSString class]] && [(NSString *)fontNameValue length] > 0) {
        font = [UIFont fontWithName:fontNameValue size:fontSize];
    }
    if (!font) {
        font = fallbackFont ?: [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
        if (fontSize > 0 && font.pointSize != fontSize) {
            font = [UIFont fontWithDescriptor:font.fontDescriptor size:fontSize];
        }
    }

    UIColor *textColor = [store yz_themecoreplus_colorWithCSSString:settings[@"TextColor"]] ?: [UIColor whiteColor];
    UIColor *shadowColor = [store yz_themecoreplus_colorWithCSSString:settings[@"ShadowColor"]];

    CGFloat widthChange = [settings[@"WidthChange"] floatValue];
    CGFloat heightChange = [settings[@"HeightChange"] floatValue];
    CGFloat xoffset = [settings[@"TextXoffset"] floatValue];
    CGFloat yoffset = [settings[@"TextYoffset"] floatValue];
    CGSize shadowOffset = CGSizeMake([settings[@"ShadowXoffset"] floatValue],
                                     [settings[@"ShadowYoffset"] floatValue]);
    CGFloat shadowBlur = [settings[@"ShadowBlurRadius"] floatValue];

    NSString *drawText = text;
    NSString *textCase = [settings[@"TextCase"] isKindOfClass:[NSString class]] ? settings[@"TextCase"] : nil;
    if ([textCase.lowercaseString isEqualToString:@"lowercase"]) drawText = text.lowercaseString;
    else if ([textCase.lowercaseString isEqualToString:@"uppercase"]) drawText = text.uppercaseString;

    CGSize textSize = [drawText sizeWithAttributes:@{NSFontAttributeName: font}];
    if (textSize.width <= 0 || textSize.height <= 0) return nil;
    CGSize imageSize = CGSizeMake(textSize.width + widthChange, textSize.height + heightChange);

    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = [UIScreen mainScreen].scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:imageSize format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef ctx = context.CGContext;
        if (shadowColor) {
            CGContextSetShadowWithColor(ctx, shadowOffset, shadowBlur, shadowColor.CGColor);
        }
        [drawText drawAtPoint:CGPointMake(xoffset, yoffset) withAttributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: textColor,
        }];
    }];
    if (!image) return nil;

    NSString *key = [NSString stringWithFormat:@"YzTCPlus.BadgeText|%@|%@|%.1f|%d|%lu",
        drawText, font.fontName, font.pointSize, highlighted ? 1 : 0,
        (unsigned long)store.yz_themecoreplus_generation];
    return yz_themecoreplus_wrapAccessoryImage(image, key);
}

// ---- 挂站原实现 ----
static id (*orig_bgTuple)(id self, SEL _cmd) = NULL;
static id (*orig_bgInst)(id self, SEL _cmd) = NULL;
static id (*orig_bgClass)(id self, SEL _cmd) = NULL;
static id (*orig_textFont)(id self, SEL _cmd, NSString *text, UIFont *font, BOOL highlighted) = NULL;
static id (*orig_text)(id self, SEL _cmd, NSString *text, BOOL highlighted) = NULL;
static void (*orig_layoutSubviews)(id self, SEL _cmd) = NULL;

static id repl_bgTuple(id self, SEL _cmd) { return yz_themecoreplus_badgeBackground() ?: orig_bgTuple(self, _cmd); }
static id repl_bgInst(id self, SEL _cmd) { return yz_themecoreplus_badgeBackground() ?: orig_bgInst(self, _cmd); }
static id repl_bgClass(id self, SEL _cmd) { return yz_themecoreplus_badgeBackground() ?: orig_bgClass(self, _cmd); }
static id repl_textFont(id self, SEL _cmd, NSString *text, UIFont *font, BOOL highlighted) {
    return yz_themecoreplus_textImage(text, font, highlighted) ?: orig_textFont(self, _cmd, text, font, highlighted);
}
static id repl_text(id self, SEL _cmd, NSString *text, BOOL highlighted) {
    return yz_themecoreplus_textImage(text, nil, highlighted) ?: orig_text(self, _cmd, text, highlighted);
}
static void repl_layoutSubviews(id self, SEL _cmd) {
    orig_layoutSubviews(self, _cmd);
    if (!yz_themecoreplus_badgeActive()) return;
    UIImage *bg = [[YzThemeCorePlusThemeStore yz_themecoreplus_shared]
        yz_themecoreplus_badgeBackgroundImageForScale:[UIScreen mainScreen].scale];
    if (!bg) return;
    UIView *bgView = [self valueForKey:@"_backgroundView"];
    if ([bgView isKindOfClass:[UIImageView class]]) {
        [(UIImageView *)bgView setImage:bg];
        [bgView setBackgroundColor:[UIColor clearColor]];
    }
}

__attribute__((constructor))
static void yz_badges_init(void) {
    @autoreleasepool {
        Class cls = objc_getClass("SBIconBadgeView");
        if (!cls) return;
        Class meta = object_getClass(cls);
        MSHookMessageEx(cls, @selector(_checkoutBackgroundImageTuple), (IMP)&repl_bgTuple, (IMP*)&orig_bgTuple);
        MSHookMessageEx(cls, @selector(_checkoutBackgroundImage), (IMP)&repl_bgInst, (IMP*)&orig_bgInst);
        MSHookMessageEx(meta, @selector(_checkoutBackgroundImage), (IMP)&repl_bgClass, (IMP*)&orig_bgClass);
        MSHookMessageEx(meta, @selector(_checkoutImageForText:font:highlighted:), (IMP)&repl_textFont, (IMP*)&orig_textFont);
        MSHookMessageEx(meta, @selector(_checkoutImageForText:highlighted:), (IMP)&repl_text, (IMP*)&orig_text);
        MSHookMessageEx(cls, @selector(layoutSubviews), (IMP)&repl_layoutSubviews, (IMP*)&orig_layoutSubviews);
    }
}
