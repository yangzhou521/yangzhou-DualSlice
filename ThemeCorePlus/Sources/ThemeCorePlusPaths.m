#import "ThemeCorePlusPaths.h"
#import "ApelinBootstrap.h"
#import <mach-o/dyld.h>

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

NSArray<NSString *> *TCPSourceThemeRoots(void) {
    // 根列表在一个进程里不会变（jbroot 每次越狱才改名），缓存一次。
    static NSArray<NSString *> *roots;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSString *> *list = [NSMutableArray array];
        NSArray<NSString *> *relative = @[ @"/Library/ThemeCore", @"/Library/Themes" ];
        NSString *jbroot = ApelinBootstrapRoot() ?: TCPDiscoveredJBRoot();
        if (jbroot.length > 0) {
            // 引导路径：必须过隐根，绝不能把根路径写死进产物里。
            for (NSString *path in relative) {
                [list addObject:[jbroot stringByAppendingString:path]];
            }
        } else {
            // 连根都找不到时的兜底拼法：rootless 的 /var/jb（本机它是指向 jbroot 的软链）。
            for (NSString *path in relative) {
                [list addObject:[@"/var/jb" stringByAppendingString:path]];
            }
        }
        // 系统路径：用户目录下的主题，原样使用。
        [list addObject:@"/var/mobile/Library/Themes"];
        roots = list;
    });
    return roots;
}

BOOL TCPPathIsInsideThemeRoots(NSString *path) {
    if (path.length == 0) return NO;
    for (NSString *root in TCPSourceThemeRoots()) {
        if ([path hasPrefix:root]) return YES;
    }
    return NO;
}

NSString *TCPLibraryRoot(void) {
    return @"/var/mobile/Library/ThemeCorePlus";
}

NSString *TCPRevisionsRoot(void) {
    return [TCPLibraryRoot() stringByAppendingPathComponent:@"revisions"];
}
