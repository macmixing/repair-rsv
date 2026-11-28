#!/bin/zsh
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/bin/untrunc-rsv"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /path/to/donor.mp4 /path/to/broken.RSV" >&2
  exit 64
fi

DONOR="$1"
BROKEN="$2"

if [[ ! -x "$TOOL" ]]; then
  echo "Missing executable: $TOOL" >&2
  exit 1
fi

if [[ ! -f "$DONOR" ]]; then
  echo "Missing donor file: $DONOR" >&2
  exit 1
fi

if [[ ! -f "$BROKEN" ]]; then
  echo "Missing broken RSV file: $BROKEN" >&2
  exit 1
fi

"$TOOL" -rsv "$DONOR" "$BROKEN"
