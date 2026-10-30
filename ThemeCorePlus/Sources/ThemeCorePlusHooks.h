//
//  ThemeCorePlusHooks.h —— 「一站一槽」站点框架 + 运行期普查。
//
//  为什么不是一串 MSHookMessageEx 循环：
//   · R1 一站一槽：每个 (类, 选择器) 站点有自己的静态原 IMP 槽；包装函数只往自己的槽里
//     转发，绝不按 self 的类反查原实现（那会在继承链上回环，NotesReadOnly 1.0.8 就是这么
//     炸掉的：共用一张 (class,selector)→原 IMP 表，子类站点读到了自己那一格）。
//   · R2 声明者才挂：只有类「自己声明」了这个方法才挂站；从父类继承来的不挂。否则一个
//     父类的站会在几十个子类上被重复触发，原 IMP 也就指向了错的那一层。
//   · 槽位是静态数组 + 宏展开的包装函数：站点在运行期按普查结果生成，数量不定，所以
//     每种站点预备有限个槽位，按序占用；用不到就永远空着。
//
#pragma once

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
// objc_msgSend 的真身：私有类的消息一律走它（见 ThemeCorePlusPrivate.h 的链接铁律），
// 少了这个头文件 objc_msgSend 只是个未声明的符号，编译直接报错。
#import <objc/message.h>
// MSHookMessageEx：站点框架和 ThemeCorePlusFiles.m 都用它。头文件在 theos 的 vendor/include
// （构建脚本的 -I$THEOS/vendor/include）。
#import <substrate.h>
#import <os/log.h>

// 日志：subsystem 必须是包 id（apelin-tweak-runtime 的要求），apelin_log_read 才收得到。
static inline os_log_t TCPLogHandle(void) {
    static os_log_t handle = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = os_log_create("com.yangzhou.themecoreplus", "tweak");
    });
    return handle;
}

// iOS 14+ 传给 -[SBIcon iconImageWithInfo:] / -generateIconImageWithInfo: 的结构体。
//
// 铁律（2026-10-30 用崩溃报告坐实，别再犯）：**字段必须和系统一模一样，多一个都不行**。
// 系统里是 {CGSize size; CGFloat scale; CGFloat cornerRadius;}，sizeof = 32、全是 double，
// 在 arm64 ABI 里算「同质浮点聚合（HFA）」，4 个成员正好走 d0–d3 寄存器。
// 我们曾在这后面补 reserved[5] 想「多读不亏」，结果它变成 8 个 double、不再是 HFA，
// 编译器于是改成「从 x2 取结构体指针、按内存读」——而真实调用根本不填 x2。
// 崩溃实证（SpringBoard-2026-10-30-112204.ips）：tcpIconHook6+0x20 读 [x2+0x20]，
// x2 = 0 → KERN_INVALID_ADDRESS at 0x20，consecutiveCrashCount=8。
// 结论：宁可字段少，也绝不能让结构体越过 4 个 double 的 HFA 界限。
typedef struct {
    CGSize size;
    CGFloat scale;
    CGFloat cornerRadius;
} TCPIconImageInfo;

// 编译期闸门：这个结构体必须是 4 个 double（32 字节）的 HFA，多一个字段
// 就会从「d0–d3 传值」变成「x2 传指针」，而系统调用方根本不设 x2 —— 装机即安全模式。
// 断言放在这里，谁以后再往里加字段，CI 当场编译失败，而不是在 SpringBoard 里炸。
_Static_assert(sizeof(TCPIconImageInfo) == 32,
               "TCPIconImageInfo must be 4 doubles (HFA): {CGSize, scale, cornerRadius}");

typedef NS_ENUM(NSUInteger, TCPSiteKind) {
    // -[SBIcon iconImageWithInfo:] / -[SBIcon unmaskedIconImageWithInfo:]：结构体进、UIImage 出
    TCPSiteKindIconImageInfo = 0,
    // 角标底板图：无参、出 UIImage
    TCPSiteKindBadgeBackground,
    // 角标底板 tuple：无参、出 SBHIconAccessoryCountedMapImageTuple
    TCPSiteKindBadgeTuple,
    // 角标「含数字的成图」：+ (UIImage *)_checkoutImageForText:font:highlighted:
    TCPSiteKindBadgeTextImage,
    // 文件夹底板：无参、出 UIImage
    TCPSiteKindFolderBackground,
    // 图标显示层：SBIconImageView 的 displayedImage / contentsImage / squareContentsImage，
    // 无参、出「屏幕上那张图」（UIImage 或 CGImage）。
    // 为什么要有这一站：iOS 16 起 SBIcon 的 -iconImageWithInfo: 在 SpringBoard 里没有调用者
    // （实测 look=0，站点挂了但一次没被问过），图由 IconServices 生成、经缓存直接交给视图显示。
    // 实证：ThemeCore 0.5.1 注入的类里同样有 SBIconImageView / SBIconView，
    // MarkTheme16 0.2.0 则整套 MTIcon*SnapshotModule 挂在 IconServices 的图集管线上。
    TCPSiteKindDisplayImage,
    TCPSiteKindCount
};

// 类「自己声明」了这个方法（不是从父类继承的）。R2 的判据。
BOOL TCPClassDeclaresMethod(Class cls, SEL sel);

// 在类名以 prefixes 之一开头的类上，挂它自己声明了的 selectors 站点。
// excludingSubstrings 里的子串命中类名时跳过（视图/缓存类不该吃图标站）。
// 类方法是元类上的站。返回这一轮新挂上的站点数。
NSUInteger TCPInstallSitesForClassPrefixes(NSArray<NSString *> *prefixes,
                                           NSArray<NSString *> *excludingSubstrings,
                                           NSArray<NSString *> *selectors,
                                           TCPSiteKind kind);

// 同上，但按「类名**包含**某个子串」匹配。锁屏通知那套角标视图的类名事先不知道
// （不在 SpringBoardHome 的 SBIconBadge* 家族里），用子串兜住：凡是类名带 Badge 又自己
// 声明了角标站的类都挂上，有素材才动图，没素材照原样转发。
NSUInteger TCPInstallSitesForClassSubstrings(NSArray<NSString *> *substrings,
                                             NSArray<NSString *> *excludingSubstrings,
                                             NSArray<NSString *> *selectors,
                                             TCPSiteKind kind);

// 普查：类名含 substrings 之一、且自己声明了 selectors 之一的类，写成
// "类名=方法名 方法名" 的行；用它在设备上坐实「锁屏通知的角标到底是哪个类」。
NSString *TCPClassCensusForSubstrings(NSArray<NSString *> *substrings,
                                      NSArray<NSString *> *selectors,
                                      NSUInteger limit);

NSUInteger TCPTotalSiteCount(void);
NSArray<NSString *> *TCPSiteDescriptions(void);

// 运行期普查：把这些类自己声明的方法名列出来。钩子点靠它坐实，不靠猜。
NSString *TCPCensusForClasses(NSArray<NSString *> *classNames, NSUInteger limit);

// 「谁在这个站点上做了手脚」：对每个 (类, 选择器)，用 dladdr 看它现在的 IMP 属于哪个镜像。
// MSHookMessageEx 换上的 IMP 属于插件自己的 dylib，所以能直接从运行中的 SpringBoard 读出
// 可用的同类插件（MarkTheme16 / ThemeCore）到底 hook 了哪些站点 —— 不反汇编、不猜。
// 返回 "类:选择器=镜像名" 逗号串；系统自己的实现（SpringBoardHome / IconServices 等）不计。
NSString *TCPHookOwnerCensus(NSArray<NSString *> *classNames,
                             NSArray<NSString *> *selectorNames,
                             NSUInteger limit);

// —— 站点拿到机会时问模块要替换素材；模块拿不出就返回 nil / 原对象，包装函数照原样转发 ——
// 由 ThemeCorePlusIcons.m / ThemeCorePlusBadges.m / ThemeCorePlusFolders.m 实现。
UIImage *TCPThemedIconImage(id icon, TCPIconImageInfo info);
// 图标站打点：被问过几次、参数不可信跳过几次、没素材几次、换成几张。写进诊断。
NSString *TCPIconProbeReport(void);
// 显示层站：original 是视图正要画的那张图（UIImage 或 CGImage），view 是 SBIconImageView。
// 换不了（没素材、尺寸未知）就原样返回 original。
id TCPThemedDisplayReplacement(id original, id view);
// 显示层打点：look/hit/未换原因，写进诊断。
NSString *TCPDisplayProbeReport(void);

// 即时生效：不注销，把桌面上已建好的图标视图的图缓存清掉、按当前 info 重取一遍。
// 改完设置（面板广播、或 shell 手写偏好后 respring）由 ThemeCorePlusMain.m 调。
void TCPRefreshIconImages(void);
NSString *TCPRefreshProbeReport(void);
UIImage *TCPThemedBadgeBackground(CGFloat scale);
UIImage *TCPThemedBadgeBackgroundInBox(CGFloat scale, CGSize box);
UIImage *TCPThemedBadgeTextImage(NSString *text, UIFont *font, CGFloat scale, CGSize systemBox);
UIImage *TCPThemedFolderBackground(CGFloat scale);
NSString *TCPBadgeProbeReport(void);

// 类型安全替换（实现在 ThemeCorePlusHooks.m）：原返回什么类型就还什么类型，只把里面的图
// 换成 themed；themed 为 nil、original 为 nil 或类型认不出时，原样返回 original。
// 铁律：绝不拿 UIImage 顶替别的类型 —— iOS 16.7 的角标元组就是这样把 SpringBoard 送进
// 安全模式的（调用方向 UIImage 发元组的选择器 → unrecognized selector → abort）。
id TCPThemedImageReplacement(id original, UIImage *themed);
