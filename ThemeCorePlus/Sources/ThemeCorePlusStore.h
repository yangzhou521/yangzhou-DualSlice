//
//  ThemeCorePlusStore.h —— 主题素材索引（图标 / 文件覆盖 / 角标 / 文件夹底板 / 遮罩 / overlay）。
//
//  阶段一直接在注入进程里读**主题原素材**并合成；阶段二起改由管理器 App 预先编译成
//  不可变成品，这里只换成读成品，对外接口不变。
//
//  扫描一次、查表无数次：所有方法都只做字典查找和缓存命中，绝不在钩子里读磁盘目录。
//
#pragma once

#import <UIKit/UIKit.h>

@interface TCPThemeStore : NSObject

+ (instancetype)shared;

// 重新扫盘（读偏好、解析主题链、建索引）。任何线程可用；挂在通知回调与首次使用时。
- (void)reload;

// —— 生效状态（诊断用）——
@property (atomic, readonly) BOOL active;             // 是否挂上了主题（没挂 = 系统原生外观）
// themeName 是**所有生效主题**的名字用 " + " 连起来（按叠加顺序），单个主题时就是它自己。
@property (atomic, copy, readonly) NSString *themeName;
// themePath 是**最上层**那个主题（数组最后一个）；themePaths 是完整的叠加链，靠后的优先。
@property (atomic, copy, readonly) NSString *themePath;
@property (atomic, copy, readonly) NSArray<NSString *> *themePaths;
@property (atomic, readonly) NSUInteger generation;   // 每次 reload +1，缓存键里带它

// —— 功能独立开关（各自默认开）——
- (BOOL)iconsEnabled;
- (BOOL)foldersEnabled;
- (BOOL)badgesEnabled;
- (BOOL)filesEnabled;
// 没有作者遮罩素材时的兜底圆角（IconCornerMask，默认关）。
- (BOOL)cornerMaskEnabled;
// 角标文字样式（可空：主色 / PostScript 字体名 / 字号）。
- (UIColor *)badgeTextColor;
- (NSString *)badgeFontName;
- (CGFloat)badgeFontSize;

// —— 查询：图标 ——
// 已按「底图 → 遮罩裁剪 → 图标 → overlay」合成；没有素材返回 nil（调用方原样返回系统图）。
// size 是点，scale 是屏倍率。
- (UIImage *)iconImageForBundleID:(NSString *)bundleID
                             size:(CGSize)size
                            scale:(CGFloat)scale
                     cornerRadius:(CGFloat)cornerRadius;
- (NSString *)iconPathForBundleID:(NSString *)bundleID scale:(CGFloat)scale;
// 这张图是不是本插件合成的（供视图级兜底钩子避免二次套用）。
- (BOOL)isRenderedImage:(UIImage *)image;

// —— 查询：角标 / 文件夹底板 / 任意点名素材 ——
- (UIImage *)badgeBackgroundImageForScale:(CGFloat)scale;
- (UIImage *)folderBackgroundImageForScale:(CGFloat)scale;
// 按规范名找（不带 @2x/@3x 的裸名，例如 SBBadgeBG、ANEMFolderIconBG、AppIconMask）。
- (UIImage *)imageForNamedAsset:(NSString *)name scale:(CGFloat)scale;

// —— 查询：文件覆盖 ——
// bundleID 为空时只查全局表。
- (NSString *)overridePathForBundleID:(NSString *)bundleID fileName:(NSString *)fileName;

// —— 诊断 ——
- (NSArray<NSString *> *)availableThemePaths;
- (NSString *)diagnostics;

@end
