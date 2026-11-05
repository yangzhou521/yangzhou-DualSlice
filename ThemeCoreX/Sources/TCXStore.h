#pragma once

#import <UIKit/UIKit.h>

// 主题库：一次扫描、O(1) 查表。
// 目录扫描只发生在 reload（进程启动 / 偏好里的主题名变了），绝不在 hook 里扫盘。
//
// 素材根唯一：<jbroot>/Library/Themes（见 TCXPaths.h 第三条铁律）。
// 主题内部布局按 ThemeCore 0.5.1 认可的几种（用户主题「液态玻璃.theme」实测就是这个形状）：
//   图标   <主题>/IconBundles/<bundle id>[-large][@2x|@3x].png
//          <主题>/Icons|icons/<bundle id>.png
//          <主题>/Bundles/<bundle id>/<资源名>@2x.png
//   阴影   <主题>/Bundles/AnemoneEffects/iPhoneShadow@3x.png
//          <主题>/AnemoneEffects|Iconomatic|Effects/<含 Shadow 的 png>
//   时钟   <主题>/Bundles/com.apple.springboard/ClockIcon{BackgroundSquare,HourHand,MinuteHand,RedDot}@3x.png
//   配置   <主题>/Info.plist（CalendarIconDateSettings / CalendarIconDaySettings / IB-MaskIcons）
@interface TCXStore : NSObject

+ (instancetype)shared;

@property (atomic, readonly) NSString *themeName;
@property (atomic, readonly) NSString *themePath;
// 主题叠加层（ThemeCore 0.5.1 的 layers）：按顺序找，前一层没有的素材去后一层拿。
// 你的主题往往是「一个给图标、一个给角标」，单选任一个都会缺图。
@property (atomic, readonly) NSArray<NSString *> *themePaths;
@property (atomic, readonly) NSUInteger layerCount;
@property (atomic, readonly) NSUInteger generation;
// 该主题里 IconBundles/Icons/icons 下有多个图标文件（面板与诊断用）。
@property (atomic, readonly) NSUInteger iconCount;
// 主题 Info.plist（读不到返回 nil）。
@property (atomic, readonly) NSDictionary *themeInfo;
// 主题声明了 IB-MaskIcons（图标需要圆角遮罩）。
@property (atomic, readonly) BOOL maskIcons;

- (void)reload;
- (void)reloadIfNeeded;

// 该 bundle id 在主题里有没有图标（按 scale 选档位）。
- (BOOL)hasIconForBundleID:(NSString *)bundleID scale:(CGFloat)scale;

// 取该图标的可显示版本：加载 → 圆角裁切 → 缩放到 size。
- (UIImage *)imageForBundleID:(NSString *)bundleID size:(CGSize)size scale:(CGFloat)scale;

// 主题里的 springboard 资源（时钟表盘/指针/角标底板等）。
- (UIImage *)springboardImageNamed:(NSString *)name scale:(CGFloat)scale;

// 主题里的某一 bundle 目录下的资源。
- (UIImage *)imageNamed:(NSString *)name inBundle:(NSString *)bundleID scale:(CGFloat)scale;

// 阴影素材（AnemoneEffects / Iconomatic / Effects 里名字含 Shadow 的那张）。
- (UIImage *)shadowImage;

// 日历文字设置。ThemeCore 0.5.1 的证据里读的就是这两个键：
//   Info.plist → CalendarIconDateSettings（日期数字）/ CalendarIconDaySettings（星期）
//   每个字典里的字段：FontSize / TextXoffset / TextYoffset / TextColor / FontName / FontWeight
// 两个键都没有 → 返回 nil，调用方就不该自绘（主题没给字体信息，自绘只能是瞎猜）。
- (NSDictionary *)calendarDateSettings;
- (NSDictionary *)calendarDaySettings;

@end