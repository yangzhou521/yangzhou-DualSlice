#pragma once
//
//  YzThemeCorePlusPaths.h —— 引导（隐根）路径解析。
//
//  改写了原交付版：原版这个头用的是 Theos 的 <roothide.h> / <rootless.h>，只有 Theos 构建才有；
//  本仓库不用 Theos（AGENTS.md：本机 iPhone10,1 没有可用工具链，一切走 GitHub Actions 云编译），
//  所以换成仓库自己的 ApelinBootstrap.h（与 ThemeCorePlus/Sources/ApelinBootstrap.h 同一份实现），
//  由构建脚本定义 APELIN_BOOTSTRAP_ROOTHIDE。
//
//  两条铁律（硬规矩，踩过坑）：
//    ① 隐根前缀每次重越狱都会变 —— 一律运行时算（dladdr / 扫容器目录），绝不写死。
//    ② 只有**引导本体路径**（/Library/... ）需要加前缀；/var/mobile 下的用户数据在真实根上，
//       加了前缀反而读到引导里那份不存在的文件。
//
//  头文件里全是 static inline：只被本插件内部包含，不产生外部符号。

#import <Foundation/Foundation.h>
#import "ApelinBootstrap.h"

// 扫 /private/var/containers/Bundle/Application 里叫 .jbroot-* 的目录，取第一个**真的含这条相对路径**的
// （dladdr 在本镜像里拿不到时用；本仓 ThemeCorePlusPaths.m 里同一招已在使用）。
static inline NSString *yz_themecoreplus_scanBootstrap(NSString *rootfsPath) {
    static NSArray<NSString *> *roots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *parent = @"/private/var/containers/Bundle/Application";
        NSMutableArray<NSString *> *found = [NSMutableArray array];
        for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:parent error:NULL]) {
            if ([entry hasPrefix:@".jbroot-"]) {
                [found addObject:[parent stringByAppendingPathComponent:entry]];
            }
        }
        roots = [found sortedArrayUsingSelector:@selector(compare:)];
    });
    for (NSString *root in roots) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:
                [root stringByAppendingString:rootfsPath]]) {
            return root;
        }
    }
    return nil;
}

// 引导相对路径（/Library/… ）→ 本进程真正该打开的那个绝对路径。
// 顺序照抄 roothide 的 jbroot()：先看引导里那份在不在，再退回真实路径，最后扫容器目录。
static inline NSString *yz_themecoreplus_resourcePath(NSString *rootfsPath) {
    if (rootfsPath.length == 0) return nil;
    NSFileManager *manager = [NSFileManager defaultManager];

    NSString *prefixed = ApelinBootstrapPath(rootfsPath);     // 引导根 + 路径（roothide）
    if (prefixed.length > 0 && [manager fileExistsAtPath:prefixed]) return prefixed;

    if ([manager fileExistsAtPath:rootfsPath]) return rootfsPath;   // 真实路径上就有

    NSString *root = yz_themecoreplus_scanBootstrap(rootfsPath);
    if (root.length > 0) return [root stringByAppendingString:rootfsPath];

    // 目录还不存在（用户一个主题都没放）：有引导就返回引导里的位置，
    // 让调用方看到「这个目录是空的」，而不是错到真实根上那个不相干的地方。
    return prefixed.length > 0 ? prefixed : rootfsPath;
}

// 用户数据（偏好文件）：/var/mobile/… 在真实根上，**永远不加引导前缀**，两端写读同一个文件。
static inline NSString *yz_themecoreplus_preferencesPath(void) {
    return @"/var/mobile/Library/Preferences/com.yangzhou.themecoreplus.plist";
}
