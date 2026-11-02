#import "YzThemeCorePlusCalendarInk.h"

// 内存说明：全部用 C 内存(malloc/CF)管理 CG 资源，ObjC 对象交由 ARC（工程 -fobjc-arc）。

static inline uint8_t yz_tc_max2(uint8_t a, uint8_t b) { return a > b ? a : b; }
static inline uint8_t yz_tc_max3(uint8_t a, uint8_t b, uint8_t c) { return yz_tc_max2(yz_tc_max2(a, b), c); }

// 把 UIImage 拉平成 RGBA 字节（上到下）。调用方负责 free。
static uint8_t *yz_tc_rgba_of_image(UIImage *img, int *outW, int *outH, CGFloat *outScale) {
    if (!img) return NULL;
    CGImageRef cg = img.CGImage;
    if (!cg) return NULL;
    int W = (int)CGImageGetWidth(cg);
    int H = (int)CGImageGetHeight(cg);
    if (W <= 0 || H <= 0) return NULL;

    uint8_t *buf = (uint8_t *)malloc((size_t)W * H * 4);
    if (!buf) return NULL;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    // kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big => 内存序 R,G,B,A
    CGContextRef ctx = CGBitmapContextCreate(buf, W, H, 8, W * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(buf); return NULL; }

    // UIKit 坐标系 y 向下，翻转一次得到"上到下"的字节
    CGContextTranslateCTM(ctx, 0, H);
    CGContextScaleCTM(ctx, 1, -1);
    CGContextDrawImage(ctx, CGRectMake(0, 0, W, H), cg);
    CGContextRelease(ctx);

    *outW = W;
    *outH = H;
    if (outScale) *outScale = img.scale;
    return buf;
}

// 8 连通 BFS，把面积 < minArea 的连通域置 0（去噪点）。
static void yz_tc_remove_small_components(uint8_t *mask, int W, int H, int minArea) {
    int total = W * H;
    uint8_t *vis = (uint8_t *)calloc((size_t)total, 1);
    int *queue = (int *)malloc((size_t)total * sizeof(int));
    if (!vis || !queue) { free(vis); free(queue); return; }

    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            int idx = y * W + x;
            if (!mask[idx] || vis[idx]) continue;

            int head = 0, tail = 0;
            queue[tail++] = idx; vis[idx] = 1;

            while (head < tail) {
                int c = queue[head++];
                int cx = c % W, cy = c / W;
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        if (!dx && !dy) continue;
                        int nx = cx + dx, ny = cy + dy;
                        if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
                        int ni = ny * W + nx;
                        if (mask[ni] && !vis[ni]) { vis[ni] = 1; queue[tail++] = ni; }
                    }
                }
            }

            if (tail < minArea) {
                for (int k = 0; k < tail; k++) mask[queue[k]] = 0;
            }
        }
    }

    free(queue);
    free(vis);
}

// 近黑选数字：max(R,G,B) < 阈值，且非"偏红"（排除红色星期文字）。
// 返回 1 = 墨（数字），0 = 背景（白底/红字/阴影/透明角点）。
static inline int yz_tc_is_ink(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
    if (a < YZ_TC_CAL_ALPHA_MIN) return 0;
    uint8_t mx = yz_tc_max3(r, g, b);
    if (mx >= YZ_TC_CAL_MAX_CHANNEL) return 0;
    if ((r - (int)yz_tc_max2(g, b)) > YZ_TC_CAL_RED_DIFF) return 0;
    return 1;
}

UIImage *yz_themecoreplus_calendarInkImage(UIImage *systemImage, UIColor *inkColor, float *outCoverage) {
    if (outCoverage) *outCoverage = 0;
    if (!systemImage) return nil;

    int W = 0, H = 0;
    CGFloat scale = 1.0f;
    uint8_t *px = yz_tc_rgba_of_image(systemImage, &W, &H, &scale);
    if (!px) return nil;

    int total = W * H;
    uint8_t *mask = (uint8_t *)calloc((size_t)total, 1);
    if (!mask) { free(px); return nil; }

    int opaque = 0;
    for (int i = 0; i < total; i++) {
        uint8_t a = px[i * 4 + 3];
        if (a < YZ_TC_CAL_ALPHA_MIN) continue;
        opaque++;
        if (yz_tc_is_ink(px[i * 4 + 0], px[i * 4 + 1], px[i * 4 + 2], a)) mask[i] = 1;
    }

    // 连通域过滤：去掉噪点
    yz_tc_remove_small_components(mask, W, H, (int)((float)total * YZ_TC_CAL_MIN_AREA));

    int finalInk = 0;
    for (int i = 0; i < total; i++) if (mask[i]) finalInk++;
    if (outCoverage) *outCoverage = opaque > 0 ? (float)finalInk / (float)opaque : 0;

    // 取填色（默认白，避免取色失败出不可见图）
    CGFloat fr = 1, fg = 1, fb = 1, fa = 1;
    if (inkColor) [inkColor getRed:&fr green:&fg blue:&fb alpha:&fa];
    uint8_t FR = (uint8_t)(fr * 255.0f + 0.5f);
    uint8_t FG = (uint8_t)(fg * 255.0f + 0.5f);
    uint8_t FB = (uint8_t)(fb * 255.0f + 0.5f);

    uint8_t *out = (uint8_t *)malloc((size_t)total * 4);
    if (!out) { free(px); free(mask); return nil; }
    for (int i = 0; i < total; i++) {
        if (mask[i]) {
            out[i * 4 + 0] = FR; out[i * 4 + 1] = FG; out[i * 4 + 2] = FB; out[i * 4 + 3] = 255;
        } else {
            out[i * 4 + 0] = 0;  out[i * 4 + 1] = 0;  out[i * 4 + 2] = 0;  out[i * 4 + 3] = 0;
        }
    }
    free(px);
    free(mask);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(out, W, H, 8, W * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    CGImageRef cgimg = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
    if (ctx) CGContextRelease(ctx);
    free(out);

    UIImage *result = nil;
    if (cgimg) {
        result = [UIImage imageWithCGImage:cgimg scale:scale orientation:UIImageOrientationUp];
        CGImageRelease(cgimg);
    }
    return result;
}

CGFloat yz_themecoreplus_averageLuminance(UIImage *image) {
    if (!image) return 0.5f;
    int W = 0, H = 0;
    uint8_t *px = yz_tc_rgba_of_image(image, &W, &H, NULL);
    if (!px) return 0.5f;

    double sum = 0;
    int count = 0;
    for (int i = 0; i < W * H; i++) {
        uint8_t a = px[i * 4 + 3];
        if (a < YZ_TC_CAL_ALPHA_MIN) continue;
        double lum = 0.299 * px[i * 4 + 0] + 0.587 * px[i * 4 + 1] + 0.114 * px[i * 4 + 2];
        sum += lum;
        count++;
    }
    free(px);
    return count > 0 ? (CGFloat)(sum / count / 255.0) : 0.5f;
}

UIImage *yz_themecoreplus_composeCalendar(UIImage *base, UIImage *ink) {
    if (!base) return nil;
    if (!ink) return base;

    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = base.scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:base.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect bounds = CGRectMake(0, 0, base.size.width, base.size.height);
        [base drawInRect:bounds];
        [ink drawInRect:bounds];
    }];
}
