---
name: themecoreplus-1045-features
description: 记录 ThemeCorePlus 1.0.45 关键改动与分析结论，供后续对话调用。
---

1.0.45 版本主要改动：
- 日历图标文字改为系统动态层（TCPCompositeCalendarInk → TCPCompositeCalendarText，系统图文字层，nil时回退自绘）。
- 角标加等比适配辅助函数 TCPBadgeAspectFitRect，overlay.contentMode 固定为 ScaleAspectFit，记录 sBadgeOverlayGeom（WxH/imgWxH）用于 probe 报告。
- 探针字段 TCPBadgeProbeReport 格式串末尾加入 ,ovl=%@，参数为 sBadgeOverlayGeom。
- 版本号同步至 1.0.45（ThemeCorePlusVersion.h、scripts/build-themecoreplus.sh、.github/workflows/themecoreplus.yml）。
- 新增诊断文档 docs/cases/icon-shadow-not-working.md 与 docs/cases/springboard-icon-fast-load.md，记录图标阴影与秒加载失败的病灶、证据、已证伪猜测与候选修法。
- 钩子 ThemeCorePlusHooks.m 冻结不改；ThemeCorePlusBadges.m 与 Prefs/ 仅加读诊断，行为改动须用户点头。
- 版本锁 scripts/version-lock.txt 遵守 owner 8401d377-d2c1-4b25-b4e9-8ca0b71a8197。

使用方法：在以后的对话中使用 apelin_skill_read name=themecoreplus-1045-features 即可检索上述要点。
