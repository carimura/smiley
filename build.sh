#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=Smiley.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/"   # regenerate via gen_icon.swift (see header there)
MIN_MACOS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)
swiftc -O -target "$(uname -m)-apple-macosx${MIN_MACOS}" -parse-as-library main.swift -o "$APP/Contents/MacOS/Smiley"
codesign --force -s - "$APP"
echo "Built $APP"
