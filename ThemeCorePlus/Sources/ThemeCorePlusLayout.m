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
//    2) 系统保存布局时跟着存一份（保存站；诊断 site= 里能看到挂了哪些）。
//    3) 5 秒一拍的主线程定时器（0.9.18 修）：
//       · 源文件比备份新 → 跟存；
//       · 活的模型摆位签名变了（用户动过图标）而系统还没写盘 → 主动让它写，再跟存。
//
//  0.9.17 及以前 tick 恒为 0 的原因：dispatch_source_t 在 ARC 下是对象，
//  原来把它存在 TCPLayoutInstall() 的局部变量里 —— 函数返回即被释放，源随之被取消，
//  handler 一次都没跑过（恢复能跑是因为它是同步调用，所以 sav 只有启动那一次）。
//  现在源存在文件级静态变量 sLayoutTimer 里，活到进程结束。
//
//  0.9.19 → 0.9.20 的真病灶（诊断 lay{... last=nomodel, sav=1}）：
//  上一版靠猜 `[SBIconController sharedInstance]` → `-iconModel` 拿活模型，iOS 16.7 上不通；
//  而保存站虽然挂上了（sav=1 说明它确实被系统调用过一次），却用「respondsToSelector:leafIcons」
//  来判断「self 是不是模型」，于是 self 是模型也认不出来，模型永远拿不到。
//  0.9.20 改成**不猜**：
//    · 运行时枚举 SBIconModel 家族（及其子类）**自己声明的**方法（class_copyMethodList），
//      把「零参数 + 名字含 IconState 且含 save/persist/write/store」的判成保存站，
//      把「零参数 + 名字是 leafIcons / allIcons / icons 之类」的判成图标列表站；
//    · 两类站都挂（各挂各的槽），从站的 self 直接拿到**活的模型实例**和**活的图标数组**；
//    · 「是不是模型」改成「类名链里有没有 IconModel」或「响应 leafIcons」，不再是唯一判据。
//  签名（谁动了图标）直接用图标列表站返回的数组算，不再自己再去问模型。
//
//  ── 0.9.22：0.9.21 把 SpringBoard 打进安全模式（连崩 5 次，consecutiveCrashCount=5）──
//  崩溃栈：dyld 构造函数 → TCPLayoutInstall() → TCPLayoutHookSave() → TCPLayoutCandidateClasses()
//          → `objc_getClassList` 枚举出的某个类 → `-[NSObject isSubclassOfClass:]`。
//  病灶：构造函数里枚举**全进程所有类**，并对每一个（包括 dyld 还没 realize 的根类，
//        崩时寄存器里是 ISOverlayEmbossedFolder）发消息。构造函数阶段 UIKit/Foundation
//        还没就绪，消息一进转发就 SIGTRAP，dyld 直接 abort —— 连崩 5 次进安全模式。
//  0.9.22 四条修法（AGENTS.md「构造函数硬规矩」）：
//    ① 判类关系一律用 C 函数 class_getSuperclass() 往上走，绝不对运行时枚举出来的类发消息；
//    ② 枚举类 + 挂站（重活）搬出构造函数，交给主队列第一拍（2 秒后）；
//    ③ 重活前写启动护栏文件，跑完删；下次启动还在 = 上次崩在这里 → 整段跳过（safeskip=1）；
//    ④ 挂站前用 method_getNumberOfArguments + method_getTypeEncoding 验真实签名（v@:），
//       宁可一个都不挂，也不挂错。
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
// 启动护栏（0.9.22 起）：重活前写，跑完删。下次启动它还在 = 上次崩在重活里。
static NSString *const TCPLayoutGuardPath  = @"/var/mobile/Library/ThemeCorePlus/.tcp-launch-guard";

static volatile int sLayoutRestored = 0;
static volatile int sLayoutSaved = 0;
static volatile int sLayoutTicks = 0;
static volatile int sLayoutForced = 0;
static volatile int sLayoutSafeSkip = 0;       // 上次崩在重活里 → 这次整段跳过（诊断 safeskip=1）
static volatile int sLayoutEnumRan = 0;        // 类枚举真的跑过一遍（护栏可以撤了）
static volatile int sLayoutGuardCleared = 0;
static volatile int sLayoutHooked = 0;         // 本进程真正挂上的站数（区分 prefs 里的历史残留）
static volatile int sLayoutSaves = 0;          // 本进程保存站被系统调用过几次
static NSString *sLayoutLast = @"-";

// ── 保存站 / 图标列表站（一站一槽：每个 (类, 选择器) 一格，绝不按 self 的类反查总表）──
#define TCPLayoutMaxSlots 48
enum { TCPLayoutKindSave = 0, TCPLayoutKindLeaf = 1 };
typedef struct {
    Class cls;
    SEL sel;
    IMP orig;
    int kind;
} TCPLayoutSlot;
static TCPLayoutSlot sLayoutSlots[TCPLayoutMaxSlots];
static int sLayoutSlotCount = 0;
static NSString *sLayoutSite = @"none";      // 挂了哪些站（诊断 site=）
static NSString *sLayoutProbe = @"-";        // 枚举到的候选方法（诊断 probe=）

// 定时器必须由本文件长期持有（见文件头第 3 条）。
static dispatch_source_t sLayoutTimer = NULL;

// 活的模型实例、活的图标数组与「走了哪条路拿到它」。
static id sLayoutModel = nil;                // SBIconModel（或其子类）的实例
static id sLayoutLeaves = nil;               // 图标列表（图标列表站返回的数组）
static NSString *sLayoutModelPath = @"-";    // hooked:save / hooked:leaf / none:…

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

// ── 站的工具 ──────────────────────────────────────────────────────────────

// 类的继承链上有没有名字含 needle 的类（IconModel 家族判定用）。
static BOOL TCPLayoutClassChainHas(Class cls, const char *needle) {
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        const char *n = class_getName(c);
        if (n != NULL && strstr(n, needle) != NULL) return YES;
    }
    return NO;
}

// 「这个对象是不是图标模型」：类名链里有 IconModel，或者它响应 leafIcons。
static BOOL TCPLayoutLooksLikeModel(id object) {
    if (object == nil) return NO;
    if (TCPLayoutClassChainHas(object_getClass(object), "IconModel")) return YES;
    return [object respondsToSelector:NSSelectorFromString(@"leafIcons")];
}

// 一个方法的原 IMP：按 self 的类链从具体到泛型找同一格（一站一槽，不查总表）。
static IMP TCPLayoutOriginalFor(id self, SEL sel) {
    for (Class c = object_getClass(self); c != Nil; c = class_getSuperclass(c)) {
        for (int i = 0; i < sLayoutSlotCount; i++) {
            if (sLayoutSlots[i].cls == c && sel_isEqual(sLayoutSlots[i].sel, sel)) {
                return sLayoutSlots[i].orig;
            }
        }
    }
    return NULL;
}

// 名字判据：保存站（零参数）——含 IconState，且含 save/persist/write/store。
static BOOL TCPLayoutIsSaveName(const char *name) {
    if (name == NULL) return NO;
    char lower[128];
    size_t n = strlen(name);
    if (n >= sizeof(lower)) n = sizeof(lower) - 1;
    for (size_t i = 0; i < n; i++) {
        char c = name[i];
        lower[i] = (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : c;
    }
    lower[n] = '\0';
    if (strstr(lower, "iconstate") == NULL) return NO;
    if (strstr(lower, "save") != NULL) return YES;
    if (strstr(lower, "persist") != NULL) return YES;
    if (strstr(lower, "write") != NULL) return YES;
    if (strstr(lower, "store") != NULL) return YES;
    return NO;
}

// 名字判据：图标列表 getter（零参数）——leafIcons / allIcons / icons 之类。
static BOOL TCPLayoutIsLeafName(const char *name) {
    if (name == NULL) return NO;
    static const char *candidates[] = { "leafIcons", "allLeafIcons", "allIcons", "icons", "iconList" };
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        if (strcmp(name, candidates[i]) == 0) return YES;
    }
    return NO;
}

// 判类关系一律用 C 函数沿父类链往上走 —— **绝不对运行时枚举出来的类发消息**。
// 0.9.21 就是在构造函数里对 objc_getClassList 枚举出的每个类发 -isSubclassOfClass:，
// 撞上还没 realize 的根类（崩时是 ISOverlayEmbossedFolder）→ SIGTRAP → 安全模式。
static BOOL TCPLayoutClassDescendsFrom(Class cls, Class base) {
    if (cls == Nil || base == Nil) return NO;
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        if (c == base) return YES;
    }
    return NO;
}

// 挂站前先验真实签名：零参数（self + _cmd）且返回 void。
// 带参数的保存方法（saveIconStateAndWait: 之类）被我们无参调用会丢参数，把系统写盘弄坏；
// 返回值不是 void 的也不碰 —— 宁可一个都不挂。
static BOOL TCPLayoutSignatureHookable(Method m) {
    if (m == NULL) return NO;
    if (method_getNumberOfArguments(m) != 2) return NO;
    const char *enc = method_getTypeEncoding(m);
    if (enc == NULL) return NO;
    if (enc[0] != 'v') return NO;                 // 返回类型必须是 void
    if (strchr(enc, '@') == NULL) return NO;      // 必须有 self
    if (strchr(enc, ':') == NULL) return NO;      // 必须有 _cmd
    return YES;
}

// ── 站 ────────────────────────────────────────────────────────────────────

static void tcpLayoutSaveHook(id self, SEL _cmd) {
    // 系统自己保存时顺手把模型实例留下：站的 self 就是活的 SBIconModel。
    if (TCPLayoutLooksLikeModel(self)) {
        sLayoutModel = self;
        sLayoutModelPath = @"hooked:save";
    }
    IMP orig = TCPLayoutOriginalFor(self, _cmd);
    if (orig != NULL) ((void (*)(id, SEL))orig)(self, _cmd);
    TCPLayoutBackup(@"saveIconState");
}

static id tcpLayoutLeafHook(id self, SEL _cmd) {
    IMP orig = TCPLayoutOriginalFor(self, _cmd);
    id result = nil;
    if (orig != NULL) result = ((id (*)(id, SEL))orig)(self, _cmd);
    // 图标列表站的 self 就是模型，result 就是活的图标数组 —— 摆位签名直接用它算。
    if (TCPLayoutLooksLikeModel(self)) {
        sLayoutModel = self;
        sLayoutModelPath = @"hooked:leaf";
        if (result != nil) sLayoutLeaves = result;
    }
    return result;
}

// ── 挂站：运行时枚举 SBIconModel 家族自己声明的零参数方法 ──────────────────

// 候选类：SBIconModel 及其子类（SBHomeScreenIconModel 之类）。
static NSArray<Class> *TCPLayoutCandidateClasses(void) {
    NSMutableArray *out = [NSMutableArray array];
    Class base = objc_getClass("SBIconModel");
    if (base == Nil) {
        sLayoutProbe = @"base=nil";       // 类根本没进 dyld：这一拍什么也挂不了
        return out;
    }
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        sLayoutProbe = @"classlist=0";
        return out;
    }
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (classes == NULL) return out;
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count; i++) {
        Class c = classes[i];
        if (c == Nil) continue;
        if (class_isMetaClass(c)) continue;
        // 只用 C 函数往上走父类链，绝不发消息（见 TCPLayoutClassDescendsFrom 的注释）。
        if (TCPLayoutClassDescendsFrom(c, base)) [out addObject:c];
    }
    free(classes);
    if (out.count == 0) {
        // 类表里有 SBIconModel 这个名字，却没有任何类沿父链走得到它 —— 记下来，
        // 免得「挂不上」只有 noinstance 一个症状、看不出是枚举还是挂站的问题。
        sLayoutProbe = [NSString stringWithFormat:@"base=%@,scanned=%d,hit=0",
                        NSStringFromClass(base), count];
    }
    return out;
}

// 宽名单：任何名字里带这些词之一的零参数方法都值得看一眼。
// 0.9.24 之前的判据要求「同时含 iconstate 且含 save/persist/write/store」，
// 一旦系统那个方法叫别的名字（例如 -_writeIconStateData、-persistIconState:. 之外的形式）
// 就会一个都匹配不上，而 probe 又只在匹配成功时写 —— 于是诊断只剩一个 "-"，什么都看不出来。
static BOOL TCPLayoutIsInterestingName(const char *name) {
    if (name == NULL) return NO;
    char lower[160];
    size_t n = strlen(name);
    if (n == 0) return NO;
    if (n >= sizeof(lower)) n = sizeof(lower) - 1;
    for (size_t i = 0; i < n; i++) {
        char c = name[i];
        lower[i] = (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : c;
    }
    lower[n] = '\0';
    static const char *words[] = { "iconstate", "saveicon", "persisticon", "writeicon",
                                   "storeicon", "flush", "syncicon", "commit" };
    for (size_t i = 0; i < sizeof(words) / sizeof(words[0]); i++) {
        if (strstr(lower, words[i]) != NULL) return YES;
    }
    return NO;
}

// 控制器类：SBIconController 及其子类。iOS 16 上写盘很可能挂在控制器而不是模型上，
// 只枚举 SBIconModel 家族会把这条路整条漏掉。
static NSArray<Class> *TCPLayoutControllerClasses(void) {
    NSMutableArray *out = [NSMutableArray array];
    Class base = objc_getClass("SBIconController");
    if (base == Nil) return out;
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return out;
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (classes == NULL) return out;
    count = objc_getClassList(classes, count);
    int scan = count;
    for (int i = 0; i < scan; i++) {
        Class c = classes[i];
        if (c == Nil) continue;
        if (class_isMetaClass(c)) continue;
        if (TCPLayoutClassDescendsFrom(c, base)) [out addObject:c];
    }
    free(classes);
    return out;
}

// 挂站。构造函数里 SBIconModel 可能还没被 dyld 载进来，所以定时器每一拍都会再试一次，
// 挂上就不再重挂（同一 (类,选择器) 只挂一次）。
static void TCPLayoutHookSave(void) {
    NSArray<Class> *modelClasses = TCPLayoutCandidateClasses();
    NSArray<Class> *ctrlClasses = TCPLayoutControllerClasses();
    sLayoutEnumRan = 1;                  // 类枚举真跑过了：启动护栏可以撤

    NSMutableArray<Class> *classes = [NSMutableArray array];
    [classes addObjectsFromArray:modelClasses];
    [classes addObjectsFromArray:ctrlClasses];

    NSMutableArray<NSString *> *hooked = [NSMutableArray array];
    NSMutableArray<NSString *> *skipped = [NSMutableArray array];
    NSMutableArray<NSString *> *probe = [NSMutableArray array];

    // probe 一律先写枚举事实（0.9.25 起）：以前只有「挂上/跳过」时才写，
    // 于是「找到了类但一个名字都没匹配上」会退化成 probe=-，看起来像什么都没枚举到。
    [probe addObject:[NSString stringWithFormat:@"cand[model=%lu,ctrl=%lu]",
                      (unsigned long)modelClasses.count, (unsigned long)ctrlClasses.count]];

    for (Class cls in classes) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        if (methods == NULL) { [probe addObject:[NSString stringWithFormat:@"%@:0", NSStringFromClass(cls)]]; continue; }
        NSMutableArray<NSString *> *saveNames = [NSMutableArray array];
        NSMutableArray<NSString *> *leafNames = [NSMutableArray array];
        // 宽名单：名字像但判据没命中的，照样记进 probe，用来定下一次该认哪些名字。
        NSMutableArray<NSString *> *nearNames = [NSMutableArray array];

        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            const char *name = sel_getName(sel);
            if (name == NULL) continue;

            int kind = -1;
            if (TCPLayoutIsSaveName(name)) kind = TCPLayoutKindSave;
            else if (TCPLayoutIsLeafName(name)) kind = TCPLayoutKindLeaf;
            if (kind < 0) {
                // 判据没命中，但名字像：记下来（限 8 条），下一版就知道真实名字。
                if (nearNames.count < 8 && TCPLayoutIsInterestingName(name)) {
                    NSString *nm = [NSString stringWithUTF8String:name] ?: @"?";
                    BOOL zeroArg = (method_getNumberOfArguments(methods[i]) == 2);
                    [nearNames addObject:zeroArg ? nm : [nm stringByAppendingString:@":"]];
                }
                continue;
            }

            // 铁律：只挂零参数、返回 void 的方法（隐式 self + _cmd 两个参数）。
            // 带参数的保存方法（saveIconStateAndWait: 之类）被我们无参调用会丢掉参数，
            // 把系统写盘弄坏 —— 一律不碰。0.9.22 起连零参数也要验真实签名
            // （method_getTypeEncoding），宁可一个都不挂。
            if (!TCPLayoutSignatureHookable(methods[i])) {
                if (skipped.count < 6) {
                    [skipped addObject:[NSString stringWithFormat:@"%@:%s(%s)",
                                        NSStringFromClass(cls), name,
                                        method_getTypeEncoding(methods[i]) ?: "?"]];
                }
                continue;
            }

            // 同一 (类,选择器) 只挂一次。
            BOOL already = NO;
            for (int k = 0; k < sLayoutSlotCount; k++) {
                if (sLayoutSlots[k].cls == cls && sel_isEqual(sLayoutSlots[k].sel, sel)) { already = YES; break; }
            }
            if (already) continue;
            if (sLayoutSlotCount >= TCPLayoutMaxSlots) break;

            IMP orig = NULL;
            MSHookMessageEx(cls, sel,
                            kind == TCPLayoutKindSave ? (IMP)tcpLayoutSaveHook : (IMP)tcpLayoutLeafHook,
                            (IMP *)&orig);
            if (orig == NULL) continue;

            sLayoutSlots[sLayoutSlotCount].cls = cls;
            sLayoutSlots[sLayoutSlotCount].sel = sel;
            sLayoutSlots[sLayoutSlotCount].orig = orig;
            sLayoutSlots[sLayoutSlotCount].kind = kind;
            sLayoutSlotCount++;
            __sync_fetch_and_add(&sLayoutHooked, 1);   // 本进程真挂上的站数

            NSString *entry = [NSString stringWithFormat:@"-%@:%@",
                               NSStringFromClass(cls), NSStringFromSelector(sel)];
            [hooked addObject:entry];
            [probe addObject:[NSString stringWithFormat:@"%@{%@:%@}",
                              NSStringFromClass(cls),
                              kind == TCPLayoutKindSave ? @"save" : @"leaf",
                              NSStringFromSelector(sel)]];
            if (kind == TCPLayoutKindSave) [saveNames addObject:NSStringFromSelector(sel)];
            else [leafNames addObject:NSStringFromSelector(sel)];
        }
        free(methods);

        if (saveNames.count > 0 || leafNames.count > 0) {
            [probe addObject:[NSString stringWithFormat:@"%@[%@]",
                              NSStringFromClass(cls),
                              [[saveNames arrayByAddingObjectsFromArray:leafNames]
                               componentsJoinedByString:@","]]];
        }
        if (nearNames.count > 0) {
            [probe addObject:[NSString stringWithFormat:@"near(%@)[%@]",
                              NSStringFromClass(cls),
                              [nearNames componentsJoinedByString:@","]]];
        }
    }

    if (skipped.count > 0) {
        [probe addObject:[NSString stringWithFormat:@"skip[%@]",
                          [skipped componentsJoinedByString:@","]]];
    }
    if (hooked.count > 0) sLayoutSite = [hooked componentsJoinedByString:@","];
    // 无条件写：即便一个都没挂上、名字一个都没命中，也要留下 cand[] 与 near[]。
    sLayoutProbe = [probe componentsJoinedByString:@";"];
}

// 模型身上有没有零参数保存方法（挂着的那几站）。
static BOOL TCPLayoutHasSaveStationFor(id model) {
    if (model == nil) return NO;
    for (int i = 0; i < sLayoutSlotCount; i++) {
        if (sLayoutSlots[i].kind != TCPLayoutKindSave) continue;
        if (![model isKindOfClass:sLayoutSlots[i].cls]) continue;
        if (!sel_isEqual(sLayoutSlots[i].sel, NSSelectorFromString(@"saveIconState")) &&
            sLayoutSlots[i].orig == NULL) continue;
        return YES;
    }
    return NO;
}

// ── 摆位签名 ──────────────────────────────────────────────────────────────

static NSString *TCPLayoutSignatureOfLeaves(id leaves) {
    if (leaves == nil) return nil;
    if (![leaves respondsToSelector:NSSelectorFromString(@"count")]) return nil;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    @try {
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

// 图标数组：优先用图标列表站返回的（那是活的），否则自己问模型要。
static id TCPLayoutCurrentLeaves(id model) {
    if (sLayoutLeaves != nil) return sLayoutLeaves;
    if (model == nil) return nil;
    SEL sel = NSSelectorFromString(@"leafIcons");
    if (![model respondsToSelector:sel]) return nil;
    @try {
        id leaves = ((id (*)(id, SEL))objc_msgSend)(model, sel);
        if (leaves != nil) sLayoutLeaves = leaves;
        return leaves;
    } @catch (NSException *e) {
        return nil;
    }
}

// ── 主动保存 ──────────────────────────────────────────────────────────────

// 让系统自己把当前布局写进 IconState.plist。
// 只调零参数版本：多一个参数的保存方法（saveIconStateAndWait: 之类）被我们无参调用会丢掉参数。
static BOOL TCPLayoutAskSystemToSave(id model) {
    if (model == nil) return NO;
    for (int i = 0; i < sLayoutSlotCount; i++) {
        if (sLayoutSlots[i].kind != TCPLayoutKindSave) continue;
        if (![model isKindOfClass:sLayoutSlots[i].cls]) continue;
        IMP orig = sLayoutSlots[i].orig;
        if (orig == NULL) continue;
        @try {
            ((void (*)(id, SEL))orig)(model, sLayoutSlots[i].sel);
            return YES;
        } @catch (NSException *e) {
            continue;
        }
    }
    return NO;
}

// ── 每 5 秒一拍（主线程） ─────────────────────────────────────────────────

static void TCPLayoutTickBody(void) {
    TCPLayoutHookSave();                 // 类晚到也能补挂

    TCPLayoutBackupIfNewer(@"timer");    // 系统自己写过 → 跟存

    // 上一拍请求过保存：看源文件有没有真被写（避免「以为保存了其实没写」）。
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

    id model = sLayoutModel;
    if (!TCPLayoutLooksLikeModel(model)) {
        if (objc_getClass("SBIconModel") == Nil) { TCPLayoutNote(@"noclass"); return; }
        if (sLayoutModel == nil) { TCPLayoutNote(@"noinstance"); return; }
    }

    id leaves = TCPLayoutCurrentLeaves(model);
    if (leaves == nil) { TCPLayoutNote(@"nosignature"); return; }
    NSString *signature = TCPLayoutSignatureOfLeaves(leaves);
    if (signature == nil) { TCPLayoutNote(@"nosignature"); return; }
    NSString *previous = sLayoutSignature;
    sLayoutSignature = signature;
    if (previous == nil) { TCPLayoutNote(@"baseline"); return; }   // 第一次只记基线
    if ([previous isEqualToString:signature]) return;              // 没动过

    if (!TCPLayoutHasSaveStationFor(model)) { TCPLayoutNote(@"nosavemethod"); return; }

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
// 状态（rst/sav/force/site/model/last）变了立刻写，没变也最多每 12 拍（60 秒）写一次，
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

    // 重活（枚举类 + 挂站）已经跑完了 → 撤掉启动护栏文件。
    // 类迟迟不出现（枚举根本没跑）也在 24 拍（约 2 分钟）后撤，免得护栏永久留着把功能锁死。
    if (!sLayoutGuardCleared && (sLayoutEnumRan || sLayoutTicks >= 24)) {
        sLayoutGuardCleared = 1;
        [[NSFileManager defaultManager] removeItemAtPath:TCPLayoutGuardPath error:NULL];
    }
}

void TCPLayoutInstall(void) {
    static BOOL installed = NO;
    if (installed) return;
    installed = YES;

    // 只在 SpringBoard 里做：别的进程（设置、Spotlight）没有 IconState 这件事。
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

    // 0) 启动护栏（0.9.22 起）：重活之前先写一个文件，重活跑完就删掉（见 TCPLayoutTick）。
    //    下次启动它还在 = 上次就崩在这段重活里 → 整段跳过（诊断 safeskip=1），
    //    宁可布局功能不生效，也绝不再把 SpringBoard 送进安全模式。
    //    恢复干净：删掉 TCPLayoutGuardPath 这一个文件，下次启动就会重新尝试。
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:TCPLayoutGuardPath]) {
        sLayoutSafeSkip = 1;
        TCPLayoutNote(@"safeskip");
        TCPLayoutPublish();
        return;
    }
    [fm createDirectoryAtPath:TCPLayoutBackupDir withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm createFileAtPath:TCPLayoutGuardPath contents:[NSData data] attributes:nil];

    // 1) 恢复。构造函数阶段，早于 SBIconModel 读布局；只做文件读写，不碰任何运行时类。
    TCPLayoutRestore();

    // 2) 系统保存布局后同步备份 —— 挂站这一步**不再在构造函数里做**。
    //    ⚠️ 0.9.21 就是死在这里：构造函数里调 TCPLayoutHookSave()，它枚举全进程所有类并
    //    逐个发 -isSubclassOfClass:（枚举到还没 realize 的根类就 SIGTRAP），连崩 5 次进安全模式。
    //    0.9.22 起交给主队列第一拍（2 秒后），构造函数里只留纯赋值与定时器创建。

    // 3) 5 秒一拍：第一拍（2 秒后）枚举类 + 挂站，之后每拍 mtime 兜底 + 「动过图标就让系统写盘」。
    //    主队列上跑，所以碰 SBIconModel 是安全的；不拖慢启动。
    if (sLayoutTimer == NULL) {
        sLayoutTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                             dispatch_get_main_queue());
        if (sLayoutTimer != NULL) {
            dispatch_source_set_timer(sLayoutTimer,
                                      dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
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
    return [NSString stringWithFormat:@"lay{rst=%d,sav=%d,tick=%d,force=%d,site=%@,model=%@,last=%@,probe=%@,safeskip=%d,hooked=%d}",
            (int)sLayoutRestored, (int)sLayoutSaved, (int)sLayoutTicks, (int)sLayoutForced,
            sLayoutSite, sLayoutModelPath, sLayoutLast, sLayoutProbe, (int)sLayoutSafeSkip,
            (int)sLayoutHooked];
}
