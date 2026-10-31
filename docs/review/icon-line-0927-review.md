# 图标线 0.9.27 复核意见（复核方：5781b4c7，只读）

> 复核对象：`157b2985` 对 `ThemeCorePlusIcons.m` + `ThemeCorePlusStore.m` 的改法。
> 基线：本机 `ThemeCorePlus/Sources/` 现状（08:44/08:57），对照调度台四要点逐条落。
> **我只复核，不改码。** 出包（0.9.27）后按此表对照，再回 `f8fbdbd5`。

## 根因坐实（与调度台一致）

- 登记处 `Store.m:970-1000` 只把 `rendered.CGImage` 的**指针**塞进 `renderedCGPointers`（限量 800）；
  `renderedFingerprints` / `fingerprintCache`（266-268、314-316）**建了但任何一行都没往里写**。
- 判定端 `isRenderedCGImagePointer:`（1008-1011）只 `@synchronized` 比 `renderedCGPointers` 指针集。
- CA 把 `layer.contents` 的 CGImage 复制后**指针变** → 屏幕上的图一个都认不出是自己的 →
  `census{layer{ours=0}}` 而 `census{icon{ours=6}}`（icon 站认的是 UIImage，disp 站也认得出）。
- 所以「图标其实已经换成主题图了」，只是「屏幕上的 layer 没被认成我们的」。157b2985 补指纹接线是对的。

## 四条复核要点（出包后逐条对）

### ① 指纹接线会不会假阳性（把别人的图认成我们的）

- **危险点**：指纹（CGImage 内容的散列/特征）若只算「分辨率 + 几个采样像素」，系统原生图标
  与我们套了主题的同尺寸图可能**指纹相撞**（尤其同 App、同尺寸的 stock 图与 themed 图）。
  → `layer{ours>0}` 可能把 stock 图误判成 ours，统计就失真，失去「到底换没换」的判别力。
- **要求**：指纹必须取自**合成后那张图的内容**，且与系统 stock 图有足够区分度。
  「≥40px 才算」这道闸只是**性能闸**（小图不算，省得每次都散列），**不是判别闸**——
  它不能防止误判。真正的判别力取决于指纹算法本身（采样点是否落在主题改过的区域）。
- **缓存无限涨 = 发热**：`fingerprintCache.countLimit=512` 已有上限，但 `renderedFingerprints`
  是 `NSMutableSet` 只增不减（`removeAllObjects` 只在 409-411 清一次）。**接线后必须确认：
  指纹集要么进 NSCache（带上限），要么有淘汰，不能跟着合成次数无限涨**，否则发热比像素统计还狠。

### ② 像素统计 memo 会不会出陈旧图

- 现状 `Icons.m:79` 附近 `TCPNoteComposedImage(image, bundleID)` 每次取图都量 24×24 像素，滚动时高频。
- memo key = `identifier|尺寸|scale|generation`。**坑：generation 变了清空没问题；
  但「generation 不变、同一 identifier 的图标被换了」**（用户在设置里切主题但没触发 generation++，
  或同一图标滚动中被重画成另一张）→ memo 返回**旧统计结果**，像素自检就失真。
- **要求**：memo 的 key 里除 generation 外，最好再带上**图片身份**（image 指针或内容指纹），
  否则「同 identifier 换了图」会命中陈旧缓存。要么接受「统计可旧一帧」并写进注释说清后果。

### ③ 有没有踩两条铁律

- **构造阶段禁碰 UIKit（0.9.21 崩过的坑）**：Icons.m 里 `+[UIScreen mainScreen]` 在 1098 行，
  是普通方法体内、不是构造函数；`TCPInstallIconSites()`（86 行）无 `__attribute__((constructor))`。
  **要求**：157b2985 新加的指纹初始化、memo 表初始化**一律放惰性/首用时创建**，
  不许挪进 dyld 构造函数；指纹散列若在首次判定时才建，注意线程（判定端 `@synchronized` 已有，保持）。
- **隐根路径不写死**：Icons/Store 不涉及文件路径硬编码（素材走 Store 的 namedMap），
  复核时确认没新增任何 `/var/mobile/...`、`/private/...` 字面量。

### ④ 有没有动到角标共用的素材读取链

- 角标 `SBBadgeBG` 读取在 `Store.m:1059 imageForNamedAsset:@"SBBadgeBG"`，图标与角标**共用 Store 的
  namedMap 与 `imageForNamedAsset:`**。
- **硬判据（用户 2026-10-31 13:20 硬指令：角标冻结）**：157b2985 只应动「判定端
  `isRenderedCGImage:`」与「Icons 的 memo」，**不许碰 `imageForNamedAsset:`、
  `cachedImageAtPath:`、namedMap 的构建、`badgeBackgroundImageForScale:`、
  `TCPMaterialKindOfFile`/`TCPIsImageFile`/`TCPStripScaleSuffix`**。用户已认可 0.9.23 的角标
  效果、明确「不要再动角标」——图标线若动了角标素材链任一处，**直接判不合格**。
  出包后对照 `git diff`，这几行/这几个符号被改 = 退回。

## 验收（第 2 轮注销后，只读，三组字段分开归因）

- 图标：`census{layer{ours>0}}`（指纹生效）+ `file{hit>0}`。
- 角标：`sys{…tree=…*…}`（底板已清）+ `sys{host=N}`。
- 布局：`probe=` 的 `cand[model=N,ctrl=M]`（0.9.25 无条件写出）。
- 三组字段互不重叠，能分开归因；屏幕目视交用户。

## 给 157b2985 的一句话

指纹接线方向对；但「≥40px」只是性能闸不是判别闸，**真正防误判靠指纹算法取在主题改过的区域**；
指纹集要带淘汰（进 NSCache 或限量），别只增不减；memo 的 key 加图片身份防陈旧；
别把新初始化挪进构造阶段；别碰角标共用的 `imageForNamedAsset:`。

---

## 出包前复核结论（2026-10-31 13:2x，对照 commit `88a3de2e43` 的 patch，只读）

> 0.9.27 的源码改动就在 commit `88a3de2e43`（那次 run 被取消，随后 `352ab3e7` 只改 yml 重触发，
> run `41172682266` 正在编）。patch 已拿到，逐条判：

### ① 指纹假阳性 —— ⚠️ 需装机验证，算法本身有理论风险但可接受
- `TCPFingerprintOfCGImage`：降采样 12×12 灰度 = 144 字节。注释自己写「取在主题改过的区域」，
  但实际算法是**整图降采样**，并没有只取主题改过的区域——区分力取决于「themed 图与同 App 同尺寸
  stock 图在 12×12 灰度上是否不同」。大多数主题确实会改整体配色/底图，相撞概率低；但**纯换角标
  或只改局部小区域的图标**，12×12 灰度可能撞 → 假阳性把 stock 图认成 ours。
- **这不会让图标变坏**（只是普查统计 `layer{ours}` 偏高），最坏后果是「计数失真」，不是「图标错」。
  可接受，但装机后若 `layer{ours}` 异常高（接近全屏），要怀疑假阳性。
- **限量淘汰 OK**：`count > 600` 时保留一半（`removeObjectsInRange(0, count/2)` + `intersectSet`），
  `fingerprintCache` 是 NSCache（countLimit 512）。不会无限涨。✅

### ② memo 陈旧图 —— ✅ 安全（只跳过统计，不影响图本身）
- `sComposedMemo` key = UIImage **指针**，countLimit 1024。注释写明「只影响是否重复统计，不影响行为」。
- 「generation 不变但图换了」确实会命中旧 memo 跳过统计，但跳过的只是**像素自检统计**（诊断用），
  不影响实际渲染的图。诊断 `gen{}` 可能旧一帧，可接受。✅

### ③ 构造阶段 UIKit / 隐根路径 —— ✅ 合规
- memo 用 `dispatch_once` 惰性创建，非 dyld 构造函数。指纹函数 `TCPFingerprintOfCGImage` 纯 CoreGraphics
  （CGBitmapContext），不碰 UIKit。无路径字面量。✅

### ④ 角标素材链 —— ✅ 符合硬判据（用户角标冻结指令）
- patch 只动 Icons.m 的 memo 段 + Store.m 的指纹段。**未触碰** `imageForNamedAsset:`、
  `cachedImageAtPath:`、namedMap 构建、`badgeBackgroundImageForScale:`、
  `TCPMaterialKindOfFile`/`TCPIsImageFile`/`TCPStripScaleSuffix`。✅

### 复核结论
- 四条全部通过或可接受，**没有需要退回的硬伤**。
- 唯一装机后要盯的：`layer{ours}` 若异常高（接近全屏图标数）→ 怀疑 12×12 灰度指纹假阳性，
  那时才需要收紧指纹算法（取更细粒度或只取主题改过的区域）。
- 角标素材链零改动，符合用户「不要再动角标」硬指令。
