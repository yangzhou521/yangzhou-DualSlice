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
        @"v=%s;proc=%@;role=%@;hooked=%lu;sites=%@;theme=%@;layers=%lu;icon=%lu;hit=%lu;bdg=%lu;shd=%lu;last=%@;err=%@",
        TCX_VERSION, @(getprogname() ?: "?"), sRole,
        (unsigned long)sSites.count, TCXSiteList(),
        store.themeName ?: @"none",
        (unsigned long)[store layerCount],
        (unsigned long)sIconLook, (unsigned long)sIconHit,
        (unsigned long)sBadgeLook, (unsigned long)sShadowApplied,
        sLastBundle ?: @"-", sLastError ?: @"-"];
    if (force) TCXDiagWriteForce(text); else TCXDiagWrite(text);
}

// 站挂了没被调用时，光靠 hook 内部计数看不出来；所以给各模块一个统一的落点，
// 让 Main 定期（这里用「被问就写、节流 5 秒」的轻办法）把总数刷出去。
//
// ★ 架构对齐 ThemeCore 0.5.1（用户 2026-11-05 23:49 强调「优先和 ThemeCore 0.5.1 架构一致」）：
// ThemeCore 把工作拆成 TCIconServicesInstallHooks（生图层）与 TCIconShadowInstallHooks（阴影层）
// 两个阶段，构造函数里只做进程判断与配置读取，**挂站不放在 dyld 构造函数阶段**。
//
// 为什么这么重要（用户报「注销后黑屏、再起一次桌面才正常」的老 bug）：
// 构造函数阶段是 SpringBoard 启动的关键窗口，系统在这个窗口里等桌面就绪。
// 我们原来在这里同步挂 27 个站（每个都要 class_copyMethodList + MSHookMessageEx），
// 桌面迟迟不 ready，系统就把进程杀掉重启 → 用户看到黑屏，第二次才正常。
// 修法：构造函数只判断角色与开关（纯内存操作，微秒级），
// 挂站与诊断全部 dispatch_async 到**低优先级后台串行队列** —— 启动期一个站都不挂、一次盘都不读。
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

        // 后台串行队列先建好：开关判断分支与正常分支都用它。
        static dispatch_queue_t sInstallQueue;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dispatch_queue_attr_t attr =
                dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
            sInstallQueue = dispatch_queue_create("com.yangzhou.appicon.install", attr);
        });

        // 用户关掉总开关：一个站都不挂，只留一行诊断（方便确认「是关着」而不是「坏了」）。
        if (!TCXPrefBool(@"Enabled", YES)) {
            sRole = [sRole stringByAppendingString:@":disabled"];
            dispatch_async(sInstallQueue, ^{
                TCXWriteDiagnostics(YES);
            });
            return;
        }

        BOOL isSpringBoard = [sRole isEqualToString:@"springboard"];
        (void)isSpringBoard;

        // ★ 挂站放在自己的后台串行队列里做（队列在上面已经建好），不是主队列。
        // ThemeCore 的符号表里有 dispatch_queue_create + dispatch_queue_attr_make_with_qos_class
        // + dispatch_get_global_queue，说明它把重活放在低优先级后台队列，
        // 主队列只在必须碰 UI 时才用。
        //
        // 为什么不放主队列（这是「注销后黑屏、要再进一次桌面」的关键）：
        // dyld 构造函数之后主队列马上就要跑 SpringBoard 的启动任务、画桌面首帧。
        // 我们把 27 个站的 class_copyMethodList + MSHookMessageEx 全丢进主队列，
        // 等于和桌面首帧抢同一个队列 —— 首帧迟迟出不来，watchdog 判超时就杀进程重启。
        dispatch_async(sInstallQueue, ^{
            @autoreleasepool {
                @try {
                    // 生图层在**每个**被注入的进程里都挂 —— ThemeCore 0.5.1 就是这个模型：
                    // 过滤器命中 com.apple.UIKit，凡是链接 UIKit 的进程都进得来，
                    // IconServices 的生图对象在各进程里都存在，换的是 UIImage，类型不变。
                    TCXInstallIconHooks();

                    if (isSpringBoard) {
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

                // 诊断落盘：文件 IO，也在后台队列，绝不占主队列。
                TCXWriteDiagnostics(YES);
            }
        });
    }
}
