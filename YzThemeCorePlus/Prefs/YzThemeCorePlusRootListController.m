#import "YzThemeCorePlusRootListController.h"
#import "YzThemeCorePlusPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@implementation YzThemeCorePlusRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"YzThemeCorePlusRoot"
                                                           target:self] mutableCopy];
        PSSpecifier *about = [PSSpecifier preferenceSpecifierNamed:@"关于"
                                                            target:self set:nil get:nil
                                                            detail:nil cell:PSGroupCell edit:nil];
        [about setProperty:@"作者：yangzhou\n图标与角标主题均来自用户主题目录，与本插件无关。仅供学习交流。"
                   forKey:@"footerText"];
        [items addObject:about];
        _specifiers = items;
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return yz_themecoreplus_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!yz_themecoreplus_writePreference(key, value, &error)) {
        [self yz_themecoreplus_showAlert:@"设置未保存"
          message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"];
        [self reloadSpecifiers];
    }
}

- (void)yz_themecoreplus_refreshIcons:(PSSpecifier *)sender {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)YzThemeCorePlusPreferencesChanged, NULL, NULL, true);
    [self yz_themecoreplus_showAlert:@"已发送刷新指令"
        message:@"桌面图标正在应用所选主题。如果图标或角标没有立即变化，请注销（Respring）一次后重试。"];
}

- (void)yz_themecoreplus_showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
