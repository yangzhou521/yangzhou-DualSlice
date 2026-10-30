//
//  ThemeCorePlusPaths.h —— 主题与产物目录。
//
//  两种路径必须分清（见 apelin-bootstrap-paths）：
//   · 主题素材在**引导根**里（/Library/ThemeCore、/Library/Themes）：roothide 下是
//     .jbroot-xxxx/…（本机 = /var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/…），
//     rootless 下是 /var/jb/…。**隐根哈希每次越狱都会变**，所以运行时解析（jbroot() → dladdr
//     → 扫已加载镜像 → /var/jb → 空前缀），并且每个候选都先 stat 一次，谁真能打开就用谁。
//   · 本插件自己的库在 **/var/mobile/Library/ThemeCorePlus**：系统路径，两种引导下
//     都是真实路径，绝不能过隐根转换。
//
#pragma once

#import <Foundation/Foundation.h>

// 主题搜索根，按优先级排列（前面的主题优先）：存在的引导根目录 + 存在的用户目录，已去重。
NSArray<NSString *> *TCPSourceThemeRoots(void);

// 诊断用：本进程里各候选策略对主题目录的可见性（try=[jbroot:1,…]）与最终采用的策略（pick=…）。
// 装完机读 `icli prefs read <进程域> ThemeCorePlusDiagnostics` 就能看出根对不对。
NSString *TCPSourceThemeRootsReport(void);

// 这个路径是否落在某个主题搜索根里。用于文件覆盖钩子里的「自己人读自己素材不替换」护栏：
// store 自己合成图标时会走 +[UIImage imageWithContentsOfFile:]，不拦住就会自我递归。
BOOL TCPPathIsInsideThemeRoots(NSString *path);

// 把「存下来的主题路径」重新对到本进程真实存在的目录上，认不出来返回 nil。
//   · 存下来的可能是**上一个隐根时代**的绝对路径（roothide 重越狱会换 .jbroot-xxxx 名字，
//     本机实测过），也可能是 shell 手写的「/Library/ThemeCore/…」这种引导相对写法 ——
//     后者在系统进程里 plain 策略是看不见的（诊断里 plain:0）。
//   · 所以先按原样试，不行就截出 /Library/… 之后的部分重新贴到当前解析出的根上，
//     再不行就按目录名在根里找同名目录（用户自己挪过位置也能救回来）。
NSString *TCPReResolveThemePath(NSString *stored);

// 插件自己的库根（系统路径）。
NSString *TCPLibraryRoot(void);
// 编译产物目录（阶段二由管理器 App 写入；阶段一不使用）。
NSString *TCPRevisionsRoot(void);
