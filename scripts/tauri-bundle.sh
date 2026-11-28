#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$ROOT/app"

"$ROOT/scripts/build-from-source.sh"
"$ROOT/scripts/bundle-ffmpeg-dylibs.sh"
"$ROOT/scripts/sign-runtime-assets.sh"

cd "$APP_DIR"
"$ROOT/scripts/with-appledouble-cleaner.sh" tauri build --bundles dmg
