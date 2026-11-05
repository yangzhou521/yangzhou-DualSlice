#import "TCXStore.h"
#import "TCXPaths.h"
#import "TCXPrefs.h"
#import <objc/runtime.h>

// 主题库实现。素材根只有一个：<jbroot>/Library/Themes（TCXPaths.h 第三条铁律）。

@interface TCXStore () {
    NSMutableDictionary<NSString *, NSString *> *_iconPathCache;
    NSCache<NSString *, UIImage *> *_imageCache;
    // 通用 Bundles 索引：bid -> @{ 资源基名(小写) -> 完整路径 }。
    // reload 时把每层主题 Bundles/<bid>/ 下的**所有文件**整个扫进来，
    // 与素材名无关 —— 用户以后往 Bundles 里新加任何素材，reload 一次就自动生效。
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *_bundleAssets;
    NSString *_themeName;
    NSString *_themePath;
    NSArray<NSString *> *_themePaths;
    NSDictionary *_themeInfo;
    UIImage *_shadowImage;
    NSUInteger _generation;
    NSUInteger _iconCount;
    NSString *_lastPreference;
}
@end

@implementation TCXStore

+ (instancetype)shared {
    static TCXStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[TCXStore alloc] init]; });
    return store;
}

- (instancetype)init {
    if ((self = [super init])) {
        _iconPathCache = [NSMutableDictionary dictionary];
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 320;
        _bundleAssets = [NSMutableDictionary dictionary];
        _generation = 1;
        [self reload];
    }
    return self;
}

- (NSString *)themeName { return _themeName; }
- (NSString *)themePath { return _themePath; }
- (NSArray<NSString *> *)themePaths { return _themePaths; }
- (NSUInteger)layerCount { return _themePaths.count; }
- (NSDictionary *)themeInfo { return _themeInfo; }
- (NSUInteger)generation { return _generation; }
- (NSUInteger)iconCount { return _iconCount; }

- (BOOL)maskIcons {
    id value = _themeInfo[@"IB-MaskIcons"];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

#pragma mark - 扫描

// 一个目录算不算主题：里面得有 Info.plist 或 IconBundles / Icons / icons / Bundles。
static BOOL TCXLooksLikeTheme(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) return NO;
    for (NSString *sub in @[@"Info.plist", @"IconBundles", @"Icons", @"icons", @"Bundles"]) {
        if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:sub]]) return YES;
    }
    return NO;
}

// 数一遍图标文件（面板与诊断要显示「N 个图标」，不数会让用户以为没加载）。
// 主题里有没有图标文件。只数到第一个就停 —— 调用方只判「有没有」与排序，
// 不需要精确总数。原来用 contentsOfDirectoryAtPath: 会把整个目录一次读进内存，
// Smartisan.theme 有 2379 个文件，那是启动期最重的一次 IO。
// ThemeCore 0.5.1 的符号表里用的是 enumeratorAtPath:（惰性枚举），这里对齐它。
static NSUInteger TCXCountIcons(NSString *themePath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *sub in @[@"IconBundles", @"Icons", @"icons"]) {
        NSString *dir = [themePath stringByAppendingPathComponent:sub];
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
        if (!en) continue;
        for (NSString *entry in en) {
            if ([[entry pathExtension].lowercaseString isEqualToString:@"png"]) return 1;
        }
    }
    return 0;
}

// 一次扫描内计数不许重复做：排序比较器会对同一个主题扫十几遍，
// Smartisan.theme 有 2379 个图标文件，重复扫描是白耗启动时间。
// 每次 reload 开头清空这张表。
static NSMutableDictionary<NSString *, NSNumber *> *sIconCountCache = nil;
static NSUInteger TCXCountIconsCached(NSString *themePath) {
    if (!themePath.length) return 0;
    if (!sIconCountCache) sIconCountCache = [NSMutableDictionary dictionary];
    NSNumber *hit = sIconCountCache[themePath];
    if (hit) return hit.unsignedIntegerValue;
    NSUInteger n = TCXCountIcons(themePath);
    sIconCountCache[themePath] = @(n);
    return n;
}

// 把一层主题 Bundles/<bid>/ 下的**所有素材**登记进索引。
// 不挑名字、不挑目录 —— 控制中心模块、系统设置、springboard、AnemoneEffects、
// 以及用户以后新建的任何 bundle 目录，全都自动收进来。
// 键用「资源基名小写」（去掉 @2x/@3x/-large/~iphone/.png 等后缀），
// 这样系统传来的 name 无论带不带后缀都能命中。
static NSString *TCXAssetKey(NSString *fileName) {
    NSString *base = [fileName stringByDeletingPathExtension];
    for (NSString *suffix in @[@"@3x~iphone", @"@2x~iphone", @"@3x~ipad", @"@2x~ipad",
                               @"@3x", @"@2x", @"~iphone", @"~ipad", @"-large"]) {
        if ([base hasSuffix:suffix]) { base = [base substringToIndex:base.length - suffix.length]; break; }
    }
    return base.lowercaseString;
}

static void TCXIndexBundlesForLayer(NSString *layer,
                                    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *out) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *bundles = [layer stringByAppendingPathComponent:@"Bundles"];
    NSArray<NSString *> *bids = [fm contentsOfDirectoryAtPath:bundles error:NULL] ?: @[];
    for (NSString *bid in bids) {
        if ([bid hasPrefix:@"."] || [bid isEqualToString:@"IconBundles"]) continue;
        NSString *dir = [bundles stringByAppendingPathComponent:bid];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:dir];
        NSMutableDictionary<NSString *, NSString *> *table = out[bid];
        if (!table) { table = [NSMutableDictionary dictionary]; out[bid] = table; }
        for (NSString *rel in en) {
            NSString *ext = rel.pathExtension.lowercaseString;
            if (![ext isEqualToString:@"png"] && ![ext isEqualToString:@"jpg"] &&
                ![ext isEqualToString:@"jpeg"]) continue;
            NSString *key = TCXAssetKey(rel.lastPathComponent);
            if (!key.length) continue;
            // 叠加层：先扫到的层优先（reload 按顺序调用本函数），不要被后面的层覆盖。
            if (!table[key]) table[key] = [dir stringByAppendingPathComponent:rel];
        }
    }
}

- (void)reload {
    _themeName = nil;
    _themePath = nil;
    _themePaths = nil;
    _themeInfo = nil;
    [sIconCountCache removeAllObjects];   // 主题目录可能变了，计数从头算
    _shadowImage = nil;
    _iconCount = 0;
    [_iconPathCache removeAllObjects];
    [_imageCache removeAllObjects];
    [_bundleAssets removeAllObjects];

    NSString *wanted = TCXPrefString(@"ActiveTheme");
    _lastPreference = wanted ?: @"";

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];

    // 唯一根。它本身可能是主题，也可能装着若干主题目录。
    NSString *root = TCXThemesRoot();
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:root isDirectory:&isDir] && isDir) {
        if (TCXLooksLikeTheme(root)) [candidates addObject:root];
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:root error:NULL] ?: @[];
        for (NSString *entry in [entries sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
            if ([entry hasPrefix:@"."]) continue;
            NSString *child = [root stringByAppendingPathComponent:entry];
            if (TCXLooksLikeTheme(child)) [candidates addObject:child];
        }
    }

    NSString *picked = nil;
    if (wanted.length > 0) {
        for (NSString *path in candidates) {
            NSString *name = [path lastPathComponent];
            // 主题名允许带或不带 .theme 后缀，面板里存的是目录名。
            if ([name isEqualToString:wanted] ||
                [[name stringByDeletingPathExtension] isEqualToString:wanted] ||
                [[name stringByDeletingPathExtension].lowercaseString isEqualToString:wanted.lowercaseString]) {
                picked = path;
                break;
            }
        }
    }
    if (!picked) {
        // 没指定主题时挑「真有图标」的第一个：角标/蒙板类目录里只有一两张素材，
        // 当默认主题会让桌面看起来什么都没换。都有图标时取排序第一（与面板同一规则）。
        for (NSString *path in candidates) {
            if (TCXCountIconsCached(path) > 0) { picked = path; break; }
        }
        if (!picked) picked = candidates.firstObject;
    }

    if (picked) {
        _themePath = picked;
        _themeName = [picked lastPathComponent];
        _iconCount = TCXCountIconsCached(picked);
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                              [picked stringByAppendingPathComponent:@"Info.plist"]];
        _themeInfo = [info isKindOfClass:[NSDictionary class]] ? info : nil;

        // —— 叠加层（ThemeCore 0.5.1 的 layers）——
        // 用户主题常常是「一个目录放图标、另一个目录放角标/蒙板」，单选任一个都缺图
        // （ThemeCore 诊断里就是 theme=角标：透明玻璃 + 液态玻璃.theme、layers=2）。
        // 规则：选中的放第一层，其余候选按图标数量从多到少跟在后面；查找时逐层往下走。
        NSMutableArray<NSString *> *layers = [NSMutableArray arrayWithObject:picked];
        NSArray<NSString *> *rest = [candidates sortedArrayUsingComparator:
            ^NSComparisonResult(NSString *a, NSString *b) {
                NSUInteger ca = TCXCountIconsCached(a), cb = TCXCountIconsCached(b);
                if (ca != cb) return ca > cb ? NSOrderedAscending : NSOrderedDescending;
                return [a compare:b];
            }];
        for (NSString *path in rest) {
            if (![path isEqualToString:picked]) [layers addObject:path];
        }
        _themePaths = layers;
        // 按叠加层顺序扫 Bundles —— 先扫到的层优先，逐层补齐。
        // 这样 Bundles 里现在有的、以后新加的素材，reload 一次就全部登记，不用改代码。
        for (NSString *layer in layers) TCXIndexBundlesForLayer(layer, _bundleAssets);
    } else {
        _themePaths = @[];
    }
    _generation++;
}

- (void)reloadIfNeeded {
    NSString *wanted = TCXPrefString(@"ActiveTheme") ?: @"";
    if (![_lastPreference ?: @"" isEqualToString:wanted]) {
        [self reload];
    } else if (!_themePath) {
        [self reload];
    }
}

#pragma mark - 图标

static NSArray<NSString *> *TCXSuffixes(CGFloat scale) {
    if (scale >= 2.5)      return @[@"@3x", @"@2x", @""];
    else if (scale >= 1.5) return @[@"@2x", @"@3x", @""];
    else                   return @[@"", @"@2x", @"@3x"];
}

// 文件名候选：ThemeCore 主题的图标主文件是「-large」变体
// （实测 液态玻璃.theme/IconBundles 里全是 xxx-large.png / xxx@3x-large.png），
// 所以 -large 一律排在普通命名之前；两套都试，缺哪套都能落到另一套。
static NSArray<NSString *> *TCXIconFileNames(NSString *bundleID, CGFloat scale) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *suffix in TCXSuffixes(scale)) {
        [names addObject:[bundleID stringByAppendingFormat:@"%@-large.png", suffix]];
    }
    for (NSString *suffix in TCXSuffixes(scale)) {
        [names addObject:[bundleID stringByAppendingFormat:@"%@.png", suffix]];
    }
    return names;
}

- (NSString *)iconPathForBundleID:(NSString *)bundleID scale:(CGFloat)scale {
    if (bundleID.length == 0 || _themePaths.count == 0) return nil;

    NSString *key = [NSString stringWithFormat:@"%@|%.1f", bundleID, scale];
    id cached = _iconPathCache[key];
    if (cached) return (cached == (id)[NSNull null]) ? nil : cached;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = TCXIconFileNames(bundleID, scale);
    NSString *found = nil;

    // 逐层查找：前一层没有这张图，就去下一层拿（叠加层语义同 ThemeCore 0.5.1）。
    for (NSString *layer in _themePaths) {
        for (NSString *sub in @[@"IconBundles", @"Icons", @"icons"]) {
            NSString *dir = [layer stringByAppendingPathComponent:sub];
            for (NSString *name in names) {
                NSString *path = [dir stringByAppendingPathComponent:name];
                if ([fm fileExistsAtPath:path]) { found = path; break; }
            }
            if (found) break;
        }
        if (found) break;
    }

    // 主题把图标放在 Bundles/<bundle id>/ 的也有：只在前面都没命中时兜底，同样逐层。
    if (!found) {
        for (NSString *layer in _themePaths) {
            NSString *dir = [layer stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"Bundles/%@", bundleID]];
            for (NSString *base in @[@"Icon", bundleID]) {
                for (NSString *suffix in TCXSuffixes(scale)) {
                    for (NSString *tail in @[@"-large", @""]) {
                        NSString *path = [dir stringByAppendingPathComponent:
                                          [base stringByAppendingFormat:@"%@%@.png", suffix, tail]];
                        if ([fm fileExistsAtPath:path]) { found = path; break; }
                    }
                    if (found) break;
                }
                if (found) break;
            }
            if (found) break;
        }
    }

    _iconPathCache[key] = found ?: (id)[NSNull null];
    return found;
}

- (BOOL)hasIconForBundleID:(NSString *)bundleID scale:(CGFloat)scale {
    return [self iconPathForBundleID:bundleID scale:scale] != nil;
}

static UIImage *TCXImageFromFile(NSString *path);

// iOS 图标圆角≈边长 22.37%，这里用普通圆角近似（视觉上没差别，算得快）。
static UIImage *TCXRoundCorners(UIImage *image, CGSize size) {
    if (!image) return nil;
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = image.scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect
                                                       cornerRadius:size.width * 0.2237f];
        [path addClip];
        [image drawInRect:rect];
    }];
}

- (UIImage *)imageForBundleID:(NSString *)bundleID size:(CGSize)size scale:(CGFloat)scale {
    NSString *path = [self iconPathForBundleID:bundleID scale:scale];
    if (!path) return nil;
    if (size.width <= 0 || size.height <= 0) return nil;

    BOOL keepMask = YES;   // 圆角遮罩常开（面板已无开关）
    NSString *key = [NSString stringWithFormat:@"%@|%.0fx%.0f|%d|%lu",
                     path, size.width, size.height, (int)keepMask, (unsigned long)_generation];
    UIImage *cached = [_imageCache objectForKey:key];
    if (cached) return cached;

    UIImage *source = TCXImageFromFile(path);
    if (!source) return nil;

    // 源图缩放到目标尺寸，再圆角裁切。目标尺寸由调用方给（图标格大小），不猜。
    // 输出档位用调用方要的 scale：写成 source.scale 会让「@2x 源图 → @3x 屏」
    // 少一半像素，图标发虚。
    CGFloat outScale = scale > 0 ? scale : source.scale;
    UIImage *scaled = source;
    if (!CGSizeEqualToSize(source.size, size)) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = outScale;
        format.opaque = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
        scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [source drawInRect:CGRectMake(0, 0, size.width, size.height)];
        }];
    }

    UIImage *result = keepMask ? TCXRoundCorners(scaled, size) : scaled;
    TCXMarkThemedImage(result);
    if (result) [_imageCache setObject:result forKey:key];
    return result;
}

#pragma mark - 主题图标记

// 「这张图是我们产出的」标记。视图层（SBIconImageView setImage:）据此防重入：
// 不标记就会对自己的输出再套一次主题图，滚动时无限重绘。
static char kTCXThemedImageKey;

BOOL TCXIsThemedImage(UIImage *image) {
    if (!image) return NO;
    return objc_getAssociatedObject(image, &kTCXThemedImageKey) != nil;
}

void TCXMarkThemedImage(UIImage *image) {
    if (!image) return;
    objc_setAssociatedObject(image, &kTCXThemedImageKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 从文件读图，但**按文件名的档位还原 scale**。
// [UIImage imageWithContentsOfFile:] 一律给 scale=1：@3x 的 PNG 会被当成 1x，
// 于是系统把像素尺寸当点尺寸显示 —— 图会大 3 倍。必须自己按名字定 scale。
static UIImage *TCXImageFromFile(NSString *path) {
    if (!path.length) return nil;
    NSString *file = path.lastPathComponent;
    CGFloat scale = 1.0;
    if ([file containsString:@"@3x"])      scale = 3.0;
    else if ([file containsString:@"@2x"]) scale = 2.0;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    UIImage *image = [UIImage imageWithData:data scale:scale];
    if (image) TCXMarkThemedImage(image);
    return image;
}

#pragma mark - 主题里的其它资源

// 文件名候选：设备修饰符 + 尺寸后缀 + 「-large」的组合。
//
// 实测（本机 /Library/Themes）：
//   Smartisan.theme   ClockIconBackgroundSquare@3x~iphone.png   ← 带 ~iphone
//   Smartisan.theme   ClockIconHourHand@2x.png
//   液态玻璃.theme    ClockIconBackgroundSquare.png             ← 裸名
//   液态玻璃.theme    IconBundles/ClockIconBackgroundSquare@3x-large.png
// 四类都要试；顺序照 iOS 自己解析资源的习惯：设备修饰符优先、分辨率从高到低、
// 「-large」是主题圈的主命名所以在同档里排前面。
static NSArray<NSString *> *TCXResourceFileNames(NSString *name, CGFloat scale) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSArray<NSString *> *suffixes = TCXSuffixes(scale);
    for (NSString *tail in @[@"-large", @""]) {
        for (NSString *suffix in suffixes) {
            [names addObject:[name stringByAppendingFormat:@"%@~iphone%@", suffix, tail]];
        }
        for (NSString *suffix in suffixes) {
            [names addObject:[name stringByAppendingFormat:@"%@%@", suffix, tail]];
        }
        for (NSString *suffix in suffixes) {
            [names addObject:[name stringByAppendingFormat:@"%@~ipad%@", suffix, tail]];
        }
    }
    return names;
}

// 资源查找带路径缓存：候选名有十几个 × 四个目录，每次问都扫一遍太浪费
// （时钟表盘是被反复问的）。
- (NSString *)resourcePathForName:(NSString *)name
                         bundleID:(NSString *)bundleID
                            scale:(CGFloat)scale {
    if (name.length == 0 || _themePaths.count == 0) return nil;

    NSString *key = [NSString stringWithFormat:@"res|%@|%@|%.1f|%lu",
                     bundleID ?: @"", name, scale, (unsigned long)_generation];
    id cached = [_iconPathCache objectForKey:key];
    if (cached) return (cached == (id)[NSNull null]) ? nil : cached;

    // 逐层展开成目录列表：每一层内部还是「该 bundle 目录 → springboard → IconBundles → 主题根」。
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    for (NSString *layer in _themePaths) {
        if (bundleID.length) {
            [dirs addObject:[layer stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"Bundles/%@", bundleID]]];
        }
        [dirs addObject:[layer stringByAppendingPathComponent:@"Bundles/com.apple.springboard"]];
        [dirs addObject:[layer stringByAppendingPathComponent:@"IconBundles"]];
        [dirs addObject:layer];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *found = nil;
    NSArray<NSString *> *names = TCXResourceFileNames(name, scale);
    for (NSString *dir in dirs) {
        for (NSString *fileName in names) {
            NSString *path = [dir stringByAppendingPathComponent:fileName];
            if ([fm fileExistsAtPath:path]) { found = path; break; }
        }
        if (found) break;
    }

    [_iconPathCache setObject:found ?: (id)[NSNull null] forKey:key];
    return found;
}

// 通用 Bundles 素材入口：不依赖素材名，直接查 reload 时扫好的索引。
// 任何 imageNamed:inBundle: 来问，只要这个 bid 的目录里有对应基名的图就返回。
- (UIImage *)imageForAsset:(NSString *)name inBundle:(NSString *)bundleID {
    if (name.length == 0 || bundleID.length == 0) return nil;
    NSDictionary<NSString *, NSString *> *table = _bundleAssets[bundleID];
    if (!table) return nil;
    NSString *path = table[TCXAssetKey(name)];
    if (!path) return nil;

    NSString *key = [NSString stringWithFormat:@"res-idx|%@|%lu", path, (unsigned long)_generation];
    UIImage *cached = [_imageCache objectForKey:key];
    if (cached) return cached;
    UIImage *image = TCXImageFromFile(path);
    if (image) [_imageCache setObject:image forKey:key];
    return image;
}

- (NSUInteger)indexedBundleCount { return _bundleAssets.count; }
- (NSUInteger)indexedAssetCount {
    NSUInteger n = 0;
    for (NSDictionary *table in _bundleAssets.allValues) n += table.count;
    return n;
}

- (UIImage *)imageNamed:(NSString *)name inBundle:(NSString *)bundleID scale:(CGFloat)scale {
    // 先走通用索引（覆盖 Bundles 下所有素材，含用户以后新加的）；
    // 索引没命中再退回按名字拼路径的旧规则。
    UIImage *indexed = [self imageForAsset:name inBundle:bundleID];
    if (indexed) return indexed;
    NSString *path = [self resourcePathForName:name bundleID:bundleID scale:scale];
    if (!path) return nil;

    NSString *key = [NSString stringWithFormat:@"res-img|%@|%lu", path, (unsigned long)_generation];
    UIImage *cached = [_imageCache objectForKey:key];
    if (cached) return cached;

    UIImage *image = TCXImageFromFile(path);
    if (image) [_imageCache setObject:image forKey:key];
    return image;
}

- (UIImage *)springboardImageNamed:(NSString *)name scale:(CGFloat)scale {
    return [self imageNamed:name inBundle:@"com.apple.springboard" scale:scale];
}

#pragma mark - 阴影素材

// 阴影目录：ThemeCore 认的三个（AnemoneEffects / Iconomatic / Effects），
// 实测主题把阴影放在 <主题>/Bundles/AnemoneEffects/iPhoneShadow@3x.png。
static NSArray<NSString *> *TCXShadowDirectories(NSString *themePath) {
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    for (NSString *sub in @[@"Bundles/AnemoneEffects", @"AnemoneEffects",
                            @"Bundles/Iconomatic", @"Iconomatic",
                            @"Bundles/Effects", @"Effects"]) {
        [dirs addObject:[themePath stringByAppendingPathComponent:sub]];
    }
    return dirs;
}

- (UIImage *)shadowImage {
    if (_shadowImage) return _shadowImage;
    if (_themePaths.count == 0) return nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *allDirs = [NSMutableArray array];
    for (NSString *layer in _themePaths) {
        [allDirs addObjectsFromArray:TCXShadowDirectories(layer)];
    }
    for (NSString *dir in allDirs) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;

        NSMutableArray<NSString *> *hits = [NSMutableArray array];
        for (NSString *entry in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
            if (![[entry pathExtension].lowercaseString isEqualToString:@"png"]) continue;
            if ([entry rangeOfString:@"shadow" options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
            if ([entry hasPrefix:@"备"]) continue;   // 主题里的「备…」是备份文件
            [hits addObject:entry];
        }
        if (hits.count == 0) continue;

        // @3x → @2x → 其他，稳定挑一张。
        [hits sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            int sa = [a containsString:@"@3x"] ? 0 : ([a containsString:@"@2x"] ? 1 : 2);
            int sb = [b containsString:@"@3x"] ? 0 : ([b containsString:@"@2x"] ? 1 : 2);
            if (sa != sb) return sa < sb ? NSOrderedAscending : NSOrderedDescending;
            return [a compare:b];
        }];
        UIImage *image = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:hits.firstObject]];
        if (image) {
            _shadowImage = image;
            return image;
        }
    }
    return nil;
}

#pragma mark - 日历设置

// 主题 Info.plist 里的日历文字设置。两个键都认，取不到给 nil。
- (NSDictionary *)calendarSettingsForKey:(NSString *)key {
    // 走叠加层：从第一层往下找，第一个有这个键的层生效。
    // 之前只读 _themeInfo（第一层），当前生效主题是「角标：透明玻璃」时它没有日历配置，
    // 于是永远回落默认样式、主题给的位置与颜色全被忽略（用户 2026-11-06 01:50 报的）。
    for (NSString *layer in _themePaths) {
        NSDictionary *info = nil;
        if ([layer isEqualToString:_themePath ?: @""]) {
            info = _themeInfo;
        } else {
            id raw = [NSDictionary dictionaryWithContentsOfFile:
                      [layer stringByAppendingPathComponent:@"Info.plist"]];
            info = [raw isKindOfClass:[NSDictionary class]] ? raw : nil;
        }
        if (!info) continue;
        id value = info[key];
        if ([value isKindOfClass:[NSDictionary class]]) return value;
    }
    // 最后一层兜底：_themeInfo
    id value = _themeInfo[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSDictionary *)calendarDateSettings { return [self calendarSettingsForKey:@"CalendarIconDateSettings"]; }
- (NSDictionary *)calendarDaySettings  { return [self calendarSettingsForKey:@"CalendarIconDaySettings"]; }

@end