#pragma once
//
//  TCXDiag.h —— 一个诊断键，两条读法。
//
//  写两处，任一处都能读：
//    ① 文件  /var/mobile/Library/AppIcon/diag.txt          （cat 即可）
//    ② 偏好  com.apple.springboard 域的 AppIconDiagnostics  （sh scripts/device.sh read com.apple.springboard AppIconDiagnostics）
//
//  格式（一行，分号分隔）：
//    v=<版本>;proc=<进程名>;role=<springboard|iconservice|other>;hooked=<挂上的站数>;sites=<站1,站2>;
//    theme=<主题名|none>;icon=<取图站被问次数>;hit=<换成主题图次数>;bdg=<角标站被问次数>;
//    shd=<阴影层贴了几次>;last=<最后一个 bundle id>;err=<最后一次异常>
//
//  为什么必须有它：用户报「没效果」时，光看图分不清
//    「插件没注入」/「注入了没挂上站」/「挂上了没被调用」/「调用到了没换成图」。
//  这一行把四种情况分开了。
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CFPreferences.h>
#import "TCXPaths.h"
#import "TCXVersion.h"

static inline void TCXDiagWrite(NSString *text) {
    static NSTimeInterval lastWritten = 0;
    static NSString *lastText = nil;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (lastText && [lastText isEqualToString:text] && now - lastWritten < 5.0) return;
    lastWritten = now;
    lastText = text;

    NSString *dir = TCXDataDirectory();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
    });
    [text writeToFile:[dir stringByAppendingPathComponent:@"diag.txt"]
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    CFPreferencesSetAppValue(CFSTR("AppIconDiagnostics"),
                             (__bridge CFStringRef)text,
                             CFSTR("com.apple.springboard"));
    CFPreferencesAppSynchronize(CFSTR("com.apple.springboard"));
}

static inline void TCXDiagWriteForce(NSString *text) {
    NSString *dir = TCXDataDirectory();
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
    });
    [text writeToFile:[dir stringByAppendingPathComponent:@"diag.txt"]
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    CFPreferencesSetAppValue(CFSTR("AppIconDiagnostics"),
                             (__bridge CFStringRef)text,
                             CFSTR("com.apple.springboard"));
    CFPreferencesAppSynchronize(CFSTR("com.apple.springboard"));
}

// 跨模块共享的计数与诊断落点（实现在 Hooks/TCXMain.m）。
// 每个模块只往这里报「我挂上了哪个站」「我被问了几次」，诊断行由 Main 统一拼。
void TCXNoteSite(NSString *site);
void TCXCountIconLook(void);
void TCXCountIconHit(NSString *bundleID);
void TCXCountBadgeLook(void);
void TCXCountShadow(void);
void TCXRecordError(NSString *error);
void TCXWriteDiagnostics(BOOL force);

// 主题库是否已经预热好（TCXMain 在后台队列里 [TCXStore shared] 之后置位）。
// 取图 hook 必须先用它放行：未就绪时直接返回原图，
// 否则主线程会为了第一张图标去扫 Library/Themes（Smartisan 2379 个文件）——
// 那是「注销后黑屏、要再进一次桌面」的直接原因。
BOOL TCXStoreReady(void);
void TCXMarkStoreReady(void);