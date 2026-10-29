//
//  ThemeCorePlusConfig.h —— 偏好快照。
//
//  钩子里每秒可能被调用上百次，所以只读内存里的快照；目录扫描、偏好读取只发生在
//  reload（加载时、以及收到偏好变更通知时）。
//
#pragma once

#import <Foundation/Foundation.h>

@interface TCPConfig : NSObject

+ (instancetype)shared;

// 原子快照，可被任意线程读。
@property (atomic, copy, readonly) NSDictionary *values;

- (void)reload;

// 总开关：键不存在时默认开启（主题里没有对应素材时插件本身就是空转）。
- (BOOL)enabled;

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
- (NSString *)stringForKey:(NSString *)key;
- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key;

@end
