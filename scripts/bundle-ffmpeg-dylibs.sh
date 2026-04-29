#!/bin/zsh
set -euo pipefail
setopt NULL_GLOB

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
BIN="$ROOT/bin/untrunc-rsv"
LIB_DIR="$ROOT/lib"

mkdir -p "$LIB_DIR"

typeset -a queue
typeset -A copied

resolve_bundle_dep() {
  local dep="$1"
  local base candidate

  if [[ "$dep" == /opt/homebrew/* || "$dep" == /usr/local/* ]]; then
    [[ -f "$dep" ]] && print -r -- "$dep"
    return 0
  fi

  case "$dep" in
    @rpath/*|@loader_path/*|@executable_path/*)
      base="$(basename "$dep")"
      for candidate in \
        "/opt/homebrew/lib/$base" \
        "/usr/local/lib/$base" \
        /opt/homebrew/opt/*/lib/"$base" \
        /opt/homebrew/Cellar/*/*/lib/"$base" \
        /usr/local/opt/*/lib/"$base" \
        /usr/local/Cellar/*/*/lib/"$base"; do
        if [[ -f "$candidate" ]]; then
          print -r -- "$candidate"
          return 0
        fi
      done
      ;;
  esac
}

copy_dep() {
  local dep="$1"
  local base
  base="$(basename "$dep")"

  [[ -f "$dep" ]] || return 0
  [[ -n "${copied[$base]:-}" ]] && return 0

  copied[$base]="$dep"
  cp -f "$dep" "$LIB_DIR/$base"
  chmod 755 "$LIB_DIR/$base"
  queue+=("$LIB_DIR/$base")
}

collect_deps() {
  local file="$1"
  local dep resolved

  while IFS= read -r dep; do
    resolved="$(resolve_bundle_dep "$dep")"
    if [[ -n "$resolved" ]]; then
      copy_dep "$resolved"
    fi
  done < <(otool -L "$file" | awk 'NR > 1 { print $1 }')
}

rewrite_deps() {
  local file="$1"
  local prefix="$2"
  local dep base resolved

  while IFS= read -r dep; do
    resolved="$(resolve_bundle_dep "$dep")"
    if [[ -n "$resolved" ]]; then
      base="$(basename "$dep")"
      if [[ -f "$LIB_DIR/$base" ]]; then
        install_name_tool -change "$dep" "$prefix/$base" "$file"
      fi
    fi
  done < <(otool -L "$file" | awk 'NR > 1 { print $1 }')
}

collect_deps "$BIN"

while (( ${#queue[@]} )); do
  current="${queue[1]}"
  queue=("${queue[@]:1}")
  collect_deps "$current"
done

for lib in "$LIB_DIR"/*.dylib(N); do
  install_name_tool -id "@loader_path/$(basename "$lib")" "$lib"
done

rewrite_deps "$BIN" "@loader_path/../lib"

for lib in "$LIB_DIR"/*.dylib(N); do
  rewrite_deps "$lib" "@loader_path"
done

echo "Bundled FFmpeg/Homebrew dylibs into $LIB_DIR"
