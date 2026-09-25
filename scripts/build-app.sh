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
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"
fi

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
