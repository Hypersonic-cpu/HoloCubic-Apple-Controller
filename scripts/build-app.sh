#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_ROOT="$ROOT_DIR/build/Xcode"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
PRODUCT_APP="$DERIVED_DATA/Build/Products/Release/MacCtrlHTTP.app"
APP_DIR="$ROOT_DIR/build/MacCtrlHTTP.app"
WIDGET="$APP_DIR/Contents/PlugIns/WidgetExtension.appex"

xcodebuild -quiet -jobs 1 \
    -project "$ROOT_DIR/MacCtrlHTTP.xcodeproj" \
    -scheme MacCtrlHTTP \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

rm -rf "$APP_DIR"
ditto "$PRODUCT_APP" "$APP_DIR"

# Ad-hoc signatures keep the local development build runnable without a Developer ID.
codesign --force --sign - --entitlements "$ROOT_DIR/WidgetExtension/WidgetExtension.entitlements" "$WIDGET"
codesign --force --sign - --entitlements "$ROOT_DIR/MacCtrlHTTP.entitlements" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

printf 'Built %s\n' "$APP_DIR"
