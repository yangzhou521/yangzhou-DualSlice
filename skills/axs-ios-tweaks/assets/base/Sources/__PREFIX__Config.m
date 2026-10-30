#import "__PREFIX__Config.h"
#import "__PREFIX__Preferences.h"

@interface __PREFIX__Config ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void __SYMBOL___preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    __PREFIX__Config *config = (__bridge __PREFIX__Config *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config __SYMBOL___reload];
    });
}

@implementation __PREFIX__Config

+ (instancetype)__SYMBOL___shared {
    static __PREFIX__Config *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("__DOMAIN__.preferences", DISPATCH_QUEUE_SERIAL);
        [self __SYMBOL___reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, __SYMBOL___preferencesDidChange,
            (__bridge CFStringRef)__PREFIX__PreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self __SYMBOL___reload]; });
    }
    return self;
}

- (void)__SYMBOL___reload {
    self.snapshot = __SYMBOL___readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:__PREFIX__PreferencesChanged object:self];
    });
}

- (id)__SYMBOL___valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)__SYMBOL___isEnabled {
    id value = [self __SYMBOL___valueForKey:@"enabled" defaultValue:@(__DEFAULT_ENABLED__)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : __DEFAULT_ENABLED__;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
