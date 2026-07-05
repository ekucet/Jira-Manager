#!/bin/bash
# Builds JiraManager in Release, ad-hoc signs it, and packages a distributable DMG.
set -euo pipefail

cd "$(dirname "$0")/.."
SCHEME="JiraManager"
APP="JiraManager"
DERIVED="build"

echo "▶︎ Release derleniyor…"
xcodebuild -project "$APP.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  clean build

APP_PATH="$DERIVED/Build/Products/Release/$APP.app"
[ -d "$APP_PATH" ] || { echo "✗ Build çıktısı bulunamadı: $APP_PATH"; exit 1; }

echo "▶︎ Ad-hoc imzalanıyor…"
codesign --force --deep --sign - "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 1.0.0)"
DMG="$APP-$VERSION.dmg"

echo "▶︎ DMG paketleniyor: $DMG"
STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "✅ Oluşturuldu: $DMG ($(du -h "$DMG" | cut -f1))"
