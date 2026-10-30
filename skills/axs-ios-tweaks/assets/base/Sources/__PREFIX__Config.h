#pragma once

#import <Foundation/Foundation.h>

@interface __PREFIX__Config : NSObject
+ (instancetype)__SYMBOL___shared;
- (BOOL)__SYMBOL___isEnabled;
- (id)__SYMBOL___valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)__SYMBOL___reload;
@end
