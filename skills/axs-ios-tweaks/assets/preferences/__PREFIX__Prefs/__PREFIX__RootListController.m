#import "__PREFIX__RootListController.h"
#import "__PREFIX__Preferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
__SLIDER_IMPORT__

@interface __PREFIX__RootListController ()__SLIDER_PROTOCOL__
@end

@implementation __PREFIX__RootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"__PREFIX__Root"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于我们" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self __SYMBOL___addButton:@"Sileo 越狱源" action:@selector(__SYMBOL___openRepository:) to:items];
        [self __SYMBOL___addButton:@"TG分享频道" action:@selector(__SYMBOL___openTelegram:) to:items];
        [self __SYMBOL___addButton:@"QQ交流群组" action:@selector(__SYMBOL___openQQ:) to:items];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)__SYMBOL___addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
                          set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    item.buttonAction = action;
    [items addObject:item];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return __SYMBOL___readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!__SYMBOL___writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

- (void)__SYMBOL___openURL:(NSURL *)url fallback:(NSURL *)fallback {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        if (fallback) {
            [self __SYMBOL___openURL:fallback fallback:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开链接"
                message:@"请确认已安装对应应用。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)__SYMBOL___openRepository:(id)sender {
    NSString *source = @"__REPOSITORY__";
    // Encode the entire URL as a path component, including its own delimiters.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [source stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    NSURL *primary = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:encoded]];
    [self __SYMBOL___openURL:primary fallback:[NSURL URLWithString:source]];
}

- (void)__SYMBOL___openTelegram:(id)sender {
    [self __SYMBOL___openURL:[NSURL URLWithString:@"__TELEGRAM__"]
                   fallback:[NSURL URLWithString:@"__TELEGRAM_FALLBACK__"]];
}

- (void)__SYMBOL___openQQ:(id)sender {
    [self __SYMBOL___openURL:[NSURL URLWithString:@"__QQ__"] fallback:nil];
}

__SLIDER_METHODS__
@end
