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

// —— 单层闸门 + 各站打点（0.9.4）——
// iOS 16 的角标视图会先问底板站、再问成图站；两站都往结果里画同一张素材底板，
// 屏幕上就是底板画了两遍（用户 2026-10-30 说的「图标目前二个图层」）。现在的分工：
//   底板站（_checkoutBackgroundImage*）换成功过 → 成图站只出「数字」（透明底），底板归底板站；
//   底板站一次都没命中（有的版本只走成图站） → 成图站照旧出「底板 + 数字」的整图。
// 每站被问几次、换成功几次写进诊断 badge{}，装完机不用看屏幕就知道哪条路在跑。
static NSInteger sBadgeBackLook = 0, sBadgeBackHit = 0;
static NSInteger sBadgeTupleLook = 0, sBadgeTupleHit = 0;
static NSInteger sBadgeTextLook = 0, sBadgeTextHit = 0;

// —— 0.9.11：单层化，把「系统自己画的那层底板」清掉 ——
// 本机实测（诊断串，2026-10-31 04:2x）：
//   bg{look=0,hit=0};tup{look=0,hit=0};txt{look=6,hit=6};gate=composed
// 也就是 iOS 16.7.16 的角标只有「成图站」一条路（+[SBIconBadgeView
// _checkoutImageForText:font:highlighted:]），底板那两站的方法在这台系统上根本不存在。
// 于是我们交出去的整图里自带主题底板，而角标视图自己还会再画一层系统底板 ——
// 屏幕上就是「系统底板 + 主题底板」两层（用户 2026-10-31 04:07 原话：
// 「一层是原系统角标没有被隐藏！二层又同时加载第三方角标素材了！」）。
//
// icli probe 把角标视图摊开（2026-10-31，SpringBoardHome）：
//   SBIconBadgeView (backgroundColor = nil)
//     └ backgroundView = SBDarkeningImageView  frame (1 1; 24 24)
//                        backgroundColor = 系统红 (1, 0.231, 0.188, 1)   ← 这就是「没被隐藏的那层」
//         └ UIImageView  image = 系统给这段文字准备的图（数字）        ← 我们的整图换的就是它
// 关键：**我们的图就画在 backgroundView 里面**。所以不能像藏普通子视图那样把
// backgroundView 藏掉 —— 那会连我们自己的图一起藏没。只清它的底色（和它自己那张
// 非我们的底图），屏幕上就只剩主题那一层。
static BOOL sBadgeComposedServed = NO;
static BOOL sBadgeHiding = NO;
static NSMutableArray<UIImage *> *sBadgeRenderedImages = nil;
static NSInteger sBadgeSysLook = 0, sBadgeSysHidden = 0, sBadgeSysWait = 0;
static NSInteger sBadgeLayoutCalls = 0, sBadgeConfigCalls = 0, sBadgeMoveCalls = 0, sBadgeLayCalls = 0;
static NSString *sBadgeSysTree = nil;

// 我们合成过的角标图（底板、整图、纯数字三种都记）。角标站拿到的 self 是**类对象**
// （成图站是类方法），碰不到视图，所以「哪张图是我们的」只能靠这张表自己认。
static void TCPBadgeRememberImage(UIImage *image) {
    if (image == nil) return;
    if (sBadgeRenderedImages == nil) sBadgeRenderedImages = [NSMutableArray array];
    if (sBadgeRenderedImages.count >= 64) [sBadgeRenderedImages removeObjectAtIndex:0];
    [sBadgeRenderedImages addObject:image];
}

static BOOL TCPBadgeImageIsOurs(UIImage *image) {
    if (image == nil) return NO;
    for (UIImage *ours in sBadgeRenderedImages) {
        if (ours == image) return YES;
        if (ours.CGImage != NULL && ours.CGImage == image.CGImage) return YES;
    }
    return NO;
}

static BOOL TCPBadgeLayerIsOurs(CALayer *layer) {
    id contents = layer.contents;
    if (contents == nil) return NO;
    if ([contents isKindOfClass:[UIImage class]]) return TCPBadgeImageIsOurs((UIImage *)contents);
    if (CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
        CGImageRef cg = (__bridge CGImageRef)contents;
        for (UIImage *ours in sBadgeRenderedImages) {
            if (ours.CGImage != NULL && ours.CGImage == cg) return YES;
        }
    }
    return NO;
}

// 把角标收拾成一层：只清「系统底板」的底色，绝不动我们那张图所在的节点。
// 本机结构（probe 实测）：SBIconBadgeView → backgroundView(SBDarkeningImageView，系统红底)
// → UIImageView(我们的整图)。所以 backgroundView 是**祖先**，不能藏，只能清色。
// 判据很硬：**树里一张我们的图都没有就什么都不做** —— 宁可多留一层，也绝不把角标清成空白。
static void TCPBadgeHideSystemBackground(UIView *view) {
    if (view == nil || !sBadgeComposedServed || sBadgeHiding) return;
    if (![view isKindOfClass:[UIView class]]) return;
    sBadgeHiding = YES;
    sBadgeSysLook++;

    NSMutableArray<UIView *> *all = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:view.subviews];
    NSUInteger guard = 0;
    while (queue.count > 0 && guard++ < 24) {
        UIView *sub = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [all addObject:sub];
        if (sub.subviews.count > 0) [queue addObjectsFromArray:sub.subviews];
    }

    BOOL sawOurs = TCPBadgeLayerIsOurs(view.layer);
    UIView *ourHost = nil;   // 握着我们那张图的 image view
    for (UIView *sub in all) {
        if ([sub isKindOfClass:[UIImageView class]] &&
            TCPBadgeImageIsOurs(((UIImageView *)sub).image)) { sawOurs = YES; ourHost = sub; break; }
        if (TCPBadgeLayerIsOurs(sub.layer)) { sawOurs = YES; ourHost = sub; break; }
    }
    if (!sawOurs) {
        sBadgeSysWait++;   // 图还没换上来（或这一格没主题素材），先不动
        sBadgeHiding = NO;
        return;
    }

    // 底板候选：KVC 的 backgroundView，以及类名带 Darkening 的直接子视图。
    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    id bgView = nil;
    @try { bgView = [view valueForKey:@"backgroundView"]; } @catch (NSException *exception) { (void)exception; }
    if ([bgView isKindOfClass:[UIView class]]) [targets addObject:(UIView *)bgView];
    for (UIView *sub in view.subviews) {
        if (![sub isKindOfClass:[UIView class]]) continue;
        if ([NSStringFromClass([sub class]) containsString:@"Darkening"] && ![targets containsObject:sub]) {
            [targets addObject:sub];
        }
    }

    NSUInteger cleared = 0;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UIView *target in targets) {
        // 这层就是我们的图（或装着它）—— 一个字节都不许动
        if (target == ourHost || TCPBadgeLayerIsOurs(target.layer)) continue;
        BOOL touched = NO;
        UIColor *color = target.backgroundColor;
        if (color != nil && CGColorGetAlpha(color.CGColor) > 0.01) {
            target.backgroundColor = [UIColor clearColor];
            touched = YES;
        }
        if ([target isKindOfClass:[UIImageView class]]) {
            UIImage *image = ((UIImageView *)target).image;
            if (image != nil && !TCPBadgeImageIsOurs(image)) {
                ((UIImageView *)target).image = nil;
                touched = YES;
            }
        }
        CALayer *layer = target.layer;
        if (layer.backgroundColor != NULL && CGColorGetAlpha(layer.backgroundColor) > 0.01) {
            layer.backgroundColor = NULL;
            touched = YES;
        }
        // SBDarkeningImageView 的红底/暗化底是画在 layer.contents 里的：只清 backgroundColor 时
        // 它自己那张图还在，屏幕上就是「我们的角标 + 系统红底」两层（用户 2026-10-31 04:53
        // 「一个图标二层、一个图标一层」）。contents 不是我们的图就一并清掉。
        if (layer.contents != NULL && !TCPBadgeLayerIsOurs(layer)) {
            layer.contents = nil;
            touched = YES;
        }
        if (touched) cleared++;
        if (names.count < 6) {
            [names addObject:[NSString stringWithFormat:@"%@%@",
                              NSStringFromClass([target class]), touched ? @"*" : @""]];
        }
    }
    // 除「我们的图」这条祖先链之外，其余子视图一律藏起来。本机实测：只清颜色清不干净，
    // 系统自己还会画一层（用户 2026-10-31 04:53「一个图标二层、一个图标一层」，
    // 诊断 tree=SBDarkeningImageView 没有 * 就是那层根本没被清动）。
    NSMutableSet<UIView *> *keep = [NSMutableSet set];
    for (UIView *p = ourHost; p != nil && p != view; p = p.superview) [keep addObject:p];
    for (UIView *sub in view.subviews) {
        if (sub == ourHost || [keep containsObject:sub]) continue;
        if (TCPBadgeLayerIsOurs(sub.layer)) continue;
        if (!sub.hidden) {
            sub.hidden = YES;
            cleared++;
            if (names.count < 6) [names addObject:[NSString stringWithFormat:@"%@!", NSStringFromClass([sub class])]];
        }
    }

    // 系统角标本身也不许再画（用户 2026-10-31 05:10「先隐藏系统角标，再正常加载第三方素材」）：
    // 清掉它自己的底色与 layer.contents。我们的图是它的子视图，不受影响。
    if (!TCPBadgeLayerIsOurs(view.layer)) {
        if (view.layer.contents != NULL) { view.layer.contents = nil; cleared++; }
        if (view.layer.backgroundColor != NULL) { view.layer.backgroundColor = NULL; cleared++; }
        if (view.backgroundColor != nil) { view.backgroundColor = [UIColor clearColor]; cleared++; }
    }

    if (cleared > 0) sBadgeSysHidden += (NSInteger)cleared;

    // 取证：底板节点是谁、清没清掉（带 * = 清过，带 ! = 被藏），装完机不看屏幕也知道做对没有。
    sBadgeSysTree = names.count > 0 ? [names componentsJoinedByString:@","] : @"-";

    sBadgeHiding = NO;
}

void TCPBadgeResetStations(void) {
    sBadgeBackLook = sBadgeBackHit = 0;
    sBadgeTupleLook = sBadgeTupleHit = 0;
    sBadgeTextLook = sBadgeTextHit = 0;
    sBadgeComposedServed = NO;
}

// 成图站（Hooks.m）在「交出去的是底板 + 数字整图」时叫一声，视图侧才知道该收掉系统底板。
void TCPBadgeNoteComposedServed(void) {
    sBadgeComposedServed = YES;
}

void TCPBadgeNoteStation(TCPSiteKind kind, BOOL replaced) {
    switch (kind) {
        case TCPSiteKindBadgeBackground: sBadgeBackLook++; if (replaced) sBadgeBackHit++; break;
        case TCPSiteKindBadgeTuple:      sBadgeTupleLook++; if (replaced) sBadgeTupleHit++; break;
        case TCPSiteKindBadgeTextImage:  sBadgeTextLook++; if (replaced) sBadgeTextHit++; break;
        default: break;
    }
}

BOOL TCPBadgeBackgroundServed(void) {
    return (sBadgeBackHit + sBadgeTupleHit) > 0;
}

NSString *TCPBadgeProbeReport(void) {
    return [NSString stringWithFormat:
            @"%@;bg{look=%ld,hit=%ld};tup{look=%ld,hit=%ld};txt{look=%ld,hit=%ld};gate=%@;"
            @"sys{look=%ld,hid=%ld,wait=%ld,tree=%@};v{lay=%ld,cfg=%ld,mv=%ld,lo=%ld}",
            sBadgeProbe ?: @"badge=-",
            (long)sBadgeBackLook, (long)sBadgeBackHit,
            (long)sBadgeTupleLook, (long)sBadgeTupleHit,
            (long)sBadgeTextLook, (long)sBadgeTextHit,
            TCPBadgeBackgroundServed() ? @"text-only" : @"composed",
            (long)sBadgeSysLook, (long)sBadgeSysHidden, (long)sBadgeSysWait,
            sBadgeSysTree ?: @"-",
            (long)sBadgeLayoutCalls, (long)sBadgeConfigCalls, (long)sBadgeMoveCalls,
            (long)sBadgeLayCalls];
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
    TCPBadgeRememberImage(image);
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
    TCPBadgeRememberImage(image);
    return image;
}

// 数字单独一张、透明底（0.9.4）：底板站已经把主题底板换上去时，成图站只交数字，
// 屏幕上就只剩一层底板 —— 「二个图层」就是这么消掉的。
// 画布按系统给的盒子（底板那张也是同一个盒子），拿不到盒子才退回素材的自然宽度。
// 字号、颜色、自动缩放的规则与整图站完全同一套，两种走法出来的字一样大。
UIImage *TCPThemedBadgeTextOnlyImage(NSString *text, UIFont *font, CGFloat scale, CGSize systemBox) {
    if (text.length == 0) return nil;
    TCPThemeStore *store = [TCPThemeStore shared];
    UIImage *asset = TCPThemedBadgeBackground(scale);
    if (scale <= 0) scale = [UIScreen mainScreen].scale;
    if (scale <= 0) scale = 3.0;

    CGFloat side = systemBox.height > 0 ? systemBox.height : asset.size.height;
    if (side <= 0) return nil;
    CGFloat aspect = (asset.size.height > 0) ? asset.size.width / asset.size.height : 1.0;
    CGFloat naturalWidth = side * aspect;
    CGFloat width = systemBox.width > 0 ? systemBox.width : naturalWidth;

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

    NSDictionary<NSAttributedStringKey, id> *attributes = @{ NSFontAttributeName: drawFont,
                                                             NSForegroundColorAttributeName: color };
    CGSize textSize = [text sizeWithAttributes:attributes];
    CGFloat fitWidth = MAX(1.0, width * 0.84);
    CGFloat fitHeight = MAX(1.0, side * 0.78);
    CGFloat factor = 1.0;
    if (textSize.width > fitWidth) factor = MIN(factor, fitWidth / textSize.width);
    if (textSize.height > fitHeight) factor = MIN(factor, fitHeight / textSize.height);
    if (factor < 0.999) {
        drawFont = [drawFont fontWithSize:MAX(1.0, drawFont.pointSize * factor)];
        attributes = @{ NSFontAttributeName: drawFont, NSForegroundColorAttributeName: color };
        textSize = [text sizeWithAttributes:attributes];
    }
    if (width <= 0 || side <= 0) return nil;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, side), NO, scale);
    [text drawInRect:CGRectMake((width - textSize.width) / 2.0,
                                (side - textSize.height) / 2.0,
                                textSize.width, textSize.height)
      withAttributes:attributes];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    sBadgeProbe = [NSString stringWithFormat:@"badge=%@;asset=%.0fx%.0f;canvas=%.0fx%.0f;fit=%.2f;only=1",
                   text, asset.size.width, asset.size.height, width, side, factor];
    TCPBadgeRememberImage(image);
    return image;
}

// —— 0.9.11 视图侧：把系统自己画的那层底板藏掉 ——
// 成图站是**类方法**（诊断里写作 +SBIconBadgeView:_checkoutImageForText:font:highlighted:），
// self 是类对象，碰不到视图，所以「藏底板」只能挂在视图自己的回调上。
// 三处入口都挂，哪个先来用哪个：-layoutSubviews（布局）、
// -_configureAnimatedForText:highlighted:animator:（配置数字）、-didMoveToWindow（上屏）。
// 铁律 R2：只有类「自己声明」了才挂 —— layoutSubviews / didMoveToWindow 是 UIView 的实现，
// 直接 MSHook 到父类那一份会把全系统的视图都拖进来。
static IMP sBadgeLayoutOrig = NULL;
static IMP sBadgeConfigOrig = NULL;
static IMP sBadgeMoveOrig = NULL;
static IMP sBadgeLayOrig = NULL;

static void TCPBadgeLayoutHook(id self, SEL _cmd) {
    if (sBadgeLayoutOrig) ((void (*)(id, SEL))sBadgeLayoutOrig)(self, _cmd);
    sBadgeLayoutCalls++;
    TCPBadgeHideSystemBackground(self);
}

static void TCPBadgeConfigHook(id self, SEL _cmd, NSString *text, BOOL highlighted, id animator) {
    if (sBadgeConfigOrig) {
        ((void (*)(id, SEL, NSString *, BOOL, id))sBadgeConfigOrig)(self, _cmd, text, highlighted, animator);
    }
    sBadgeConfigCalls++;
    TCPBadgeHideSystemBackground(self);
}

// -_layOutTextImageView: —— 系统摆数字图的那一下，也是它可能重新涂底板底色的地方。
static void TCPBadgeLayHook(id self, SEL _cmd, id arg) {
    if (sBadgeLayOrig) ((void (*)(id, SEL, id))sBadgeLayOrig)(self, _cmd, arg);
    sBadgeLayCalls++;
    TCPBadgeHideSystemBackground(self);
}

static void TCPBadgeMoveHook(id self, SEL _cmd) {
    if (sBadgeMoveOrig) ((void (*)(id, SEL))sBadgeMoveOrig)(self, _cmd);
    sBadgeMoveCalls++;
    TCPBadgeHideSystemBackground(self);
}

static void TCPInstallBadgeViewSites(void) {
    Class cls = objc_getClass("SBIconBadgeView");
    if (cls == Nil) return;
    SEL layout = NSSelectorFromString(@"layoutSubviews");
    if (sBadgeLayoutOrig == NULL && TCPClassDeclaresMethod(cls, layout)) {
        MSHookMessageEx(cls, layout, (IMP)TCPBadgeLayoutHook, (IMP *)&sBadgeLayoutOrig);
    }
    SEL config = NSSelectorFromString(@"_configureAnimatedForText:highlighted:animator:");
    if (sBadgeConfigOrig == NULL && TCPClassDeclaresMethod(cls, config)) {
        MSHookMessageEx(cls, config, (IMP)TCPBadgeConfigHook, (IMP *)&sBadgeConfigOrig);
    }
    SEL lay = NSSelectorFromString(@"_layOutTextImageView:");
    if (sBadgeLayOrig == NULL && TCPClassDeclaresMethod(cls, lay)) {
        MSHookMessageEx(cls, lay, (IMP)TCPBadgeLayHook, (IMP *)&sBadgeLayOrig);
    }
    SEL move = NSSelectorFromString(@"didMoveToWindow");
    if (sBadgeMoveOrig == NULL && TCPClassDeclaresMethod(cls, move)) {
        MSHookMessageEx(cls, move, (IMP)TCPBadgeMoveHook, (IMP *)&sBadgeMoveOrig);
    }
}

void TCPInstallBadgeSites(void) {
    NSArray<NSString *> *badgeClasses = @[ @"SBIconBadge" ];
    NSArray<NSString *> *badgeSelectors = @[ @"_checkoutBackgroundImage",
                                             @"_checkoutBackgroundImageTuple",
                                             @"_checkoutImageForText:font:highlighted:" ];
    TCPInstallSitesForClassPrefixes(badgeClasses, nil, @[ @"_checkoutBackgroundImage" ],
                                    TCPSiteKindBadgeBackground);
    TCPInstallSitesForClassPrefixes(@[ @"SBHIconAccessory" ], nil, @[ @"_checkoutBackgroundImage" ],
                                    TCPSiteKindBadgeBackground);
    TCPInstallSitesForClassPrefixes(badgeClasses, nil, @[ @"_checkoutBackgroundImageTuple" ],
                                    TCPSiteKindBadgeTuple);
    TCPInstallSitesForClassPrefixes(badgeClasses, nil, @[ @"_checkoutImageForText:font:highlighted:" ],
                                    TCPSiteKindBadgeTextImage);

    // 用户 2026-10-30 15:13 的要求：**「角标」开着时，锁屏通知上的角标也要跟着主题走**
    // （桌面与锁屏通知同时生效，默认就生效，面板里不写这几个字）。
    //
    // 锁屏通知那套视图不是 SBIconBadge* 家族的类（通知列表在 SpringBoard 里自成一系），
    // 名字又不固定，所以这里按「类名含 Badge」兜：**只要这个类自己声明了角标站**，就挂上；
    // 不是角标类（没声明这些方法）根本挂不上，挂上了也只在主题真有角标素材时才动图。
    // 挂到的类名写进诊断（ThemeCorePlusBadgeCensus），设备上能直接看是哪几个类在干活。
    NSArray<NSString *> *excluding = @[ @"Accessibility" ];
    for (NSString *selectorName in badgeSelectors) {
        TCPSiteKind kind = TCPSiteKindBadgeBackground;
        if ([selectorName isEqualToString:@"_checkoutBackgroundImageTuple"]) {
            kind = TCPSiteKindBadgeTuple;
        } else if ([selectorName hasPrefix:@"_checkoutImageForText"]) {
            kind = TCPSiteKindBadgeTextImage;
        }
        TCPInstallSitesForClassSubstrings(@[ @"Badge" ], excluding, @[ selectorName ], kind);
    }

    // 0.9.11：单层化的视图侧入口（见上面 TCPInstallBadgeViewSites 的注释）。
    TCPInstallBadgeViewSites();
}
