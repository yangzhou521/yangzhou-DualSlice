#import "ThemeCorePlusConfig.h"
#import "ThemeCorePlusPreferences.h"

@implementation TCPConfig

+ (instancetype)shared {
    static TCPConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _values = @{};
        [self reload];
    }
    return self;
}

- (void)reload {
    self.values = TCPReadPreferences();
}

- (BOOL)enabled {
    return [self boolForKey:@"Enabled" defaultValue:YES];
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = self.values[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [value boolValue];
    }
    return defaultValue;
}

- (NSString *)stringForKey:(NSString *)key {
    id value = self.values[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key {
    id value = self.values[key];
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (id entry in (NSArray *)value) {
            if ([entry isKindOfClass:[NSString class]] && [entry length] > 0) {
                [names addObject:entry];
            }
        }
        return names;
    }
    NSString *single = [self stringForKey:key];
    return single.length > 0 ? @[ single ] : @[];
}

@end
