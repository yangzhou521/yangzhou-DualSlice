#!/bin/sh
#
# CountdownHUD —— 自绘倒计时胶囊的构建脚本（只跑在 CI 的 macOS runner 上）。
#
# 与 build-dualslice.sh 同形：clang 直编 arm64 + arm64e 两片再 lipo，ldid 签名，dpkg-deb 打包。
# 开发机是 iPhone10,1（A11），没有工具链，**不要在本机跑**。
#
# 本插件不 hook 任何东西，所以**不链接 substrate**：constructor 里起一个轮询就够了。
#
# 用法（仓库根目录）：
#   sh scripts/build-countdownhud.sh            # roothide：arm64 + arm64e
#   sh scripts/build-countdownhud.sh rootless   # rootless：arm64
#
set -eu

# ── 包身份 ───────────────────────────────────────────────────────────
PRODUCT=CountdownHUD
PACKAGE_ID=com.yangzhou.countdownhud
VERSION=1.2.0
NAME_ZH="倒计时胶囊"
DESCRIPTION="注销/装包前的自绘倒计时 HUD，兼作灵动岛纯文案提醒（任务完成/进度）：脚本写请求文件，SpringBoard 里按灵动岛容器的实际尺寸与位置画胶囊。不依赖通知。"
MAINTAINER=yangzhou
MIN_IOS=16.0
# ───────────────────────────────────────────────────────────────────

cd "$(dirname "$0")/.."

KIND=${1:-roothide}
case "$KIND" in
  roothide)
    ARCHS="arm64 arm64e"
    ARCH_TAG=iphoneos-arm64e
    INSTALL_NAME="@loader_path/.jbroot/usr/lib/TweakInject/$PRODUCT.dylib"
    ;;
  rootless)
    ARCHS="arm64"
    ARCH_TAG=iphoneos-arm64
    INSTALL_NAME="@loader_path/../../usr/lib/TweakInject/$PRODUCT.dylib"
    echo "build-countdownhud.sh: 警告：rootless 腿没有被任何设备验证过" >&2
    ;;
  *)
    echo "usage: $0 [roothide|rootless]" >&2
    exit 2
    ;;
esac

THEOS=${THEOS:-theos}
SDKROOT=${SDKROOT:-$THEOS/sdks/iPhoneOS16.5.sdk}
OUTDIR=${APELIN_PACKAGE_DIR:-packages}

if [ ! -d "$SDKROOT" ]; then
  echo "build-countdownhud.sh: SDK not found: $SDKROOT" >&2
  exit 2
fi
if [ ! -f "CountdownHUD/Sources/$PRODUCT.m" ]; then
  echo "build-countdownhud.sh: CountdownHUD/Sources/$PRODUCT.m not found" >&2
  exit 2
fi

SHARED_FLAGS="-fobjc-arc -fvisibility=hidden -miphoneos-version-min=$MIN_IOS \
-isysroot $SDKROOT -O2"
# 这个 SDK 的 UIKit.tbd 不 reexport CoreGraphics，用到 CGRect 得显式列出来。
FRAMEWORKS="-framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics"

BUILD=build/countdownhud
DY="$BUILD/out/$PRODUCT.dylib"

echo "build-countdownhud.sh: $PACKAGE_ID $VERSION kind=$KIND archs=$ARCHS"
echo "build-countdownhud.sh: $(uname -s) $(uname -m)"
echo "build-countdownhud.sh: SDKROOT=$SDKROOT"

rm -rf "$BUILD/thin" "$BUILD/out" "$BUILD/stage"
mkdir -p "$BUILD/thin" "$BUILD/out" "$BUILD/stage"

for arch in $ARCHS; do
  mkdir -p "$BUILD/thin/$arch"
  echo "build-countdownhud.sh: compiling $arch"
  # shellcheck disable=SC2086
  clang -dynamiclib -arch "$arch" $SHARED_FLAGS $FRAMEWORKS \
      -install_name "$INSTALL_NAME" \
      "CountdownHUD/Sources/$PRODUCT.m" \
      -o "$BUILD/thin/$arch/$PRODUCT.dylib"
done

lipo -create "$BUILD"/thin/*/"$PRODUCT.dylib" -output "$DY"

SLICES=$(lipo -archs "$DY")
echo "build-countdownhud.sh: slices = $SLICES"
for want in $ARCHS; do
  case " $SLICES " in
    *" $want "*) ;;
    *) echo "build-countdownhud.sh: missing $want slice in $DY" >&2; exit 4 ;;
  esac
done

echo "build-countdownhud.sh: --- otool -L ---"
otool -L "$DY"

# 没签名的 dylib 不加载。
ldid -S "$DY"

# ---- 打包 ----
STAGE="$BUILD/stage"
mkdir -p "$STAGE/Library/MobileSubstrate/DynamicLibraries" "$STAGE/DEBIAN"
cp "$DY" "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.dylib"
cp "Support/$PRODUCT.plist" \
   "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.plist"

plutil -lint "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.plist"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE_ID
Version: $VERSION
Architecture: $ARCH_TAG
Name: $NAME_ZH
Section: Tweaks
Maintainer: $MAINTAINER
Depends: firmware (>= $MIN_IOS), mobilesubstrate
Description: $DESCRIPTION
EOF

mkdir -p "$OUTDIR"
DEB="$OUTDIR/${PACKAGE_ID}_${VERSION}_${ARCH_TAG}.deb"
dpkg-deb -b --root-owner-group "$STAGE" "$DEB"

echo "build-countdownhud.sh: --- deb contents ---"
dpkg-deb -c "$DEB"
echo "build-countdownhud.sh: --- deb control ---"
dpkg-deb -I "$DEB"
echo "build-countdownhud.sh: sha256 $DEB = $(shasum -a 256 "$DEB" | awk '{print $1}')"
echo "build-countdownhud.sh: wrote $DEB"