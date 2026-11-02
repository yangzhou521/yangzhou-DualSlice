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

// —— 图片工作量闸门（1.0.35）——
// dyld 构造函数阶段（任何 main() 之前）读图会命中 +[UIScreen mainScreen] 的断言 → SIGABRT
// （2026-11-02 00:24 SpringBoard 连崩两次进安全模式就是这条）。所以：
//   · TCPStoreImageWorkReady()      是否已经可以读图（构造函数阶段返回 NO）
//   · TCPStoreEnableImageWork()     构造函数里先排好、进程起来之后（+2 秒，主队列）调它开闸，
//                                   顺带补做被推迟的遮罩体检与图标预热。幂等。
BOOL TCPStoreImageWorkReady(void);
void TCPStoreEnableImageWork(void);
// 闸门打开时补做推迟工作的内部方法（实现细节，外部不用调）。
- (void)performDeferredImageWork;
// 1.0.38：清掉系统图标图缓存（SBIconController→iconManager→iconImageCache 上那些
// purge / clear 无参方法）。必须在开闸之后、刷新视图之前调，否则重画又会把原图贴回来。
- (void)purgeSystemIconCache;

// —— 生效状态（诊断用）——
@property (atomic, readonly) BOOL active;             // 是否挂上了主题（没挂 = 系统原生外观）
// themeName 是**所有生效主题**的名字用 " + " 连起来（按叠加顺序），单个主题时就是它自己。
@property (atomic, copy, readonly) NSString *themeName;
// themePath 是**最上层**那个主题（数组最后一个）；themePaths 是完整的叠加链，靠后的优先。
@property (atomic, copy, readonly) NSString *themePath;
@property (atomic, copy, readonly) NSArray<NSString *> *themePaths;
// 1.0.38：清系统图标缓存的打点（诊断里 purgeName 看出走没走到、用了哪个方法名）。
@property (atomic, copy) NSString *purgeName;
@property (atomic) NSUInteger purgeCount;
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
// 这个 CGImage 是不是本插件合成的（屏幕上 layer.contents 里放的就是 CGImage）。
- (BOOL)isRenderedCGImage:(CGImageRef)cg;
// 同一个判断，按裸指针来（layer.contents 在视图树里是 id，直接比指针即可）。
- (BOOL)isRenderedCGImagePointer:(const void *)ptr;

// —— 查询：角标 / 文件夹底板 / 任意点名素材 ——
- (UIImage *)badgeBackgroundImageForScale:(CGFloat)scale;
- (UIImage *)folderBackgroundImageForScale:(CGFloat)scale;
// 按规范名找（不带 @2x/@3x 的裸名，例如 SBBadgeBG、ANEMFolderIconBG、AppIconMask）。
- (UIImage *)imageForNamedAsset:(NSString *)name scale:(CGFloat)scale;

// —— 查询：文件覆盖 ——
// bundleID 为空时只查全局表。
- (NSString *)overridePathForBundleID:(NSString *)bundleID fileName:(NSString *)fileName;

// —— 面板用：一个主题自己带了哪几类素材 ——
// 键就是下面这四个常量，值都是 NSNumber 计数（件数，不是 App 个数；0 = 这类素材是空的）。
// 只做浅扫：不建索引、不读图、不合成，也不缓存。
extern NSString * const TCPMaterialIcons;    // IconBundles/ / icons/ / Bundles/<bundleid>/icon*
extern NSString * const TCPMaterialFolders;  // 文件夹底板（ANEMFolderIconBG / FolderIconBG…）
extern NSString * const TCPMaterialBadges;   // 角标底图（SBBadgeBG…）
extern NSString * const TCPMaterialFiles;    // 其余覆盖素材（状态栏 / 拨号盘 / 设置 / 分享…）
- (NSDictionary<NSString *, NSNumber *> *)materialSummaryForThemePath:(NSString *)theme;

// —— 诊断 ——
- (NSArray<NSString *> *)availableThemePaths;
- (NSString *)diagnostics;

@end
