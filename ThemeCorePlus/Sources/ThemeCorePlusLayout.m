//
//  ThemeCorePlusLayout.m —— 桌面图标布局的备份与恢复。
//
//  用户 2026-10-31 05:30：「保存图标布局，注销后和 SpringBoard 崩溃后，保留之前 App 桌面图标的布局」。
//
//  病灶：桌面布局存在 /var/mobile/Library/SpringBoard/IconState.plist，只有 SpringBoard
//  正常收尾时才会写盘。注销（sbreload）来得急、崩溃更不用说，那一份没写下去 ——
//  下次启动 SpringBoard 拿到的就是上一次的旧布局，或者自己重排一遍。
//
//  做法两步，都不碰 UIKit，所以在 dyld 构造函数阶段做是安全的：
//    1) 恢复：SpringBoard 启动最早的时刻（构造函数）把备份放回原位。此刻 SBIconModel
//       还没建、还没读这个文件，所以放回去的就是它读到的。
//    2) 备份：系统每次自己保存布局（-[SBIconModel saveIconState] 一族）之后立刻同步一份；
//       另有 20 秒一次的 mtime 兜底，万一某个系统版本不走那个方法也跟得上。
//
//  备份位置：/var/mobile/Library/ThemeCorePlus/IconState.backup.plist
//  （SpringBoard 以 mobile 身份运行，这个目录它写得了；CountdownHUD 也在这个目录下写过请求文件。）
//
#import "ThemeCorePlusHooks.h"
#import <objc/runtime.h>

static NSString *const TCPLayoutSourcePath = @"/var/mobile/Library/SpringBoard/IconState.plist";
static NSString *const TCPLayoutBackupDir  = @"/var/mobile/Library/ThemeCorePlus";
static NSString *const TCPLayoutBackupPath = @"/var/mobile/Library/ThemeCorePlus/IconState.backup.plist";

static volatile int sLayoutRestored = 0;
static volatile int sLayoutSaved = 0;
static volatile int sLayoutTicks = 0;
static NSString *sLayoutLast = @"-";

static BOOL TCPLayoutCopy(NSString *from, NSString *to) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:to error:NULL];
    return [fm copyItemAtPath:from toPath:to error:NULL];
}

// 把当前布局存成备份（系统刚写完、或兜底定时发现文件更新了）。
static void TCPLayoutBackup(NSString *why) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:TCPLayoutSourcePath]) return;
    [fm createDirectoryAtPath:TCPLayoutBackupDir
  withIntermediateDirectories:YES
                   attributes:nil
                        error:NULL];
    if (TCPLayoutCopy(TCPLayoutSourcePath, TCPLayoutBackupPath)) {
        __sync_fetch_and_add(&sLayoutSaved, 1);
        sLayoutLast = [NSString stringWithFormat:@"saved:%@", why];
    } else {
        sLayoutLast = [NSString stringWithFormat:@"savefail:%@", why];
    }
}

// 备份能不能当布局用：必须是一份读得出来的 plist。坏文件绝不往 SpringBoard 嘴里塞 ——
// 那是崩溃循环的入口。
static BOOL TCPLayoutUsable(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length < 32) return NO;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:NULL];
    return plist != nil;
}

// 把备份放回原位（只在 SpringBoard 启动最早的时刻调用一次）。
//
// 0.9.17 改：**只在「系统那份布局不见了 / 读不出来」时才回填**。
// 原来是无条件覆盖 —— 用户 2026-10-31 08:37 报「桌面图标注销没有保存功能」：
// 备份停在 05:23，此后每次注销启动都把 05:23 的旧布局糊回 IconState.plist，
// 用户改过的摆位（以及新装的图标）每注销一次丢一次。回填是给「崩溃/文件损坏」兜底的，
// 不是每次开机都强制回滚；系统自己有文件、而且读得出来，就一个字节都不许动。
static void TCPLayoutRestore(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:TCPLayoutBackupPath]) { sLayoutLast = @"nobackup"; return; }
    if ([fm fileExistsAtPath:TCPLayoutSourcePath]) {
        if (TCPLayoutUsable(TCPLayoutSourcePath)) {
            // 系统那份好着 —— 以它为准，顺手把备份刷新成这一份（下次真出事回填的就是最新的）。
            sLayoutLast = @"keepsource";
            TCPLayoutBackup(@"startup");
            return;
        }
        sLayoutLast = @"sourcebad";
    }
    if (!TCPLayoutUsable(TCPLayoutBackupPath)) { sLayoutLast = @"backupbad"; return; }
    if (TCPLayoutCopy(TCPLayoutBackupPath, TCPLayoutSourcePath)) {
        __sync_fetch_and_add(&sLayoutRestored, 1);
        sLayoutLast = @"restored";
    } else {
        sLayoutLast = @"restorefail";
    }
}

// 系统自己保存布局时，跟着存一份。
static void (*tcpLayoutSaveOrig)(id, SEL) = NULL;
static void tcpLayoutSaveHook(id self, SEL _cmd) {
    if (tcpLayoutSaveOrig != NULL) tcpLayoutSaveOrig(self, _cmd);
    TCPLayoutBackup(@"saveIconState");
}

void TCPLayoutInstall(void) {
    static BOOL installed = NO;
    if (installed) return;
    installed = YES;

    // 只在 SpringBoard 里做：别的进程（设置、Spotlight）没有 IconState 这件事。
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

    // 1) 恢复。构造函数阶段，早于 SBIconModel 读布局。
    TCPLayoutRestore();

    // 2) 系统保存布局后同步备份。方法名各版本不一样，挂上第一个存在的。
    Class modelClass = objc_getClass("SBIconModel");
    if (modelClass != Nil) {
        NSArray<NSString *> *names = @[ @"saveIconState", @"saveIconStateAndWait",
                                        @"persistIconState", @"_saveIconState" ];
        for (NSString *name in names) {
            SEL selector = NSSelectorFromString(name);
            if (class_getInstanceMethod(modelClass, selector) == NULL) continue;
            MSHookMessageEx(modelClass, selector, (IMP)tcpLayoutSaveHook, (IMP *)&tcpLayoutSaveOrig);
            break;
        }
    }

    // 3) 兜底：5 秒比一次 mtime，系统改了布局而上面那站没挂上时也能跟上。
    //    两次 stat 而已，代价可以忽略；窗口越小，崩溃前丢掉的那点改动越少。
    dispatch_source_t timer =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                               dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    if (timer != NULL) {
        dispatch_source_set_timer(timer,
                                  dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                                  5 * NSEC_PER_SEC,
                                  2 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            __sync_fetch_and_add(&sLayoutTicks, 1);
            NSFileManager *fm = [NSFileManager defaultManager];
            NSDictionary *source = [fm attributesOfItemAtPath:TCPLayoutSourcePath error:NULL];
            NSDictionary *backup = [fm attributesOfItemAtPath:TCPLayoutBackupPath error:NULL];
            NSDate *sourceDate = source[NSFileModificationDate];
            NSDate *backupDate = backup[NSFileModificationDate];
            if (sourceDate != nil &&
                (backupDate == nil || [sourceDate compare:backupDate] == NSOrderedDescending)) {
                TCPLayoutBackup(@"timer");
            }
        });
        dispatch_resume(timer);
    }
}

NSString *TCPLayoutDiagnostics(void) {
    return [NSString stringWithFormat:@"lay{rst=%d,sav=%d,tick=%d,last=%@}",
            (int)sLayoutRestored, (int)sLayoutSaved, (int)sLayoutTicks, sLayoutLast];
}
