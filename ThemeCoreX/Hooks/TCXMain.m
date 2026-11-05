#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "TCXPrivate.h"
#import "TCXPaths.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"
#import "TCXStore.h"

// 入口：进程判定 + 分层挂站 + 诊断。
//
// 铁律（1.4.0 那次把 SpringBoard 打进安全模式学到的）：
//   构造函数阶段**绝不碰任何 UIKit API**（连 [UIScreen mainScreen] 都不行）。
//   这里只用 getprogname / 文件 / Foundation。

extern void TCXInstallIconHooks(void);
extern void TCXInstallShadowHooks(void);
extern void TCXInstallBadgeHooks(void);
extern void TCXInstallClockHooks(void);
extern void TCXInstallBundleImageHooks(void);
extern void TCXInstallFolderHooks(void);

NSString *TCXRole(void);
NSUInteger TCXHookCount(void);
NSString *TCXSiteList(void);
void TCXNoteSite(NSString *site);
void TCXCountIconLook(void);
void TCXCountIconHit(NSString *bundleID);
void TCXCountBadgeLook(void);
void TCXCountShadow(void);

static NSString *sRole = @"other";
static NSMutableArray<NSString *> *sSites;
static NSUInteger sIconLook = 0;
static NSUInteger sIconHit = 0;
static NSString *sLastBundle = nil;
static NSUInteger sBadgeLook = 0;
static NSUInteger sShadowApplied = 0;
static NSString *sLastError = nil;

NSString *TCXRole(void) { return sRole; }
NSUInteger TCXHookCount(void) { return sSites.count; }

NSString *TCXSiteList(void) {
    return sSites.count ? [sSites componentsJoinedByString:@","] : @"-";
}

void TCXNoteSite(NSString *site) {
    if (!sSites) sSites = [NSMutableArray array];
    if (site.length && ![sSites containsObject:site]) [sSites addObject:site];
}

void TCXCountIconLook(void) { sIconLook++; }
void TCXCountIconHit(NSString *bundleID) {
    sIconHit++;
    if (bundleID.length) sLastBundle = bundleID;
}
void TCXCountBadgeLook(void) { sBadgeLook++; }
void TCXCountShadow(void) { sShadowApplied++; }
void TCXRecordError(NSString *error) { if (error.length) sLastError = error; }

void TCXWriteDiagnostics(BOOL force) {
    TCXStore *store = [TCXStore shared];
    const char *pn = getprogname();
    NSString *role = [@(pn ?: "?") isEqualToString:@"SpringBoard"] ? @"springboard"
                   : [@(pn ?: "?") isEqualToString:@"iconservicesagent"] ? @"iconservice"
                   : @"other";
    NSString *text = [NSString stringWithFormat:
        @"v=%s;proc=%@;role=%@;hooked=%lu;sites=%@;theme=%@;layers=%lu;bundles=%lu;assets=%lu;icon=%lu;hit=%lu;bdg=%lu;shd=%lu;last=%@;err=%@",
        TCX_VERSION, @(pn ?: "?"), role,
        (unsigned long)sSites.count, TCXSiteList(),
        store.themeName ?: @"none",
        (unsigned long)[store layerCount],
        (unsigned long)[store indexedBundleCount],
        (unsigned long)[store indexedAssetCount],
        (unsigned long)sIconLook, (unsigned long)sIconHit,
        (unsigned long)sBadgeLook, (unsigned long)sShadowApplied,
        sLastBundle ?: @"-", sLastError ?: @"-"];
    if (force) TCXDiagWriteForce(text); else TCXDiagWrite(text);
}

// 构造函数：照 ThemeCore 0.5.1 的实证结构：
//   TCIconServicesIsCurrentProcess() 判断进程 → TCReadConfiguration() 读配置（含 Enabled 开关）
//   → TCIconServicesInstallHooks()（生图层）→ TCIconShadowInstallHooks()（阴影层）。
// 不发明「后台队列挂站」「关开关写诊断」这类它没有的东西。
__attribute__((constructor)) static void TCXInitialize(void) {
    @autoreleasepool {
        const char *progname = getprogname();
        NSString *proc = progname ? @(progname) : @"";

        BOOL isSpringBoard = [proc isEqualToString:@"SpringBoard"];

        // 对应 TCReadConfiguration：读「启用插件」总开关。关掉时一个站都不挂。
        // （ThemeCore 有 _TCConfigurationEnabledKey / _TCReadConfiguration / isEnabled。）
        if (!TCXPrefBool(@"Enabled", YES)) {
            return;
        }

        @try {
            // 对应 TCIconServicesInstallHooks：生图层，每个被注入的进程都挂。
            TCXInstallIconHooks();

            if (isSpringBoard) {
                // 对应 TCIconShadowInstallHooks 那一层的呈现模块。
                // 阴影 / 角标 / 时钟 / 日历 / 圆角遮罩功能用户定为常开（面板无开关）。
                TCXInstallShadowHooks();
                TCXInstallBadgeHooks();
                TCXInstallClockHooks();
                // 控制中心模块图标（Bundles/com.apple.control-center.*）
                TCXInstallBundleImageHooks();
                TCXInstallFolderHooks();
            }
        } @catch (NSException *exception) {
            TCXRecordError([NSString stringWithFormat:@"%@:%@", exception.name, exception.reason]);
        }

        // 诊断是我们自己的取证设施（ThemeCore 没有诊断，但删了就没法验证），
        // 挂完站写一次，文件 IO 只此一次，不在启动关键路径之前。
        TCXWriteDiagnostics(YES);
    }
}
