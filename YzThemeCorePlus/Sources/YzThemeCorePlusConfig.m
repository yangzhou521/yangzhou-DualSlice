#import "YzThemeCorePlusConfig.h"
#import "YzThemeCorePlusPreferences.h"

@interface YzThemeCorePlusConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void yz_themecoreplus_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    YzThemeCorePlusConfig *config = (__bridge YzThemeCorePlusConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config yz_themecoreplus_reload];
    });
}

@implementation YzThemeCorePlusConfig

+ (instancetype)yz_themecoreplus_shared {
    static YzThemeCorePlusConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.yangzhou.themecoreplus.preferences", DISPATCH_QUEUE_SERIAL);
        [self yz_themecoreplus_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, yz_themecoreplus_preferencesDidChange,
            (__bridge CFStringRef)YzThemeCorePlusPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self yz_themecoreplus_reload]; });
    }
    return self;
}

- (void)yz_themecoreplus_reload {
    self.snapshot = yz_themecoreplus_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:YzThemeCorePlusPreferencesChanged object:self];
    });
}

- (id)yz_themecoreplus_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)yz_themecoreplus_isEnabled {
    id value = [self yz_themecoreplus_valueForKey:@"enabled" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
