#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Dominic Esposito (U7YT4DBC54)}"
ENTITLEMENTS="$ROOT/app/src-tauri/Entitlements.plist"

for lib in "$ROOT/lib"/*.dylib(N); do
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$lib"
done

codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$ROOT/bin/untrunc-rsv"
codesign --verify --deep --strict --verbose=2 "$ROOT/bin/untrunc-rsv"

echo "Signed runtime helper and bundled dylibs"
