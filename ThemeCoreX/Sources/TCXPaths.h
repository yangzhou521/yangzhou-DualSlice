#pragma once
//
//  TCXPaths.h —— 路径解析 + 偏好域。
//
//  三条铁律（踩过坑）：
//    ① roothide 的 jbroot 前缀每次重新越狱都会变 —— 必须运行时算，绝不写死。
//    ② 只有「引导本体」路径（/Library/…、/usr/…）要加前缀；/var/mobile/… 是用户数据，
//       在真实根上，加了前缀反而读不到。
//    ③ **图标素材只有一个来源**：<jbroot>/Library/Themes/<主题名>/ 。
//       这是 ThemeCore 系主题包的系统默认安装位置；不扫 /var/mobile/Library/Themes、
//       不扫真实根的 /Library/Themes（那里面没有主题）。
//       用户 2026-11-05 17:04 定：主题根就用 Library/Themes。
//       主题目录名不强制 .theme 后缀（实测本机三个：Smartisan.theme、
//       液态玻璃.theme、角标：透明玻璃）。
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>

// 本进程所在引导根（roothide 的 .jbroot-XXXX）。探不到返回 nil。
static inline NSString *TCXBootstrapRoot(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static const char anchor = 0;
        Dl_info info;
        if (dladdr(&anchor, &info) == 0 || info.dli_fname == NULL) return;
        NSArray<NSString *> *parts = [@(info.dli_fname) componentsSeparatedByString:@"/"];
        for (NSUInteger i = 0; i < parts.count; i++) {
            if ([parts[i] hasPrefix:@".jbroot-"]) {
                root = [[parts subarrayWithRange:NSMakeRange(0, i + 1)]
                    componentsJoinedByString:@"/"];
                break;
            }
        }
    });
    return root;
}

// 引导相对路径 → 本进程真正该打开的绝对路径。先看引导里那份，再退回真实路径。
static inline NSString *TCXResourcePath(NSString *path) {
    if (path.length == 0) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = TCXBootstrapRoot();
    if (root.length > 0) {
        NSString *prefixed = [root stringByAppendingString:path];
        if ([fm fileExistsAtPath:prefixed]) return prefixed;
    }
    if ([fm fileExistsAtPath:path]) return path;
    return root.length > 0 ? [root stringByAppendingString:path] : path;
}

// 偏好：用户数据，永远不加前缀。
static inline NSString *TCXPreferencesPath(void) {
    return @"/var/mobile/Library/Preferences/com.yangzhou.appicon.plist";
}

// 插件自己的运行目录（诊断、缓存）。
static inline NSString *TCXDataDirectory(void) {
    return @"/var/mobile/Library/AppIcon";
}

// 唯一素材根：<jbroot>/Library/Themes（主题目录形如 Smartisan.theme、液态玻璃.theme）。
static inline NSString *TCXThemesRoot(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *jb = TCXBootstrapRoot();
        root = jb.length ? [jb stringByAppendingString:@"/Library/Themes"]
                         : @"/Library/Themes";
    });
    return root;
}