#!/usr/bin/env bash
# RSV recovery regression tests. Generates source clips with FFmpeg, builds RSV
# fixtures from them, recovers each with the engine (using the source clip as the
# donor) and checks the recovered video and audio payloads byte for byte.
#
# usage: tests/rsv/run.sh <path-to-untrunc-rsv>
# Needs: ffmpeg/ffprobe with libx264 and libx265, python3
set -euo pipefail

ENGINE="$(cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")"
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SECONDS_LONG=10

# Noise keeps every GOP well above the engine's 500KB rtmd search offset, like real camera bitrates.
video_input() { echo "testsrc2=size=1280x720:rate=$1:duration=$SECONDS_LONG,noise=alls=40:allf=t"; }
sine() { echo "sine=frequency=$1:sample_rate=48000:duration=$SECONDS_LONG"; }

make_source() {
  local out="$1"; shift
  ffmpeg -v error -y "$@" -f mp4 "$out"
}

echo "Generating source clips"
# HEVC 50p, 48-frame GOPs, four mono 24-bit PCM tracks
make_source "$WORK/hevc50_4x24.mp4" \
  -f lavfi -i "$(video_input 50)" \
  -f lavfi -i "$(sine 440)" -f lavfi -i "$(sine 550)" -f lavfi -i "$(sine 660)" -f lavfi -i "$(sine 770)" \
  -map 0:v -map 1:a -map 2:a -map 3:a -map 4:a \
  -c:v libx265 -preset ultrafast -pix_fmt yuv420p10le -b:v 12M -tag:v hvc1 \
  -x265-params "keyint=48:min-keyint=48:scenecut=0:open-gop=0:aud=1:repeat-headers=1:log-level=error" \
  -c:a pcm_s24be
# H.264 29.97p, 15-frame GOPs, four mono 24-bit PCM tracks
make_source "$WORK/h264_2997_4x24.mp4" \
  -f lavfi -i "$(video_input 30000/1001)" \
  -f lavfi -i "$(sine 440)" -f lavfi -i "$(sine 550)" -f lavfi -i "$(sine 660)" -f lavfi -i "$(sine 770)" \
  -map 0:v -map 1:a -map 2:a -map 3:a -map 4:a \
  -c:v libx264 -preset ultrafast -b:v 16M -x264-params "keyint=15:min-keyint=15:scenecut=0" \
  -bsf:v h264_metadata=aud=insert \
  -c:a pcm_s24be
# H.264 29.97p, 15-frame GOPs, one stereo 16-bit PCM track
make_source "$WORK/h264_2997_stereo16.mp4" \
  -f lavfi -i "$(video_input 30000/1001)" \
  -f lavfi -i "aevalsrc=sin(440*2*PI*t)/4|sin(660*2*PI*t)/4:s=48000:d=$SECONDS_LONG" \
  -map 0:v -map 1:a \
  -c:v libx264 -preset ultrafast -b:v 16M -x264-params "keyint=15:min-keyint=15:scenecut=0" \
  -bsf:v h264_metadata=aud=insert \
  -c:a pcm_s16be

echo "Building fixtures"
python3 -I "$HERE/make_fixture.py" "$WORK/hevc50_4x24.mp4" "$WORK/hevc50_4x24" 48
python3 -I "$HERE/make_fixture.py" "$WORK/h264_2997_4x24.mp4" "$WORK/h264_2997_4x24" 15
python3 -I "$HERE/make_fixture.py" "$WORK/h264_2997_stereo16.mp4" "$WORK/h264_2997_stereo16" 15
# Real chunk of 24000 samples per track where GOP timing gives 24024: only the measured size recovers it
python3 -I "$HERE/make_fixture.py" "$WORK/h264_2997_4x24.mp4" "$WORK/h264_2997_4x24_measured_chunk" 15 24000
# Audio at the start of a GOP that reads as a NAL unit. Each case is caught by one guard only:
#   fake_valid_header:   GOP 0, 1796-byte step, not sample-aligned, valid header  -> whole-sample check
#   fake_split_tracks:   GOP 0, 1797-byte step, whole samples for one track only  -> whole-sample check across all tracks
#   fake_invalid_header: GOP 0, 1800-byte step, sample-aligned, forbidden bit set -> NAL header check
#   fake_sample_aligned: GOP 0, 1800-byte step, sample-aligned, valid header      -> GOP vote
#   fake_last_gop:       last GOP, same as fake_sample_aligned                   -> GOP vote, not last GOP wins
python3 -I "$HERE/plant_nal.py" "$WORK/hevc50_4x24" "$WORK/hevc50_4x24_fake_valid_header" 0 0000070001
python3 -I "$HERE/plant_nal.py" "$WORK/hevc50_4x24" "$WORK/hevc50_4x24_fake_split_tracks" 0 0000070101
python3 -I "$HERE/plant_nal.py" "$WORK/hevc50_4x24" "$WORK/hevc50_4x24_fake_invalid_header" 0 00000704ff
python3 -I "$HERE/plant_nal.py" "$WORK/hevc50_4x24" "$WORK/hevc50_4x24_fake_sample_aligned" 0 0000070401
python3 -I "$HERE/plant_nal.py" "$WORK/hevc50_4x24" "$WORK/hevc50_4x24_fake_last_gop" -1 0000070401
python3 -I "$HERE/plant_nal.py" "$WORK/h264_2997_4x24" "$WORK/h264_2997_4x24_fake_valid_header" 0 0000070001

failures=0
# run_case <fixture> <donor> <GOPs expected to disagree with the measured audio chunk>
run_case() {
  local fixture="$1" donor="$2" expected_disagree="$3"
  echo "== $(basename "$fixture")"
  rm -f "$fixture.RSV_fixed-rsv.MP4"
  if ! "$ENGINE" -rsv "$donor" "$fixture.RSV" > "$fixture.log" 2>&1; then
    echo "  engine failed:"; tail -20 "$fixture.log"; failures=$((failures + 1)); return
  fi
  local measured agree examined
  measured="$(grep -E "measured audio chunk" "$fixture.log" || true)"
  echo "  ${measured:-no measured audio chunk}"
  if [[ "$measured" =~ ([0-9]+)\ of\ ([0-9]+)\ GOPs\ agree ]]; then
    agree="${BASH_REMATCH[1]}" examined="${BASH_REMATCH[2]}"
    if [[ $((examined - agree)) -ne $expected_disagree ]]; then
      echo "  GOP agreement: MISMATCH (expected $expected_disagree disagreeing GOP(s))"; failures=$((failures + 1))
    fi
  else
    echo "  GOP agreement: MISMATCH (engine did not measure the audio chunk)"; failures=$((failures + 1))
  fi
  python3 -I "$HERE/check_recovery.py" "$fixture.RSV_fixed-rsv.MP4" "$fixture" || failures=$((failures + 1))
}

run_case "$WORK/hevc50_4x24" "$WORK/hevc50_4x24.mp4" 0
run_case "$WORK/hevc50_4x24_fake_valid_header" "$WORK/hevc50_4x24.mp4" 0
run_case "$WORK/hevc50_4x24_fake_split_tracks" "$WORK/hevc50_4x24.mp4" 0
run_case "$WORK/hevc50_4x24_fake_invalid_header" "$WORK/hevc50_4x24.mp4" 0
run_case "$WORK/hevc50_4x24_fake_sample_aligned" "$WORK/hevc50_4x24.mp4" 1
run_case "$WORK/hevc50_4x24_fake_last_gop" "$WORK/hevc50_4x24.mp4" 1
run_case "$WORK/h264_2997_4x24" "$WORK/h264_2997_4x24.mp4" 0
run_case "$WORK/h264_2997_4x24_fake_valid_header" "$WORK/h264_2997_4x24.mp4" 0
run_case "$WORK/h264_2997_4x24_measured_chunk" "$WORK/h264_2997_4x24.mp4" 0
run_case "$WORK/h264_2997_stereo16" "$WORK/h264_2997_stereo16.mp4" 0

if [[ $failures -gt 0 ]]; then
  echo "$failures RSV recovery case(s) failed"
  exit 1
fi
echo "All RSV recovery cases passed"
