#!/bin/bash
# Builds JiraManager signed with Developer ID + hardened runtime, packages a DMG,
# notarizes it with Apple, and staples the ticket so it opens with no Gatekeeper prompt.
#
# Prerequisites (one-time):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A stored notarytool credential profile named by $NOTARY_PROFILE, e.g.:
#        xcrun notarytool store-credentials "JiraManager-notary" \
#          --key /path/AuthKey_XXXX.p8 --key-id KEYID --issuer ISSUER-UUID
#
# Usage: ./scripts/build-notarized-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SCHEME="JiraManager"
APP="JiraManager"
DERIVED="build"
NOTARY_PROFILE="${NOTARY_PROFILE:-JiraManager-notary}"

# --- Resolve the Developer ID Application identity + team ---
IDENTITY_LINE="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 || true)"
[ -n "$IDENTITY_LINE" ] || { echo "✗ 'Developer ID Application' sertifikası bulunamadı. Xcode → Settings → Accounts → Manage Certificates'tan üret."; exit 1; }
IDENTITY_NAME="$(echo "$IDENTITY_LINE" | sed -E 's/.*"(.*)".*/\1/')"
TEAM_ID="$(echo "$IDENTITY_NAME" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')"
echo "▶︎ İmza kimliği: $IDENTITY_NAME (team $TEAM_ID)"

# --- Build (Developer ID, hardened runtime, secure timestamp) ---
echo "▶︎ Release derleniyor ve imzalanıyor…"
xcodebuild -project "$APP.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY_NAME" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean build

APP_PATH="$DERIVED/Build/Products/Release/$APP.app"
[ -d "$APP_PATH" ] || { echo "✗ Build çıktısı yok: $APP_PATH"; exit 1; }

# --- Package DMG ---
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG="$APP-$VERSION.dmg"
echo "▶︎ DMG paketleniyor: $DMG"
STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

# --- Sign the DMG itself ---
echo "▶︎ DMG imzalanıyor…"
codesign --force --timestamp --sign "$IDENTITY_NAME" "$DMG"

# --- Notarize + staple ---
echo "▶︎ Apple'a notarization gönderiliyor (birkaç dakika sürebilir)…"
# CI: use a direct API key (NOTARY_KEY .p8 + NOTARY_KEY_ID + NOTARY_ISSUER).
# Local: fall back to the stored keychain profile.
if [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
  xcrun notarytool submit "$DMG" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
else
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
fi

echo "▶︎ Ticket staple ediliyor…"
xcrun stapler staple "$DMG"

echo "▶︎ Doğrulama:"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo "✅ Notarize edilmiş DMG hazır: $DMG ($(du -h "$DMG" | cut -f1))"
