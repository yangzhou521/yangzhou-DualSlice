#import "ThemeCorePlusPreferences.h"

static NSString *TCPPreferencesFilePath(void) {
    // 系统路径，不做隐根转换。
    return [@"/var/mobile/Library/Preferences"
        stringByAppendingPathComponent:[TCPPreferencesDomain stringByAppendingPathExtension:@"plist"]];
}

NSDictionary *TCPReadPreferences(void) {
    CFStringRef domain = (__bridge CFStringRef)TCPPreferencesDomain;
    CFDictionaryRef values = CFPreferencesCopyMultiple(NULL, domain,
                                                      kCFPreferencesCurrentUser,
                                                      kCFPreferencesAnyHost);
    NSDictionary *result = values ? (__bridge_transfer NSDictionary *)values : nil;
    if (result.count > 0) {
        return result;
    }
    id fileValues = [NSDictionary dictionaryWithContentsOfFile:TCPPreferencesFilePath()];
    return [fileValues isKindOfClass:[NSDictionary class]] ? fileValues : @{};
}

BOOL TCPWritePreference(NSString *key, id value) {
    if (key.length == 0) {
        return NO;
    }
    CFStringRef domain = (__bridge CFStringRef)TCPPreferencesDomain;
    // value 为 nil 时 CFPreferencesSetAppValue 收到 NULL = 删键，正是「恢复原生外观」要的语义。
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, domain);
    return CFPreferencesAppSynchronize(domain) ? YES : NO;
}

void TCPPostPreferencesChanged(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)TCPPreferencesChangedNotification,
                                         NULL, NULL, true);
}
