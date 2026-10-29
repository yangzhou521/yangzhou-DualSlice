//
//  ThemeCorePlusPreferences.h —— 偏好域的读写。
//
//  域写在用户自己的偏好目录（/var/mobile/Library/Preferences）：那是**系统路径**，
//  两种引导下都是真实路径，不能走隐根转换。读用 cfprefsd，文件只是兜底。
//
#pragma once

#import <Foundation/Foundation.h>

static NSString * const TCPPreferencesDomain = @"com.yangzhou.themecoreplus";
// 面板（或任意进程）改完设置后广播它，SpringBoard 里重新读快照并重排图标。
static NSString * const TCPPreferencesChangedNotification =
    @"com.yangzhou.themecoreplus.preferences-changed";

// 只读，不写默认值：键不存在就是「没设置」，由调用方决定默认行为。
NSDictionary *TCPReadPreferences(void);

// 写一个键（value 传 nil = 删掉这个键；诊断与面板都走这里）。
BOOL TCPWritePreference(NSString *key, id value);

// 广播「设置变了」：SpringBoard 里的观察者收到就重读快照、重排图标。面板改完设置立刻调用。
// 用 Darwin 通知中心（CFNotificationCenterGetDarwinNotifyCenter），不用 notify_post：
// libnotify.tbd 不保证在 headerless SDK 里，CoreFoundation 一定在。
void TCPPostPreferencesChanged(void);
