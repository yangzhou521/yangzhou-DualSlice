#pragma once
//
//  TCXPrefs.h —— 偏好读取。
//
//  面板还没做（0.0.1 先要「能跑、不崩」），所以偏好直接读文件：
//    /var/mobile/Library/Preferences/com.yangzhou.appicon.plist
//  键名少而稳，用 shell（defaults write / plutil）就能改，改完图标会自己重取。
//

#import <Foundation/Foundation.h>
#import "TCXPaths.h"

static inline id TCXPref(NSString *key) {
    static NSDictionary *cache;
    static NSTimeInterval cachedAt;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!cache || now - cachedAt > 3.0) {
        cache = [NSDictionary dictionaryWithContentsOfFile:TCXPreferencesPath()];
        cachedAt = now;
    }
    id value = cache[key];
    return value;
}

static inline BOOL TCXPrefBool(NSString *key, BOOL fallback) {
    id value = TCXPref(key);
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static inline double TCXPrefDouble(NSString *key, double fallback) {
    id value = TCXPref(key);
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : fallback;
}

static inline NSString *TCXPrefString(NSString *key) {
    id value = TCXPref(key);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}