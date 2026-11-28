#!/usr/bin/env bash
# Cross-builds bin/untrunc-rsv.exe (static, no DLLs) with mingw-w64 on Linux.
# Needs: mingw-w64 nasm curl make
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/.build-win}"
FF=ffmpeg-6.1.2
mkdir -p "$WORK"
if [[ ! -f "$WORK/ff/lib/libavcodec.a" ]]; then
  cd "$WORK"
  [[ -d $FF ]] || { curl -sSfL "https://ffmpeg.org/releases/$FF.tar.xz" | tar xJ; mv $FF/VERSION $FF/VERSION.bak; }
  cd $FF
  ./configure --prefix="$WORK/ff" --target-os=mingw32 --arch=x86_64 --cross-prefix=x86_64-w64-mingw32- \
    --enable-static --disable-shared --disable-doc --disable-programs --disable-everything \
    --enable-decoders --enable-demuxers --enable-protocol=file --disable-avdevice --disable-swresample \
    --disable-swscale --disable-avfilter --disable-postproc --disable-zlib --disable-bzlib --disable-lzma --disable-iconv
  make -j"$(nproc)" && make install
fi
cd "$ROOT/source/untrunc-rsv"
make clean
make -j"$(nproc)" IS_RELEASE=1 CXX=x86_64-w64-mingw32-g++-posix \
  CXXFLAGS="-isystem$WORK/ff/include -std=c++17 -O3 -D_FILE_OFFSET_BITS=64" \
  LDFLAGS="-L$WORK/ff/lib -lavformat -lavcodec -lavutil -lbcrypt -lws2_32 -lsecur32 -static -s"
cp untrunc.exe "$ROOT/bin/untrunc-rsv.exe"
echo "Built $ROOT/bin/untrunc-rsv.exe"
