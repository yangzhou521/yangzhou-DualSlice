#!/bin/sh
#
# YzThemeCorePlus —— 交付版 ThemeCore+ 5.2.0（Theos 工程）移植进本仓库后的构建脚本。
#
# 形状照抄本仓库 scripts/build-themecoreplus.sh（那份在 CI 上跑通过）：clang 直编，不用 Theos
# 的构建规则，只跑在 CI 的 macOS runner 上。开发机是 iPhone10,1（A11），没有可用工具链，
# **不要在本机跑**（apelin-project.json 里刻意没声明 external.script，本机 apelin_project_build 必然失败）。
#
# 一次产出两个 Mach-O：
#   1. 插件本体 YzThemeCorePlus.dylib（挂在 /Library/MobileSubstrate/DynamicLibraries/）
#   2. 设置面板 YzThemeCorePlusPrefs（bundle，挂在 /Library/PreferenceBundles/）
#
# 用法（仓库根目录）：
#   sh scripts/build-yzthemecoreplus.sh            # roothide：arm64 + arm64e（装本机的那一份）
#   sh scripts/build-yzthemecoreplus.sh rootless   # rootless：arm64（未在设备上验证过）
#
# 环境变量：
#   THEOS               theos 检出目录（默认 ./theos）
#   SDKROOT             headerless iPhoneOS SDK（默认 $THEOS/sdks/iPhoneOS16.5.sdk）
#   APELIN_PACKAGE_DIR  .deb 输出目录（默认 packages）
#
set -eu

# ── 包身份：换版本时只改这里 ＋ Sources/YzThemeCorePlusVersion.h 的 YZ_THEMECOREPLUS_VERSION ──
# 注意：PACKAGE_ID 是**交付件自己的身份**（原 control 里就是它），与本仓 1.0.38 那条线同名。
# 两条线同时装会互相抢挂 SpringBoard 的同名方法、共用同一个偏好文件，所以装机前必须先跟用户
# 定身份（换 id 或先卸旧），不许一边装一边猜。移植只保真，不在构建脚本里擅自改身份。
PRODUCT=YzThemeCorePlus
PREFS_BUNDLE=YzThemeCorePlusPrefs
PACKAGE_ID=com.yangzhou.themecoreplus
VERSION=5.2.0
NAME_ZH="ThemeCore+"
AUTHOR=yangzhou
DESCRIPTION="轻量化桌面图标与通知角标主题插件：第三方图标替换 + 桌面通知角标主题化，兼容 ThemeCore/Anemone 主题格式。作者 yangzhou。"
MIN_IOS=15.0
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
    # 隐根解析头 ApelinBootstrap.h：roothide 下用 dladdr 从本镜像路径里认 .jbroot- 前缀。
    BOOTSTRAP_DEFINE=-DAPELIN_BOOTSTRAP_ROOTHIDE
    ;;
  rootless)
    ARCHS="arm64"
    ARCH_TAG=iphoneos-arm64
    INSTALL_NAME="@loader_path/../../usr/lib/TweakInject/$PRODUCT.dylib"
    WANTED_SUBSTRATE="@loader_path/../libsubstrate.dylib"
    BOOTSTRAP_DEFINE=-DAPELIN_BOOTSTRAP_ROOTLESS
    echo "build-yzthemecoreplus.sh: 警告：rootless 腿没有被任何设备验证过（只在 roothide/A11 上验过）" >&2
    ;;
  *)
    echo "usage: $0 [roothide|rootless]" >&2
    exit 2
    ;;
esac

THEOS=${THEOS:-theos}
SDKROOT=${SDKROOT:-$THEOS/sdks/iPhoneOS16.5.sdk}
OUTDIR=${APELIN_PACKAGE_DIR:-packages}
SRC=YzThemeCorePlus/Sources
HOOKS=YzThemeCorePlus/Hooks
PREFS_SRC=YzThemeCorePlus/Prefs

for dir in "$SDKROOT" "$THEOS/vendor/include" "$SRC" "$HOOKS" "$PREFS_SRC"; do
  if [ ! -d "$dir" ]; then
    echo "build-yzthemecoreplus.sh: missing $dir" >&2
    exit 2
  fi
done

# 源码清单：与交付工程 Makefile 的 $(wildcard Hooks/*.m Sources/*.m) 逐文件对应（写死更好核）。
TWEAK_SRCS="$SRC/YzThemeCorePlusConfig.m $SRC/YzThemeCorePlusThemeStore.m \
$SRC/YzThemeCorePlusCalendarInk.m $SRC/YzThemeCorePlusCacheProbe.m \
$HOOKS/YzThemeCorePlusMain.m $HOOKS/YzThemeCorePlusIcons.m $HOOKS/YzThemeCorePlusFolders.m \
$HOOKS/YzThemeCorePlusClock.m $HOOKS/YzThemeCorePlusBadges.m"
# 面板自己扫盘、自己读写偏好，不带插件那份共享源码（与交付工程 Prefs/Makefile 的 $(wildcard *.m) 一致）。
PREFS_SRCS="$PREFS_SRC/YzThemeCorePlusRootListController.m $PREFS_SRC/YzThemeCorePlusThemeListController.m"

for file in $TWEAK_SRCS $PREFS_SRCS; do
  if [ ! -f "$file" ]; then
    echo "build-yzthemecoreplus.sh: missing source $file" >&2
    exit 2
  fi
done

# substrate：$THEOS/lib 里没有它，vendor/lib/libsubstrate.tbd 只是一行指向框架的指针。
if [ -d "$THEOS/vendor/lib/CydiaSubstrate.framework" ]; then
  SUBSTRATE_LDFLAGS="-F$THEOS/vendor/lib -framework CydiaSubstrate"
else
  SUBSTRATE_LDFLAGS="-lsubstrate"
fi

# <Preferences/PSListController.h> 只有 roothide 的私有头里才有（theos/vendor/include 是
# roothide/headers 子模块），SDK 里**没有** Preferences.framework 的头（只有 Preferences.tbd）。
# 缺了它面板编不过，所以提前把话说清，别让 CI 报一个看不懂的 file not found。
if [ ! -f "$THEOS/vendor/include/Preferences/PSListController.h" ]; then
  echo "build-yzthemecoreplus.sh: $THEOS/vendor/include/Preferences/PSListController.h 不存在" >&2
  echo "build-yzthemecoreplus.sh: theos 的 vendor/include（子模块 roothide/headers）没拉全；用 submodules: recursive 重拉" >&2
  exit 2
fi

# 面板要 PSListController / PSSpecifier。已核实：SDK 里有
# System/Library/PrivateFrameworks/Preferences.framework/Preferences.tbd，
# 所以能真链接（不需要 -undefined dynamic_lookup，也不许用它 —— dlopen 时符号全留空
# 会让「面板编译通过、装机后加载即崩」）。万一哪天 tbd 不在了才退到逐符号 -Wl,-U，
# 只放开这三个符号，其余未绑定符号仍会在链接期报错。
PREFS_LDFLAGS='-Wl,-U,_OBJC_CLASS_$_PSListController -Wl,-U,_OBJC_METACLASS_$_PSListController -Wl,-U,_OBJC_CLASS_$_PSSpecifier'
if [ -f "$SDKROOT/System/Library/PrivateFrameworks/Preferences.framework/Preferences.tbd" ]; then
  PREFS_LDFLAGS="-F$SDKROOT/System/Library/PrivateFrameworks -framework Preferences"
fi

# 该 SDK 的 UIKit.tbd 不 reexport CoreGraphics（Foundation 仍 reexport CoreFoundation），
# 凡用到 CGContext… / CGRect… 必须显式列出来（日历墨层就在用）。
SHARED_FLAGS="-fobjc-arc -miphoneos-version-min=$MIN_IOS -isysroot $SDKROOT -O2 \
-I$THEOS/vendor/include -I$SRC -I$HOOKS -IYzThemeCorePlus/Headers $BOOTSTRAP_DEFINE"
FRAMEWORKS="-framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore"

# 交付件的时钟钩子直接引用了 SBIconController 的类符号（Hooks/YzThemeCorePlusMain.m）——
# 原 Theos 工程靠 Theos 默认的 -undefined dynamic_lookup 蒙过去，本仓库铁律不许整体放开
# （dlopen 时符号全留空会让「编得过、装上崩」），所以**逐个符号** -U：只放开这一个，
# 其余未绑定符号照样在链接期报错。run 41405575032 报的就是它。
TWEAK_LDFLAGS="-Wl,-U,_OBJC_CLASS_\$_SBIconController"

BUILD=build/yzthemecoreplus
DY="$BUILD/out/$PRODUCT.dylib"
PREFS_BIN="$BUILD/out/$PREFS_BUNDLE"

echo "build-yzthemecoreplus.sh: $PACKAGE_ID $VERSION kind=$KIND archs=$ARCHS"
echo "build-yzthemecoreplus.sh: $(uname -s) $(uname -m)"
echo "build-yzthemecoreplus.sh: SDKROOT=$SDKROOT"
echo "build-yzthemecoreplus.sh: THEOS=$THEOS"
echo "build-yzthemecoreplus.sh: prefs link: $PREFS_LDFLAGS"
echo "build-yzthemecoreplus.sh: tweak extra link: $TWEAK_LDFLAGS"

rm -rf "$BUILD/thin" "$BUILD/out" "$BUILD/stage"
mkdir -p "$BUILD/thin" "$BUILD/out" "$BUILD/stage"

for arch in $ARCHS; do
  mkdir -p "$BUILD/thin/$arch"
  echo "build-yzthemecoreplus.sh: compiling $arch (tweak)"
  # shellcheck disable=SC2086
  clang -dynamiclib -arch "$arch" -fvisibility=hidden $SHARED_FLAGS $FRAMEWORKS \
      $SUBSTRATE_LDFLAGS $TWEAK_LDFLAGS \
      -install_name "$INSTALL_NAME" \
      $TWEAK_SRCS \
      -o "$BUILD/thin/$arch/$PRODUCT.dylib"

  echo "build-yzthemecoreplus.sh: compiling $arch (prefs bundle)"
  # 面板是 MH_BUNDLE，由设置 App 用 dlopen 加载；不挂站、所以不链 substrate，
  # 也不能带 -install_name（ld 只在 -dynamiclib 下接受它）。
  # shellcheck disable=SC2086
  clang -bundle -arch "$arch" $SHARED_FLAGS $FRAMEWORKS $PREFS_LDFLAGS \
      $PREFS_SRCS \
      -o "$BUILD/thin/$arch/$PREFS_BUNDLE"
done

lipo -create "$BUILD"/thin/*/"$PRODUCT.dylib" -output "$DY"
lipo -create "$BUILD"/thin/*/"$PREFS_BUNDLE" -output "$PREFS_BIN"

# ---- 切片核对：arm64 + arm64e 缺一不可，缺了就 fail 掉，别把坏包发出去 ----
for binary in "$DY" "$PREFS_BIN"; do
  SLICES=$(lipo -archs "$binary")
  echo "build-yzthemecoreplus.sh: slices($(basename "$binary")) = $SLICES"
  for want in $ARCHS; do
    case " $SLICES " in
      *" $want "*) ;;
      *) echo "build-yzthemecoreplus.sh: missing $want slice in $binary" >&2; exit 4 ;;
    esac
  done
done

# ---- 依赖形状核对：substrate 必须是相对安装路径，否则本机解析不到 ----
echo "build-yzthemecoreplus.sh: --- otool -L (tweak) ---"
otool -L "$DY"
# 依赖名是 CydiaSubstrate（大写 S）：匹配要忽略大小写。
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk 'tolower($0) ~ /substrate/ {print $1; exit}')
if [ -z "$SUBSTRATE_ENTRY" ]; then
  echo "build-yzthemecoreplus.sh: no substrate dependency at all" >&2
  exit 5
fi
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-yzthemecoreplus.sh: rewriting $SUBSTRATE_ENTRY -> $WANTED_SUBSTRATE"
  install_name_tool -change "$SUBSTRATE_ENTRY" "$WANTED_SUBSTRATE" "$DY"
fi
SUBSTRATE_ENTRY=$(otool -L "$DY" | awk 'tolower($0) ~ /substrate/ {print $1; exit}')
if [ "$SUBSTRATE_ENTRY" != "$WANTED_SUBSTRATE" ]; then
  echo "build-yzthemecoreplus.sh: substrate entry is '$SUBSTRATE_ENTRY', wanted '$WANTED_SUBSTRATE'" >&2
  exit 6
fi

echo "build-yzthemecoreplus.sh: --- otool -L (prefs bundle) ---"
otool -L "$PREFS_BIN"
# 面板不许有 substrate 依赖（它不挂站）。
if otool -L "$PREFS_BIN" | grep -qi substrate; then
  echo "build-yzthemecoreplus.sh: prefs bundle must not link substrate" >&2
  exit 7
fi
echo "build-yzthemecoreplus.sh: --- undefined symbols (prefs bundle) ---"
nm -u "$PREFS_BIN" | sort -u > "$BUILD/prefs-undefined.txt"
cat "$BUILD/prefs-undefined.txt"
UNEXPECTED=$(grep -v -E '^_?OBJC_(CLASS|METACLASS)_\$_PS(ListController|Specifier)$' "$BUILD/prefs-undefined.txt" \
             | grep -v -E '^$|^_?objc_|^_?NS|^_?UI|^_?CG|^_?CF|^_?dispatch|^dyld_stub|^_[A-Za-z_]*$' || true)
if [ -n "$UNEXPECTED" ]; then
  echo "build-yzthemecoreplus.sh: 面板还有未绑定的符号：" >&2
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
# 源文件叫 …PreferenceLoader.plist，装进包里按插件名 YzThemeCorePlus.plist。
cp "Support/YzThemeCorePlusPreferenceLoader.plist" \
   "$STAGE/Library/PreferenceLoader/Preferences/$PRODUCT.plist"
plutil -lint "$STAGE/Library/PreferenceLoader/Preferences/$PRODUCT.plist"

cp "$PREFS_BIN" "$PREFS_STAGE/$PREFS_BUNDLE"
cp "$PREFS_SRC/Info.plist" "$PREFS_SRC/YzThemeCorePlusRoot.plist" "$PREFS_STAGE/"
# 设置里那一行的小图标：入口 plist 的 icon 键写的是 "icon"，所以包里得是 icon.png / icon@2x / icon@3x。
# 交付件自己带的是 Prefs/icon@2x.png（96×96，96 个字节头其实是 JPEG）—— 它的字节一个不改照抄成 2x，
# 另两档在 CI 上用 sips 从它转正成真 PNG 并缩到 29 / 87；CI 上没有 sips 时三档都用同一份字节。
cp "$PREFS_SRC/icon@2x.png" "$PREFS_STAGE/icon@2x.png"
if command -v sips >/dev/null 2>&1; then
  sips -s format png -z 29 29 "$PREFS_SRC/icon@2x.png" --out "$PREFS_STAGE/icon.png" >/dev/null
  sips -s format png -z 87 87 "$PREFS_SRC/icon@2x.png" --out "$PREFS_STAGE/icon@3x.png" >/dev/null
else
  cp "$PREFS_SRC/icon@2x.png" "$PREFS_STAGE/icon.png"
  cp "$PREFS_SRC/icon@2x.png" "$PREFS_STAGE/icon@3x.png"
fi
for staged_icon in "$PREFS_STAGE"/icon.png "$PREFS_STAGE"/icon@2x.png "$PREFS_STAGE"/icon@3x.png; do
  echo "build-yzthemecoreplus.sh: $(basename "$staged_icon") $(file -b "$staged_icon") $([ -n "$(command -v sips)" ] && sips -g pixelWidth -g pixelHeight "$staged_icon" | tr -d ' \n' || echo '')"
done
# 版本只有一处来源：拷进包之后按 VERSION 改写 Info.plist，防止两处漂移。
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PREFS_STAGE/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$PREFS_STAGE/Info.plist"
plutil -lint "$PREFS_STAGE/Info.plist"
echo "build-yzthemecoreplus.sh: bundle Info.plist version = $(plutil -extract CFBundleShortVersionString raw "$PREFS_STAGE/Info.plist")"

# 维护者脚本：装完让「设置」自己重读面板（更轻的「注销」）。
# 面板 bundle 是设置 App 打开面板时才 dlopen 进来的，设置 App 不重启就一直用内存里的旧代码。
# 杀掉设置 App 进程只影响设置本身，别的 App 与界面状态都不动；当时没在跑就静默跳过。
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

echo "build-yzthemecoreplus.sh: --- deb contents ---"
dpkg-deb -c "$DEB"
echo "build-yzthemecoreplus.sh: --- deb control ---"
dpkg-deb -I "$DEB"
echo "build-yzthemecoreplus.sh: sha256 $DEB = $(shasum -a 256 "$DEB" | awk '{print $1}')"
echo "build-yzthemecoreplus.sh: wrote $DEB"
