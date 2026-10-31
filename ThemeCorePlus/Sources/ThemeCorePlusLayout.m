//
//  ThemeCorePlusLayout.m —— 桌面图标布局的备份与恢复。
//
//  用户 2026-10-31 05:30：「保存图标布局，注销后和 SpringBoard 崩溃后，保留之前 App 桌面图标的布局」。
//  用户 2026-10-31 09:07 再报「图标不保存」—— 0.9.17 的诊断一直是 lay{tick=0}，见下面第 3 条。
//
//  病灶：桌面布局存在 /var/mobile/Library/SpringBoard/IconState.plist，只有 SpringBoard
//  自己保存时才会写盘。注销（sbreload）来得急、崩溃更不用说，那一份可能停在几分钟前 ——
//  下次启动 SpringBoard 拿到的就是旧布局。
//
//  三步，都不碰 UIKit，所以在 dyld 构造函数阶段做是安全的：
//    1) 恢复：SpringBoard 启动最早的时刻（构造函数）比较「系统那份」与「备份」——
//       系统那份读得出来、而且与备份内容一致 → 一个字节都不动（keepsource）；
//       系统那份不见了 / 读不出来 → 用备份回填；备份更新（崩溃前系统没来得及写）→ 用备份回填。
//    2) 系统保存布局时跟着存一份（-saveIconState 一族，哪个存在挂哪个，诊断 site= 里能看到）。
//    3) 5 秒一拍的主线程定时器（0.9.18 修）：
//       · 源文件比备份新 → 跟存；
//       · 活的 SBIconModel 摆位签名变了（用户动过图标）而系统还没写盘 → 主动让它写，再跟存。
//
//  0.9.17 及以前 tick 恒为 0 的原因：dispatch_source_t 在 ARC 下是对象，
//  原来把它存在 TCPLayoutInstall() 的局部变量里 —— 函数返回即被释放，源随之被取消，
//  handler 一次都没跑过（恢复能跑是因为它是同步调用，所以 sav 只有启动那一次）。
//  现在源存在文件级静态变量 sLayoutTimer 里，活到进程结束。
//
//  备份位置：/var/mobile/Library/ThemeCorePlus/IconState.backup.plist
//  （SpringBoard 以 mobile 身份运行，这个目录它写得了；CountdownHUD 也在这个目录下写过请求文件。）
//
#import "ThemeCorePlusHooks.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdlib.h>
#import <string.h>

static NSString *const TCPLayoutSourcePath = @"/var/mobile/Library/SpringBoard/IconState.plist";
static NSString *const TCPLayoutBackupDir  = @"/var/mobile/Library/ThemeCorePlus";
static NSString *const TCPLayoutBackupPath = @"/var/mobile/Library/ThemeCorePlus/IconState.backup.plist";

static volatile int sLayoutRestored = 0;
static volatile int sLayoutSaved = 0;
static volatile int sLayoutTicks = 0;
static volatile int sLayoutForced = 0;
static NSString *sLayoutLast = @"-";

// 挂上的保存站（诊断 site= 用的就是这里）。
#define TCPLayoutMaxSlots 6
typedef struct {
    Class cls;
    SEL sel;
    IMP orig;
} TCPLayoutSlot;
static TCPLayoutSlot sLayoutSlots[TCPLayoutMaxSlots];
static int sLayoutSlotCount = 0;
static NSString *sLayoutSite = @"none";

// 定时器必须由本文件长期持有（见文件头第 3 条）。
static dispatch_source_t sLayoutTimer = NULL;

// 活的模型实例与「走了哪条路拿到它」（0.9.20：保存站捕获 / 控制器 KVC / 扫类表）。
static id sLayoutModel = nil;
static id sLayoutController = nil;      // 找到模型的那只控制器（主动保存时再试一次它）
static NSString *sLayoutModelPath = @"-";
static BOOL TCPLayoutLooksLikeModel(id object);

// 主动保存后要确认系统真写了盘：记下请求那一刻源文件的 mtime，下一拍比对。
static NSDate *sLayoutPendingMtime = nil;
static int sLayoutPendingTick = -1;

// 活的模型摆位签名：只用来判断「用户动过图标」，不做任何写入。
static NSString *sLayoutSignature = nil;

static id TCPLayoutLockObject(void) {
    static id lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSObject alloc] init]; });
    return lock;
}

static void TCPLayoutNote(NSString *text) {
    @synchronized (TCPLayoutLockObject()) {
        sLayoutLast = text ?: @"-";
    }
}

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
        TCPLayoutNote([NSString stringWithFormat:@"saved:%@", why]);
    } else {
        TCPLayoutNote([NSString stringWithFormat:@"savefail:%@", why]);
    }
}

// 源文件比备份新才存（定时器每拍都调，没变就不写盘）。
static void TCPLayoutBackupIfNewer(NSString *why) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *source = [fm attributesOfItemAtPath:TCPLayoutSourcePath error:NULL];
    NSDictionary *backup = [fm attributesOfItemAtPath:TCPLayoutBackupPath error:NULL];
    NSDate *sourceDate = source[NSFileModificationDate];
    NSDate *backupDate = backup[NSFileModificationDate];
    if (sourceDate == nil) return;
    if (backupDate != nil && [sourceDate compare:backupDate] != NSOrderedDescending) return;
    TCPLayoutBackup(why);
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

static BOOL TCPLayoutSameContents(void) {
    NSData *source = [NSData dataWithContentsOfFile:TCPLayoutSourcePath];
    NSData *backup = [NSData dataWithContentsOfFile:TCPLayoutBackupPath];
    if (source == nil || backup == nil) return NO;
    return [source isEqualToData:backup];
}

static NSDate *TCPLayoutSourceMtime(void) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:TCPLayoutSourcePath error:NULL];
    return attributes[NSFileModificationDate];
}

static BOOL TCPLayoutNewer(NSString *path, NSString *than) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDate *a = [fm attributesOfItemAtPath:path error:NULL][NSFileModificationDate];
    NSDate *b = [fm attributesOfItemAtPath:than error:NULL][NSFileModificationDate];
    if (a == nil) return NO;
    if (b == nil) return YES;
    return [a compare:b] == NSOrderedDescending;
}

// 把备份放回原位（只在 SpringBoard 启动最早的时刻调用一次）。
//
// 0.9.17 起不再无条件覆盖（用户 2026-10-31 08:37 报「图标注销没有保存」就是无条件覆盖造成的：
// 旧备份每次启动都把用户改过的摆位糊回去）。0.9.18 加一条对称的：**备份比系统那份新**
// （崩溃前系统没来得及写盘）才用备份回填 —— 内容相同则一个字节都不动。
static void TCPLayoutRestore(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:TCPLayoutBackupPath]) { TCPLayoutNote(@"nobackup"); return; }
    if (!TCPLayoutUsable(TCPLayoutBackupPath)) { TCPLayoutNote(@"backupbad"); return; }

    BOOL hasSource = [fm fileExistsAtPath:TCPLayoutSourcePath];
    if (hasSource && TCPLayoutUsable(TCPLayoutSourcePath)) {
        if (TCPLayoutSameContents()) { TCPLayoutNote(@"keepsource"); return; }
        if (TCPLayoutNewer(TCPLayoutBackupPath, TCPLayoutSourcePath)) {
            if (TCPLayoutCopy(TCPLayoutBackupPath, TCPLayoutSourcePath)) {
                __sync_fetch_and_add(&sLayoutRestored, 1);
                TCPLayoutNote(@"restored:newer");
            } else {
                TCPLayoutNote(@"restorefail");
            }
            return;
        }
        // 系统那份更新 —— 以它为准，顺手把备份刷新成这一份（下次真出事回填的就是最新的）。
        TCPLayoutBackup(@"startup");
        TCPLayoutNote(@"keepsource");
        return;
    }
    if (hasSource) TCPLayoutNote(@"sourcebad");

    if (TCPLayoutCopy(TCPLayoutBackupPath, TCPLayoutSourcePath)) {
        __sync_fetch_and_add(&sLayoutRestored, 1);
        TCPLayoutNote(@"restored");
    } else {
        TCPLayoutNote(@"restorefail");
    }
}

// ── 保存站 ────────────────────────────────────────────────────────────────

static void tcpLayoutSaveHook(id self, SEL _cmd) {
    // 系统自己保存时顺手把模型实例留下：0.9.20 起这是「拿到活模型」最可靠的一条路
    // （控制器那几条在 iOS 16.7 上不保证找得到）。
    if (TCPLayoutLooksLikeModel(self)) {
        sLayoutModel = self;
        sLayoutModelPath = @"hooked:save";
    }
    IMP orig = NULL;
    for (int i = 0; i < sLayoutSlotCount; i++) {
        if (sel_isEqual(sLayoutSlots[i].sel, _cmd)) { orig = sLayoutSlots[i].orig; break; }
    }
    if (orig != NULL) ((void (*)(id, SEL))orig)(self, _cmd);
    TCPLayoutBackup(@"saveIconState");
}

// 挂保存站。构造函数里 SBIconModel / SBIconController 可能还没被 dyld 载进来，
// 所以定时器每一拍都会再试一次，挂上就不再试。
//
// 只挂「零参数」的保存方法：钩子签名是 (id, SEL)，带参数的版本（saveIconStateAndWait: 之类）
// 被系统调用时原参数会被我们丢掉，反而会坏事 —— 那种一律不碰。
static void TCPLayoutHookSave(void) {
    if (sLayoutSlotCount > 0) return;
    NSArray<NSString *> *names = @[ @"saveIconState", @"_saveIconState", @"persistIconState" ];
    NSArray<NSString *> *classNames = @[ @"SBIconModel", @"SBIconController" ];
    NSMutableArray<NSString *> *hooked = [NSMutableArray array];

    for (NSString *className in classNames) {
        Class cls = objc_getClass(className.UTF8String);
        if (cls == Nil) continue;
        for (NSString *name in names) {
            if (sLayoutSlotCount >= TCPLayoutMaxSlots) break;
            SEL sel = NSSelectorFromString(name);
            Method method = class_getInstanceMethod(cls, sel);
            if (method == NULL) continue;
            if (method_getNumberOfArguments(method) != 2) continue;   // self + _cmd，多一个都不挂
            IMP orig = NULL;
            MSHookMessageEx(cls, sel, (IMP)tcpLayoutSaveHook, (IMP *)&orig);
            if (orig == NULL) continue;
            sLayoutSlots[sLayoutSlotCount].cls = cls;
            sLayoutSlots[sLayoutSlotCount].sel = sel;
            sLayoutSlots[sLayoutSlotCount].orig = orig;
            sLayoutSlotCount++;
            [hooked addObject:[NSString stringWithFormat:@"-%@:%@", className, name]];
        }
    }
    sLayoutSite = hooked.count ? [hooked componentsJoinedByString:@","] : @"none";
}

// ── 活的模型 ──────────────────────────────────────────────────────────────
//
// 0.9.19 装机后诊断是 lay{rst=0,sav=2,tick=13,force=0,site=-SBIconModel:_saveIconState,last=nomodel}：
// 定时器活了、保存站也挂上了，但每拍都拿不到模型 —— 原来只试
// `[SBIconController sharedInstance]` + `-iconModel` 这一条路，iOS 16.7 上显然不通
// （要么类名不对，要么这个 getter 换了地方）。改成三条退路 + 自己记录走了哪条：
//   ① 保存站被系统调用时顺手把 self（SBIconModel 实例）留下 —— 最可靠，但要有系统保存才发生；
//   ② 控制器上按 KVC 找 iconModel / model，再退到它的 iconManager 上找；
//   ③ 还不行就扫一遍类表，找名字带 IconController / IconManager 的类试同样的路。
// 找到一次就缓存（进程内是单例），不再每拍重扫。
static BOOL TCPLayoutLooksLikeModel(id object) {
    if (object == nil) return NO;
    return [object respondsToSelector:NSSelectorFromString(@"leafIcons")];
}

// KVC：找不到 key 会抛 NSUndefinedKeyException，必须接住。
static id TCPLayoutValue(id object, NSString *key) {
    if (object == nil || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (NSException *e) {
        return nil;
    }
}

static id TCPLayoutModelFromHolder(id holder, NSString *prefix) {
    for (NSString *key in @[ @"iconModel", @"model" ]) {
        id candidate = TCPLayoutValue(holder, key);
        if (!TCPLayoutLooksLikeModel(candidate)) continue;
        sLayoutModel = candidate;
        sLayoutModelPath = [prefix stringByAppendingString:key];
        return candidate;
    }
    return nil;
}

static id TCPLayoutModelFromController(id controller, NSString *prefix) {
    id model = TCPLayoutModelFromHolder(controller, prefix);
    if (model != nil) return model;
    for (NSString *managerKey in @[ @"iconManager", @"homeScreenIconManager" ]) {
        id manager = TCPLayoutValue(controller, managerKey);
        if (manager == nil) continue;
        model = TCPLayoutModelFromHolder(manager, [prefix stringByAppendingFormat:@"%@.", managerKey]);
        if (model != nil) return model;
    }
    return nil;
}

// 扫类表兜底：只在上面全部失败时跑一次。
static id TCPLayoutModelFromScan(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return nil;
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (classes == NULL) return nil;
    count = objc_getClassList(classes, count);
    id found = nil;
    for (int i = 0; i < count && found == nil; i++) {
        const char *name = class_getName(classes[i]);
        if (name == NULL) continue;
        // 只认 IconController：名字里带 IconManager 的类太多，而且它们的 sharedInstance
        // 未必是现成的单例，乱调有副作用。
        if (strstr(name, "IconController") == NULL) continue;
        SEL shared = NSSelectorFromString(@"sharedInstance");
        if (![(id)classes[i] respondsToSelector:shared]) continue;
        id instance = nil;
        @try {
            instance = ((id (*)(id, SEL))objc_msgSend)((id)classes[i], shared);
        } @catch (NSException *e) { instance = nil; }
        if (instance == nil) continue;
        NSString *prefix = [NSString stringWithFormat:@"scan:%s.", name];
        found = TCPLayoutModelFromController(instance, prefix);
        if (found != nil) sLayoutController = instance;
    }
    free(classes);
    return found;
}

static id TCPLayoutIconModel(void) {
    if (TCPLayoutLooksLikeModel(sLayoutModel)) return sLayoutModel;

    Class controllerClass = objc_getClass("SBIconController");
    if (controllerClass != Nil) {
        for (NSString *selName in @[ @"sharedInstance", @"sharedIconController" ]) {
            SEL sel = NSSelectorFromString(selName);
            if (![(id)controllerClass respondsToSelector:sel]) continue;
            id controller = nil;
            @try {
                controller = ((id (*)(id, SEL))objc_msgSend)((id)controllerClass, sel);
            } @catch (NSException *e) { controller = nil; }
            if (controller == nil) continue;
            id model = TCPLayoutModelFromController(controller, @"controller.");
            if (model != nil) { sLayoutController = controller; return model; }
        }
        sLayoutModelPath = @"none:nocontroller";
    } else {
        sLayoutModelPath = @"none:noclass";
    }

    // 扫类表很贵（SpringBoard 里上万个类），只在没别的路可走时每 30 秒试一次。
    if (sLayoutTicks % 6 == 0) {
        id scanned = TCPLayoutModelFromScan();
        if (scanned != nil) return scanned;
    }
    if ([sLayoutModelPath hasPrefix:@"none:"]) sLayoutModelPath = @"none:noiconmodel";
    return nil;
}

// 摆位签名：每个图标的标识 + 位置。用户动过图标它才会变。
static NSString *TCPLayoutSignature(id model) {
    @try {
        SEL leavesSel = NSSelectorFromString(@"leafIcons");
        if (![model respondsToSelector:leavesSel]) return nil;
        id leaves = ((id (*)(id, SEL))objc_msgSend)(model, leavesSel);
        if (leaves == nil) return nil;

        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (id icon in leaves) {
            NSString *ident = nil;
            for (NSString *key in @[ @"leafIdentifier", @"uniqueIdentifier" ]) {
                @try {
                    id value = [icon valueForKey:key];
                    if ([value isKindOfClass:[NSString class]]) { ident = value; break; }
                } @catch (NSException *e) {}
            }
            if (ident == nil) ident = [icon description] ?: @"?";
            NSString *pos = nil;
            for (NSString *key in @[ @"indexPath", @"gridPosition" ]) {
                @try {
                    id value = [icon valueForKey:key];
                    if (value != nil) { pos = [value description]; break; }
                } @catch (NSException *e) {}
            }
            [parts addObject:[NSString stringWithFormat:@"%@@%@", ident, pos ?: @"-"]];
        }
        [parts sortUsingSelector:@selector(compare:)];
        return [parts componentsJoinedByString:@"|"];
    } @catch (NSException *e) {
        return nil;
    }
}

// 让系统自己把当前布局写进 IconState.plist（走我们挂上的那站，会顺带跟存备份）。
// 只调零参数版本：多一个参数的保存方法（saveIconStateAndWait: 之类）被我们无参调用会丢掉参数。
static BOOL TCPLayoutAskObjectToSave(id object) {
    if (object == nil) return NO;
    for (NSString *name in @[ @"saveIconState", @"_saveIconState", @"persistIconState" ]) {
        SEL sel = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(object_getClass(object), sel);
        if (method == NULL) continue;
        if (method_getNumberOfArguments(method) != 2) continue;
        @try {
            ((void (*)(id, SEL))objc_msgSend)(object, sel);
            return YES;
        } @catch (NSException *e) {}
    }
    return NO;
}

static BOOL TCPLayoutAskSystemToSave(id model) {
    if (TCPLayoutAskObjectToSave(model)) return YES;
    // 有的系统版本把保存挂在控制器上而不是模型上。
    if (TCPLayoutAskObjectToSave(sLayoutController)) return YES;
    Class controllerClass = objc_getClass("SBIconController");
    if (controllerClass == Nil) return NO;
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    if (![controllerClass respondsToSelector:sharedSelector]) return NO;
    id controller = nil;
    @try {
        controller = ((id (*)(id, SEL))objc_msgSend)((id)controllerClass, sharedSelector);
    } @catch (NSException *e) { controller = nil; }
    return TCPLayoutAskObjectToSave(controller);
}

// ── 每 5 秒一拍（主线程） ─────────────────────────────────────────────────

static void TCPLayoutTickBody(void) {
    TCPLayoutHookSave();                 // 类晚到也能补挂

    TCPLayoutBackupIfNewer(@"timer");    // 系统自己写过 → 跟存

    // 上一拍请求过保存：看源文件有没有真被写（0.9.20 新增，避免「以为保存了其实没写」）。
    if (sLayoutPendingMtime != nil) {
        NSDate *now = TCPLayoutSourceMtime();
        if (now != nil && [now compare:sLayoutPendingMtime] == NSOrderedDescending) {
            TCPLayoutNote(@"forced:wrote");
            sLayoutPendingMtime = nil;
        } else if (sLayoutTicks - sLayoutPendingTick > 6) {   // 约 30 秒还没写
            TCPLayoutNote(@"forced:nowrite");
            sLayoutPendingMtime = nil;
        }
    }

    id model = TCPLayoutIconModel();
    if (model == nil) { TCPLayoutNote(@"nomodel"); return; }
    NSString *signature = TCPLayoutSignature(model);
    if (signature == nil) { TCPLayoutNote(@"nosignature"); return; }
    NSString *previous = sLayoutSignature;
    sLayoutSignature = signature;
    if (previous == nil) { TCPLayoutNote(@"baseline"); return; }   // 第一次只记基线
    if ([previous isEqualToString:signature]) return;              // 没动过

    sLayoutPendingMtime = TCPLayoutSourceMtime();
    sLayoutPendingTick = sLayoutTicks;
    if (TCPLayoutAskSystemToSave(model)) {
        __sync_fetch_and_add(&sLayoutForced, 1);
        TCPLayoutNote(@"forced:changed");
        TCPLayoutBackupIfNewer(@"changed");
    } else {
        TCPLayoutNote(@"forcefail");
        sLayoutPendingMtime = nil;
    }
}

// 单独一条轻量诊断键：主诊断（Main.m 那条）只在启动那几轮和面板改设置时才重写，
// 里面嵌的 lay{} 会停在启动那一刻 —— 2026-10-31 09:0x 就被它骗过一次（读到 tick=0
// 无法区分「定时器没跑」和「诊断没刷新」）。所以这里每拍自己写一次：
// 状态（rst/sav/force/site/last）变了立刻写，没变也最多每 12 拍（60 秒）写一次，
// 保证读到的 tick 最多旧一分钟，而且不刷整个主诊断（那要跑普查，太重）。
static void TCPLayoutPublish(void) {
    static NSString *publishedState = nil;
    static int publishedTick = -1;
    NSString *state = [NSString stringWithFormat:@"%d/%d/%d/%@/%@/%@",
                       (int)sLayoutRestored, (int)sLayoutSaved, (int)sLayoutForced,
                       sLayoutSite, sLayoutModelPath, sLayoutLast];
    BOOL changed = (publishedState == nil) || ![publishedState isEqualToString:state];
    if (!changed && publishedTick >= 0 && sLayoutTicks - publishedTick < 12) return;
    publishedState = [state copy];
    publishedTick = (int)sLayoutTicks;

    NSString *text = TCPLayoutDiagnostics();
    CFPreferencesSetAppValue(CFSTR("ThemeCorePlusLayout"),
                             (__bridge CFPropertyListRef)text,
                             kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
}

static void TCPLayoutTick(void) {
    __sync_fetch_and_add(&sLayoutTicks, 1);
    TCPLayoutTickBody();
    TCPLayoutPublish();                  // 每拍（或状态一变）现写，tick 才可信
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

    // 2) 系统保存布局后同步备份（类没载进来也没关系，定时器每拍补挂）。
    TCPLayoutHookSave();

    // 3) 5 秒一拍：mtime 兜底 + 「动过图标就主动让系统写盘」。
    //    主队列上跑，所以碰 SBIconModel 是安全的；第一次触发在 5 秒后，不拖慢启动。
    if (sLayoutTimer == NULL) {
        sLayoutTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                             dispatch_get_main_queue());
        if (sLayoutTimer != NULL) {
            dispatch_source_set_timer(sLayoutTimer,
                                      dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                                      5 * NSEC_PER_SEC,
                                      1 * NSEC_PER_SEC);
            dispatch_source_set_event_handler(sLayoutTimer, ^{
                TCPLayoutTick();
            });
            dispatch_resume(sLayoutTimer);
        }
    }

    // 构造函数阶段就把这条轻量诊断写出去：等第一拍要 5 秒，中间读诊断也不该是空的。
    TCPLayoutPublish();
}

NSString *TCPLayoutDiagnostics(void) {
    return [NSString stringWithFormat:@"lay{rst=%d,sav=%d,tick=%d,force=%d,site=%@,model=%@,last=%@}",
            (int)sLayoutRestored, (int)sLayoutSaved, (int)sLayoutTicks, (int)sLayoutForced,
            sLayoutSite, sLayoutModelPath, sLayoutLast];
}
