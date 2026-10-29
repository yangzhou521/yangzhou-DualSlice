//
//  ThemeCorePlusPaths.h —— 主题与产物目录。
//
//  两种路径必须分清（见 apelin-bootstrap-paths）：
//   · 主题素材在**引导根**里（/Library/ThemeCore、/Library/Themes）：roothide 下是
//     .jbroot-xxxx/…，rootless 下是 /var/jb/…，所以拼路径必须走 ApelinBootstrapPath()。
//   · 本插件自己的库在 **/var/mobile/Library/ThemeCorePlus**：系统路径，两种引导下
//     都是真实路径，绝不能过隐根转换。
//
#pragma once

#import <Foundation/Foundation.h>

// 主题搜索根，按优先级排列（前面的主题优先）。前两个是引导路径，最后一个是系统路径。
NSArray<NSString *> *TCPSourceThemeRoots(void);

// 这个路径是否落在某个主题搜索根里。用于文件覆盖钩子里的「自己人读自己素材不替换」护栏：
// store 自己合成图标时会走 +[UIImage imageWithContentsOfFile:]，不拦住就会自我递归。
BOOL TCPPathIsInsideThemeRoots(NSString *path);

// 插件自己的库根（系统路径）。
NSString *TCPLibraryRoot(void);
// 编译产物目录（阶段二由管理器 App 写入；阶段一不使用）。
NSString *TCPRevisionsRoot(void);
