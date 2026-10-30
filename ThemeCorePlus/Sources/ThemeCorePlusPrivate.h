//
//  ThemeCorePlusPrivate.h —— 站点模块的装配入口。
//
//  这里不声明任何 SpringBoard / SpringBoardHome 私有类：私有类一律在运行期用 objc_getClass
//  取，取不到就整站不装，方法用 objc_msgSend 直接发。理由很实在 —— 只要代码里出现
//  [SBIconController sharedInstance] 这种写法，链接期就会多出一个 SDK 里没有的类符号，
//  而本工程明令不许用 -undefined dynamic_lookup 混过去（见 AGENTS.md 的链接铁律）。
//
#pragma once

#import <UIKit/UIKit.h>
#import "ThemeCorePlusHooks.h"

// 各站点模块的入口；装配顺序由 ThemeCorePlusMain.m 的构造函数决定。
void TCPInstallIconSites(void);     // ThemeCorePlusIcons.m
void TCPInstallDisplaySites(void);  // ThemeCorePlusIcons.m（SBIconImageView 显示层）
void TCPInstallBadgeSites(void);    // ThemeCorePlusBadges.m
void TCPInstallFolderSites(void);   // ThemeCorePlusFolders.m
void TCPInstallFileSites(void);     // ThemeCorePlusFiles.m
