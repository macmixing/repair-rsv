"""Check that a recovered MP4's video and audio payloads match a fixture's expected payloads.

usage: check_recovery.py <recovered.mp4> <fixture-prefix>
Exits non-zero when any stream differs.
"""
import json
import subprocess
import sys


def stream_payload(mp4, map_spec):
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", mp4, "-map", map_spec, "-c", "copy", "-f", "data", "-"],
        check=True, capture_output=True).stdout


def main():
    mp4, prefix = sys.argv[1], sys.argv[2]
    with open(prefix + ".layout.json") as f:
        tracks = len(json.load(f)["track_chunks"])

    streams = [("video", "0:v:0", prefix + ".expected_video")] + \
              [(f"audio {t + 1}", f"0:a:{t}", prefix + f".expected_a{t}") for t in range(tracks)]
    failed = False
    for name, map_spec, expected_path in streams:
        got = stream_payload(mp4, map_spec)
        with open(expected_path, "rb") as f:
            expected = f.read()
        if got == expected:
            print(f"  {name}: match ({len(got)} bytes)")
        else:
            failed = True
            print(f"  {name}: MISMATCH (got {len(got)} bytes, expected {len(expected)})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
