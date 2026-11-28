#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
PROFILE="${NOTARY_PROFILE:-repair-rsv-notary}"

DMG="$(find -L "$APP_DIR/src-tauri/target/release/bundle/dmg" -maxdepth 1 -name '*.dmg' -print -quit 2>/dev/null || true)"

if [[ -z "$DMG" ]]; then
  DMG="$(find "$APP_DIR/dist-bundle" -maxdepth 1 -name '*.dmg' -print -quit 2>/dev/null || true)"
fi

if [[ -z "$DMG" ]]; then
  DMG="$(find /tmp/repair-rsv-tauri-target/release/bundle/dmg -maxdepth 1 -name '*.dmg' -print -quit 2>/dev/null || true)"
fi

if [[ -z "$DMG" ]]; then
  echo "No DMG found. Run npm run bundle from app/ first." >&2
  exit 1
fi

echo "Submitting $DMG for notarization with keychain profile $PROFILE"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "Stapling notarization ticket to $DMG"
xcrun stapler staple "$DMG"

echo "Validating stapled DMG"
xcrun stapler validate "$DMG"

echo "Done: $DMG"
