#!/usr/bin/env bash
# Builds a release build and packages it as build/AllSet.app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="AllSet"
APP_DIR="build/${APP_NAME}.app"
HELPER="libAllSetMediaHelper.dylib"

# Builds every product, including the media helper the app loads at runtime.
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$HELPER" "$APP_DIR/Contents/Frameworks/$HELPER"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

# Plain HTTP for exactly one host: the personal, Tailscale-only library server.
# Its address isn't in the source; set ALLSET_LIBRARY_SERVER_HOST, or put
# ALLSET_LIBRARY_SERVER_HOST=100.x.y.z in scripts/local.env (git-ignored).
if [ -z "${ALLSET_LIBRARY_SERVER_HOST:-}" ] && [ -f scripts/local.env ]; then
  ALLSET_LIBRARY_SERVER_HOST="$(sed -n 's/^ALLSET_LIBRARY_SERVER_HOST=//p' scripts/local.env | tr -d '"' | head -1)"
fi
if [ -n "${ALLSET_LIBRARY_SERVER_HOST:-}" ]; then
  PLIST="$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$ALLSET_LIBRARY_SERVER_HOST dict" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$ALLSET_LIBRARY_SERVER_HOST:NSExceptionAllowsInsecureHTTPLoads bool true" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:$ALLSET_LIBRARY_SERVER_HOST:NSIncludesSubdomains bool false" "$PLIST"
  echo "Library server: plain HTTP allowed for $ALLSET_LIBRARY_SERVER_HOST only"
else
  echo "No ALLSET_LIBRARY_SERVER_HOST: the app can't fetch wallpapers over plain HTTP from a library server"
fi
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"
fi
cp -R Sources/AllSetCore/Resources/ThemeArt "$APP_DIR/Contents/Resources/"

# Sign with the local development certificate when it exists (see
# setup-signing.sh) so macOS keeps Accessibility permission across rebuilds;
# otherwise sign ad hoc. Distribution will need a Developer ID certificate and
# notarization.
IDENTITY="-"
if security find-certificate -c "All Set Development" >/dev/null 2>&1; then
  IDENTITY="All Set Development"
fi
codesign --force --sign "$IDENTITY" "$APP_DIR/Contents/Frameworks/$HELPER"
codesign --force --sign "$IDENTITY" "$APP_DIR"

echo "Built $APP_DIR"
