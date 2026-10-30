//
//  ThemeCorePlusBadges.m —— 角标：把系统角标底板换成主题里的 SBBadgeBG。
//
//  iOS 16 的角标流程有好几处「同一件事」的入口，版本间来回搬过，所以三处候选全挂：
//   · -_checkoutBackgroundImage        出底板图（数字由视图自己画在上面）
//   · -_checkoutBackgroundImageTuple   出 SBHIconAccessoryCountedMapImageTuple（底板 + 计数键）
//   · +_checkoutImageForText:font:highlighted:  出「含数字的整图」，这时得自己把数字画上去
//
//  三站的「替换」全部交给 ThemeCorePlusHooks.m 的 TCPThemedImageReplacement：先让原实现
//  出它该出的东西，再只把里面的图换成主题图。iOS 16.7 实测这三站出的都是
//  SBHIconAccessoryCountedMapImageTuple，不是 UIImage —— 类型顶替必崩（安全模式）。
//
#import "ThemeCorePlusHooks.h"
#import "ThemeCorePlusStore.h"

UIImage *TCPThemedBadgeBackground(CGFloat scale) {
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;
    return [store badgeBackgroundImageForScale:scale];
}

// 把一张素材**等比**画进盒子里（aspect-fit，居中）。角标是圆的就还是圆的：
// 盒子比素材宽时，两边留白，绝不横向拉长 —— 这就是「不变形」的全部秘密。
static void TCPDrawAssetAspectFitted(UIImage *image, CGRect box) {
    CGSize size = image.size;
    if (size.width <= 0 || size.height <= 0 || box.size.width <= 0 || box.size.height <= 0) return;
    CGFloat factor = MIN(box.size.width / size.width, box.size.height / size.height);
    CGSize drawn = CGSizeMake(size.width * factor, size.height * factor);
    [image drawInRect:CGRectMake(box.origin.x + (box.size.width - drawn.width) / 2.0,
                                 box.origin.y + (box.size.height - drawn.height) / 2.0,
                                 drawn.width, drawn.height)];
}

// 角标形状的取证串：最近一次合成用的文字、素材尺寸、画布尺寸。
// 有这个就不必看屏幕判断形状 —— 一个数字时画布必须等于素材的宽高比（正方形素材 → 正方形画布）。
static NSString *sBadgeProbe = nil;

NSString *TCPBadgeProbeReport(void) {
    return sBadgeProbe ?: @"badge=-";
}

// 圆头拉伸时两头要留多宽：按素材自己的尺寸算，素材两头是什么形状（圆弧、尖角、异形）都原样保留。
static CGFloat TCPBadgeCapInset(UIImage *asset) {
    if (asset.size.height <= 0) return 0;
    return MIN(asset.size.height * 0.45, MAX(0.0, asset.size.width / 2.0 - 0.5));
}

// 底板：系统给了盒子（它自己的角标图尺寸）时，把素材**按它自己的形状**渲染进那个盒子：
//   · 素材是什么形状就是什么形状 —— 圆、方、异形、带尖角都行，**永远不拉伸**；
//   · 盒子比素材的自然宽度还窄：按自然比例画满高度、居中（多出来的是留白）；
//   · 盒子更宽（两位以上数字，系统本来给的就是宽版）：只拉伸素材中间那一段，两头原样保留。
UIImage *TCPThemedBadgeBackgroundInBox(CGFloat scale, CGSize box) {
    UIImage *asset = TCPThemedBadgeBackground(scale);
    if (asset == nil || asset.size.height <= 0) return nil;
    if (box.width <= 0 || box.height <= 0) return asset;
    if (scale <= 0) scale = [UIScreen mainScreen].scale;
    if (scale <= 0) scale = 3.0;

    // 盒子跟素材差得太远（系统给了个明显不合理的值）就按素材自己的尺寸来，免得角标被放大成怪物。
    if (box.height > asset.size.height * 2.0 || box.height < asset.size.height * 0.5) return asset;

    CGFloat aspect = asset.size.width / asset.size.height;   // 素材自己的宽高比 = 它的形状
    CGFloat naturalWidth = box.height * aspect;
    UIGraphicsBeginImageContextWithOptions(box, NO, scale);
    if (box.width <= naturalWidth + 0.5) {
        TCPDrawAssetAspectFitted(asset, CGRectMake(0, 0, box.width, box.height));
    } else {
        CGFloat cap = TCPBadgeCapInset(asset);
        UIImage *stretchable = [asset resizableImageWithCapInsets:UIEdgeInsetsMake(0, cap, 0, cap)
                                                     resizingMode:UIImageResizingModeStretch];
        [stretchable drawInRect:CGRectMake(0, 0, box.width, box.height)];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image ?: asset;
}

// 底板上画数字。形状完全听素材的：
//   · 一个数字 = 素材的自然宽度（圆的是圆、方的是方、异形是异形，绝不为一个数字把形状改了）；
//   · 多个数字 = 把素材中间拉宽（圆头拉伸），两头形状原样保留；
//   · 字一律居中，且**自动缩到装得下**（素材内缘留 8% 边距），再怪的字形也不会溢出角标。
// 尺寸以**系统给的盒子**为准（systemBox 就是系统为这段文本准备的角标图尺寸，它才决定屏幕上占多大），
// 系统没给才退回素材自己的点数。
UIImage *TCPThemedBadgeTextImage(NSString *text, UIFont *font, CGFloat scale, CGSize systemBox) {
    if (text.length == 0) return nil;
    TCPThemeStore *store = [TCPThemeStore shared];
    UIImage *asset = TCPThemedBadgeBackground(scale);
    if (asset == nil || asset.size.height <= 0) return nil;
    if (scale <= 0) scale = [UIScreen mainScreen].scale;
    if (scale <= 0) scale = 3.0;

    CGFloat side = systemBox.height > 0 ? systemBox.height : asset.size.height;
    if (side <= 0) return nil;
    CGFloat aspect = asset.size.width / asset.size.height;
    CGFloat naturalWidth = side * aspect;

    UIFont *drawFont = font;
    CGFloat configuredSize = [store badgeFontSize];
    NSString *configuredName = [store badgeFontName];
    if (configuredName.length > 0) {
        UIFont *named = [UIFont fontWithName:configuredName size:(configuredSize > 0 ? configuredSize : side * 0.62)];
        if (named) drawFont = named;
    } else if (configuredSize > 0 && font != nil) {
        drawFont = [font fontWithSize:configuredSize];
    }
    if (drawFont == nil) drawFont = [UIFont systemFontOfSize:side * 0.62];
    UIColor *color = [store badgeTextColor] ?: [UIColor whiteColor];

    // 文字自动缩放：先按素材的自然宽度算一遍，装不下就整体缩小（不改形状，只缩字）。
    NSDictionary<NSAttributedStringKey, id> *attributes = @{ NSFontAttributeName: drawFont,
                                                             NSForegroundColorAttributeName: color };
    CGSize textSize = [text sizeWithAttributes:attributes];
    CGFloat fitWidth = MAX(1.0, naturalWidth * 0.84);
    CGFloat fitHeight = MAX(1.0, side * 0.78);
    CGFloat factor = 1.0;
    if (textSize.width > fitWidth) factor = MIN(factor, fitWidth / textSize.width);
    if (textSize.height > fitHeight) factor = MIN(factor, fitHeight / textSize.height);
    if (factor < 0.999) {
        drawFont = [drawFont fontWithSize:MAX(1.0, drawFont.pointSize * factor)];
        attributes = @{ NSFontAttributeName: drawFont, NSForegroundColorAttributeName: color };
        textSize = [text sizeWithAttributes:attributes];
    }

    CGFloat width = naturalWidth;
    if (text.length > 1) {
        width = MAX(naturalWidth, ceil(textSize.width + side * 0.5));
    }
    if (width <= 0 || side <= 0) return nil;

    CGRect canvas = CGRectMake(0, 0, width, side);
    UIGraphicsBeginImageContextWithOptions(canvas.size, NO, scale);
    if (width <= naturalWidth + 0.5) {
        // 一个数字：素材按自然比例铺满高度，形状原样（正方形素材 → 还是正圆）。
        [asset drawInRect:CGRectMake((width - naturalWidth) / 2.0, 0, naturalWidth, side)];
    } else {
        CGFloat cap = TCPBadgeCapInset(asset);
        UIImage *stretchable = [asset resizableImageWithCapInsets:UIEdgeInsetsMake(0, cap, 0, cap)
                                                     resizingMode:UIImageResizingModeStretch];
        [stretchable drawInRect:canvas];
    }
    CGRect textRect = CGRectMake((width - textSize.width) / 2.0,
                                 (side - textSize.height) / 2.0,
                                 textSize.width, textSize.height);
    [text drawInRect:textRect withAttributes:attributes];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    sBadgeProbe = [NSString stringWithFormat:@"badge=%@;asset=%.0fx%.0f;canvas=%.0fx%.0f;fit=%.2f",
                   text, asset.size.width, asset.size.height, width, side, factor];
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
