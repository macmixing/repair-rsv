#!/bin/zsh
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "Usage: $0 <command> [args...]" >&2
  exit 2
fi

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET_DIR="$ROOT/app/src-tauri/target"

export COPYFILE_DISABLE=1
unset CARGO_TARGET_DIR

"$ROOT/scripts/ensure-tauri-target.sh"
"$ROOT/scripts/clean-appledouble.sh"

(
  while true; do
    find "$TARGET_DIR" -name '._*' -type f -delete 2>/dev/null || true
    sleep 0.1
  done
) &
CLEANER_PID=$!

cleanup() {
  kill "$CLEANER_PID" 2>/dev/null || true
  wait "$CLEANER_PID" 2>/dev/null || true
  "$ROOT/scripts/clean-appledouble.sh"
}

trap cleanup EXIT INT TERM

"$@"
