#pragma once

#import <UIKit/UIKit.h>

// 日历图标"日期数字"墨层提取。
// iOS 16.7 系统日历图 = 白底 + 红色星期文字(如 "MON") + 黑色日期数字，
// 且图标图带圆角遮罩、四角 alpha≈0（透明）。
// 旧的"四角均值当背景 + 距阈值"会把整张图都判成墨，本模块改用"近黑选数字"，
// 不依赖背景估计，天然排除白底、红色星期文字、灰阴影与边框。

// ---- 阈值（按实测微调）----
#define YZ_TC_CAL_ALPHA_MIN    16      // alpha < 此值视为透明(圆角)背景
#define YZ_TC_CAL_MAX_CHANNEL  140     // max(R,G,B) < 此值 = 近黑(数字+抗锯齿灰边)
#define YZ_TC_CAL_RED_DIFF     30      // 排除红色星期文字：R 比 G/B 高出的差值（相对值，抗预乘变暗）
#define YZ_TC_CAL_MIN_AREA     0.006f  // 连通域最小面积占比（去掉噪点）

/// 从系统日历图标里提取「日期数字」墨层（其余透明），数字已按 inkColor 填色。
/// @param systemImage 系统动态日历图（含透明圆角、任意尺寸/scale）
/// @param inkColor    数字填色（由底图明暗决定：亮底→黑字，暗底→白字）
/// @param outCoverage 可选，返回墨层覆盖率（=最终墨/不透明，正确约 0.08~0.15）
/// @return 只有日期数字、其余透明的 UIImage；失败返回 nil
UIImage *yz_themecoreplus_calendarInkImage(UIImage *systemImage, UIColor *inkColor, float *outCoverage);

/// 图像平均亮度 0..1（忽略透明像素），用于按底图明暗选黑/白字。
CGFloat yz_themecoreplus_averageLuminance(UIImage *image);

/// 把「只有数字」的墨层图铺满合成到日历底图上，返回合成结果。
UIImage *yz_themecoreplus_composeCalendar(UIImage *base, UIImage *ink);
