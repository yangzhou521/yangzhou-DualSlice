#!/bin/sh
#
# SileoFix —— 修 SileoWallpaper 挡住 Sileo 输入框的补丁插件，构建脚本（只跑在 CI 的 macOS runner 上）。
#
# 开发机是 iPhone10,1（A11），缺 FEAT_LRCPC、没有工具链，**不要在本机跑**。
#
# 用法（仓库根目录）：
#   sh scripts/build-sileofix.sh            # roothide：arm64 + arm64e
#   sh scripts/build-sileofix.sh rootless   # rootless：arm64
#
set -eu

# ── 包身份 ───────────────────────────────────────────────────────────
PRODUCT=SileoFix
PACKAGE_ID=com.yangzhou.sileofix
VERSION=1.0.1
NAME_ZH="Sileo 输入框修复"
DESCRIPTION="修 SileoWallpaper 壁纸插件导致 Sileo 搜索/输入框点不进去、键盘打不开、打不了字的问题：只把盖在输入框上吃触摸的装饰层设成不接收触摸，壁纸效果照旧。"
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
    WANTED_SUBSTRATE="@loader_path/.jbroot/usr/lib/libsubstrate.dylib"
    ;;
  rootless)
    ARCHS="arm64"
    ARCH_TAG=iphoneos-arm64
    INSTALL_NAME="@loader_path/../../usr/lib/TweakInject/$PRODUCT.dylib"
    WANTED_SUBSTRATE="@loader_path/../libsubstrate.dylib"
    echo "build-sileofix.sh: 警告：rootless 腿没有被任何设备验证过" >&2
    ;;
  *)
    echo "usage: $0 [roothide|rootless]" >&2
    exit 2
    ;;
esac

THEOS=${THEOS:-theos}
SDKROOT=${SDKROOT:-$THEOS/sdks/iPhoneOS16.5.sdk}
OUTDIR=${APELIN_PACKAGE_DIR:-packages}
SRC=SileoFix/Sources

if [ ! -d "$SDKROOT" ]; then
  echo "build-sileofix.sh: SDK not found: $SDKROOT" >&2
  exit 2
fi
if [ ! -f "$SRC/$PRODUCT.m" ]; then
  echo "build-sileofix.sh: $SRC/$PRODUCT.m not found" >&2
  exit 2
fi

# substrate：$THEOS/lib 里没有它，vendor/lib/libsubstrate.tbd 只是一行指向框架的指针。
if [ -d "$THEOS/vendor/lib/CydiaSubstrate.framework" ]; then
  SUBSTRATE_LDFLAGS="-F$THEOS/vendor/lib -framework CydiaSubstrate"
else
  SUBSTRATE_LDFLAGS="-lsubstrate"
fi

SHARED_FLAGS="-fobjc-arc -fvisibility=hidden -miphoneos-version-min=$MIN_IOS \
-isysroot $SDKROOT -O2 -I$THEOS/vendor/include"
# 这个 SDK 的 UIKit.tbd 不 reexport CoreGraphics，用到 CGRect 得显式列出来。
FRAMEWORKS="-framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics"

BUILD=build/sileofix
DY="$BUILD/out/$PRODUCT.dylib"

echo "build-sileofix.sh: $PACKAGE_ID $VERSION kind=$KIND archs=$ARCHS"
echo "build-sileofix.sh: $(uname -s) $(uname -m)"
echo "build-sileofix.sh: SDKROOT=$SDKROOT"

rm -rf "$BUILD/thin" "$BUILD/out" "$BUILD/stage"
mkdir -p "$BUILD/thin" "$BUILD/out" "$BUILD/stage"

for arch in $ARCHS; do
  mkdir -p "$BUILD/thin/$arch"
  echo "build-sileofix.sh: compiling $arch"
  # shellcheck disable=SC2086
  clang -dynamiclib -arch "$arch" $SHARED_FLAGS $FRAMEWORKS $SUBSTRATE_LDFLAGS \
      -install_name "$INSTALL_NAME" \
      "$SRC/$PRODUCT.m" \
      -o "$BUILD/thin/$arch/$PRODUCT.dylib"
done

lipo -create "$BUILD"/thin/*/"$PRODUCT.dylib" -output "$DY"

SLICES=$(lipo -archs "$DY")
echo "build-sileofix.sh: slices = $SLICES"
for want in $ARCHS; do
  case " $SLICES " in
    *" $want "*) ;;
    *) echo "build-sileofix.sh: missing $want slice in $DY" >&2; exit 4 ;;
  esac
done

echo "build-sileofix.sh: --- otool -L ---"
otool -L "$DY"
# substrate 依赖必须是相对安装路径（roothide 走 @loader_path/.jbroot/…），否则本机解析不到。
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk 'tolower($0) ~ /substrate/ {print $1; exit}')
if [ -z "$SUBSTRATE_ENTRY" ]; then
  echo "build-sileofix.sh: no substrate dependency at all" >&2
  exit 5
fi
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-sileofix.sh: rewriting $SUBSTRATE_ENTRY -> $WANTED_SUBSTRATE"
  install_name_tool -change "$SUBSTRATE_ENTRY" "$WANTED_SUBSTRATE" "$DY"
fi
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk 'tolower($0) ~ /substrate/ {print $1; exit}')
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-sileofix.sh: substrate entry is '$SUBSTRATE_ENTRY', wanted '$WANTED_SUBSTRATE'" >&2
  exit 5
fi

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

echo "build-sileofix.sh: --- deb contents ---"
dpkg-deb -c "$DEB"
echo "build-sileofix.sh: --- deb control ---"
dpkg-deb -I "$DEB"
echo "build-sileofix.sh: sha256 $DEB = $(shasum -a 256 "$DEB" | awk '{print $1}')"
echo "build-sileofix.sh: wrote $DEB"