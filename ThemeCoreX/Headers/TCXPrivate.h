#pragma once

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// AppIcon —— 全新架构（0.0.1）
//
// 架构来源：ThemeCore 0.5.1（SuSuDear）的注入模型，逆向结论：
//   Filter = Bundles:[com.apple.UIKit] + Executables:[iconservicesagent,ShareUI,sharingd] + Mode:Any
//   → "或"语义：进程加载了 UIKit（SpringBoard 本身也算）或可执行文件名命中，即注入。
//   链接面：UIKit / QuartzCore / ImageIO / CoreGraphics + IconFoundation + IconServices，
//   不链接 SpringBoardServices —— SBIcon* 一律运行时 objc_getClass 弱取，拿不到就跳过。
//
// 本文件只放私有声明：结构体、弱获取的类接口。所有类都不在编译期被引用。

// SpringBoardHome / SpringBoard 私有结构体（iOS 13-16 一致）
typedef struct {
    CGSize size;
    CGFloat scale;
    CGFloat variant;
} TCXIconImageInfo;

// ── 图标 ────────────────────────────────────────────────
@interface SBApplicationIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBLeafIcon : NSObject
- (NSString *)leafIdentifier;
@end

// ── 角标 ────────────────────────────────────────────────
// iOS 16 的角标视图：底板/文字图都是「结账式」取图，挂这四个站即可换外观。
@interface SBIconBadgeView : UIView
+ (id)_checkoutBackgroundImage;
+ (id)_checkoutImageForText:(NSString *)text font:(UIFont *)font highlighted:(BOOL)highlighted;
+ (id)_checkoutImageForText:(NSString *)text highlighted:(BOOL)highlighted;
@end

@interface SBIconAccessoryImage : UIImage
- (instancetype)initWithImage:(UIImage *)image;
@end

@interface SBHIconAccessoryCountedMapImageTuple : NSObject
- (instancetype)initWithImage:(UIImage *)image countedMapKey:(NSString *)countedMapKey;
@end

// ── 图标视图（阴影层挂这里）────────────────────────────
@interface SBIconImageView : UIView
- (void)setImage:(UIImage *)image;
- (void)updateImageAnimated:(BOOL)animated;
- (UIImage *)contentsImage;
@end

@interface SBIconView : UIView
@end

// ── 时钟 ────────────────────────────────────────────────
@interface SBClockApplicationIconImageView : UIView
- (void)updateAnimatingState;
- (BOOL)isAnimationAllowed;
- (UIImage *)contentsImage;
@end

// ── 圆角遮罩（UIKit 私有；没有就退回公开 API）─────────
@interface UIBezierPath (TCXPrivate)
+ (UIBezierPath *)bezierPathWithRoundedRect:(CGRect)rect
                         byRoundingCorners:(UIRectCorner)corners
                             cornerInsets:(UIEdgeInsets)insets;
@end

// 弱获取：不存在就返回 Nil，绝不 NSLog 报错、绝不崩。
static inline Class TCXClass(NSString *name) {
    return objc_getClass([name UTF8String]);
}

// 类是否「自己声明」了这个选择器（不是从父类继承来的）。
// 「一站一槽」铁律的前提：只有声明者才挂，并配一个属于它的原实现槽，
// 否则父子类共用一个槽会互相覆盖（历史上就栽在这）。
static inline BOOL TCXClassDeclaresSelector(Class cls, SEL selector) {
    if (!cls || !selector) return NO;
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(list[i]) == selector) { found = YES; break; }
    }
    if (list) free(list);
    return found;
}