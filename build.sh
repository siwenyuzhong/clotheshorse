#!/bin/bash
# 晾衣架 —— 无 Xcode 也能构建：swiftc 编译 universal 二进制 → 组装 .app → ad-hoc 签名 → 打 DMG
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.0"
APP_NAME="晾衣架"
EXEC_NAME="Clothesline"
BUNDLE_ID="com.clotheshorse.app"
DIST="dist"
APP="$DIST/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path)"
MIN_OS="13.0"

step() { printf "\n\033[1;36m==> %s\033[0m\n" "$1"; }

step "1/6 自检核心逻辑"
mkdir -p build
swiftc -swift-version 5 -sdk "$SDK" -target "arm64-apple-macos$MIN_OS" \
    $(ls Sources/*.swift | grep -v 'main.swift') Tools/main.swift -o build/selftest
# 自检跑在临时目录里，绝不碰 ~/Library/Application Support/Clothesline 的用户数据
rm -rf /tmp/clothesline-selftest
CLOTHESLINE_STORE_DIR=/tmp/clothesline-selftest build/selftest

step "2/6 生成应用图标"
swift -swift-version 5 -sdk "$SDK" Tools/icon/main.swift build/iconset >/dev/null
rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
cp build/iconset/icon_*.png build/AppIcon.iconset/
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

step "3/6 编译通用二进制 (arm64 + x86_64)"
SOURCES=$(ls Sources/*.swift)
swiftc -swift-version 5 -O -sdk "$SDK" -target "arm64-apple-macos$MIN_OS" $SOURCES -o build/$EXEC_NAME-arm64
if swiftc -swift-version 5 -O -sdk "$SDK" -target "x86_64-apple-macos$MIN_OS" $SOURCES -o build/$EXEC_NAME-x86_64 2>/dev/null; then
    lipo -create build/$EXEC_NAME-arm64 build/$EXEC_NAME-x86_64 -output build/$EXEC_NAME
    echo "    已产出通用二进制"
else
    cp build/$EXEC_NAME-arm64 build/$EXEC_NAME
    echo "    x86_64 编译不可用，仅产出 Apple Silicon 二进制"
fi

step "4/6 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp build/$EXEC_NAME "$APP/Contents/MacOS/$EXEC_NAME"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/$EXEC_NAME"

step "5/6 ad-hoc 签名"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" 2>&1 | sed 's/^/    /'
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

step "6/6 制作 DMG"
STAGE="$DIST/stage"
rm -rf "$STAGE" "$DIST/$APP_NAME-$VERSION.dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO \
    "$DIST/$APP_NAME-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

DMG="$DIST/$APP_NAME-$VERSION.dmg"
printf "\n\033[1;32m完成\033[0m  %s (%s)\n" "$DMG" "$(du -h "$DMG" | cut -f1 | xargs)"
echo "安装：打开 dmg → 把「晾衣架」拖到「应用程序」→ 首次打开右键选「打开」"
