#!/bin/sh
#
# SileoWallpaper 合并包 —— 原壁纸插件 + Sileo 输入框修复，装成一个包（只跑在 CI 的 macOS runner 上）。
#
# 2026-10-30：用户要求把独立的 com.yangzhou.sileofix 全部并回原包 com.sileowallpaper.tweak，
# 所以本脚本产出**单一 deb**：
#   Library/MobileSubstrate/DynamicLibraries/SileoWallpaper.dylib  ← OriginalPlugin/ 里的原二进制，逐字节不改
#   Library/MobileSubstrate/DynamicLibraries/SileoWallpaper.plist
#   Library/MobileSubstrate/DynamicLibraries/SileoFix.dylib        ← SileoFix/Sources/SileoFix.m 现场编译
#   Library/MobileSubstrate/DynamicLibraries/SileoFix.plist
# 两个 dylib 都只注入 org.coolstar.SileoStore，互相独立：壁纸照旧，修复另跑。
#
# 开发机是 iPhone10,1（A11），缺 FEAT_LRCPC、没有工具链，**不要在本机跑**。
#
# 用法（仓库根目录）：
#   sh scripts/build-sileowallpaper.sh            # roothide：arm64 + arm64e
#
set -eu

cd "$(dirname "$0")/.."

# ── 包身份 ───────────────────────────────────────────────────────────
PRODUCT=SileoWallpaper
FIX=SileoFix
PACKAGE_ID=com.sileowallpaper.tweak
VERSION=0.1.9
FIX_VERSION=1.0.4
NAME_ZH="Sileo 壁纸（已修复搜索框）"
AUTHOR=MoWang
MAINTAINER=MoWang
MIN_IOS=16.0
DESCRIPTION="为 Sileo 设置自定义背景壁纸，支持相册选图、文字颜色、背景柔化和列表底色调节。本版已修复：壁纸插件挡住 Sileo 输入框，导致任意软件源里「搜索软件包」点不进去、键盘打不开、打不了字的问题（由随包安装的 SileoFix.dylib 完成，壁纸效果不变）。"
# ───────────────────────────────────────────────────────────────────

KIND=${1:-roothide}
case "$KIND" in
  roothide)
    ARCHS="arm64 arm64e"
    ARCH_TAG=iphoneos-arm64e
    INSTALL_NAME="@loader_path/.jbroot/usr/lib/TweakInject/$FIX.dylib"
    WANTED_SUBSTRATE="@loader_path/.jbroot/usr/lib/libsubstrate.dylib"
    ;;
  *)
    echo "usage: $0 [roothide]" >&2
    exit 2
    ;;
esac

THEOS=${THEOS:-theos}
SDKROOT=${SDKROOT:-$THEOS/sdks/iPhoneOS16.5.sdk}
OUTDIR=${APELIN_PACKAGE_DIR:-packages}
SRC=$FIX/Sources

if [ ! -d "$SDKROOT" ]; then
  echo "build-sileowallpaper.sh: SDK not found: $SDKROOT" >&2
  exit 2
fi
if [ ! -f "$SRC/$FIX.m" ]; then
  echo "build-sileowallpaper.sh: $SRC/$FIX.m not found" >&2
  exit 2
fi
# 原插件本体：二进制必须逐字节带过来，源码早已不在（旧 jbroot 被换掉丢了）。
ORIG=$PRODUCT
if [ ! -f "OriginalPlugin/$ORIG.dylib" ] || [ ! -f "OriginalPlugin/$ORIG.plist" ]; then
  echo "build-sileowallpaper.sh: OriginalPlugin/$ORIG.{dylib,plist} not found" >&2
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

BUILD=build/sileowallpaper
DY="$BUILD/out/$FIX.dylib"

echo "build-sileowallpaper.sh: $PACKAGE_ID $VERSION（含 $FIX $FIX_VERSION）kind=$KIND archs=$ARCHS"
echo "build-sileowallpaper.sh: $(uname -s) $(uname -m)"
echo "build-sileowallpaper.sh: SDKROOT=$SDKROOT"

rm -rf "$BUILD/thin" "$BUILD/out" "$BUILD/stage"
mkdir -p "$BUILD/thin" "$BUILD/out" "$BUILD/stage"

for arch in $ARCHS; do
  mkdir -p "$BUILD/thin/$arch"
  echo "build-sileowallpaper.sh: compiling $arch"
  # shellcheck disable=SC2086
  clang -dynamiclib -arch "$arch" $SHARED_FLAGS $FRAMEWORKS $SUBSTRATE_LDFLAGS \
      -install_name "$INSTALL_NAME" \
      "$SRC/$FIX.m" \
      -o "$BUILD/thin/$arch/$FIX.dylib"
done

lipo -create "$BUILD"/thin/*/"$FIX.dylib" -output "$DY"

SLICES=$(lipo -archs "$DY")
echo "build-sileowallpaper.sh: SileoFix slices = $SLICES"
for want in $ARCHS; do
  case " $SLICES " in
    *" $want "*) ;;
    *) echo "build-sileowallpaper.sh: missing $want slice in $DY" >&2; exit 4 ;;
  esac
done

# 原插件本体两片都要有，否则 A11 上不加载。
ORIG_SLICES=$(lipo -archs "OriginalPlugin/$ORIG.dylib")
echo "build-sileowallpaper.sh: $ORIG slices = $ORIG_SLICES"
for want in $ARCHS; do
  case " $ORIG_SLICES " in
    *" $want "*) ;;
    *) echo "build-sileowallpaper.sh: missing $want slice in OriginalPlugin/$ORIG.dylib" >&2; exit 4 ;;
  esac
done

echo "build-sileowallpaper.sh: --- otool -L $FIX ---"
otool -L "$DY"
# substrate 依赖必须是相对安装路径（roothide 走 @loader_path/.jbroot/…），否则本机解析不到。
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk 'tolower($0) ~ /substrate/ {print $1; exit}')
if [ -z "$SUBSTRATE_ENTRY" ]; then
  echo "build-sileowallpaper.sh: no substrate dependency at all" >&2
  exit 5
fi
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-sileowallpaper.sh: rewriting $SUBSTRATE_ENTRY -> $WANTED_SUBSTRATE"
  install_name_tool -change "$SUBSTRATE_ENTRY" "$WANTED_SUBSTRATE" "$DY"
fi
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk 'tolower($0) ~ /substrate/ {print $1; exit}')
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-sileowallpaper.sh: substrate entry is '$SUBSTRATE_ENTRY', wanted '$WANTED_SUBSTRATE'" >&2
  exit 5
fi

echo "build-sileowallpaper.sh: --- otool -L $ORIG（原样带过去，不改）---"
otool -L "OriginalPlugin/$ORIG.dylib"

# 没签名的 dylib 不加载（修复合集是新编的，签一次）。
ldid -S "$DY"
# 原插件**不重签**：它本来就是签好的（正在本机跑），重签会改字节，
# 而这个包的卖点之一就是「本体逐字节未改」——CI 里会拿 sha256 核这件事。

# ---- 打包 ----
STAGE="$BUILD/stage"
LIBDIR="$STAGE/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$LIBDIR" "$STAGE/DEBIAN"
cp "OriginalPlugin/$ORIG.dylib" "$LIBDIR/$ORIG.dylib"
cp "OriginalPlugin/$ORIG.plist" "$LIBDIR/$ORIG.plist"
cp "$DY" "$LIBDIR/$FIX.dylib"
cp "Support/$FIX.plist" "$LIBDIR/$FIX.plist"
chmod 0755 "$LIBDIR/$ORIG.dylib" "$LIBDIR/$FIX.dylib"

plutil -lint "$LIBDIR/$ORIG.plist" "$LIBDIR/$FIX.plist"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE_ID
Version: $VERSION
Architecture: $ARCH_TAG
Name: $NAME_ZH
Section: Tweaks
Maintainer: $MAINTAINER
Author: $AUTHOR
Depends: mobilesubstrate, firmware (>= $MIN_IOS)
Conflicts: com.yangzhou.sileofix
Replaces: com.yangzhou.sileofix
Description: $DESCRIPTION
EOF

mkdir -p "$OUTDIR"
DEB="$OUTDIR/${PACKAGE_ID}_${VERSION}_${ARCH_TAG}.deb"
dpkg-deb -b --root-owner-group "$STAGE" "$DEB"

echo "build-sileowallpaper.sh: --- deb contents ---"
dpkg-deb -c "$DEB"
echo "build-sileowallpaper.sh: --- deb control ---"
dpkg-deb -I "$DEB"

# 自检：四个文件都在包里，两个 dylib 都是双片。
for want in "$ORIG.dylib" "$ORIG.plist" "$FIX.dylib" "$FIX.plist"; do
  dpkg-deb -c "$DEB" | grep -q "$want" || { echo "build-sileowallpaper.sh: $want 不在包里" >&2; exit 6; }
done
[ "$(lipo -archs "$LIBDIR/$ORIG.dylib")" = "$ORIG_SLICES" ] || {
  echo "build-sileowallpaper.sh: 包里的 $ORIG 切片数变了" >&2; exit 6; }
echo "build-sileowallpaper.sh: sha256 $DEB = $(shasum -a 256 "$DEB" | awk '{print $1}')"
echo "build-sileowallpaper.sh: wrote $DEB"
