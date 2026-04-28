#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$ROOT/app"

cd "$APP_DIR"
"$ROOT/scripts/with-appledouble-cleaner.sh" tauri build --bundles dmg
