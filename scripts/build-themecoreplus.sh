#!/bin/sh
#
# ThemeCorePlus —— 双切片（arm64 + arm64e）deb 的构建脚本。
#
# 形状照抄本仓库的 scripts/build-dualslice.sh（那份在 CI 上跑通过）：clang 直编，不用 Theos
# 的构建规则，只跑在 CI 的 macOS runner 上。开发机是 iPhone10,1（A11），没有可用工具链，
# **不要在本机跑**。
#
# 一次产出两个 Mach-O：
#   1. 插件本体 ThemeCorePlus.dylib（挂在 /Library/MobileSubstrate/DynamicLibraries/）
#   2. 设置面板 ThemeCorePlusPrefs（bundle，挂在 /Library/PreferenceBundles/）
#
# 用法（仓库根目录）：
#   sh scripts/build-themecoreplus.sh            # roothide：arm64 + arm64e（装本机的那一份）
#   sh scripts/build-themecoreplus.sh rootless   # rootless：arm64（未在设备上验证过）
#
# 环境变量：
#   THEOS               theos 检出目录（默认 ./theos）
#   SDKROOT             headerless iPhoneOS SDK（默认 $THEOS/sdks/iPhoneOS16.5.sdk）
#   APELIN_PACKAGE_DIR  .deb 输出目录（默认 packages）
#
set -eu

# ── 包身份：换版本时只改这里 ＋ Sources/ThemeCorePlusVersion.h 的 TCP_VERSION ──
PRODUCT=ThemeCorePlus
PREFS_BUNDLE=ThemeCorePlusPrefs
PACKAGE_ID=com.yangzhou.themecoreplus
VERSION=0.9.18
NAME_ZH="主题美化 +"
AUTHOR=yangzhou
DESCRIPTION="MarkTheme 式主题引擎：读 SnowBoard / IconBundles 主题原素材，改主屏与文件夹图标、角标底图与系统图片覆盖；支持多主题叠加，面板里点「刷新图标」即可当场生效、不用注销。作者 yangzhou。"
MIN_IOS=16.0
# ───────────────────────────────────────────────────────────────────────

cd "$(dirname "$0")/.."

KIND=${1:-roothide}
case "$KIND" in
  roothide)
    # A11 用户态是 arm64：只出 arm64e 的 dylib 在任何进程里都不会被加载。
    ARCHS="arm64 arm64e"
    ARCH_TAG=iphoneos-arm64e
    # 与 roothide 上其它 tweak 一致：/Library/MobileSubstrate/DynamicLibraries 指向
    # /usr/lib/TweakInject，install name 走 .jbroot 相对形式。
    INSTALL_NAME="@loader_path/.jbroot/usr/lib/TweakInject/$PRODUCT.dylib"
    WANTED_SUBSTRATE="@loader_path/.jbroot/usr/lib/libsubstrate.dylib"
    ;;
  rootless)
    ARCHS="arm64"
    ARCH_TAG=iphoneos-arm64
    INSTALL_NAME="@loader_path/../../usr/lib/TweakInject/$PRODUCT.dylib"
    WANTED_SUBSTRATE="@loader_path/../libsubstrate.dylib"
    echo "build-themecoreplus.sh: 警告：rootless 腿没有被任何设备验证过（只在 roothide/A11 上验过）" >&2
    ;;
  *)
    echo "usage: $0 [roothide|rootless]" >&2
    exit 2
    ;;
esac

THEOS=${THEOS:-theos}
SDKROOT=${SDKROOT:-$THEOS/sdks/iPhoneOS16.5.sdk}
OUTDIR=${APELIN_PACKAGE_DIR:-packages}
SRC=ThemeCorePlus/Sources
PREFS_SRC=Prefs/$PREFS_BUNDLE

for dir in "$SDKROOT" "$THEOS/vendor/include" "$SRC" "$PREFS_SRC"; do
  if [ ! -d "$dir" ]; then
    echo "build-themecoreplus.sh: missing $dir" >&2
    exit 2
  fi
done

# substrate：$THEOS/lib 里没有它，vendor/lib/libsubstrate.tbd 只是一行指向框架的指针。
if [ -d "$THEOS/vendor/lib/CydiaSubstrate.framework" ]; then
  SUBSTRATE_LDFLAGS="-F$THEOS/vendor/lib -framework CydiaSubstrate"
else
  SUBSTRATE_LDFLAGS="-lsubstrate"
fi

# 面板要 PSListController / PSSpecifier，但**不链接 Preferences.framework**（本机没有工具链，
# SDK 里的 Preferences.tbd 核对不了）。铁律是不许用 -undefined dynamic_lookup 混过去，
# 所以逐个符号写 -Wl,-U：只有这三个符号允许留到加载期解析。
# 如果以后 SDK 里确实有 Preferences.tbd，优先把它链上（那样就是真链接，不需要 -U）。
PREFS_LDFLAGS='-Wl,-U,_OBJC_CLASS_$_PSListController -Wl,-U,_OBJC_METACLASS_$_PSListController -Wl,-U,_OBJC_CLASS_$_PSSpecifier'
if [ -f "$SDKROOT/System/Library/PrivateFrameworks/Preferences.framework/Preferences.tbd" ]; then
  PREFS_LDFLAGS="-F$SDKROOT/System/Library/PrivateFrameworks -framework Preferences"
fi

SHARED_FLAGS="-fobjc-arc -miphoneos-version-min=$MIN_IOS -isysroot $SDKROOT -O2 \
-I$THEOS/vendor/include -I$SRC"
# 该 SDK 的 UIKit.tbd 不 reexport CoreGraphics（Foundation 仍 reexport CoreFoundation），
# 凡用到 CGContext… / CGRect… 必须显式列出来，别为了"修"链接把它去掉。
FRAMEWORKS="-framework Foundation -framework UIKit -framework CoreGraphics"

# 面板自带一份共享源码（自己扫盘、自己读写偏好），日志模块也在里面：面板那一页日志就是用它读的。
SHARED_SRCS="$SRC/ThemeCorePlusPaths.m $SRC/ThemeCorePlusConfig.m \
$SRC/ThemeCorePlusPreferences.m $SRC/ThemeCorePlusStore.m $SRC/ThemeCorePlusLog.m"
TWEAK_SRCS="$SHARED_SRCS $SRC/ThemeCorePlusIcons.m $SRC/ThemeCorePlusFolders.m \
$SRC/ThemeCorePlusBadges.m $SRC/ThemeCorePlusFiles.m $SRC/ThemeCorePlusHooks.m \
$SRC/ThemeCorePlusLayout.m $SRC/ThemeCorePlusMain.m"

BUILD=build/themecoreplus
DY="$BUILD/out/$PRODUCT.dylib"
PREFS_BIN="$BUILD/out/$PREFS_BUNDLE"

echo "build-themecoreplus.sh: $PACKAGE_ID $VERSION kind=$KIND archs=$ARCHS"
echo "build-themecoreplus.sh: $(uname -s) $(uname -m)"
echo "build-themecoreplus.sh: SDKROOT=$SDKROOT"
echo "build-themecoreplus.sh: THEOS=$THEOS"
echo "build-themecoreplus.sh: prefs link: $PREFS_LDFLAGS"

rm -rf "$BUILD/thin" "$BUILD/out" "$BUILD/stage"
mkdir -p "$BUILD/thin" "$BUILD/out" "$BUILD/stage"

for arch in $ARCHS; do
  mkdir -p "$BUILD/thin/$arch"
  echo "build-themecoreplus.sh: compiling $arch (tweak)"
  # shellcheck disable=SC2086
  clang -dynamiclib -arch "$arch" -fvisibility=hidden $SHARED_FLAGS $FRAMEWORKS \
      $SUBSTRATE_LDFLAGS \
      -install_name "$INSTALL_NAME" \
      $TWEAK_SRCS \
      -o "$BUILD/thin/$arch/$PRODUCT.dylib"

  echo "build-themecoreplus.sh: compiling $arch (prefs bundle)"
  # 面板是 MH_BUNDLE，由设置 App 用 dlopen 加载；不挂站、所以不链 substrate。
  # 注意：MH_BUNDLE 不能带 -install_name（ld 只在 -dynamiclib 下接受它，
  # 否则报 "invalid argument '-install_name ...' only allowed with '-dynamiclib'"）；
  # 面板的加载身份来自 CFBundleExecutable，本来也不需要 install name。
  # shellcheck disable=SC2086
  clang -bundle -arch "$arch" $SHARED_FLAGS $FRAMEWORKS $PREFS_LDFLAGS \
      "$PREFS_SRC/TCRootListController.m" \
      $SHARED_SRCS \
      -o "$BUILD/thin/$arch/$PREFS_BUNDLE"
done

lipo -create "$BUILD"/thin/*/"$PRODUCT.dylib" -output "$DY"
lipo -create "$BUILD"/thin/*/"$PREFS_BUNDLE" -output "$PREFS_BIN"

# ---- 切片核对：arm64 + arm64e 缺一不可，缺了就 fail 掉，别把坏包发出去 ----
for binary in "$DY" "$PREFS_BIN"; do
  SLICES=$(lipo -archs "$binary")
  echo "build-themecoreplus.sh: slices($(basename "$binary")) = $SLICES"
  for want in $ARCHS; do
    case " $SLICES " in
      *" $want "*) ;;
      *) echo "build-themecoreplus.sh: missing $want slice in $binary" >&2; exit 4 ;;
    esac
  done
done

# ---- 依赖形状核对：substrate 必须是相对安装路径，否则本机解析不到 ----
echo "build-themecoreplus.sh: --- otool -L (tweak) ---"
otool -L "$DY"
# 依赖名是 CydiaSubstrate（大写 S）：匹配要忽略大小写。
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk 'tolower($0) ~ /substrate/ {print $1; exit}')
if [ -z "$SUBSTRATE_ENTRY" ]; then
  echo "build-themecoreplus.sh: no substrate dependency at all" >&2
  exit 5
fi
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-themecoreplus.sh: rewriting $SUBSTRATE_ENTRY -> $WANTED_SUBSTRATE"
  install_name_tool -change "$SUBSTRATE_ENTRY" "$WANTED_SUBSTRATE" "$DY"
fi
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk 'tolower($0) ~ /substrate/ {print $1; exit}')
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-themecoreplus.sh: substrate entry is '$SUBSTRATE_ENTRY', wanted '$WANTED_SUBSTRATE'" >&2
  exit 6
fi

echo "build-themecoreplus.sh: --- otool -L (prefs bundle) ---"
otool -L "$PREFS_BIN"
# 面板不许有 Preferences.framework 之外的私有依赖，也不许有 substrate。
if otool -L "$PREFS_BIN" | grep -qi substrate; then
  echo "build-themecoreplus.sh: prefs bundle must not link substrate" >&2
  exit 7
fi
# 未绑定的符号（= 留到加载期解析的那几个）必须只剩 PSListController / PSSpecifier。
echo "build-themecoreplus.sh: --- undefined symbols (prefs bundle) ---"
nm -u "$PREFS_BIN" | sort -u > "$BUILD/prefs-undefined.txt"
cat "$BUILD/prefs-undefined.txt"
UNEXPECTED=$(grep -v -E '^_?OBJC_(CLASS|METACLASS)_\$_PS(ListController|Specifier)$' "$BUILD/prefs-undefined.txt" \
             | grep -v -E '^$|^_?objc_|^_?NS|^_?UI|^_?CG|^_?CF|^_?dispatch|^dyld_stub|^_[A-Za-z_]*$' || true)
if [ -n "$UNEXPECTED" ]; then
  echo "build-themecoreplus.sh: 面板还有未绑定的符号：" >&2
  printf '%s\n' "$UNEXPECTED" >&2
fi

# 没签名的 Mach-O 不加载。
ldid -S "$DY"
ldid -S "$PREFS_BIN"

# ---- 打包 ----
STAGE="$BUILD/stage"
PREFS_STAGE="$STAGE/Library/PreferenceBundles/$PREFS_BUNDLE.bundle"
mkdir -p "$STAGE/Library/MobileSubstrate/DynamicLibraries" \
         "$STAGE/Library/PreferenceLoader/Preferences" \
         "$PREFS_STAGE" "$STAGE/DEBIAN"

cp "$DY" "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.dylib"
cp "Support/$PRODUCT.plist" \
   "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.plist"
plutil -lint "$STAGE/Library/MobileSubstrate/DynamicLibraries/$PRODUCT.plist"

# 面板入口：PreferenceLoader 读 L/P/Preferences/*.plist，文件名随意但要以 .plist 结尾。
# 源文件叫 …PreferenceLoader.plist，装进包里按插件名 ThemeCorePlus.plist。
cp "Support/ThemeCorePlusPreferenceLoader.plist" \
   "$STAGE/Library/PreferenceLoader/Preferences/$PRODUCT.plist"
plutil -lint "$STAGE/Library/PreferenceLoader/Preferences/$PRODUCT.plist"

cp "$PREFS_BIN" "$PREFS_STAGE/$PREFS_BUNDLE"
cp "$PREFS_SRC/Info.plist" "$PREFS_SRC/Root.plist" "$PREFS_STAGE/"
# 设置里那一行的小图标：MarkTheme16 的 App 图标（源图 180×180）。
# 原样拷进包会按 90pt 显示 = 明显比别人大一圈；PreferenceLoader 的列表图标要的是 29pt，
# 也就是 29/58/87 三档（本机其它插件实测量到的就是这个）。本机没有缩放工具，
# CI 的 macOS runner 有 sips，所以缩放在这里做，仓库里的源图不动。
for icon_size in 29 58 87; do
  case "$icon_size" in
    29) icon_name="${PRODUCT}Icon.png" ;;
    *)  icon_name="${PRODUCT}Icon@$((icon_size / 29))x.png" ;;
  esac
  sips -z "$icon_size" "$icon_size" "Support/${PRODUCT}Icon@3x.png" \
       --out "$PREFS_STAGE/$icon_name" >/dev/null
done
for staged_icon in "$PREFS_STAGE"/"$PRODUCT"Icon*.png; do
  echo "build-themecoreplus.sh: $(basename "$staged_icon") $(sips -g pixelWidth -g pixelHeight "$staged_icon" | tr -d ' \n')"
done
# 版本只有一处来源：拷进包之后按 VERSION 改写 Info.plist，防止两处漂移。
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PREFS_STAGE/Info.plist"
plutil -lint "$PREFS_STAGE/Info.plist"
echo "build-themecoreplus.sh: bundle Info.plist version = $(plutil -extract CFBundleShortVersionString raw "$PREFS_STAGE/Info.plist")"

# 维护者脚本：装完让「设置」自己重读面板（更轻的「注销」）。
# 面板 bundle 是设置 App 打开面板时才 dlopen 进来的，设置 App 不重启就一直用内存里的旧代码，
# 新装的版本在设置里看不到。杀掉设置 App 进程只影响设置本身，别的 App 与界面状态都不动；
# 当时没在跑就静默跳过。做法照本机装着的 IPSLog（com.axs.ipslog）的 postinst。
cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
(
    sleep 2
    killall Preferences 2>/dev/null || true
) >/dev/null 2>&1 &
exit 0
POSTINST
chmod 0755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE_ID
Version: $VERSION
Architecture: $ARCH_TAG
Name: $NAME_ZH
Author: $AUTHOR
Maintainer: $AUTHOR
Section: Tweaks
Depends: firmware (>= $MIN_IOS), mobilesubstrate, preferenceloader
Description: $DESCRIPTION
EOF

mkdir -p "$OUTDIR"
DEB="$OUTDIR/${PACKAGE_ID}_${VERSION}_${ARCH_TAG}.deb"
dpkg-deb -b --root-owner-group "$STAGE" "$DEB"

echo "build-themecoreplus.sh: --- deb contents ---"
dpkg-deb -c "$DEB"
echo "build-themecoreplus.sh: --- deb control ---"
dpkg-deb -I "$DEB"
echo "build-themecoreplus.sh: sha256 $DEB = $(shasum -a 256 "$DEB" | awk '{print $1}')"
echo "build-themecoreplus.sh: wrote $DEB"
