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
    NSString *text = [NSString stringWithFormat:
        @"v=%s;proc=%@;role=%@;hooked=%lu;sites=%@;theme=%@;icon=%lu;hit=%lu;bdg=%lu;shd=%lu;last=%@;err=%@",
        TCX_VERSION, @(getprogname() ?: "?"), sRole,
        (unsigned long)sSites.count, TCXSiteList(),
        store.themeName ?: @"none",
        (unsigned long)sIconLook, (unsigned long)sIconHit,
        (unsigned long)sBadgeLook, (unsigned long)sShadowApplied,
        sLastBundle ?: @"-", sLastError ?: @"-"];
    if (force) TCXDiagWriteForce(text); else TCXDiagWrite(text);
}

// 站挂了没被调用时，光靠 hook 内部计数看不出来；所以给各模块一个统一的落点，
// 让 Main 定期（这里用「被问就写、节流 5 秒」的轻办法）把总数刷出去。
__attribute__((constructor)) static void TCXInitialize(void) {
    @autoreleasepool {
        const char *progname = getprogname();
        NSString *proc = progname ? @(progname) : @"";

        if ([proc isEqualToString:@"SpringBoard"]) {
            sRole = @"springboard";
        } else if ([proc isEqualToString:@"iconservicesagent"]) {
            sRole = @"iconservice";
        } else {
            sRole = @"other";
        }

        // 用户关掉总开关：一个站都不挂，只留一行诊断（方便确认「是关着」而不是「坏了」）。
        if (!TCXPrefBool(@"Enabled", YES)) {
            sRole = [sRole stringByAppendingString:@":disabled"];
            TCXWriteDiagnostics(YES);
            return;
        }

        @try {
            // 生图层在**每个**被注入的进程里都挂 —— ThemeCore 0.5.1 就是这个模型：
            // 过滤器命中 com.apple.UIKit，凡是链接 UIKit 的进程都进得来，
            // IconServices 的生图对象在各进程里都存在，换的是 UIImage，类型不变。
            TCXInstallIconHooks();

            if ([sRole isEqualToString:@"springboard"]) {
                // 呈现层专属：只有 SpringBoard 里才有 SBIconView / SBIconBadgeView / 时钟视图。
                // 阴影 / 角标 / 时钟 / 日历 / 圆角遮罩这些功能由用户定为**常开**，
                // 面板不再提供开关（2026-11-05 22:52），所以这里直接全挂，不读偏好。
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

        // 诊断写入**绝不能在构造函数里同步做**：TCXWriteDiagnostics 会 [TCXStore shared]，
        // 那要把主题库建起来、扫 Library/Themes、读每个主题的 Info.plist。
        // 在 SpringBoard 的 dyld 构造函数阶段做这件事会卡住启动，
        // 系统等不到桌面就绪就把进程杀掉 → 用户看到「注销后黑屏，再起一次才正常」。
        // 所以推迟到主队列空闲时跑，启动期一个文件都不碰。
        dispatch_async(dispatch_get_main_queue(), ^{
            TCXWriteDiagnostics(YES);
        });
    }
}
