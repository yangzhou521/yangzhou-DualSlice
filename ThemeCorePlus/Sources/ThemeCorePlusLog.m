//
//  ThemeCorePlusLog.m —— 运行日志的实现（三份：内存环 / 偏好键 / 文本文件）。
//
//  线程与性能：日志可能在任意线程、每秒上百次地被调（显示层站点），所以
//   · 一把 pthread 互斥锁护住缓冲，锁内只做内存操作与（最多每 2 秒一次的）偏好读；
//   · 写偏好键节流 3 秒、写文件节流 1 秒，都不在锁里做 IO；
//   · 相同内容 1 秒内合并成「×N」，一个高频站点也不会把 200 行的环刷满。
//  绝不在持有锁时调用会打日志的函数（偏好读不会打日志，所以是安全的）。
//
#import "ThemeCorePlusLog.h"
#import "ThemeCorePlusKeys.h"
#import "ThemeCorePlusPreferences.h"
#import "ThemeCorePlusVersion.h"

#import <pthread.h>
#import <unistd.h>

// 日志目录：/var/mobile/… 是**系统路径**（两种引导下都是真实路径），不经过隐根转换，
// 与偏好域同一处（作者素材那种引导根路径才要 ApelinBootstrapPath()）。
// SpringBoard 本身就是 mobile 身份，写这里没有 sandbox 问题；别的进程万一被沙箱挡住，
// 就退到自己的临时目录 —— 反正主通道（偏好键）不受影响。
static NSString * const TCPLogDirectory = @"/var/mobile/Library/Preferences/themecoreplus-logs";

static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableArray<NSString *> *gLines;      // 完整行（含时间戳），最多 TCPLogMaxLines
static NSString *gLastMessage;                  // 上一行的正文（去重用）
static NSTimeInterval gLastMessageTime;         // 上一行的时间
static NSUInteger gRepeat;                      // 上面那行被合并的次数
static NSTimeInterval gLastPublish;             // 上次写偏好键的时间
static NSTimeInterval gLastFileWrite;           // 上次写文件的时间
static NSString *gFilePath;                     // 本进程的日志文件路径
static BOOL gPathResolved;
static BOOL gEnabled = YES;                     // 偏好开关的缓存（最多每 2 秒重读）
static NSTimeInterval gEnabledCheckedAt;

#pragma mark - 小工具

// 进程名做文件名/标题用：只留字母数字和 . - _，别的字符（中文、空格）一律丢掉。
static NSString *TCPLogProcessTag(void) {
    static NSString *tag = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *name = [NSProcessInfo processInfo].processName ?: @"proc";
        NSMutableString *safe = [NSMutableString stringWithCapacity:name.length];
        for (NSUInteger i = 0; i < name.length; i++) {
            unichar c = [name characterAtIndex:i];
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_') {
                [safe appendFormat:@"%C", c];
            }
        }
        tag = safe.length > 0 ? [safe copy] : @"proc";
    });
    return tag;
}

static NSDateFormatter *TCPLogFormatter(NSString *format) {
    // 两种格式各缓存一份：locales 固定成 POSIX，日志不受设备语言影响。
    static NSDateFormatter *shortFormatter = nil;
    static NSDateFormatter *longFormatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shortFormatter = [[NSDateFormatter alloc] init];
        shortFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        shortFormatter.dateFormat = @"HH:mm:ss.SSS";
        longFormatter = [[NSDateFormatter alloc] init];
        longFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        longFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    return [format isEqualToString:@"long"] ? longFormatter : shortFormatter;
}

static NSString *TCPLogStamp(void) {
    return [TCPLogFormatter(@"short") stringFromDate:[NSDate date]];
}

#pragma mark - 开关与路径（都要在锁内被调用，所以分成 Locked 版本）

static BOOL TCPLogEnabledLocked(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gEnabledCheckedAt == 0 || now - gEnabledCheckedAt > 2.0) {
        gEnabledCheckedAt = now;
        NSDictionary *values = TCPReadPreferences();
        id value = values[TCPKeyLogEnabled];
        gEnabled = [value isKindOfClass:[NSNumber class]] ? [(NSNumber *)value boolValue] : YES;
    }
    return gEnabled;
}

BOOL TCPLogEnabled(void) {
    pthread_mutex_lock(&gLock);
    BOOL enabled = TCPLogEnabledLocked();
    pthread_mutex_unlock(&gLock);
    return enabled;
}

// 文件太多就按修改时间删旧的（只在首次解析路径时做一次，不是每次写盘都扫目录）。
static void TCPLogPruneDirectory(NSString *dir, NSString *keepPath) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [manager contentsOfDirectoryAtPath:dir error:NULL];
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name.pathExtension isEqualToString:@"log"]) {
            [logs addObject:[dir stringByAppendingPathComponent:name]];
        }
    }
    if (logs.count <= 16) return;
    [logs sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDate *left = [manager attributesOfItemAtPath:a error:NULL][NSFileModificationDate];
        NSDate *right = [manager attributesOfItemAtPath:b error:NULL][NSFileModificationDate];
        return [(left ?: [NSDate distantPast]) compare:(right ?: [NSDate distantPast])];
    }];
    while (logs.count > 16) {
        NSString *oldest = logs.firstObject;
        if (![oldest isEqualToString:keepPath]) {
            [manager removeItemAtPath:oldest error:NULL];
        }
        [logs removeObjectAtIndex:0];
    }
}

static NSString *TCPLogFilePathLocked(void) {
    if (gPathResolved) return gFilePath;
    gPathResolved = YES;

    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *dir = TCPLogDirectory;
    [manager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    if (![manager isWritableFileAtPath:dir]) {
        dir = NSTemporaryDirectory();   // 沙箱挡住时的兜底：至少这个进程自己还能留一份
    }
    if (dir.length == 0) return nil;

    NSString *path = [dir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@-%d.log", TCPLogProcessTag(), (int)getpid()]];
    if (![dir isEqualToString:NSTemporaryDirectory()]) {
        TCPLogPruneDirectory(dir, path);
    }
    gFilePath = path;
    return gFilePath;
}

NSString *TCPLogFilePath(void) {
    pthread_mutex_lock(&gLock);
    NSString *path = TCPLogFilePathLocked();
    pthread_mutex_unlock(&gLock);
    return path;
}

#pragma mark - 组文本

// 头部：谁写的、什么时候、什么版本 —— 面板里一份份日志贴在一起时靠它分辨。
static NSString *TCPLogHeaderLocked(void) {
    return [NSString stringWithFormat:@"%@[%d] v%@ %@",
            TCPLogProcessTag(), (int)getpid(), TCP_VERSION,
            [TCPLogFormatter(@"long") stringFromDate:[NSDate date]]];
}

// 头部 + 尾部最多 maxLines 行。偏好键能放多大无所谓，但别让它无限制地长。
static NSString *TCPLogTextLocked(NSUInteger maxLines, NSUInteger byteLimit) {
    NSUInteger count = MIN(gLines.count, maxLines);
    NSString *body = @"";
    if (count > 0) {
        NSArray<NSString *> *tail =
            [gLines subarrayWithRange:NSMakeRange(gLines.count - count, count)];
        body = [tail componentsJoinedByString:@"\n"];
    }
    NSString *text = [NSString stringWithFormat:@"%@\n%@", TCPLogHeaderLocked(), body];
    if (text.length > byteLimit) {
        // 从后往前留：最新的最要紧，头一行也留着（它说明这是哪个进程的日志）。
        NSRange keep = NSMakeRange(text.length - byteLimit, byteLimit);
        text = [NSString stringWithFormat:@"%@\n…（前面的行被截掉）\n%@",
                TCPLogHeaderLocked(), [text substringWithRange:keep]];
    }
    return text;
}

static NSString *TCPLogTextForDomain(NSString *domain, NSUInteger maxLines) {
    CFStringRef key = (__bridge CFStringRef)TCPKeyRuntimeLog;
    CFStringRef ref = CFPreferencesCopyAppValue(key,
                                                domain.length > 0
                                                    ? (__bridge CFStringRef)domain
                                                    : kCFPreferencesCurrentApplication);
    if (ref == NULL) return nil;
    NSString *text = (__bridge_transfer NSString *)ref;
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return nil;
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    if (maxLines > 0 && lines.count > maxLines) {
        lines = [lines subarrayWithRange:NSMakeRange(lines.count - maxLines, maxLines)];
    }
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - 公开接口

void TCPLogLine(NSString *format, ...) {
    if (![format isKindOfClass:[NSString class]] || format.length == 0) return;

    NSString *message = nil;
    @autoreleasepool {
        va_list args;
        va_start(args, format);
        message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
    }
    if (![message isKindOfClass:[NSString class]] || message.length == 0) return;
    // 一行太长会把环塞满，截一下（诊断串那种几百字符的本来就该截）。
    if (message.length > 400) {
        message = [[message substringToIndex:400] stringByAppendingString:@"…"];
    }

    NSString *publishText = nil;
    NSString *fileText = nil;
    NSString *filePath = nil;

    pthread_mutex_lock(&gLock);
    if (!TCPLogEnabledLocked()) {
        pthread_mutex_unlock(&gLock);
        return;
    }
    if (gLines == nil) gLines = [NSMutableArray array];

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (gLastMessage != nil && [gLastMessage isEqualToString:message] &&
        now - gLastMessageTime < 1.0 && gLines.count > 0) {
        // 同一件事在 1 秒里又发生了一次：把最后那行改成「×N」，不再新增
        //（显示层站点一秒能问上百次，全都记下来只会把有用的行挤出去）。
        gRepeat += 1;
        gLines[gLines.count - 1] = [NSString stringWithFormat:@"%@ | %@ ×%lu",
                                    TCPLogStamp(), message, (unsigned long)gRepeat];
    } else {
        gRepeat = 0;
        gLastMessage = message;
        [gLines addObject:[NSString stringWithFormat:@"%@ | %@", TCPLogStamp(), message]];
        while (gLines.count > TCPLogMaxLines) {
            [gLines removeObjectAtIndex:0];
        }
    }
    gLastMessageTime = now;

    if (now - gLastPublish >= 3.0) {
        gLastPublish = now;
        publishText = TCPLogTextLocked(TCPLogPublishLines, 8000);
    }
    filePath = TCPLogFilePathLocked();
    if (filePath.length > 0 && now - gLastFileWrite >= 1.0) {
        gLastFileWrite = now;
        fileText = TCPLogTextLocked(TCPLogMaxLines, 48000);
    }
    pthread_mutex_unlock(&gLock);

    @autoreleasepool {
        if (publishText != nil) {
            CFPreferencesSetAppValue((__bridge CFStringRef)TCPKeyRuntimeLog,
                                     (__bridge CFPropertyListRef)publishText,
                                     kCFPreferencesCurrentApplication);
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        }
        if (fileText != nil && filePath != nil) {
            [fileText writeToFile:filePath atomically:YES
                         encoding:NSUTF8StringEncoding error:NULL];
        }
    }
}

NSString *TCPLogTailText(NSUInteger maxLines) {
    NSString *text = nil;
    pthread_mutex_lock(&gLock);
    text = TCPLogTextLocked(maxLines > 0 ? maxLines : TCPLogPublishLines, 8000);
    pthread_mutex_unlock(&gLock);
    return text;
}

NSString *TCPLogCombinedText(NSString *otherDomain, NSUInteger maxLines) {
    NSUInteger limit = maxLines > 0 ? maxLines : TCPLogPublishLines;
    NSMutableArray<NSString *> *sections = [NSMutableArray array];

    // 先看别的进程（面板看桌面那份，桌面才是干活的），再看自己这份。
    if (otherDomain.length > 0) {
        NSString *other = TCPLogTextForDomain(otherDomain, limit);
        if (other.length > 0) {
            [sections addObject:[NSString stringWithFormat:@"=== %@ ===\n%@", otherDomain, other]];
        }
    }
    NSString *mine = TCPLogTextForDomain(nil, limit);
    if (mine.length > 0) {
        NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"?";
        [sections addObject:[NSString stringWithFormat:@"=== %@（本进程）===\n%@", bundleID, mine]];
    }

    if (sections.count == 0) {
        return @"还没有日志。先在桌面点一次「刷新图标」再来 —— 那一下会让插件在桌面进程里重读主题、重取图标图，"
               @"日志就有了。";
    }
    return [sections componentsJoinedByString:@"\n\n"];
}
