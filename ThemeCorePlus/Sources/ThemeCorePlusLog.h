//
//  ThemeCorePlusLog.h —— 插件自己的运行日志（内存环 + 偏好键 + 文本文件三份）。
//
//  为什么要自己留一份，而不是只靠 os_log：
//   · 统一日志在 iOS 上**没有历史**（apelin_log_read 只能从调用那刻起听 10 秒），
//     用户「把日志发给我」这件事就做不到；
//   · 诊断偏好键只在 reload 时被覆盖重写，中间发生的事（谁被问了、哪张素材没找到）全丢；
//   · 面板里原来直接把诊断串贴在「主题」组的脚注上给用户看，那串是给排查用的、不是给用户看的。
//     现在诊断进日志页，面板上不再出现技术串。
//
//  三份日志的分工：
//   1. 内存环（最近 TCPLogMaxLines 行）—— 当前进程随时可读，面板「查看运行日志」读的是下面这份；
//   2. 偏好键 ThemeCorePlusLog（写进**目标进程自己的**域，所以 SpringBoard 的在 com.apple.springboard）
//      —— 面板跨进程读它、shell 也能用 icli prefs read 读它；
//   3. 文本文件 <日志目录>/<进程名>-<pid>.log —— Filza 能直接取，出问题时整份发出来就行。
//
//  高频站点（显示层每秒被问上百次）靠「同内容 1 秒内合并成 ×N」限流，不会把缓冲刷爆。
//
#pragma once

#import <Foundation/Foundation.h>

// 内存里留多少行；写进偏好键与文件的行数按下面两个数截。
static const NSUInteger TCPLogMaxLines = 200;
static const NSUInteger TCPLogPublishLines = 120;

// 记一行（format 里别带换行）。任意线程可调，内部加锁。
void TCPLogLine(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// 本进程日志尾部若干行（读内存，不碰偏好）。
NSString *TCPLogTailText(NSUInteger maxLines);

// 合并读：otherDomain 那份（面板传 @"com.apple.springboard"）+ 本进程那份。
// 两个域都没有日志时返回一句人话。
NSString *TCPLogCombinedText(NSString *otherDomain, NSUInteger maxLines);

// 当前进程的日志文件路径（惰性解析并建目录；沙箱不允许就退到临时目录）。
// 解析不出来（理论上不会）返回 nil。
NSString *TCPLogFilePath(void);

// 是否记录：偏好键 LogEnabled，键不存在 = 开（与其它开关同一口径）。最多每 2 秒重读一次偏好。
BOOL TCPLogEnabled(void);
