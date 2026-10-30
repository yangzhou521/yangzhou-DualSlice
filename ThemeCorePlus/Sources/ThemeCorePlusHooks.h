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

// iOS 14+ 传给 -[SBIcon iconImageWithInfo:] 的结构体。真身随版本可能加字段：
// 只许多读、绝不许少读 —— 少读会让原实现从栈上读到垃圾（图标变形甚至崩）。
typedef struct {
    CGSize size;
    CGFloat scale;
    CGFloat cornerRadius;
    CGFloat reserved[5];
} TCPIconImageInfo;

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

NSUInteger TCPTotalSiteCount(void);
NSArray<NSString *> *TCPSiteDescriptions(void);

// 运行期普查：把这些类自己声明的方法名列出来。钩子点靠它坐实，不靠猜。
NSString *TCPCensusForClasses(NSArray<NSString *> *classNames, NSUInteger limit);

// —— 站点拿到机会时问模块要替换素材；模块拿不出就返回 nil / 原对象，包装函数照原样转发 ——
// 由 ThemeCorePlusIcons.m / ThemeCorePlusBadges.m / ThemeCorePlusFolders.m 实现。
UIImage *TCPThemedIconImage(id icon, TCPIconImageInfo info);
UIImage *TCPThemedBadgeBackground(CGFloat scale);
UIImage *TCPThemedBadgeTextImage(NSString *text, UIFont *font, CGFloat scale);
UIImage *TCPThemedFolderBackground(CGFloat scale);

// 类型安全替换（实现在 ThemeCorePlusHooks.m）：原返回什么类型就还什么类型，只把里面的图
// 换成 themed；themed 为 nil、original 为 nil 或类型认不出时，原样返回 original。
// 铁律：绝不拿 UIImage 顶替别的类型 —— iOS 16.7 的角标元组就是这样把 SpringBoard 送进
// 安全模式的（调用方向 UIImage 发元组的选择器 → unrecognized selector → abort）。
id TCPThemedImageReplacement(id original, UIImage *themed);
