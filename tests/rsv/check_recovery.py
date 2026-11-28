"""Check a recovered MP4 against a fixture: stream payloads byte for byte, every video
packet's size and keyframe flag, and each stream's duration.

usage: check_recovery.py <recovered.mp4> <fixture-prefix>
Exits non-zero when anything differs.
"""
import json
import subprocess
import sys
from fractions import Fraction


def stream_payload(mp4, map_spec):
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", mp4, "-map", map_spec, "-c", "copy", "-f", "data", "-"],
        check=True, capture_output=True).stdout


def probe(mp4, selector, entries):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", selector, "-show_entries", entries, "-of", "json", mp4],
        check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def stream_duration(mp4, selector):
    stream = probe(mp4, selector, "stream=time_base,duration_ts")["streams"][0]
    return Fraction(stream["time_base"]) * int(stream["duration_ts"])


def main():
    mp4, prefix = sys.argv[1], sys.argv[2]
    with open(prefix + ".layout.json") as f:
        layout = json.load(f)
    tracks = len(layout["track_chunks"])
    expected_duration = Fraction(layout["duration_seconds"])
    failed = False

    def report(name, ok, detail):
        nonlocal failed
        failed |= not ok
        print(f"  {name}: {'match' if ok else 'MISMATCH'} ({detail})")

    streams = [("video", "0:v:0", "v:0", prefix + ".expected_video")] + \
              [(f"audio {t + 1}", f"0:a:{t}", f"a:{t}", prefix + f".expected_a{t}") for t in range(tracks)]
    for name, map_spec, selector, expected_path in streams:
        got = stream_payload(mp4, map_spec)
        with open(expected_path, "rb") as f:
            expected = f.read()
        report(f"{name} payload", got == expected, f"got {len(got)} bytes, expected {len(expected)}")
        duration = stream_duration(mp4, selector)
        report(f"{name} duration", duration == expected_duration,
               f"got {float(duration):.6f}s, expected {float(expected_duration):.6f}s")

    packets = [[int(p["size"]), "K" in p["flags"]]
               for p in probe(mp4, "v:0", "packet=size,flags")["packets"]]
    expected_packets = layout["video_packets"]
    keyframes = sum(1 for _, key in expected_packets if key)
    report("video packets", packets == expected_packets,
           f"got {len(packets)} packets, expected {len(expected_packets)} with {keyframes} keyframes")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
