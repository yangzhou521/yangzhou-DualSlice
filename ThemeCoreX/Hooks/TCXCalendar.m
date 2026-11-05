#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "TCXPrivate.h"
#import "TCXStore.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"

// 日历图标 —— 动态文字层。
//
// 架构对照 ThemeCore 0.5.1（证据：ThemeCore.dylib 的字符串全集）：
//   它读主题 Info.plist 的两个键
//     CalendarIconDateSettings  → 日期数字（日）
//     CalendarIconDaySettings   → 星期
//   每个字典的字段（证据里逐字出现）：
//     FontSize / TextXoffset / TextYoffset / TextColor / FontName / FontWeight
//   FontWeight 的取值表也完全对上（证据里连着出现）：
//     ultralight thin light medium semibold demibold bold heavy black
//   星期格式串用的是 "EEEE"（证据里就有这一个格式串）。
//   缓存键形状 "static:%@|%.3f"（模板名|尺度的静态图）。
//
// 与 ThemeCore 的不同（如实记下来，别当一样）：
//   ① ThemeCore 把绘制做在 SBHCalendarApplicationIcon / SBCalendarApplicationIcon 的
//      iconImageWithInfo: 里；我们统一放在「出图之后」这一层（TCXIcons.m 的生图站与
//      呈现站都调用本文件的 TCXCalendarOverlay），因为我们的出图路径有四条，
//      分头改四处会漂。视觉效果相同，改图只改一处。
//   ② 字号单位 ThemeCore 未取证：本文件把 FontSize ≤ 2.0 当「占图标宽度的比例」，
//      大于 2.0 当「以 60pt 图标为基准的点数」，两种都能容。
//
// 主题没给这两个键 → 完全不画（主题没声明字体信息时自绘只能是瞎猜，宁可不动图）。

extern void TCXCountIconHit(NSString *bundleID);
extern void TCXNoteSite(NSString *site);

static NSCache<NSString *, UIImage *> *sCalendarCache = nil;

#pragma mark - 设置解析

// FontWeight 名 → UIFontWeight（取值表与 ThemeCore 证据逐项对应）。
static CGFloat TCXCalendarFontWeight(NSString *name) {
    if (![name isKindOfClass:[NSString class]]) return -1.0;
    NSString *key = name.lowercaseString;
    if ([key isEqualToString:@"ultralight"]) return UIFontWeightUltraLight;
    if ([key isEqualToString:@"thin"])       return UIFontWeightThin;
    if ([key isEqualToString:@"light"])      return UIFontWeightLight;
    if ([key isEqualToString:@"medium"])     return UIFontWeightMedium;
    if ([key isEqualToString:@"semibold"] ||
        [key isEqualToString:@"demibold"])   return UIFontWeightSemibold;  // 主题里两种拼写都见过
    if ([key isEqualToString:@"bold"])       return UIFontWeightBold;
    if ([key isEqualToString:@"heavy"])      return UIFontWeightHeavy;
    if ([key isEqualToString:@"black"])      return UIFontWeightBlack;
    if ([key isEqualToString:@"regular"])    return UIFontWeightRegular;
    return -1.0;
}

// TextColor 容三种写法：#RRGGBB / "r,g,b" / 0xRRGGBB 数字。
static UIColor *TCXCalendarColor(id value) {
    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *parts = value;
        if (parts.count >= 3) {
            return [UIColor colorWithRed:[parts[0] doubleValue]
                                   green:[parts[1] doubleValue]
                                    blue:[parts[2] doubleValue]
                                   alpha:parts.count > 3 ? [parts[3] doubleValue] : 1.0];
        }
        return nil;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        unsigned long long raw = [value unsignedLongLongValue];
        return [UIColor colorWithRed:((raw >> 16) & 0xFF) / 255.0
                               green:((raw >> 8) & 0xFF) / 255.0
                                blue:(raw & 0xFF) / 255.0
                               alpha:1.0];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([text hasPrefix:@"#"]) text = [text substringFromIndex:1];
        if ([text rangeOfString:@","].location != NSNotFound) {
            NSArray *parts = [text componentsSeparatedByString:@","];
            if (parts.count >= 3) {
                return [UIColor colorWithRed:[parts[0] doubleValue]
                                       green:[parts[1] doubleValue]
                                        blue:[parts[2] doubleValue]
                                       alpha:parts.count > 3 ? [parts[3] doubleValue] : 1.0];
            }
            return nil;
        }
        unsigned int raw = 0;
        NSScanner *scanner = [NSScanner scannerWithString:text];
        if ([scanner scanHexInt:&raw] && text.length >= 6) {
            return [UIColor colorWithRed:((raw >> 16) & 0xFF) / 255.0
                                   green:((raw >> 8) & 0xFF) / 255.0
                                    blue:(raw & 0xFF) / 255.0
                                   alpha:1.0];
        }
    }
    return nil;
}

// FontSize 的单位：实测两个主题都把它当「以 60pt 图标为基准的点数」：
//   Smartisan  Date=32 / Day=8    液态玻璃  Date=35 / Day=9.5
// 60pt 图标里 32pt 的日号、8pt 的星期，正好是 iOS 日历图标的比例。所以按
// size.width/60 缩放，不做「小于 2 当比例」那种猜测。
static CGFloat TCXCalendarFontSize(NSDictionary *settings, CGFloat iconWidth, CGFloat fallback) {
    double raw = [settings[@"FontSize"] doubleValue];
    CGFloat base = raw > 0.0 ? (CGFloat)raw : fallback;
    return base * (iconWidth / 60.0);
}

static UIFont *TCXCalendarFont(NSDictionary *settings, CGFloat iconWidth, CGFloat fallback) {
    CGFloat pointSize = TCXCalendarFontSize(settings, iconWidth, fallback);
    NSString *name = [settings[@"FontName"] isKindOfClass:[NSString class]] ? settings[@"FontName"] : nil;
    CGFloat weight = TCXCalendarFontWeight(settings[@"FontWeight"]);

    if (name.length) {
        UIFont *font = [UIFont fontWithName:name size:pointSize];
        if (font) return font;      // 例如 液态玻璃 的 "SF-Compact"；取不到就往下走系统字
    }
    if (weight >= 0.0) {
        return [UIFont systemFontOfSize:pointSize weight:weight];
    }
    return [UIFont systemFontOfSize:pointSize weight:UIFontWeightSemibold];
}

// TextXoffset / TextYoffset 也是「60pt 基准的点数」（实测 2 / 4 / -2 这种量级）。
static CGPoint TCXCalendarOffset(NSDictionary *settings, CGFloat iconWidth) {
    CGFloat k = iconWidth / 60.0;
    return CGPointMake([settings[@"TextXoffset"] doubleValue] * k,
                       [settings[@"TextYoffset"] doubleValue] * k);
}

// 文字阴影：ShadowColor / ShadowBlurRadius / ShadowXoffset / ShadowYoffset
// （四个键在实测主题里成组出现，ThemeCore 的证据串里也有它们）。
static NSShadow *TCXCalendarShadow(NSDictionary *settings, CGFloat iconWidth) {
    id colorValue = settings[@"ShadowColor"];
    if (!colorValue) return nil;
    UIColor *color = TCXCalendarColor(colorValue);
    if (!color) return nil;
    CGFloat k = iconWidth / 60.0;
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = color;
    shadow.shadowBlurRadius = [settings[@"ShadowBlurRadius"] doubleValue] * k;
    shadow.shadowOffset = CGSizeMake([settings[@"ShadowXoffset"] doubleValue] * k,
                                     [settings[@"ShadowYoffset"] doubleValue] * k);
    return shadow;
}

#pragma mark - 绘制

// 画一行字：center 是这一行的中心点（已含 offset），垂直居中。
static void TCXCalendarDrawText(NSString *text, UIFont *font, UIColor *color,
                                NSShadow *shadow, CGPoint center) {
    if (!text.length || !font) return;
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    attributes[NSFontAttributeName] = font;
    attributes[NSForegroundColorAttributeName] = color ?: [UIColor whiteColor];
    attributes[NSParagraphStyleAttributeName] = style;
    if (shadow) attributes[NSShadowAttributeName] = shadow;
    CGSize measured = [text sizeWithAttributes:attributes];
    CGRect rect = CGRectMake(center.x - measured.width / 2.0,
                             center.y - measured.height / 2.0,
                             measured.width, measured.height);
    [text drawInRect:rect withAttributes:attributes];
}

// 把「星期 + 日」叠到已经出好的日历图标上。
// size / scale 用调用方给的目标尺寸（与图标格一致），图本身也按这个尺寸出。
UIImage *TCXCalendarOverlay(UIImage *image, NSString *bundleID, CGSize size, CGFloat scale) {
    if (!image || !bundleID.length) return image;
    if (![bundleID isEqualToString:@"com.apple.mobilecal"]) return image;
    if (!TCXPrefBool(@"Enabled", YES)) return image;
    if (!TCXPrefBool(@"CalendarEnabled", YES)) return image;
    if (size.width < 8.0 || size.height < 8.0) return image;

    @try {
        TCXStore *store = [TCXStore shared];
        [store reloadIfNeeded];
        NSDictionary *dateSettings = [store calendarDateSettings];
        NSDictionary *daySettings = [store calendarDaySettings];
        if (!dateSettings && !daySettings) return image;   // 主题没声明 → 一动不如一静

        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDate *now = [NSDate date];
        NSInteger day = [calendar component:NSCalendarUnitDay fromDate:now];

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"EEEE";                    // 与 ThemeCore 证据一致
        NSString *weekday = [formatter stringFromDate:now];

        if (!sCalendarCache) {
            sCalendarCache = [[NSCache alloc] init];
            sCalendarCache.countLimit = 16;
        }
        NSString *key = [NSString stringWithFormat:@"cal|%@|%.0fx%.0f|%ld|%@",
                         store.themeName ?: @"none", size.width, size.height,
                         (long)day, weekday ?: @""];
        UIImage *cached = [sCalendarCache objectForKey:key];
        if (cached) return cached;

        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = scale > 0 ? scale : (image.scale > 0 ? image.scale : 2.0);
        format.opaque = NO;
        UIGraphicsImageRenderer *renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];

        UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [image drawInRect:CGRectMake(0, 0, size.width, size.height)];

            // 没有 offset 时的落点：星期在上、日期在下（与 iOS 日历图标同排版）。
            if (daySettings) {
                UIFont *font = TCXCalendarFont(daySettings, size.width, 8.0);
                UIColor *color = TCXCalendarColor(daySettings[@"TextColor"]) ?: [UIColor whiteColor];
                NSShadow *shadow = TCXCalendarShadow(daySettings, size.width);
                CGPoint offset = TCXCalendarOffset(daySettings, size.width);
                TCXCalendarDrawText(weekday, font, color, shadow,
                                    CGPointMake(size.width / 2.0 + offset.x,
                                                size.height * 0.24 + offset.y));
            }
            if (dateSettings) {
                UIFont *font = TCXCalendarFont(dateSettings, size.width, 32.0);
                UIColor *color = TCXCalendarColor(dateSettings[@"TextColor"]) ?: [UIColor whiteColor];
                NSShadow *shadow = TCXCalendarShadow(dateSettings, size.width);
                CGPoint offset = TCXCalendarOffset(dateSettings, size.width);
                TCXCalendarDrawText([NSString stringWithFormat:@"%ld", (long)day], font, color, shadow,
                                    CGPointMake(size.width / 2.0 + offset.x,
                                                size.height * 0.52 + offset.y));
            }
        }];

        if (result) {
            [sCalendarCache setObject:result forKey:key];
        }
        return result ?: image;
    } @catch (NSException *exception) {
        return image;   // 画砸了就退回原图，绝不让日历变成空白
    }
}

// 主题换了要丢掉旧画（否则换主题后仍显示上一套字体/颜色）。
void TCXCalendarInvalidate(void) {
    [sCalendarCache removeAllObjects];
}

// 挂站：**不挂**。
//
// ThemeCore 0.5.1 证据里 SBHCalendarApplicationIcon / SBCalendarApplicationIcon 上出现过
// updateImageAnimated: / updateClockImages / imageSetForMetrics: 等选择器，但它们的
// 接收者是 icon 模型对象还是视图、带不带别的参数，字符串全集里定不下来 —— 猜签名挂上去
// 会拿到错参数（丢参数、读错结构体），那是把 SpringBoard 弄进安全模式最经典的一种。
//
// 所以这里走我们自己的统一落点：出图之后叠一层（TCXIcons.m 的两条出图路径都调
// TCXCalendarOverlay）。系统每天自己重画日历图标时会重新出图，我们自然跟着叠新的一天。
// 视觉结果与 ThemeCore 相同，风险低一个量级。此事已写进 docs/cases/ 的对照表。

