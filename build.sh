#!/bin/sh
# Builds NotchControl.app with Swift Package Manager (no Xcode needed).
# Usage: ./build.sh            -> build/NotchControl.app
#        ./build.sh --install  -> also copies it to ~/Applications and launches it
set -e
cd "$(dirname "$0")"
swift build -c release
BIN=.build/release
APP=build/NotchControl.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/NotchControl" "$APP/Contents/MacOS/"
cp "$BIN/notchcontrol-bridge" "$APP/Contents/Helpers/"
cp Resources/Info.plist "$APP/Contents/"
if [ ! -f Resources/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swift Tools/make-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
if [ "$1" = "--install" ]; then
    pkill -x NotchControl 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/NotchControl.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/NotchControl.app"
    echo "Installed and launched ~/Applications/NotchControl.app"
fi
