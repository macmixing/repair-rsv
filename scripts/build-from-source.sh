#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="$ROOT/source/untrunc-rsv"
OUT="$ROOT/bin/untrunc-rsv"

export PATH="/opt/homebrew/opt/pkgconf/bin:$PATH"

: "${CPPFLAGS:=-I/opt/homebrew/include}"
: "${LDFLAGS:=-L/opt/homebrew/lib}"

cd "$SRC"
make clean
make -j2 CPPFLAGS="$CPPFLAGS" LDFLAGS="$LDFLAGS"
cp untrunc "$OUT"
chmod 700 "$OUT"

echo "Updated $OUT"
