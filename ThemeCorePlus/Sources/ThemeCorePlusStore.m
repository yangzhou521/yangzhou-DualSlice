//
//  ThemeCorePlusStore.m —— 素材库实现。
//
//  扫描一次、查表无数次：钩子里只做字典查找和一次缓存命中，绝不在钩子里读磁盘目录。
//
//  三张表：
//   · iconMap     bundleID → 倍率键 → 图标素材（IconBundles / icons / Bundles/<bundleid>/icon*）
//   · namedMap    规范名 → 倍率键 → 任意点名素材（SBBadgeBG、ANEMFolderIconBG、AppIconMask…）
//   · fileMap     文件名 → 路径（全局 + 按 bundle 分桶），系统图片覆盖用
//
#import "ThemeCorePlusStore.h"
#import "ThemeCorePlusConfig.h"
#import "ThemeCorePlusKeys.h"
#import "ThemeCorePlusPaths.h"
#import "ThemeCorePlusVersion.h"

#import <math.h>

#pragma mark - 文件名解析

// 只认图片扩展名：别的文件进索引只会白占内存。
static BOOL TCPIsImageFile(NSString *fileName) {
    NSString *ext = fileName.pathExtension.lowercaseString;
    return [ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"];
}

// 剥掉结尾的 @2x/@3x（返回倍率，0 = 没写），返回值按引用给出。
static NSString *TCPStripScaleSuffix(NSString *name, NSInteger *outScale) {
    NSInteger scale = 0;
    NSString *stem = name;
    NSString *lower = stem.lowercaseString;
    for (NSInteger s = 3; s >= 1; s--) {
        NSString *tag = [NSString stringWithFormat:@"@%ldx", (long)s];
        if ([lower hasSuffix:tag]) {
            stem = [stem substringToIndex:stem.length - tag.length];
            scale = s;
            break;
        }
    }
    if (outScale) *outScale = scale;
    return stem;
}

// SnowBoard / IconBundles 约定：<bundleid>[-large][@2x|@3x][~iphone].png
// 解析成功时把 bundle id、倍率、是否 large 写回；失败返回 NO（不是图标素材）。
static BOOL TCPParseIconFileName(NSString *fileName, NSString **outID, NSInteger *outScale, BOOL *outLarge) {
    if (!TCPIsImageFile(fileName)) return NO;
    NSString *name = [[fileName lastPathComponent] stringByDeletingPathExtension];

    BOOL large = NO;
    NSString *lower = name.lowercaseString;
    for (NSString *suffix in @[ @"-large", @"_large" ]) {
        if ([lower hasSuffix:suffix]) {
            name = [name substringToIndex:name.length - suffix.length];
            large = YES;
            break;
        }
    }
    lower = name.lowercaseString;
    for (NSString *device in @[ @"~iphone", @"~ipad", @"~ipod" ]) {
        if ([lower hasSuffix:device]) {
            name = [name substringToIndex:name.length - device.length];
            break;
        }
    }
    NSInteger scale = 0;
    name = TCPStripScaleSuffix(name, &scale);
    // 图标素材的名字就是 bundle id，必定带点（com.apple.mobilephone）。
    // 这一条同时把 ClockIconBackgroundSquare 之类的素材挡在外面。
    if (name.length < 3 || ![name containsString:@"."] || [name containsString:@"/"]) {
        return NO;
    }
    if (outID) *outID = name;
    if (outScale) *outScale = scale;
    if (outLarge) *outLarge = large;
    return YES;
}

// 图标表用的倍率键："2" = @2x，"2l" = @2x 的 -large 变体。
static NSString *TCPScaleKey(NSInteger scale, BOOL large) {
    return [NSString stringWithFormat:@"%ld%@", (long)scale, large ? @"l" : @""];
}

// 按**文件名**里的 @2x/@3x 把 UIImage 的 scale 补回来。
// +[UIImage imageWithContentsOfFile:] 不解析这个后缀，一律给 scale = 1，于是
// 「SBBadgeBG@3x.png」（75×75 像素的正圆，本该 25 点）会变成 75 点的大图：
// 角标画布、字号全按 75 点算，最后被系统压进角标的小框里就成了变形。
// 素材一律是我们自己从主题目录读的，补倍率只为让 image.size 说真话。
static UIImage *TCPImageWithNominalScale(UIImage *image, NSString *path) {
    if (image == nil || path.length == 0) return image;
    NSInteger nominal = 0;
    TCPStripScaleSuffix([[path lastPathComponent] stringByDeletingPathExtension], &nominal);
    if (nominal <= 0 || nominal == (NSInteger)image.scale) return image;
    if (image.CGImage == NULL) return image;
    return [UIImage imageWithCGImage:image.CGImage
                               scale:(CGFloat)nominal
                         orientation:image.imageOrientation];
}

// 点名素材表用的键：只有倍率，没有 -large 变体。
static NSString *TCPPlainScaleKey(NSInteger scale) {
    return [NSString stringWithFormat:@"%ld", (long)scale];
}

// 图标表：请求某个倍率时的候选顺序：本档 → 更大档 → 无后缀；每档先普通再 large。
static NSArray<NSString *> *TCPScaleLookupOrder(NSInteger want) {
    NSMutableArray<NSNumber *> *scales = [NSMutableArray array];
    void (^push)(NSInteger) = ^(NSInteger s) {
        if (![scales containsObject:@(s)]) [scales addObject:@(s)];
    };
    push(want);
    if (want < 3) push(3);
    if (want < 2) push(2);
    push(0);
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSNumber *scale in scales) {
        [keys addObject:TCPScaleKey(scale.integerValue, NO)];
        [keys addObject:TCPScaleKey(scale.integerValue, YES)];
    }
    return keys;
}

// 点名素材表：同样的顺序，但没有 -large。
static NSArray<NSString *> *TCPPlainScaleLookupOrder(NSInteger want) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in TCPScaleLookupOrder(want)) {
        if ([key hasSuffix:@"l"]) continue;
        [keys addObject:key];
    }
    return keys;
}

static NSInteger TCPScaleFromScaleFactor(CGFloat scale) {
    if (scale >= 3.0) return 3;
    if (scale >= 2.0) return 2;
    if (scale >= 1.0) return 1;
    return 0;
}

#pragma mark - 渲染

// 把任意含 alpha 的图转成 8 位 only-alpha 掩膜，CGContextClipToMask 只认这种。
// 尺寸按像素给；返回的 CGImage 由调用方释放。
static CGImageRef TCPCreateAlphaMask(CGImageRef source, CGSize pixelSize) {
    size_t width = (size_t)lround(pixelSize.width);
    size_t height = (size_t)lround(pixelSize.height);
    if (width == 0 || height == 0) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, width, space, kCGImageAlphaOnly);
    CGColorSpaceRelease(space);
    if (!ctx) return NULL;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), source);
    CGImageRef mask = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return mask;
}

// 一张图的 alpha 通道「实际画了多少」：非零 alpha 像素占比（0~1）。
// 用它在重载时把图标遮罩里「细环 / 玻璃圈」这类几乎全透明的素材认出来——
// 那种遮罩裁完图标只剩一个圈，正是「图标空白」的来源（本机「液态玻璃」主题的
// AppIconMask cov≈0.08，裁完主体全没了；实心圆角方的遮罩 cov≈0.78）。
static CGFloat TCPAlphaCoverage(UIImage *image) {
    CGImageRef cg = image.CGImage;
    if (!cg) return 1.0;
    CGFloat srcW = (CGFloat)CGImageGetWidth(cg);
    CGFloat srcH = (CGFloat)CGImageGetHeight(cg);
    if (srcW <= 0 || srcH <= 0) return 1.0;
    // 24 点宽的降采样足够分清「实心形状」与「细环」，还快；超高图（长条素材）别把预算耗光。
    size_t w = 24;
    size_t h = (size_t)MAX(1, (size_t)llround(24.0 * srcH / srcW));
    if (h > 72) h = 72;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, space, kCGImageAlphaOnly);
    CGColorSpaceRelease(space);
    if (!ctx) return 1.0;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), cg);
    unsigned char *bits = CGBitmapContextGetData(ctx);
    size_t count = 0, total = w * h;
    if (bits) {
        for (size_t i = 0; i < total; i++) {
            if (bits[i] > 8) count++;   // 8/255 以下按背景噪声算
        }
    }
    CGContextRelease(ctx);
    return total > 0 ? (CGFloat)count / (CGFloat)total : 1.0;
}

// 遮罩覆盖率的门槛（0.9.4）：低于它就算「细环 / 玻璃圈」，不能拿去裁图标。
// 实测：本机「液态玻璃」的 AppIconMask cov≈0.08（裁完图标主体全没，屏幕上就是空白图标），
// 实心圆角方的遮罩 cov≈0.78。门槛放在两者中间，留给半透明边框素材一点余地。
static const CGFloat TCPMaskCoverageFloor = 0.30;

// 按请求尺寸重画：底图 → (遮罩 | 圆角) → 图标 → overlay。
// 合成顺序按需求：遮罩先，overlay 最后压在最上面。
// 0.9.27：把一张图降采样成 12×12 灰度指纹，用来认「屏幕上那张 CA 复制过的图」是不是我们的。
// 纯指针比对在 CA 复制 CGImage 后失效（layer{ours=0} 假阴性），指纹按内容认、不随复制变。
// 取在主题改过的区域：我们合成的图与同 App 同尺寸 stock 图像素内容不同，指纹不会相撞。
static NSData *TCPFingerprintOfCGImage(CGImageRef cg) {
    if (cg == NULL) return nil;
    const size_t S = 12;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(NULL, S, S, 8, S, space, kCGImageAlphaNone);
    CGColorSpaceRelease(space);
    if (ctx == NULL) return nil;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    CGContextDrawImage(ctx, CGRectMake(0, 0, S, S), cg);
    unsigned char *bits = CGBitmapContextGetData(ctx);
    NSData *fp = nil;
    if (bits != NULL) fp = [NSData dataWithBytes:bits length:S * S];
    CGContextRelease(ctx);
    return fp;
}

static UIImage *TCPRenderIcon(UIImage *icon, UIImage *base, UIImage *mask, UIImage *overlay,
                              CGSize size, CGFloat scale, CGFloat cornerRadius, BOOL roundCorners) {
    if (!icon || size.width <= 0 || size.height <= 0) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, scale > 0 ? scale : 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return nil;
    }
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    if (base) [base drawInRect:rect];

    BOOL clipped = NO;
    if (mask) {
        CGImageRef alphaMask = TCPCreateAlphaMask(mask.CGImage, CGSizeMake(size.width * scale, size.height * scale));
        if (alphaMask) {
            CGContextSaveGState(ctx);
            CGContextClipToMask(ctx, rect, alphaMask);
            CGImageRelease(alphaMask);
            clipped = YES;
        }
    }
    if (!clipped && roundCorners && cornerRadius > 0) {
        CGContextSaveGState(ctx);
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:cornerRadius] addClip];
        clipped = YES;
    }
    [icon drawInRect:rect];
    if (clipped) CGContextRestoreGState(ctx);

    if (overlay) [overlay drawInRect:rect];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();
    return result;
}

#pragma mark - 素材库

@interface TCPThemeStore ()
// 对外只读，内部要写。
@property (atomic) NSUInteger generation;
@property (atomic) BOOL active;
@property (atomic, copy) NSString *themeName;
@property (atomic, copy) NSString *themePath;
@property (atomic, copy) NSArray<NSString *> *themePaths;   // 叠加链，靠后的优先
@property (atomic, copy) NSDictionary<NSString *, id> *badgeSettings;
@property (atomic) BOOL cornerMaskOn;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *iconMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *namedMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *globalFileMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *bundleFileMap;
@property (nonatomic, copy) NSString *maskPath;
@property (nonatomic) CGFloat maskCoverage;    // 遮罩 alpha 覆盖占比（重载时量）
@property (nonatomic) BOOL maskSkipped;        // 覆盖太低被跳过（玻璃圈那类，裁完图标就空白）
@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, copy) NSString *overlayPath;
@property (nonatomic, copy) NSString *folderPath;
@property (nonatomic) NSUInteger featureFlags;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *renderedCache;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *assetCache;   // path+size -> UIImage
@property (nonatomic, strong) NSMutableArray<UIImage *> *renderedImages;   // 我们合成的图（强引用，限量）
@property (nonatomic, strong) NSMutableSet<NSValue *> *renderedImagePointers; // 合成图指针（O(1) 身份索引）
@property (nonatomic, strong) NSMutableSet<NSValue *> *renderedCGPointers; // 合成图背后的 CGImage 指针
// 0.9.18 修法 A：像素指纹。系统只要复制/重绘/经 SBHIconImageCache 转一手，指针就变了，
// 于是「屏幕上这张就是我们的图」被误判成 stock（0.9.16 现场：disp{ours=6} 而 layer{ours=0}）。
// 指纹在渲染时算一次（12×12 灰度），判定时按指纹再比一遍，指针不中不代表不是我们的。
@property (nonatomic, strong) NSMutableSet<NSData *> *renderedFingerprints;
// 同一张图在一次次普查里会被反复问：算过就记住，别每次都把它缩到 12×12 一遍（主线程，会卡桌面）。
// 0.9.28：这张缓存已删 —— 它的键是 UIImage 的裸指针，而我们要认的是 CA 复制出来的 CGImage，
// 两者永远对不上；UIImage 释放后指针还会被复用，反而带来假阳性。每次现场算（12×12 灰度，很便宜）。
@property (nonatomic, strong) NSMutableArray<NSString *> *missSamples;
// 反过来：实际被换成主题图的 bundle id。诊断里能看出「换了哪几个 App」，不用靠肉眼。
@property (nonatomic, strong) NSMutableArray<NSString *> *hitSamples;

// 计数（诊断用）
@property (nonatomic) NSUInteger iconLookups, iconHits, badgeLookups, badgeHits, fileLookups, fileHits;

// 采样用的私有方法（定义在查询实现里，这里先声明，免得编译器报 instance method not found）。
- (void)noteMiss:(NSString *)sample;
- (void)noteHit:(NSString *)sample;
@end

enum {
    TCPFeatureIcons   = 1 << 0,
    TCPFeatureFolders = 1 << 1,
    TCPFeatureBadges  = 1 << 2,
    TCPFeatureFiles   = 1 << 3,
};

@implementation TCPThemeStore

+ (instancetype)shared {
    static TCPThemeStore *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _iconMap = [NSMutableDictionary dictionary];
        _namedMap = [NSMutableDictionary dictionary];
        _globalFileMap = [NSMutableDictionary dictionary];
        _bundleFileMap = [NSMutableDictionary dictionary];
        _badgeSettings = @{};
        _renderedCache = [[NSCache alloc] init];
        _renderedCache.countLimit = 600;
        _assetCache = [[NSCache alloc] init];
        _assetCache.countLimit = 200;
        _renderedImages = [NSMutableArray array];
        _renderedImagePointers = [NSMutableSet set];
        _renderedCGPointers = [NSMutableSet set];
        _renderedFingerprints = [NSMutableSet set];
        _missSamples = [NSMutableArray array];
        _hitSamples = [NSMutableArray array];
        _featureFlags = TCPFeatureIcons | TCPFeatureFolders | TCPFeatureBadges | TCPFeatureFiles;
        [self reload];
    }
    return self;
}

#pragma mark 配置

static BOOL TCPBoolValue(NSDictionary *values, NSString *key, BOOL defaultValue) {
    id value = values[key];
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    if ([value isKindOfClass:[NSString class]]) return [value boolValue];
    return defaultValue;
}

static NSString *TCPStringValue(NSDictionary *values, NSString *key) {
    id value = values[key];
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

- (BOOL)iconsEnabled { return (self.featureFlags & TCPFeatureIcons) != 0; }
- (BOOL)foldersEnabled { return (self.featureFlags & TCPFeatureFolders) != 0; }
- (BOOL)badgesEnabled { return (self.featureFlags & TCPFeatureBadges) != 0; }
- (BOOL)filesEnabled { return (self.featureFlags & TCPFeatureFiles) != 0; }

#pragma mark 重载

- (void)reload {
    TCPConfig *config = [TCPConfig shared];
    [config reload];
    NSDictionary *values = config.values;

    NSMutableDictionary *icons = [NSMutableDictionary dictionary];
    NSMutableDictionary *named = [NSMutableDictionary dictionary];
    NSMutableDictionary *globalFiles = [NSMutableDictionary dictionary];
    NSMutableDictionary *bundleFiles = [NSMutableDictionary dictionary];
    __block NSString *maskPath = nil, *basePath = nil, *overlayPath = nil, *folderPath = nil;

    BOOL enabled = TCPBoolValue(values, TCPKeyEnabled, YES);
    NSArray<NSString *> *paths = enabled ? [self resolveThemePathsWithValues:values] : @[];

    // 四类素材一律全换（用户 2026-10-30 16:59 / 17:00：面板上「素材开关」那四行整组删掉，
    // 全部功能默认开启）。IconsEnabled / FoldersEnabled / BadgesEnabled / FilesEnabled 这四个键
    // 不再读也不再写：老的偏好文件里留着什么值都不理会 —— 装了主题，四类素材一起换。
    NSUInteger flags = TCPFeatureIcons | TCPFeatureFolders | TCPFeatureBadges | TCPFeatureFiles;

    // 多层叠加：扫描器是「先到先得」的（见 indexDirectory / scanIconDirectory 里的 if (!entry[key])），
    // 所以**从最后一层往前扫**：靠后的主题先落表、也就覆盖掉了靠前的。单个主题内部的行为
    //（同名素材按文件名序取第一个）与只支持单主题时一字不差。
    for (NSString *theme in [paths reverseObjectEnumerator]) {
        [self scanThemeAtPath:theme
                        icons:icons
                    namedMap:named
                  globalFiles:globalFiles
                  bundleFiles:bundleFiles
                         mask:&maskPath
                         base:&basePath
                      overlay:&overlayPath
                       folder:&folderPath
                       values:values];
    }

    @synchronized (self) {
        self.iconMap = icons;
        self.namedMap = named;
        self.globalFileMap = globalFiles;
        self.bundleFileMap = bundleFiles;
        self.maskPath = maskPath;
        self.basePath = basePath;
        self.overlayPath = overlayPath;
        self.folderPath = folderPath;
        self.themePaths = paths;
        self.themePath = paths.lastObject;   // 最上层那个
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *path in paths) {
            NSString *name = path.lastPathComponent;
            if ([name hasSuffix:@".theme"]) name = [name stringByDeletingPathExtension];
            if (name.length > 0) [names addObject:name];
        }
        self.themeName = names.count > 0 ? [names componentsJoinedByString:@" + "] : nil;
        self.active = (paths.count > 0);
        self.featureFlags = flags;
        self.generation = self.generation + 1;
        self.iconLookups = self.iconHits = self.badgeLookups = self.badgeHits = self.fileLookups = self.fileHits = 0;
        [self.missSamples removeAllObjects];
        [self.hitSamples removeAllObjects];
        [self.renderedCache removeAllObjects];
        [self.assetCache removeAllObjects];
        [self.renderedImages removeAllObjects];
        [self.renderedImagePointers removeAllObjects];
        [self.renderedCGPointers removeAllObjects];
        [self.renderedFingerprints removeAllObjects];
        // 遮罩体检（0.9.4，修「图标空白」）：把遮罩的 alpha 覆盖量一遍 —— 玻璃 / 细环那类遮罩
        // 几乎全透明，拿去裁图标只会把主体裁没。低于门槛的**不使用**，让图标保持素材原样。
        CGFloat coverage = 1.0;
        BOOL skipped = NO;
        if (self.maskPath.length > 0) {
            UIImage *maskImage = [self cachedImageAtPath:self.maskPath size:CGSizeZero];
            if (maskImage != nil) {
                coverage = TCPAlphaCoverage(maskImage);
                skipped = (coverage < TCPMaskCoverageFloor);
            }
        }
        self.maskCoverage = coverage;
        self.maskSkipped = skipped;
        self.badgeSettings = [self badgeSettingsFromValues:values];
        self.cornerMaskOn = TCPBoolValue(values, TCPKeyIconCornerMask, NO);
    }
}

- (BOOL)cornerMaskEnabled {
    return self.cornerMaskOn;
}

- (UIColor *)badgeTextColor {
    NSString *hex = self.badgeSettings[TCPKeyBadgeTextColor];
    if (![hex isKindOfClass:[NSString class]] || hex.length < 6) return nil;
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6) return nil;
    unsigned int value = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&value]) return nil;
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                           green:((value >> 8) & 0xFF) / 255.0
                            blue:(value & 0xFF) / 255.0
                           alpha:1.0];
}

- (NSString *)badgeFontName {
    NSString *name = self.badgeSettings[TCPKeyBadgeFontName];
    return [name isKindOfClass:[NSString class]] && name.length > 0 ? name : nil;
}

- (CGFloat)badgeFontSize {
    NSNumber *size = self.badgeSettings[TCPKeyBadgeFontSize];
    return [size isKindOfClass:[NSNumber class]] ? size.doubleValue : 0;
}

// 生效叠加链：ThemePaths（有序数组，靠后的优先）优先；没有才退回旧的单主题键。
// 每层都经 TCPReResolveThemePath 重新对到本进程真实存在的目录上（认旧隐根的路径、认引导相对写法），
// 顺序保持配置里的顺序 —— 面板与诊断都按这个顺序说事。
- (NSArray<NSString *> *)resolveThemePathsWithValues:(NSDictionary *)values {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];

    id raw = values[TCPKeyThemePaths];
    if ([raw isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)raw) {
            if (paths.count >= TCPMaxThemeLayers) break;   // 见 Keys.h：层数上限，面板同一口径
            if (![entry isKindOfClass:[NSString class]] || [entry length] == 0) continue;
            NSString *path = (NSString *)entry;
            if ([paths containsObject:path]) continue;   // 同一层只叠一次
            NSString *resolved = TCPReResolveThemePath(path);
            if (resolved.length > 0 && ![paths containsObject:resolved]) {
                [paths addObject:resolved];
            }
        }
    }
    if (paths.count > 0) return paths;

    NSString *single = [self resolveThemePathWithValues:values outName:NULL];
    return single ? @[ single ] : @[];
}

// 单主题（旧写法）：ThemePath（绝对路径）优先，其次在主题根目录里找 ThemeName，
// 都没给就不挂主题 —— 这就是「回滚到原生外观」的实现。
- (NSString *)resolveThemePathWithValues:(NSDictionary *)values outName:(NSString **)outName {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;

    NSString *path = TCPStringValue(values, TCPKeyThemePath);
    NSString *resolved = path.length > 0 ? TCPReResolveThemePath(path) : nil;   // 见 Paths.h：认旧路径/引导相对写法
    if (resolved.length > 0) {
        if (outName) *outName = [resolved lastPathComponent];
        return resolved;
    }

    NSString *name = TCPStringValue(values, TCPKeyThemeName);
    if (name.length > 0) {
        for (NSString *root in TCPSourceThemeRoots()) {
            for (NSString *candidate in @[ name, [name stringByAppendingPathExtension:@"theme"] ]) {
                NSString *full = [root stringByAppendingPathComponent:candidate];
                if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
                    if (outName) *outName = [full lastPathComponent];
                    return full;
                }
            }
        }
    }
    return nil;
}

- (NSDictionary<NSString *, id> *)badgeSettingsFromValues:(NSDictionary *)values {
    NSMutableDictionary<NSString *, id> *settings = [NSMutableDictionary dictionary];
    NSString *color = TCPStringValue(values, TCPKeyBadgeTextColor);
    if (color) settings[TCPKeyBadgeTextColor] = color;
    NSString *font = TCPStringValue(values, TCPKeyBadgeFontName);
    if (font) settings[TCPKeyBadgeFontName] = font;
    id size = values[TCPKeyBadgeFontSize];
    if ([size isKindOfClass:[NSNumber class]]) settings[TCPKeyBadgeFontSize] = size;
    return settings;
}

#pragma mark 扫描

// 浅扫一个目录：图片文件按三种用途记账。bundleKey 非空时同时进 bundleFiles。
- (void)indexDirectory:(NSString *)dir
       intoGlobalFiles:(NSMutableDictionary *)globalFiles
         intoNamedMap:(NSMutableDictionary *)namedMap
             bundleKey:(NSString *)bundleKey
           bundleFiles:(NSMutableDictionary *)bundleFiles {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *file in [[fm contentsOfDirectoryAtPath:dir error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        if (!TCPIsImageFile(file)) continue;
        NSString *path = [dir stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) continue;
        NSString *lower = file.lowercaseString;
        if (globalFiles && !globalFiles[lower]) globalFiles[lower] = path;
        if (bundleKey.length > 0 && bundleFiles) {
            NSMutableDictionary *map = bundleFiles[bundleKey];
            if (!map) {
                map = [NSMutableDictionary dictionary];
                bundleFiles[bundleKey] = map;
            }
            if (!map[lower]) map[lower] = path;
        }
        if (namedMap) {
            NSInteger scale = 0;
            NSString *stem = TCPStripScaleSuffix([file stringByDeletingPathExtension], &scale).lowercaseString;
            if (stem.length >= 2) {
                NSMutableDictionary *entry = namedMap[stem];
                if (!entry) {
                    entry = [NSMutableDictionary dictionary];
                    namedMap[stem] = entry;
                }
                NSString *key = TCPPlainScaleKey(scale);
                if (!entry[key]) entry[key] = path;
            }
        }
    }
}

- (void)scanThemeAtPath:(NSString *)theme
                  icons:(NSMutableDictionary *)icons
               namedMap:(NSMutableDictionary *)named
             globalFiles:(NSMutableDictionary *)globalFiles
             bundleFiles:(NSMutableDictionary *)bundleFiles
                    mask:(NSString **)maskPath
                    base:(NSString **)basePath
                 overlay:(NSString **)overlayPath
                  folder:(NSString **)folderPath
                  values:(NSDictionary *)values {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1) IconBundles/：SnowBoard / IconBundles 的标准放置。
    [self scanIconDirectory:[theme stringByAppendingPathComponent:@"IconBundles"] into:icons];
    // 2) icons/：ThemeCore 风格兼容。
    [self scanIconDirectory:[theme stringByAppendingPathComponent:@"icons"] into:icons];

    // 3) 主题根目录的散图（作者常把 SBBadgeBG@3x.png 直接放在根上）。
    [self indexDirectory:theme intoGlobalFiles:globalFiles intoNamedMap:named bundleKey:nil bundleFiles:nil];

    // 4) 遮罩常在 com.apple.mobileicons.framework/ 里；overlay/shadow 在 AnemoneEffects/。
    for (NSString *sub in @[ @"com.apple.mobileicons.framework", @"AnemoneEffects", @"UIImages" ]) {
        [self indexDirectory:[theme stringByAppendingPathComponent:sub]
             intoGlobalFiles:globalFiles
               intoNamedMap:named
                   bundleKey:nil
                 bundleFiles:nil];
    }

    // 5) Bundles/<bundleid>/：Anemone 风格。icon* 当图标，其余按文件名做覆盖素材。
    //    Bundles/ 根下的扁平文件（SBBadgeBG@3x.png、ClockIconBackgroundSquare@3x.png…）也一并收。
    NSString *bundlesDir = [theme stringByAppendingPathComponent:@"Bundles"];
    [self indexDirectory:bundlesDir
         intoGlobalFiles:globalFiles
           intoNamedMap:named
               bundleKey:nil
             bundleFiles:nil];
    for (NSString *entry in [[fm contentsOfDirectoryAtPath:bundlesDir error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *sub = [bundlesDir stringByAppendingPathComponent:entry];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:sub isDirectory:&isDir] || !isDir) continue;
        NSString *bundleKey = entry.lowercaseString;
        [self indexDirectory:sub
             intoGlobalFiles:globalFiles
               intoNamedMap:named
                   bundleKey:bundleKey
                 bundleFiles:bundleFiles];
        [self scanBundleIconDirectory:sub bundleID:entry into:icons];
    }

    // 6) 作者素材：配置里的相对路径 → 素材规范名 → 内置候选相对路径。
    //    多层叠加时**表里已有的不受影响**：只有上面几层都没给这一样素材，才轮到下面这层来补。
    //    与「从最后一层往前扫」合起来，就是「靠后的主题优先，缺的由靠前的补」。
    if (!*maskPath) {
        *maskPath = [self resolveAssetForValues:values
                                           key:TCPKeyAuthorMask
                                         theme:theme
                                      namedMap:named
                                         names:@[ @"appiconmask", @"iconmask" ]
                                    candidates:@[ @"AppIconMask@2x.png", @"AppIconMask@3x.png", @"AppIconMask.png" ]];
    }
    if (!*basePath) {
        *basePath = [self resolveAssetForValues:values
                                            key:TCPKeyBaseImage
                                          theme:theme
                                       namedMap:named
                                          names:@[ @"iconbase", @"appiconbase" ]
                                     candidates:@[ @"IconBase@2x.png", @"IconBase@3x.png", @"IconBase.png" ]];
    }
    if (!*overlayPath) {
        *overlayPath = [self resolveAssetForValues:values
                                               key:TCPKeyIconOverlay
                                             theme:theme
                                          namedMap:named
                                             names:@[ @"iphoneoverlay", @"iconoverlay" ]
                                        candidates:@[ @"iPhoneOverlay@3x.png", @"IconOverlay@2x.png", @"IconOverlay@3x.png" ]];
    }
    if (!*folderPath) {
        *folderPath = [self namedAssetPathInMap:named names:@[ @"anemfoldericonbg", @"foldericonbg" ]];
    }

    // 7) 时钟表盘（0.9.11）：主题里的 ClockIconBackgroundSquare 当 com.apple.mobiletimer 的图标底图。
    //    只登记**表盘**、不画指针 —— 系统的时钟图标视图（SBHClockApplicationIconImageView）
    //    会自己在表盘上画实时指针，所以主题的时钟既「加载了主题素材」，指针又还是活的
    //    （0.9.5 之前用 Bundles/com.apple.mobiletimer/icon.png 那种小图顶替，
    //    指针和当天时间全没了，看起来就是「时钟图标不显示」）。
    //    顺序同其它素材：靠后的主题已经给了图标就不覆盖。
    if (!icons[@"com.apple.mobiletimer"]) {
        NSMutableDictionary *clockEntry = [NSMutableDictionary dictionary];
        NSDictionary *faceInIcons = icons[@"clockiconbackgroundsquare"];
        if (faceInIcons.count > 0) [clockEntry addEntriesFromDictionary:faceInIcons];
        NSDictionary *faceInNamed = named[@"clockiconbackgroundsquare"];
        for (NSString *key in faceInNamed) {
            NSString *dst = TCPScaleKey(key.integerValue, YES);
            if (!clockEntry[dst]) clockEntry[dst] = faceInNamed[key];
        }
        if (clockEntry.count > 0) icons[@"com.apple.mobiletimer"] = clockEntry;
    }
}

- (void)scanIconDirectory:(NSString *)dir into:(NSMutableDictionary *)icons {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *file in [[fm contentsOfDirectoryAtPath:dir error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *id_ = nil;
        NSInteger scale = 0;
        BOOL large = NO;
        if (!TCPParseIconFileName(file, &id_, &scale, &large)) continue;
        NSString *key = id_.lowercaseString;
        NSMutableDictionary *entry = icons[key];
        if (!entry) {
            entry = [NSMutableDictionary dictionary];
            icons[key] = entry;
        }
        NSString *scaleKey = TCPScaleKey(scale, large);
        if (!entry[scaleKey]) {
            entry[scaleKey] = [dir stringByAppendingPathComponent:file];
        }
    }
}

// Bundles/<bundleid>/ 里的 icon.png / icon@2x.png / icon-large.png：目录名就是 bundle id。
- (void)scanBundleIconDirectory:(NSString *)dir bundleID:(NSString *)bundleID into:(NSMutableDictionary *)icons {
    if (![bundleID containsString:@"."]) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *file in [[fm contentsOfDirectoryAtPath:dir error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        if (!TCPIsImageFile(file)) continue;
        NSString *stem = [[file stringByDeletingPathExtension] lowercaseString];
        BOOL large = NO;
        if ([stem hasSuffix:@"-large"] || [stem hasSuffix:@"_large"]) {
            stem = [stem substringToIndex:stem.length - 6];
            large = YES;
        }
        NSInteger scale = 0;
        stem = TCPStripScaleSuffix(stem, &scale);
        if (![stem isEqualToString:@"icon"]) continue;
        NSMutableDictionary *entry = icons[bundleID.lowercaseString];
        if (!entry) {
            entry = [NSMutableDictionary dictionary];
            icons[bundleID.lowercaseString] = entry;
        }
        NSString *key = TCPScaleKey(scale, large);
        if (!entry[key]) entry[key] = [dir stringByAppendingPathComponent:file];
    }
}

- (NSString *)namedAssetPathInMap:(NSDictionary *)namedMap names:(NSArray<NSString *> *)names {
    for (NSString *name in names) {
        NSDictionary *entry = namedMap[name.lowercaseString];
        if (!entry) continue;
        // 点名素材优先 @3x → @2x → 无后缀。
        for (NSString *key in @[ @"3", @"2", @"1", @"0" ]) {
            if (entry[key]) return entry[key];
        }
    }
    return nil;
}

- (NSString *)resolveAssetForValues:(NSDictionary *)values
                                key:(NSString *)key
                              theme:(NSString *)theme
                           namedMap:(NSDictionary *)namedMap
                              names:(NSArray<NSString *> *)names
                         candidates:(NSArray<NSString *> *)candidates {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *configured = TCPStringValue(values, key);
    if (configured.length > 0) {
        for (NSString *base in @[ theme, [theme stringByAppendingPathComponent:@"Bundles/com.apple.springboard"] ]) {
            NSString *path = [base stringByAppendingPathComponent:configured];
            if ([fm fileExistsAtPath:path]) return path;
        }
    }
    NSString *named = [self namedAssetPathInMap:namedMap names:names];
    if (named) return named;
    for (NSString *candidate in candidates) {
        for (NSString *base in @[ theme, [theme stringByAppendingPathComponent:@"Bundles/com.apple.springboard"],
                                 [theme stringByAppendingPathComponent:@"AnemoneEffects"],
                                 [theme stringByAppendingPathComponent:@"com.apple.mobileicons.framework"] ]) {
            NSString *path = [base stringByAppendingPathComponent:candidate];
            if ([fm fileExistsAtPath:path]) return path;
        }
    }
    return nil;
}

// 候选主题：带 .theme 后缀的目录，以及虽然没有后缀但确实装了素材的目录（例如「角标：透明玻璃」）。
- (NSArray<NSString *> *)availableThemePaths {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seenNames = [NSMutableSet set];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in TCPSourceThemeRoots()) {
        for (NSString *entry in [[fm contentsOfDirectoryAtPath:root error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *full = [root stringByAppendingPathComponent:entry];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:full isDirectory:&isDir] || !isDir) continue;
            // 同名主题只列第一个：/Library/ThemeCore 与 /Library/Themes 两个根里常有同名目录，
            // 不去重的话面板里就出现两行一样的（用户 2026-10-30 反馈「重复行」）。
            NSString *dirKey = entry.lowercaseString;
            if ([seenNames containsObject:dirKey]) continue;
            BOOL looksLikeTheme = [entry.pathExtension.lowercaseString isEqualToString:@"theme"];
            for (NSString *probe in @[ @"IconBundles", @"Bundles", @"AnemoneEffects", @"Info.plist" ]) {
                if ([fm fileExistsAtPath:[full stringByAppendingPathComponent:probe]]) {
                    looksLikeTheme = YES;
                    break;
                }
            }
            if (looksLikeTheme) {
                [result addObject:full];
                [seenNames addObject:dirKey];
            }
        }
    }
    return result;
}

#pragma mark 面板用：一个主题自己带了哪几类素材

NSString * const TCPMaterialIcons = @"icons";
NSString * const TCPMaterialFolders = @"folders";
NSString * const TCPMaterialBadges = @"badges";
NSString * const TCPMaterialFiles = @"files";

// 素材粗分类：只给面板那句「有几件素材」用，不做严格判定（真判定在索引表里）。
// 认名字：角标底图叫 SBBadgeBG（也有 SBBadgeBackground 之类写法），文件夹底板叫 ANEMFolderIconBG。
static NSInteger TCPMaterialKindOfFile(NSString *file) {
    if (!TCPIsImageFile(file)) return -1;                  // 非图（含目录）不进统计
    NSString *stem = [[file stringByDeletingPathExtension] lowercaseString];
    NSInteger scale = 0;
    stem = TCPStripScaleSuffix(stem, &scale);
    if ([stem containsString:@"badgebg"] || [stem containsString:@"badgebackground"]) return 2;
    if ([stem containsString:@"foldericonbg"]) return 1;
    return 0;                                              // 其余算覆盖素材
}

// 只做**浅扫**：数这个主题目录里各类素材各有多少件 —— 不建索引、不读图、不合成，也不缓存
//（只在打开「选择主题」页时算一次；主题目录随时会变，缓存只会骗人）。
// 用户 2026-10-30 16:0x 要求那四个功能开关收进「选择主题」页，并让每行都写清
//「这类素材有没有、有几件」，免得开关打开了屏幕却什么都没变。
- (NSDictionary<NSString *, NSNumber *> *)materialSummaryForThemePath:(NSString *)theme {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (theme.length == 0 || ![fm fileExistsAtPath:theme isDirectory:&isDir] || !isDir) return @{};

    NSUInteger icons = 0, folders = 0, badges = 0, files = 0;

    // 1) 图标：IconBundles/ 与 icons/ 里符合 SnowBoard / IconBundles 命名的图。
    for (NSString *sub in @[ @"IconBundles", @"icons" ]) {
        for (NSString *file in [fm contentsOfDirectoryAtPath:[theme stringByAppendingPathComponent:sub] error:NULL]) {
            NSString *bundleID = nil;
            NSInteger scale = 0;
            BOOL large = NO;
            if (TCPParseIconFileName(file, &bundleID, &scale, &large)) icons++;
        }
    }

    // 2) Bundles/：<bundleid>/icon* 是图标，其余按名字分类（Bundles/ 根下的散图同样）。
    NSString *bundlesDir = [theme stringByAppendingPathComponent:@"Bundles"];
    for (NSString *entry in [fm contentsOfDirectoryAtPath:bundlesDir error:NULL]) {
        NSString *full = [bundlesDir stringByAppendingPathComponent:entry];
        BOOL entryIsDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&entryIsDir]) continue;
        if (!entryIsDir) {
            switch (TCPMaterialKindOfFile(entry)) {
                case 2: badges++; break;
                case 1: folders++; break;
                case 0: files++; break;
                default: break;
            }
            continue;
        }
        for (NSString *file in [fm contentsOfDirectoryAtPath:full error:NULL]) {
            if (!TCPIsImageFile(file)) continue;
            NSString *stem = [[file stringByDeletingPathExtension] lowercaseString];
            for (NSString *suffix in @[ @"-large", @"_large" ]) {
                if ([stem hasSuffix:suffix]) {
                    stem = [stem substringToIndex:stem.length - suffix.length];
                    break;
                }
            }
            NSInteger scale = 0;
            stem = TCPStripScaleSuffix(stem, &scale);
            if ([stem isEqualToString:@"icon"]) { icons++; continue; }
            switch (TCPMaterialKindOfFile(file)) {
                case 2: badges++; break;
                case 1: folders++; break;
                case 0: files++; break;
                default: break;
            }
        }
    }

    // 3) 主题根散图，以及遮罩 / overlay / UIImages 这几个约定目录。
    for (NSString *dir in @[ theme,
                             [theme stringByAppendingPathComponent:@"AnemoneEffects"],
                             [theme stringByAppendingPathComponent:@"UIImages"],
                             [theme stringByAppendingPathComponent:@"com.apple.mobileicons.framework"] ]) {
        for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
            switch (TCPMaterialKindOfFile(file)) {
                case 2: badges++; break;
                case 1: folders++; break;
                case 0: files++; break;
                default: break;
            }
        }
    }

    return @{ TCPMaterialIcons: @(icons),
              TCPMaterialFolders: @(folders),
              TCPMaterialBadges: @(badges),
              TCPMaterialFiles: @(files) };
}

#pragma mark 查询：图标

- (NSString *)iconPathForBundleID:(NSString *)bundleID scale:(CGFloat)scale {
    if (bundleID.length == 0) return nil;
    NSString *key = bundleID.lowercaseString;
    NSArray<NSString *> *order = TCPScaleLookupOrder(TCPScaleFromScaleFactor(scale));
    @synchronized (self) {
        self.iconLookups = self.iconLookups + 1;
        if (!self.active || !(self.featureFlags & TCPFeatureIcons)) return nil;
        NSDictionary *entry = self.iconMap[key];
        NSString *path = nil;
        if (entry) {
            for (NSString *scaleKey in order) {
                NSString *candidate = entry[scaleKey];
                if (candidate) {
                    path = candidate;
                    break;
                }
            }
        }
        if (path) {
            self.iconHits = self.iconHits + 1;
            [self noteHit:bundleID];
        } else {
            [self noteMiss:bundleID];
        }
        return path;
    }
}

- (void)noteHit:(NSString *)sample {
    if (sample.length > 0 && self.hitSamples.count < 24 && ![self.hitSamples containsObject:sample]) {
        [self.hitSamples addObject:sample];
    }
}

- (void)noteMiss:(NSString *)sample {
    // 只留前若干条，够看出「哪些图标没主题素材」就行。
    if (sample.length > 0 && self.missSamples.count < 24 && ![self.missSamples containsObject:sample]) {
        [self.missSamples addObject:sample];
    }
}

- (UIImage *)iconImageForBundleID:(NSString *)bundleID
                             size:(CGSize)size
                            scale:(CGFloat)scale
                     cornerRadius:(CGFloat)cornerRadius {
    NSString *path = [self iconPathForBundleID:bundleID scale:scale];
    if (!path) return nil;

    if (scale <= 0) scale = 2.0;
    // 遮罩可用性（0.9.4）：reload 里量过覆盖率的「玻璃圈」遮罩一律不用 —— 它把图标裁成空白。
    BOOL maskUsable = (self.maskPath.length > 0 && !self.maskSkipped);
    BOOL roundCorners = cornerRadius > 0;
    // 遮罩被跳过时按系统图标的圆角比例（22.37%）兜底，免得换出来是直角方块的玻璃片；
    // 素材本来就带圆角的话，这一刀裁下去什么都不会改变。
    // 只在「有遮罩但被跳过」这一种情况下兜底：主题没配遮罩的老行为（不裁）一点不动。
    //
    // 0.9.5 修「双份素材 / 二个图层」：这一刀**不再看调用方传进来的 cornerRadius**。
    // 上游站（SBIcon 那一组）传的是系统给的真圆角（60pt 图标 ≈ 13.50），显示层站传 0，
    // 于是同一份素材在缓存里留下两个键（13.50 与 13.42）、被合成两份；两层叠在一起，
    // 屏幕上就是一个带重影的图标 —— 用户说的「双份素材加载显示」。
    // 现在圆角只由尺寸决定：一个图标、一个尺寸，只剩一张合成图。
    if (self.maskSkipped && size.width > 0) {
        cornerRadius = size.width * 0.2237;
        roundCorners = YES;
    }
    // 0.9.6 修「双份素材」残留：上游站（SBIcon 那组）传系统真圆角（≈13.50），
    // 显示层站（SBIconImageView）传 0；遮罩可用时圆角根本不影响合成结果（遮罩先裁了），
    // 但缓存键带了它 → 同一份素材留两条缓存、合成两份叠在屏幕上。
    // 现在遮罩可用时缓存键不带 cornerRadius，两站共用一条缓存、只渲染一张图。
    CGFloat cacheRadius = maskUsable ? 0 : (roundCorners ? cornerRadius : 0);
    NSString *cacheKey = [NSString stringWithFormat:@"%lu|%@|%.0fx%.0f|%.2f|%.2f",
                          (unsigned long)self.generation, path, size.width, size.height, scale, cacheRadius];
    UIImage *cached = [self.renderedCache objectForKey:cacheKey];
    if (cached) return cached;

    @synchronized (self) {
        // 一个图标可能同时在多个尺寸被请求（主屏 + Dock + 搜索），素材图只解一次。
        UIImage *icon = [self cachedImageAtPath:path size:CGSizeZero];
        if (!icon) return nil;
        UIImage *base = self.basePath ? [self cachedImageAtPath:self.basePath size:CGSizeZero] : nil;
        UIImage *mask = maskUsable ? [self cachedImageAtPath:self.maskPath size:CGSizeZero] : nil;
        UIImage *overlay = self.overlayPath ? [self cachedImageAtPath:self.overlayPath size:CGSizeZero] : nil;
        UIImage *rendered = TCPRenderIcon(icon, base, mask, overlay, size, scale, cornerRadius, roundCorners);
        if (rendered) {
            [self.renderedCache setObject:rendered forKey:cacheKey];
            // 0.9.8：合成图的身份记录改成**强引用**（原来弱引用 + NSCache 淘汰 →
            // 图早就没了 → isRenderedImage 认不出屏幕上那张图 → 误判成「不是我们的图」）。
            // 同时记下它背后的 CGImage 指针：显示层站走的是 CGImage 路径，
            // 屏幕上 layer.contents 里放的就是这个指针，不记它就分不出 ours/stock。
            if (self.renderedImages.count < 400) {
                [self.renderedImages addObject:rendered];
            } else {
                UIImage *old = self.renderedImages.firstObject;
                [self.renderedImagePointers removeObject:
                    [NSValue valueWithPointer:(__bridge const void *)old]];
                [self.renderedImages removeObjectAtIndex:0];
                [self.renderedImages addObject:rendered];
            }
            [self.renderedImagePointers addObject:
                [NSValue valueWithPointer:(__bridge const void *)rendered]];
            if (rendered.CGImage) {
                // 限量：指针集只增不减会慢慢涨，800 张足够覆盖一屏图标 + 几轮重画。
                if (self.renderedCGPointers.count < 800) {
                    [self.renderedCGPointers addObject:
                        [NSValue valueWithPointer:(const void *)rendered.CGImage]];
                }
                // 0.9.27：≥40pt（约 120px@3x）的图标才记指纹，小图不参与普查、记了易撞且无意义。
                // 指纹在渲染时算一次存进 renderedFingerprints（带限量淘汰），普查时按指纹再认一遍
                // CA 复制过的图（指针集认不出）。指纹缓存以 UIImage 指针为键，加速「能追溯到 UIImage」的场景。
                CGFloat pxW = size.width * (scale > 0 ? scale : 1.0);
                if (pxW >= 40.0) {
                    NSData *fp = TCPFingerprintOfCGImage(rendered.CGImage);
                    if (fp) {
                        if (self.renderedFingerprints.count > 600) {
                            // 限量淘汰：保留一半，避免无限增长（发热比像素统计更狠）。
                            NSMutableArray<NSData *> *all = [[self.renderedFingerprints allObjects] mutableCopy];
                            [all removeObjectsInRange:NSMakeRange(0, all.count / 2)];
                            [self.renderedFingerprints intersectSet:[NSSet setWithArray:all]];
                        }
                        [self.renderedFingerprints addObject:fp];
                    }
                }
            }
        }
        return rendered;
    }
}

// 这张图是不是本插件合成的：认 UIImage 本身，也认它背后的 CGImage。
- (BOOL)isRenderedImage:(UIImage *)image {
    if (!image) return NO;
    @synchronized (self) {
        if ([self.renderedImagePointers containsObject:
                [NSValue valueWithPointer:(__bridge const void *)image]]) {
            return YES;
        }
        if (image.CGImage && [self.renderedCGPointers containsObject:
                [NSValue valueWithPointer:(const void *)image.CGImage]]) {
            return YES;
        }
        return NO;
    }
}

// 这个 CGImage 是不是我们合成的（屏幕上 layer.contents 里放的就是 CGImage）。
- (BOOL)isRenderedCGImage:(CGImageRef)cg {
    return [self isRenderedCGImagePointer:(const void *)cg];
}

// 按裸指针判（layer.contents 是 id，直接比指针，不需要桥接）。
- (BOOL)isRenderedCGImagePointer:(const void *)ptr {
    if (ptr == NULL) return NO;
    @synchronized (self) {
        // 第一道：未经 CA 复制的，指针直接中。
        if ([self.renderedCGPointers containsObject:[NSValue valueWithPointer:ptr]]) return YES;
        // 第二道（0.9.27）：CA 复制过 CGImage 的，指针变了但像素内容相同。
        // 0.9.28：删掉「按 UIImage 指针键查指纹缓存」那一步 —— 复制出来的 CGImage 在原 UIImage
        // 被释放后指针会被复用，拿它当键既查不中（假阴性）又可能把别人的指纹认成我们的（假阳性）；
        // 指纹缓存本身已无用，一律现场按内容算。
        NSData *fp = TCPFingerprintOfCGImage((CGImageRef)ptr);
        if (fp && [self.renderedFingerprints containsObject:fp]) return YES;
        return NO;
    }
}

// size 给 CGSizeZero 表示原图；否则按 size×scale 重画。素材本来就小，缓存按路径即可。
- (UIImage *)cachedImageAtPath:(NSString *)path size:(CGSize)size {
    if (path.length == 0) return nil;
    NSString *key = CGSizeEqualToSize(size, CGSizeZero)
        ? path
        : [NSString stringWithFormat:@"%@|%.0fx%.0f", path, size.width, size.height];
    UIImage *cached = [self.assetCache objectForKey:key];
    if (cached) return cached;
    // store 自己读文件：这会经过 +[UIImage imageWithContentsOfFile:] 的替换钩子，
    // 但 ThemeCorePlusFiles.m 里有「主题目录内部的路径不替换」的护栏，不会自我递归。
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    // 关键：文件名里的 @2x/@3x 只有 +imageNamed: 才认，+imageWithContentsOfFile: 一律给 scale = 1。
    // 于是 75×75 的 @3x 角标素材被当成「75 点」的大图（本该 25 点），画布与字号全跟着放大，
    // 再被系统塞进角标的小框 —— 角标变形就是这么来的。这里按文件名把倍率补回去，
    // 让 image.size 是真实点数。所有绘制路径都按显式矩形画，补倍率不会改变别的行为。
    image = TCPImageWithNominalScale(image, path);
    if (image) [self.assetCache setObject:image forKey:key];
    return image;
}

#pragma mark 查询：角标 / 文件夹 / 点名素材

- (UIImage *)imageForNamedAsset:(NSString *)name scale:(CGFloat)scale {
    NSString *path = nil;
    @synchronized (self) {
        if (!self.active) return nil;
        NSDictionary *entry = self.namedMap[name.lowercaseString];
        if (entry) {
            for (NSString *key in TCPPlainScaleLookupOrder(TCPScaleFromScaleFactor(scale))) {
                if (entry[key]) {
                    path = entry[key];
                    break;
                }
            }
        }
    }
    return path ? [self cachedImageAtPath:path size:CGSizeZero] : nil;
}

- (UIImage *)badgeBackgroundImageForScale:(CGFloat)scale {
    @synchronized (self) {
        self.badgeLookups = self.badgeLookups + 1;
        if (!self.active || !(self.featureFlags & TCPFeatureBadges)) return nil;
    }
    UIImage *image = [self imageForNamedAsset:@"SBBadgeBG" scale:scale];
    if (image) {
        @synchronized (self) {
            self.badgeHits = self.badgeHits + 1;
        }
    }
    return image;
}

- (UIImage *)folderBackgroundImageForScale:(CGFloat)scale {
    @synchronized (self) {
        if (!self.active || !(self.featureFlags & TCPFeatureFolders) || self.folderPath.length == 0) return nil;
    }
    return [self cachedImageAtPath:self.folderPath size:CGSizeZero];
}

#pragma mark 查询：文件覆盖

- (NSString *)overridePathForBundleID:(NSString *)bundleID fileName:(NSString *)fileName {
    if (fileName.length == 0) return nil;
    NSString *name = [fileName lastPathComponent].lowercaseString;
    // 候选名：不带扩展名时按 png 再试一次（imageNamed: 常常不带后缀）；
    // 再按尺度变体各试一遍 —— 系统问名字时是「ClockIconBackgroundSquare」（不带 @3x），
    // 而 ThemeCore 主题里这类命名素材往往存成 `Bundles/ClockIconBackgroundSquare@3x.png`，
    // 只按原样查永远查不到（本机 file{look=52,hit=0} 就是这么来的）。
    NSString *stem = [name stringByDeletingPathExtension];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (name.pathExtension.length > 0) {
        [candidates addObject:name];
    } else {
        [candidates addObject:name];
        [candidates addObject:[name stringByAppendingPathExtension:@"png"]];
    }
    for (NSString *scale in @[ @"@3x", @"@2x", @"" ]) {
        NSString *variant = [stem stringByAppendingString:scale];
        if (variant.length == 0) continue;
        [candidates addObject:variant];
        [candidates addObject:[variant stringByAppendingPathExtension:@"png"]];
    }

    @synchronized (self) {
        self.fileLookups = self.fileLookups + 1;
        if (!self.active || !(self.featureFlags & TCPFeatureFiles)) return nil;
        NSString *path = nil;
        if (bundleID.length > 0) {
            NSDictionary *map = self.bundleFileMap[bundleID.lowercaseString];
            for (NSString *candidate in candidates) {
                if (map[candidate]) {
                    path = map[candidate];
                    break;
                }
            }
        }
        if (!path) {
            for (NSString *candidate in candidates) {
                if (self.globalFileMap[candidate]) {
                    path = self.globalFileMap[candidate];
                    break;
                }
            }
        }
        if (path) self.fileHits = self.fileHits + 1;
        return path;
    }
}

#pragma mark 诊断

- (NSString *)diagnostics {
    @synchronized (self) {
        NSString *samples = self.missSamples.count > 0 ? [self.missSamples componentsJoinedByString:@","] : @"-";
        if (samples.length > 240) samples = [samples substringToIndex:240];
        NSString *hits = self.hitSamples.count > 0 ? [self.hitSamples componentsJoinedByString:@","] : @"-";
        if (hits.length > 240) hits = [hits substringToIndex:240];
        // 叠加链：layers=N 是层数，[...] 是从最下层到最上层的目录名（最右边那个说了算）。
        // 名字用 layers 而不是 themes：诊断串末尾那个 themes= 是「扫到几个主题」的普查，
        // 与「当前挂了哪几层」是两件事，别混。
        NSMutableArray<NSString *> *chain = [NSMutableArray array];
        for (NSString *path in self.themePaths) {
            [chain addObject:path.lastPathComponent];
        }
        NSString *layers = chain.count > 0 ? [chain componentsJoinedByString:@"|"] : @"-";
        if (layers.length > 160) layers = [layers substringToIndex:160];
        return [NSString stringWithFormat:
                @"v%@;active=%d;theme=%@;layers=%lu[%@];gen=%lu;icon{look=%lu,hit=%lu};badge{look=%lu,hit=%lu};file{look=%lu,hit=%lu};named=%lu;mask=%d,cov=%.2f,skip=%d;base=%d;overlay=%d;folder=%d;hit=[%@];miss=[%@]",
                TCP_VERSION,
                self.active ? 1 : 0,
                self.themeName ?: @"-",
                (unsigned long)self.themePaths.count,
                layers,
                (unsigned long)self.generation,
                (unsigned long)self.iconLookups, (unsigned long)self.iconHits,
                (unsigned long)self.badgeLookups, (unsigned long)self.badgeHits,
                (unsigned long)self.fileLookups, (unsigned long)self.fileHits,
                (unsigned long)self.namedMap.count,
                self.maskPath ? 1 : 0, (double)self.maskCoverage, self.maskSkipped ? 1 : 0,
                self.basePath ? 1 : 0,
                self.overlayPath ? 1 : 0,
                self.folderPath ? 1 : 0,
                hits,
                samples];
    }
}

@end
