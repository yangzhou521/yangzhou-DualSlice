#pragma once

#import <Foundation/Foundation.h>

@interface YzThemeCorePlusConfig : NSObject
+ (instancetype)yz_themecoreplus_shared;
- (BOOL)yz_themecoreplus_isEnabled;
- (id)yz_themecoreplus_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)yz_themecoreplus_reload;
@end
