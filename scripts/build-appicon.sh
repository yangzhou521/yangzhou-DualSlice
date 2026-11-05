#!/bin/sh
#
# AppIcon —— 双切片（arm64 + arm64e）deb 的构建脚本。
#
# 结构对照 ThemeCore 0.5.1（com.susudear.themecore）：
#   单个 dylib 挂 /Library/MobileSubstrate/DynamicLibraries/，同名 .plist 做过滤器，
#   Architecture 写 iphoneos-arm64e，postinst/postrm 同形状。
#   另加设置面板（ThemeCore 0.5.1 也有 ThemeCorePrefs.bundle）：
#     /Library/PreferenceBundles/AppIconPrefs.bundle     面板本体
#     /Library/PreferenceLoader/Preferences/AppIcon/Root.plist  设置里那一行
#
# 只跑在 CI 的 macOS runner 上。开发机是 iPhone10,1（A11），装不了 Command Line Tools，
# **不要在本机跑**。
#
# 用法（仓库根目录）：
#   sh scripts/build-appicon.sh
#
# 环境变量：THEOS / SDKROOT / APELIN_PACKAGE_DIR
#
set -eu

# ── 包身份：换版本时只改这里 ＋ ThemeCoreX/Sources/TCXVersion.h 的 TCX_VERSION ──
PRODUCT=AppIcon
PACKAGE_ID=com.yangzhou.appicon
VERSION=0.0.8
NAME=AppIcon
AUTHOR=yangzhou
DESCRIPTION="轻量化桌面图标主题插件，修改图标、图标角标及图标阴影如此轻松，覆盖绝大部分区域，时钟日历可动态图标。作者 yangzhou。"
MIN_IOS=15.0
ARCH_TAG=iphoneos-arm64e
# ───────────────────────────────────────────────────────────────────────────

cd "$(dirname "$0")/.."

ARCHS="arm64 arm64e"

THEOS=${THEOS:-theos}
SDKROOT=${SDKROOT:-$THEOS/sdks/iPhoneOS16.5.sdk}
OUTDIR=${APELIN_PACKAGE_DIR:-packages}

SRC=ThemeCoreX/Sources
HOOKS=ThemeCoreX/Hooks
HEADERS=ThemeCoreX/Headers

for dir in "$SDKROOT" "$THEOS/vendor/include" "$SRC" "$HOOKS" "$HEADERS"; do
  if [ ! -d "$dir" ]; then
    echo "build-appicon.sh: missing $dir" >&2
    exit 2
  fi
done

if [ -d "$THEOS/vendor/lib/CydiaSubstrate.framework" ]; then
  SUBSTRATE_LDFLAGS="-F$THEOS/vendor/lib -framework CydiaSubstrate"
else
  SUBSTRATE_LDFLAGS="-lsubstrate"
fi

SHARED_FLAGS="-fobjc-arc -miphoneos-version-min=$MIN_IOS -isysroot $SDKROOT -O2 \
-I$THEOS/vendor/include -I$SRC -I$HEADERS"
FRAMEWORKS="-framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore"

SRCS="$SRC/TCXStore.m $HOOKS/TCXMain.m $HOOKS/TCXIcons.m \
$HOOKS/TCXShadow.m $HOOKS/TCXBadge.m $HOOKS/TCXClock.m $HOOKS/TCXCalendar.m \
$HOOKS/TCXBundleImages.m $HOOKS/TCXFolders.m"

PREFS_SRC=Prefs/AppIconPrefs

BUILD=build/appicon
DY="$BUILD/out/$PRODUCT.dylib"

echo "build-appicon.sh: $PACKAGE_ID $VERSION archs=$ARCHS"
echo "build-appicon.sh: $(uname -s) $(uname -m)"
echo "build-appicon.sh: SDKROOT=$SDKROOT"
echo "build-appicon.sh: sources:"
for f in $SRCS; do echo "  $f"; done

rm -rf "$BUILD/thin" "$BUILD/out" "$BUILD/stage"
mkdir -p "$BUILD/thin" "$BUILD/out" "$BUILD/stage"

for arch in $ARCHS; do
  mkdir -p "$BUILD/thin/$arch"
  echo "build-appicon.sh: compiling $arch (tweak)"
  # shellcheck disable=SC2086
  clang -dynamiclib -arch "$arch" -fvisibility=hidden $SHARED_FLAGS $FRAMEWORKS \
      $SUBSTRATE_LDFLAGS \
      -install_name "@loader_path/.jbroot/usr/lib/TweakInject/$PRODUCT.dylib" \
      $SRCS \
      -o "$BUILD/thin/$arch/$PRODUCT.dylib"

  echo "build-appicon.sh: compiling $arch (prefs bundle)"
  # 面板只声明 PSListController / PSSpecifier（不 import Preferences 头、不链接该框架），
  # 所以 -undefined dynamic_lookup 兜住一切运行时才有的符号。
  # shellcheck disable=SC2086
  clang -bundle -arch "$arch" -fvisibility=hidden $SHARED_FLAGS $FRAMEWORKS \
      -undefined dynamic_lookup \
      "$PREFS_SRC/TCXRootListController.m" \
      -o "$BUILD/thin/$arch/AppIconPrefs"
done

lipo -create "$BUILD"/thin/*/"$PRODUCT.dylib" -output "$DY"
lipo -create "$BUILD"/thin/*/AppIconPrefs -output "$BUILD/out/AppIconPrefs"

# ---- 切片核对：两片缺一不可 ----
SLICES=$(lipo -archs "$DY")
echo "build-appicon.sh: slices = $SLICES"
for want in $ARCHS; do
  case " $SLICES " in
    *" $want "*) ;;
    *) echo "build-appicon.sh: missing $want slice" >&2; exit 4 ;;
  esac
done

# ---- 依赖形状核对：substrate 必须是 .jbroot 相对路径 ----
# ⚠️ otool -L 的第 1 行是文件本身（"build/.../AppIcon.dylib:"），第 2 行是**自己的
# LC_ID_DYLIB**（install name，可能含 "MobileSubstrate" 字样）。只按 /substrate/ 抓第一行
# 会抓到自己的 ID，而 install_name_tool -change 改不了 ID（只改依赖）→ 核对永远失败、
# 以 exit 6 挂掉（run 42007994411 就是这样）。所以 NR==1 / NR==2 都跳过，只在依赖里找。
echo "build-appicon.sh: --- otool -L ---"
otool -L "$DY"
WANTED_SUBSTRATE="@loader_path/.jbroot/usr/lib/libsubstrate.dylib"
SUBSTRATE_AWK='NR==1 || NR==2 { next } { p=$1 } tolower(p) ~ /substrate/ { print p; exit }'
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk "$SUBSTRATE_AWK")
if [ -z "$SUBSTRATE_ENTRY" ]; then
  echo "build-appicon.sh: no substrate dependency at all" >&2
  exit 5
fi
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-appicon.sh: rewriting $SUBSTRATE_ENTRY -> $WANTED_SUBSTRATE" >&2
  install_name_tool -change "$SUBSTRATE_ENTRY" "$WANTED_SUBSTRATE" "$DY"
fi
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk "$SUBSTRATE_AWK")
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-appicon.sh: substrate entry is '$SUBSTRATE_ENTRY', wanted '$WANTED_SUBSTRATE'" >&2
  otool -L "$DY" >&2
  exit 6
fi

# 没签名的 Mach-O 不加载。
ldid -S "$DY"

# ---- 打包 ----
STAGE="$BUILD/stage"
mkdir -p "$STAGE/Library/MobileSubstrate/DynamicLibraries" "$STAGE/DEBIAN"

cp "$DY" "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.dylib"
cp "Support/$PRODUCT.plist" \
   "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.plist"
plutil -lint "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.plist"

# ---- 设置面板 bundle（设置 ▸ AppIcon）----
PREFS_BUNDLE="$STAGE/Library/PreferenceBundles/AppIconPrefs.bundle"
mkdir -p "$PREFS_BUNDLE"
cp "$BUILD/out/AppIconPrefs" "$PREFS_BUNDLE/AppIconPrefs"
cp "$PREFS_SRC/Info.plist" "$PREFS_BUNDLE/Info.plist"
cp "$PREFS_SRC/Root.plist" "$PREFS_BUNDLE/Root.plist"
for lproj in en.lproj zh-Hans.lproj; do
  if [ -d "$PREFS_SRC/$lproj" ]; then
    mkdir -p "$PREFS_BUNDLE/$lproj"
    cp "$PREFS_SRC/$lproj/"*.strings "$PREFS_BUNDLE/$lproj/"
  fi
done
# 版本只写两处（TCXVersion.h 与本脚本 VERSION），Info.plist 在这里跟上，少一个地方要同步。
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PREFS_BUNDLE/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$PREFS_BUNDLE/Info.plist"
plutil -lint "$PREFS_BUNDLE/Info.plist" "$PREFS_BUNDLE/Root.plist" \
            "$PREFS_BUNDLE/en.lproj/Root.strings" "$PREFS_BUNDLE/zh-Hans.lproj/Root.strings"
ldid -S "$PREFS_BUNDLE/AppIconPrefs"
echo "build-appicon.sh: prefs slices = $(lipo -archs "$PREFS_BUNDLE/AppIconPrefs")"

# ---- PreferenceLoader 入口：设置里那一行 ----
mkdir -p "$STAGE/Library/PreferenceLoader/Preferences/AppIcon"
cp Support/AppIconPreferenceLoader.plist \
   "$STAGE/Library/PreferenceLoader/Preferences/AppIcon/Root.plist"
plutil -lint "$STAGE/Library/PreferenceLoader/Preferences/AppIcon/Root.plist"
# 设置里那一行的图标：入口 plist 的 icon=AppIcon.png 相对**入口目录**与 Bundle 目录都能找，
# 两处都放一份，避免不同 PreferenceLoader 版本找法不一致时又变成「只有文字没有图标」。
cp Support/AppIcon.png Support/AppIcon@2x.png \
   "$STAGE/Library/PreferenceLoader/Preferences/AppIcon/"
cp Support/AppIcon.png Support/AppIcon@2x.png "$PREFS_BUNDLE/"

# postinst / postrm：与 ThemeCore 0.5.1 同形状（建 Themes 与 Preferences 目录、踢 sharingd）。
cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh

set -u

if [ "${1:-configure}" != "configure" ]; then
    exit 0
fi

ROOT_PREFIX=""
if [ -d /var/jb ]; then
    ROOT_PREFIX="/var/jb"
else
    for candidate in /var/containers/Bundle/Application/.jbroot-*; do
        if [ -d "$candidate" ]; then
            ROOT_PREFIX="$candidate"
            break
        fi
    done
fi

THEMES_DIR="$ROOT_PREFIX/Library/Themes"
PREFERENCES_DIR="$ROOT_PREFIX/var/mobile/Library/Preferences"
mkdir -p "$THEMES_DIR" >/dev/null 2>&1 || true
chown mobile:mobile "$THEMES_DIR" >/dev/null 2>&1 || true
chmod 0775 "$THEMES_DIR" >/dev/null 2>&1 || true
mkdir -p "$PREFERENCES_DIR" >/dev/null 2>&1 || true
chown mobile:mobile "$PREFERENCES_DIR" >/dev/null 2>&1 || true
chmod 0775 "$PREFERENCES_DIR" >/dev/null 2>&1 || true

if command -v killall >/dev/null 2>&1; then
    killall sharingd >/dev/null 2>&1 || true
fi

exit 0
POSTINST
chmod 0755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh

if command -v killall >/dev/null 2>&1; then
    killall sharingd >/dev/null 2>&1 || true
fi

exit 0
POSTRM
chmod 0755 "$STAGE/DEBIAN/postrm"

# Installed-Size 按 theme 包同样算法给出（KB，向上取整）。
INSTALLED_SIZE=$(du -sk "$STAGE" | awk '{print $1}')

# Pre-Depends: rootless-compat —— roothide 上 dylib 的 .jbroot 相对依赖要它改写到实际引导根。
# ThemeCore 0.5.1 同样声明了它；缺这条时插件能被 ellekit 看见却不保证依赖解析得动，
# 表现就是「没闪退，但一个站都没挂上、一个素材都没加载」。
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE_ID
Section: Tweaks
Installed-Size: $INSTALLED_SIZE
Maintainer: $AUTHOR
Architecture: $ARCH_TAG
Version: $VERSION
Depends: mobilesubstrate (>= 0.9.5000), preferenceloader, firmware (>= $MIN_IOS)
Pre-Depends: rootless-compat (>= 0.9)
Description: $DESCRIPTION
Name: $NAME
Author: $AUTHOR
EOF

mkdir -p "$OUTDIR"
DEB="$OUTDIR/${PACKAGE_ID}_${VERSION}_${ARCH_TAG}.deb"
dpkg-deb -b --root-owner-group "$STAGE" "$DEB"

# Release 资产名按用户要求：AppIcon0.0.1-arm64e.deb
ASSET="$OUTDIR/${PRODUCT}${VERSION}-arm64e.deb"
cp "$DEB" "$ASSET"

echo "build-appicon.sh: --- deb contents ---"
dpkg-deb -c "$DEB"
echo "build-appicon.sh: --- deb control ---"
dpkg-deb -I "$DEB"
echo "build-appicon.sh: sha256($DEB) = $(shasum -a 256 "$DEB" | awk '{print $1}')"
echo "build-appicon.sh: wrote $DEB"
echo "build-appicon.sh: wrote $ASSET"