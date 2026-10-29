//
//  ThemeCorePlusBadges.m —— 角标：把系统角标底板换成主题里的 SBBadgeBG。
//
//  iOS 16 的角标流程有好几处「同一件事」的入口，版本间来回搬过，所以三处候选全挂，
//  存在才挂、拿到主题素材才替换：
//   · -_checkoutBackgroundImage        出底板 UIImage（数字由视图自己画在上面）
//   · -_checkoutBackgroundImageTuple   出 SBHIconAccessoryCountedMapImageTuple（底板 + 计数键）
//   · +_checkoutImageForText:font:highlighted:  出「含数字的整图」，这时得自己把数字画上去
//
#import "ThemeCorePlusHooks.h"
#import "ThemeCorePlusStore.h"

UIImage *TCPThemedBadgeBackground(CGFloat scale) {
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;
    return [store badgeBackgroundImageForScale:scale];
}

id TCPThemedBadgeTuple(id originalTuple, CGFloat scale) {
    UIImage *themed = TCPThemedBadgeBackground(scale);
    if (themed == nil) return originalTuple;
    // 有的版本这一站就是直接出图。
    if ([originalTuple isKindOfClass:[UIImage class]]) return themed;
    if (originalTuple == nil) return themed;

    Class tupleClass = objc_getClass("SBHIconAccessoryCountedMapImageTuple");
    if (tupleClass == Nil) return originalTuple;

    SEL keySelector = NSSelectorFromString(@"countedMapKey");
    if (![originalTuple respondsToSelector:keySelector]) return originalTuple;
    id key = ((id (*)(id, SEL))objc_msgSend)(originalTuple, keySelector);

    SEL initSelector = NSSelectorFromString(@"initWithImage:countedMapKey:");
    if (key == nil || ![tupleClass instancesRespondToSelector:initSelector]) return originalTuple;

    id instance = ((id (*)(id, SEL))objc_msgSend)((id)tupleClass, sel_registerName("alloc"));
    if (instance == nil) return originalTuple;
    id tuple = ((id (*)(id, SEL, UIImage *, id))objc_msgSend)(instance, initSelector, themed, key);
    return tuple ?: originalTuple;
}

// 底板上画数字：底板是可拉伸的（主题里的 SBBadgeBG 就一张），横向按文字宽度拉伸，
// 文字居中。字色/字体/字号没配就用系统给的字体和白色。
UIImage *TCPThemedBadgeTextImage(NSString *text, UIFont *font, CGFloat scale) {
    if (text.length == 0) return nil;
    TCPThemeStore *store = [TCPThemeStore shared];
    UIImage *background = TCPThemedBadgeBackground(scale);
    if (background == nil || background.size.height <= 0) return nil;

    UIFont *drawFont = font;
    CGFloat configuredSize = [store badgeFontSize];
    NSString *configuredName = [store badgeFontName];
    if (configuredName.length > 0) {
        UIFont *named = [UIFont fontWithName:configuredName size:(configuredSize > 0 ? configuredSize : background.size.height * 0.62)];
        if (named) drawFont = named;
    } else if (configuredSize > 0 && font != nil) {
        drawFont = [font fontWithSize:configuredSize];
    }
    if (drawFont == nil) drawFont = [UIFont systemFontOfSize:background.size.height * 0.62];
    UIColor *color = [store badgeTextColor] ?: [UIColor whiteColor];

    NSDictionary<NSAttributedStringKey, id> *attributes = @{ NSFontAttributeName: drawFont,
                                                             NSForegroundColorAttributeName: color };
    CGSize textSize = [text sizeWithAttributes:attributes];
    CGFloat height = ceil(background.size.height);
    CGFloat width = MAX(height, ceil(textSize.width + height * 0.55));
    if (width <= 0 || height <= 0) return nil;

    CGFloat cap = height * 0.45;
    UIImage *stretchable = [background resizableImageWithCapInsets:UIEdgeInsetsMake(0, cap, 0, cap)
                                                      resizingMode:UIImageResizingModeStretch];
    CGRect canvas = CGRectMake(0, 0, width, height);
    UIGraphicsBeginImageContextWithOptions(canvas.size, NO, scale > 0 ? scale : 0);
    [stretchable drawInRect:canvas];
    CGRect textRect = CGRectMake((width - textSize.width) / 2.0,
                                 (height - textSize.height) / 2.0,
                                 textSize.width, textSize.height);
    [text drawInRect:textRect withAttributes:attributes];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

void TCPInstallBadgeSites(void) {
    NSArray<NSString *> *badgeClasses = @[ @"SBIconBadge" ];
    TCPInstallSitesForClassPrefixes(badgeClasses, nil, @[ @"_checkoutBackgroundImage" ],
                                    TCPSiteKindBadgeBackground);
    TCPInstallSitesForClassPrefixes(@[ @"SBHIconAccessory" ], nil, @[ @"_checkoutBackgroundImage" ],
                                    TCPSiteKindBadgeBackground);
    TCPInstallSitesForClassPrefixes(badgeClasses, nil, @[ @"_checkoutBackgroundImageTuple" ],
                                    TCPSiteKindBadgeTuple);
    TCPInstallSitesForClassPrefixes(badgeClasses, nil, @[ @"_checkoutImageForText:font:highlighted:" ],
                                    TCPSiteKindBadgeTextImage);
}
