"""Check a recovered MP4 against a fixture: stream payloads byte for byte, every video
packet's size and keyframe flag, and each track's stored duration (mdhd, matching its stts).

usage: check_recovery.py <recovered.mp4> <fixture-prefix>
Exits non-zero when anything differs.
"""
import json
import os
import subprocess
import sys
from fractions import Fraction

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mp4_tracks import read_tracks  # noqa: E402


def stream_payload(mp4, map_spec):
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", mp4, "-map", map_spec, "-c", "copy", "-f", "data", "-"],
        check=True, capture_output=True).stdout


def probe(mp4, selector, entries):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", selector, "-show_entries", entries, "-of", "json", mp4],
        check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def main():
    mp4, prefix = sys.argv[1], sys.argv[2]
    with open(prefix + ".layout.json") as f:
        layout = json.load(f)
    tracks = len(layout["track_chunks"])
    video_duration = Fraction(layout["video_duration_seconds"])
    audio_duration = Fraction(layout["audio_duration_seconds"])
    failed = False

    def report(name, ok, detail):
        nonlocal failed
        failed |= not ok
        print(f"  {name}: {'match' if ok else 'MISMATCH'} ({detail})")

    stored = read_tracks(mp4)
    video_tracks = [t for t in stored if t.get("handler") == "vide"]
    audio_tracks = [t for t in stored if t.get("handler") == "soun"]
    report("track layout", len(video_tracks) == 1 and len(audio_tracks) == tracks,
           f"got {len(video_tracks)} video and {len(audio_tracks)} audio tracks, expected 1 and {tracks}")
    if failed:
        sys.exit(1)

    streams = [("video", "0:v:0", video_tracks[0], prefix + ".expected_video", video_duration)] + \
              [(f"audio {t + 1}", f"0:a:{t}", audio_tracks[t], prefix + f".expected_a{t}", audio_duration)
               for t in range(tracks)]
    for name, map_spec, track, expected_path, expected_duration in streams:
        got = stream_payload(mp4, map_spec)
        with open(expected_path, "rb") as f:
            expected = f.read()
        report(f"{name} payload", got == expected, f"got {len(got)} bytes, expected {len(expected)}")
        duration = Fraction(track["duration"], track["timescale"])
        samples_duration = Fraction(track["stts_total"], track["timescale"])
        report(f"{name} duration", duration == expected_duration == samples_duration,
               f"stored {float(duration):.6f}s, samples {float(samples_duration):.6f}s, "
               f"expected {float(expected_duration):.6f}s")

    packets = [[int(p["size"]), "K" in p["flags"]]
               for p in probe(mp4, "v:0", "packet=size,flags")["packets"]]
    expected_packets = layout["video_packets"]
    keyframes = sum(1 for _, key in expected_packets if key)
    report("video packets", packets == expected_packets,
           f"got {len(packets)} packets, expected {len(expected_packets)} with {keyframes} keyframes")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
