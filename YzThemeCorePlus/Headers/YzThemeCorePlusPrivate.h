#pragma once

#import <UIKit/UIKit.h>

// SpringBoard / SpringBoardHome private interfaces confirmed against
// iOS 13-26 runtime headers; the SBIconBadgeView accessors match the
// hook surfaces used by Anemone-OSS (Badges.xm) and NeonBoard (Badges.x).
typedef struct {
    CGSize size;
    CGFloat scale;
    CGFloat variant;
} SBIconImageInfo;

@interface SBIconBadgeView : UIView
+ (id)_checkoutBackgroundImage;
+ (id)_checkoutImageForText:(NSString *)text font:(UIFont *)font highlighted:(BOOL)highlighted;
+ (id)_checkoutImageForText:(NSString *)text highlighted:(BOOL)highlighted;
@end

@interface SBIconAccessoryImage : UIImage
- (instancetype)initWithImage:(UIImage *)image;
@end

// iOS 16 (kCFCoreFoundationVersionNumber >= 1740) accessory image cache entry.
@interface SBHIconAccessoryCountedMapImageTuple : NSObject
- (instancetype)initWithImage:(UIImage *)image countedMapKey:(NSString *)countedMapKey;
@end

@interface SBApplicationIcon : NSObject
- (NSString *)applicationBundleID;
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
- (void)relayoutIcons;
@end

// 时钟图标视图（iOS 14-16 类名，注意：无 "H" 前缀；iOS 17 才改名 SBHClockApplicationIconImageView）
// 走时靠 CALayer 指针 _hours/_minutes/_seconds/_redDot/_blackDot（Anemone/NeonBoard 已验证）
@interface SBClockApplicationIconImageView : UIView
- (void)updateAnimatingState;
- (BOOL)isAnimationAllowed;
- (UIImage *)contentsImage;
@end

// 文件夹图标：mini 拼图每格入口在图标类上（不在 SBFolderIconImageCache）
@interface SBFolderIcon : NSObject
- (id)miniGridCellImageForIcon:(id)icon;
@end
