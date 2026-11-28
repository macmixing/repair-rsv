#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
PROJECT_TARGET="$ROOT/app/src-tauri/target"
CACHE_TARGET="${REPAIR_RSV_TARGET_CACHE:-$HOME/Library/Caches/repair-rsv/tauri-target}"

mkdir -p "$CACHE_TARGET"

if [[ -L "$PROJECT_TARGET" ]]; then
  CURRENT_TARGET="$(readlink "$PROJECT_TARGET")"
  if [[ "$CURRENT_TARGET" == "$CACHE_TARGET" ]]; then
    exit 0
  fi
  rm "$PROJECT_TARGET"
elif [[ -e "$PROJECT_TARGET" ]]; then
  rm -rf "$PROJECT_TARGET"
fi

ln -s "$CACHE_TARGET" "$PROJECT_TARGET"
