#import "ThemeCorePlusPaths.h"
#import "ApelinBootstrap.h"
#import <mach-o/dyld.h>
#import <dlfcn.h>

// 兜底找隐根：dladdr 在本镜像里不一定拿得到（面板进程里 anchor 的符号可能归属别的镜像），
// 所以再扫一遍已加载镜像名，找路径里含 .jbroot- 的那一段。找不到返回 nil。
static NSString *TCPDiscoveredJBRoot(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name == NULL) continue;
        NSArray<NSString *> *parts = [@(name) componentsSeparatedByString:@"/"];
        for (NSUInteger j = 0; j < parts.count; j++) {
            if ([parts[j] hasPrefix:@".jbroot-"]) {
                return [[parts subarrayWithRange:NSMakeRange(0, j + 1)] componentsJoinedByString:@"/"];
            }
        }
    }
    return nil;
}

#pragma mark 候选策略（本机教训：算出来的根必须**真的能打开**才算数）

// roothide 的 jbroot()：唯一"官方"答案，返回**调用方命名空间里真实的绝对路径**。
// 返回值是它自己 malloc 的，我们拷成 NSString 后**故意不 free**：认错分配器会把 SpringBoard /
// 设置 直接带走，而这条路径每个进程只算一次，这点泄漏不值一提。
static NSString *TCPJBrootSymbolPath(NSString *relative) {
    static char *(*fn)(const char *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
    });
    if (fn == NULL || relative.length == 0) return nil;
    char *out = fn(relative.UTF8String);
    return out != NULL ? @(out) : nil;   // 不 free
}

// 1) jbroot()（最权威）2) dladdr/扫镜像推出来的隐根 3) /var/jb（rootless、或指向隐根的软链）
// 4) 空前缀（有些引导把 /Library 直接重定向到自己那份）。
static NSString *TCPStrategyJBroot(NSString *relative) {
    return TCPJBrootSymbolPath(relative);
}

static NSString *TCPStrategyAnchor(NSString *relative) {
    NSString *root = ApelinBootstrapRoot() ?: TCPDiscoveredJBRoot();
    return root.length > 0 ? [root stringByAppendingString:relative] : nil;
}

static NSString *TCPStrategyVarJB(NSString *relative) {
    return [@"/var/jb" stringByAppendingString:relative];
}

// 最后一个兜底：直接翻 /private/var/containers/Bundle/Application 里叫 .jbroot-* 的目录
// （隐根本体就在那儿），取第一个真的含这条相对路径的那个。只有前面几招都失手才会走到这里。
static NSString *TCPStrategyScan(NSString *relative) {
    static NSArray<NSString *> *roots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *parent = @"/private/var/containers/Bundle/Application";
        NSMutableArray<NSString *> *found = [NSMutableArray array];
        for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:parent error:NULL]) {
            if ([entry hasPrefix:@".jbroot-"]) [found addObject:[parent stringByAppendingPathComponent:entry]];
        }
        roots = [found sortedArrayUsingSelector:@selector(compare:)];
    });
    for (NSString *root in roots) {
        NSString *full = [root stringByAppendingString:relative];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && isDir) return full;
    }
    return nil;
}

static NSString *TCPStrategyPlain(NSString *relative) {
    return relative;
}

static NSString *(*const TCPStrategies[])(NSString *) = {
    TCPStrategyJBroot, TCPStrategyAnchor, TCPStrategyVarJB, TCPStrategyScan, TCPStrategyPlain
};
static const NSUInteger TCPStrategyCount = sizeof(TCPStrategies) / sizeof(TCPStrategies[0]);

static NSString *TCPStrategyName(NSUInteger index) {
    switch (index) {
        case 0: return @"jbroot";
        case 1: return @"anchor";
        case 2: return @"varjb";
        case 3: return @"scan";
        case 4: return @"plain";
        default: return @"?";
    }
}

static NSArray<NSString *> *TCPBootstrapThemeRelatives(void) {
    return @[ @"/Library/ThemeCore", @"/Library/Themes" ];
}

// 真目录才算：不存在的候选直接跳过。本机踩过的坑——/var/jb 是指向 "/" 的软链，
// 对系统进程来说它落到**真实根**上，那里根本没有 /Library/ThemeCore，于是主题一个都扫不到。
static BOOL TCPAddThemeRootIfDirectory(NSMutableArray<NSString *> *list,
                                      NSMutableSet<NSString *> *seen,
                                      NSString *path) {
    if (path.length == 0) return NO;
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] || !isDir) return NO;
    NSString *key = path.stringByResolvingSymlinksInPath.lowercaseString ?: path.lowercaseString;
    if (![seen containsObject:key]) {
        [seen addObject:key];
        [list addObject:path];
    }
    return YES;
}

static NSString *TCPRootsReport;          // 诊断用，dispatch_once 里填
static NSString *TCPRootsPickedStrategy;  // 命中的策略名

static void TCPResolveThemeRoots(NSMutableArray<NSString *> *list) {
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSString *> *relatives = TCPBootstrapThemeRelatives();

    // 每个引导相对路径：取第一个在本进程里**真的存在**的策略，避免同一份目录被记多次。
    for (NSString *relative in relatives) {
        for (NSUInteger i = 0; i < TCPStrategyCount; i++) {
            NSString *full = TCPStrategies[i](relative);
            if (full.length == 0) continue;
            if (TCPAddThemeRootIfDirectory(list, seen, full)) {
                if (TCPRootsPickedStrategy.length == 0) TCPRootsPickedStrategy = TCPStrategyName(i);
                break;
            }
        }
    }

    // 系统路径：用户目录下的主题，原样使用（绝不过隐根）。
    for (NSString *path in @[ @"/var/mobile/Library/ThemeCore", @"/var/mobile/Library/Themes" ]) {
        TCPAddThemeRootIfDirectory(list, seen, path);
    }

    // 诊断：每个策略在**本进程**里能不能看到 /Library/ThemeCore（1/0），以及最终用了谁。
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    for (NSUInteger i = 0; i < TCPStrategyCount; i++) {
        NSString *full = TCPStrategies[i](relatives.firstObject);
        BOOL isDir = NO;
        BOOL ok = full.length > 0 &&
                  [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && isDir;
        [flags addObject:[NSString stringWithFormat:@"%@:%@", TCPStrategyName(i), ok ? @"1" : @"0"]];
    }
    TCPRootsReport = [NSString stringWithFormat:@"pick=%@;try=[%@]",
                      TCPRootsPickedStrategy ?: @"none", [flags componentsJoinedByString:@","]];
}

NSArray<NSString *> *TCPSourceThemeRoots(void) {
    // 根列表在一个进程里不会变（jbroot 每次越狱才改名），缓存一次。
    static NSArray<NSString *> *roots;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSString *> *list = [NSMutableArray array];
        TCPResolveThemeRoots(list);
        if (list.count > 0) {
            roots = list;
        } else {
            // 一个都打不开：保留干净的兜底写法，让诊断说出 pick=none，别把根写死。
            roots = @[ @"/Library/ThemeCore", @"/Library/Themes", @"/var/mobile/Library/Themes" ];
        }
    });
    return roots;
}

// 诊断串：本进程里各策略的可见性 + 最终采用的策略（写在诊断里，装完机一眼能看出根对不对）。
NSString *TCPSourceThemeRootsReport(void) {
    (void)TCPSourceThemeRoots();
    return TCPRootsReport.length > 0 ? TCPRootsReport : @"unresolved";
}

BOOL TCPPathIsInsideThemeRoots(NSString *path) {
    if (path.length == 0) return NO;
    for (NSString *root in TCPSourceThemeRoots()) {
        if ([path hasPrefix:root]) return YES;
    }
    return NO;
}

// 目录名相同的候选：在主题根里直接找同名目录（先试原名，再试加 .theme）。
static NSString *TCPThemePathByName(NSString *name) {
    if (name.length == 0) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in TCPSourceThemeRoots()) {
        for (NSString *candidate in @[ name, [name stringByAppendingPathExtension:@"theme"] ]) {
            NSString *full = [root stringByAppendingPathComponent:candidate];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) return full;
        }
    }
    return nil;
}

NSString *TCPReResolveThemePath(NSString *stored) {
    if (stored.length == 0) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:stored isDirectory:&isDir] && isDir) return stored;

    // 1) 按「/Library/…」之后的相对部分重新贴到当前的同名根上：
    //    既治隐根换名，也治 shell 手写的引导相对路径。
    NSRange range = [stored rangeOfString:@"/Library/"];
    if (range.location != NSNotFound) {
        NSString *tail = [stored substringFromIndex:range.location];   // /Library/Themes/Vela
        for (NSString *relative in TCPBootstrapThemeRelatives()) {     // /Library/ThemeCore, /Library/Themes
            if (![tail hasPrefix:relative]) continue;
            NSString *rest = [tail substringFromIndex:relative.length]; // /Vela
            for (NSString *root in TCPSourceThemeRoots()) {
                if (![root hasSuffix:relative]) continue;               // 只往同名的根上贴
                NSString *candidate = [root stringByAppendingString:rest];
                if ([fm fileExistsAtPath:candidate isDirectory:&isDir] && isDir) return candidate;
            }
        }
    }

    // 2) 还是不行就按目录名找同名主题（用户把主题挪到另一个根里了）。
    return TCPThemePathByName(stored.lastPathComponent);
}

NSString *TCPLibraryRoot(void) {
    return @"/var/mobile/Library/ThemeCorePlus";
}

NSString *TCPRevisionsRoot(void) {
    return [TCPLibraryRoot() stringByAppendingPathComponent:@"revisions"];
}
