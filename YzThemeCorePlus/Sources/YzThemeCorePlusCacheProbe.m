// 秒加载 / 缓存层 probe（临时文件，定位完可删）
// 用途：把 SBHIconImageCache 及关联类的「全方法表」写到文件 + 日志，
//       用于定位真实取图方法名（iconImageForRequest: 之类）。
// 装机后读：cat /var/mobile/Library/Preferences/YzCacheProbe.txt
// 拿到的命中方法名贴回来，我据此补真正的秒加载 hook。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <string.h>

static void yz_cacheprobe_dumpClass(const char *name, NSMutableString *out) {
    Class cls = objc_getClass(name);
    if (!cls) {
        [out appendFormat:@"\n===== %s: NOT FOUND =====\n", name];
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    [out appendFormat:@"\n===== %s (%u methods) =====\n", name, count];
    for (unsigned int i = 0; i < count; i++) {
        [out appendFormat:@"  %@\n", NSStringFromSelector(method_getName(methods[i]))];
    }
    if (methods) free(methods);
}

// UIImage 方法表太大，只 dump 与 app 图标相关的私有方法（设置App/文档选择器/share sheet 用），
// 并附 method_getTypeEncoding 精确类型编码（@=id d=double i=int q=long long f=float v=void : =SEL），
// 用于不猜签名直接拿到 +_applicationIconImageForBundleIdentifier:format:scale: 的确切参数类型。
static void yz_cacheprobe_dumpUIImageAppIconMethods(NSMutableString *out) {
    Class cls = objc_getClass("UIImage");
    if (!cls) { [out appendString:@"\n===== UIImage: NOT FOUND =====\n"]; return; }

    [out appendString:@"\n===== UIImage 实例方法 (appIcon, name [typeEncoding]) =====\n"];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *name = sel_getName(method_getName(methods[i]));
        if (strstr(name, "applicationIcon") || strstr(name, "IconImage")) {
            const char *enc = method_getTypeEncoding(methods[i]);
            [out appendFormat:@"  %s  [%s]\n", name, enc ? enc : "?"];
        }
    }
    if (methods) free(methods);

    [out appendString:@"\n===== UIImage 类方法 (appIcon, name [typeEncoding]) =====\n"];
    methods = class_copyMethodList(object_getClass(cls), &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *name = sel_getName(method_getName(methods[i]));
        if (strstr(name, "applicationIcon") || strstr(name, "IconImage")) {
            const char *enc = method_getTypeEncoding(methods[i]);
            [out appendFormat:@"  %s  [%s]\n", name, enc ? enc : "?"];
        }
    }
    if (methods) free(methods);
}

static void yz_cacheprobe_dumpAll(void) {
    NSMutableString *out = [NSMutableString string];
    const char *names[] = {
        "SBHIconImageCache",
        "SBHIconImageCacheRequest",
        "SBHIconImageCacheRequestBuilder",
        "SBHIconImageCacheResult",
        "SBHIconImageCacheObserver",
        "SBIconImageCache",
        "SBIconImageStore",
        "SBIconImage",
        "SBIconController",
        "SBHFileStackIcon",
        "SBHFileStackIconImageProvider",
        "SBFluidSwitcherIconImageContainerView",
        NULL
    };
    for (int i = 0; names[i]; i++) {
        yz_cacheprobe_dumpClass(names[i], out);
    }
    yz_cacheprobe_dumpUIImageAppIconMethods(out);

    // 写文件，方便 cat/grep
    NSString *path = @"/var/mobile/Library/Preferences/YzCacheProbe.txt";
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[YzCacheProbe] dumped to %@", path);
}

__attribute__((constructor))
static void yz_cacheprobe_init(void) {
    // 延迟 5 秒，确保 SpringBoardHome 等 framework 全部加载完毕
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @autoreleasepool {
            yz_cacheprobe_dumpAll();
        }
    });
}

// ===== 占位：秒加载 hook 骨架（等 probe 拿到真实方法名后启用，删掉本文件本段注释即可）=====
// %hook SBHIconImageCache
// - (id)iconImageForRequest:(id)request {   // ← TODO: 方法名以 YzCacheProbe.txt 结果为准
//     id result = %orig;
//     // 在这里把 result 里携带的图换成主题图（或直接返回主题图）
//     return result;
// }
// %end
