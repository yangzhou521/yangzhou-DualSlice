//
//  ThemeCorePlusFiles.m —— 指名素材替换：状态栏、设置、电话、照片分享面板、系统分享面板…
//
//  这些位置的图不走桌面图标那条管线，SnowBoard/Anemone 主题对它们一律按「文件名」整包替换。
//  主题里 Bundles/<bundleid>/<文件名> 或 Bundles/ 根下的同名文件就是替换源，所以这里挂三个
//  出图入口，把「要读的路径」换掉，图本身仍由系统自己解码（不做二次绘制，不破坏深浅色/缓存）。
//
//  护栏：store 自己合成图标时会走 +[UIImage imageWithContentsOfFile:]，主题目录内部的路径
//  一律不替换，否则会自我递归。
//
#import "ThemeCorePlusHooks.h"
#import "ThemeCorePlusStore.h"
#import "ThemeCorePlusPaths.h"

static UIImage *(*tcpOrigImageWithContentsOfFile)(id, SEL, NSString *) = NULL;
static id (*tcpOrigInitWithContentsOfFile)(id, SEL, NSString *) = NULL;
static UIImage *(*tcpOrigImageNamed)(id, SEL, NSString *) = NULL;

static NSString *TCPCurrentBundleIdentifier(void) {
    static NSString *identifier = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        identifier = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    });
    return identifier;
}

// 路径版：问 store 有没有这个文件名的替换源。
static NSString *TCPReplacementPathForFile(NSString *path) {
    if (path.length == 0) return nil;
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;
    if (TCPPathIsInsideThemeRoots(path)) return nil;   // 自己人读自己素材
    NSString *replacement = [store overridePathForBundleID:TCPCurrentBundleIdentifier() fileName:path];
    if (replacement.length == 0 || [replacement isEqualToString:path]) return nil;
    return replacement;
}

// 名字版（+imageNamed:）：名字不是路径，只有「目录名之外」的部分参与匹配。
static NSString *TCPReplacementPathForName(NSString *name) {
    if (name.length == 0) return nil;
    TCPThemeStore *store = [TCPThemeStore shared];
    if (!store.active) return nil;
    NSString *replacement = [store overridePathForBundleID:TCPCurrentBundleIdentifier() fileName:name];
    if (replacement.length == 0) return nil;
    return replacement;
}

static UIImage *TCPImageWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    NSString *replacement = TCPReplacementPathForFile(path);
    return tcpOrigImageWithContentsOfFile(self, _cmd, replacement ?: path);
}

static id TCPInitWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    NSString *replacement = TCPReplacementPathForFile(path);
    return tcpOrigInitWithContentsOfFile(self, _cmd, replacement ?: path);
}

static UIImage *TCPImageNamed(id self, SEL _cmd, NSString *name) {
    NSString *replacement = TCPReplacementPathForName(name);
    return tcpOrigImageNamed(self, _cmd, replacement ?: name);
}

void TCPInstallFileSites(void) {
    Class imageClass = objc_getClass("UIImage");
    if (imageClass == Nil) return;
    Class imageMeta = object_getClass(imageClass);

    if (tcpOrigImageWithContentsOfFile == NULL) {
        MSHookMessageEx(imageMeta, @selector(imageWithContentsOfFile:), (IMP)TCPImageWithContentsOfFile,
                        (IMP *)&tcpOrigImageWithContentsOfFile);
    }
    if (tcpOrigInitWithContentsOfFile == NULL) {
        MSHookMessageEx(imageClass, @selector(initWithContentsOfFile:), (IMP)TCPInitWithContentsOfFile,
                        (IMP *)&tcpOrigInitWithContentsOfFile);
    }
    if (tcpOrigImageNamed == NULL) {
        MSHookMessageEx(imageMeta, @selector(imageNamed:), (IMP)TCPImageNamed,
                        (IMP *)&tcpOrigImageNamed);
    }
}
