#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/repair-rsv-tauri-target}"
APP_BUNDLE="$TARGET_DIR/release/bundle/macos/Repair RSV.app"
MAIN_EXE="$APP_BUNDLE/Contents/MacOS/repair-rsv"
HELPER_EXE="$APP_BUNDLE/Contents/Resources/bin/untrunc-rsv"
STAGING="/tmp/repair-rsv-dmg-staging"
DMG_TMP="/tmp/Repair-RSV-notary.dmg"
DMG_OUT="$APP_DIR/dist-bundle/Repair RSV_0.1.0_aarch64.dmg"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Dominic Esposito (U7YT4DBC54)}"
TIMESTAMP_ARG=()

if [[ "${CODESIGN_TIMESTAMP:-0}" == "1" ]]; then
  TIMESTAMP_ARG=(--timestamp)
fi

export COPYFILE_DISABLE=1
export CARGO_TARGET_DIR="$TARGET_DIR"

cd "$APP_DIR"
tauri build --bundles app

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

codesign --force --options runtime "${TIMESTAMP_ARG[@]}" --sign "$SIGNING_IDENTITY" "$HELPER_EXE"
codesign --force --options runtime "${TIMESTAMP_ARG[@]}" --sign "$SIGNING_IDENTITY" "$MAIN_EXE"
codesign --force --options runtime "${TIMESTAMP_ARG[@]}" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"

rm -rf "$STAGING" "$DMG_TMP"
mkdir -p "$STAGING" "$APP_DIR/dist-bundle"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Repair RSV" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_TMP"

cp "$DMG_TMP" "$DMG_OUT"
echo "Built $DMG_OUT"
