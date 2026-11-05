#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "TCXPrivate.h"
#import "TCXStore.h"
#import "TCXPrefs.h"
#import "TCXDiag.h"

// 角标层。
//
// iOS 16 的 SBIconBadgeView 不给「设置一张图」的入口，它从缓存里结账式取图：
//   +[SBIconBadgeView _checkoutBackgroundImage]              （类方法，一次取一张底板）
//   -[SBIconBadgeView _checkoutBackgroundImage]              （实例方法）
// 返回值可能是 UIImage，也可能是 SBHIconAccessoryCountedMapImageTuple 包着 UIImage ——
// 所以**绝不改变返回类型**：是 tuple 就用 tuple 重新包一层，是 image 就直接换。
// 换了类型会让调用方按错误类型取属性，立刻崩，这是 1.0.x 最贵的一课。
//
// 主题素材（按顺序找）：
//   <主题>/Bundles/com.apple.springboard/SBBadgeBackground@2x.png
//   <主题>/SBBadgeBackground@2x.png

static id (*orig_bgInstance)(id, SEL);
static id (*orig_bgClass)(id, SEL);

static id TCXBadgeBackground(id self, SEL _cmd, id original) {
    if (!original) return nil;
    if (!TCXPrefBool(@"Enabled", YES)) return original;
    if (!TCXPrefBool(@"BadgeEnabled", YES)) return original;

    TCXCountBadgeLook();

    TCXStore *store = [TCXStore shared];
    [store reloadIfNeeded];

    UIImage *art = [store springboardImageNamed:@"SBBadgeBackground" scale:2.0];
    if (!art) return original;

    Class tupleClass = TCXClass(@"SBHIconAccessoryCountedMapImageTuple");
    if (tupleClass && [original isKindOfClass:tupleClass]) {
        SEL initSel = @selector(initWithImage:countedMapKey:);
        if ([tupleClass instancesRespondToSelector:initSel]) {
            NSString *key = [NSString stringWithFormat:@"appicon-%@-%lu",
                             store.themeName ?: @"none", (unsigned long)store.generation];
            id tuple = ((id (*)(id, SEL, id, id))objc_msgSend)([tupleClass alloc], initSel, art, key);
            if (tuple) return tuple;
        }
        return original;   // 包不上就退回原值，绝不返回类型不对的东西
    }

    if ([original isKindOfClass:[UIImage class]]) return art;
    return original;
}

static id repl_bgInstance(id self, SEL _cmd) {
    id original = orig_bgInstance ? orig_bgInstance(self, _cmd) : nil;
    @try {
        return TCXBadgeBackground(self, _cmd, original);
    } @catch (NSException *exception) {
        return original;
    }
}

static id repl_bgClass(id self, SEL _cmd) {
    id original = orig_bgClass ? orig_bgClass(self, _cmd) : nil;
    @try {
        return TCXBadgeBackground(self, _cmd, original);
    } @catch (NSException *exception) {
        return original;
    }
}

void TCXInstallBadgeHooks(void) {
    Class cls = TCXClass(@"SBIconBadgeView");
    if (!cls) {
        TCXNoteSite(@"badge:noclass");
        return;
    }

    // 实例方法：只挂在**自己声明**它的类上（俯视继承会拿到空原实现）。
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL hasInstanceBg = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(list[i]) == @selector(_checkoutBackgroundImage)) { hasInstanceBg = YES; break; }
    }
    free(list);

    if (hasInstanceBg) {
        MSHookMessageEx(cls, @selector(_checkoutBackgroundImage),
                        (IMP)&repl_bgInstance, (IMP *)&orig_bgInstance);
        if (orig_bgInstance) TCXNoteSite(@"SBIconBadgeView:-_checkoutBackgroundImage");
    }

    // 类方法：声明在 metaclass 上。
    Class meta = object_getClass(cls);
    unsigned int classCount = 0;
    Method *classList = class_copyMethodList(meta, &classCount);
    BOOL hasClassBg = NO;
    for (unsigned int i = 0; i < classCount; i++) {
        if (method_getName(classList[i]) == @selector(_checkoutBackgroundImage)) { hasClassBg = YES; break; }
    }
    free(classList);

    if (hasClassBg) {
        MSHookMessageEx(meta, @selector(_checkoutBackgroundImage),
                        (IMP)&repl_bgClass, (IMP *)&orig_bgClass);
        if (orig_bgClass) TCXNoteSite(@"SBIconBadgeView:+_checkoutBackgroundImage");
    }
}