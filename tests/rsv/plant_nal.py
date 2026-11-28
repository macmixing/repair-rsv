"""Copy an RSV fixture and overwrite the start of one GOP's audio with given bytes.

The bytes model PCM audio that reads as a NAL length plus header, so the video/audio
boundary walk can mistake audio for video. The expected track 1 payload is patched
with the same bytes, because a correct recovery keeps them as audio.

usage: plant_nal.py <src-prefix> <dst-prefix> <gop-index> <hex-bytes>
(a negative gop-index counts from the last complete GOP)
"""
import json
import shutil
import sys


def main():
    src, dst, gop, data = sys.argv[1], sys.argv[2], int(sys.argv[3]), bytes.fromhex(sys.argv[4])
    with open(src + ".layout.json") as f:
        layout = json.load(f)
    assert len(data) <= layout["track_chunks"][0], "planted bytes must fit in track 1's chunk"
    gop %= layout["gops"]

    for suffix in [".RSV", ".expected_video", ".layout.json"] + \
                  [f".expected_a{t}" for t in range(len(layout["track_chunks"]))]:
        shutil.copyfile(src + suffix, dst + suffix)
    with open(dst + ".RSV", "r+b") as f:
        f.seek(layout["audio_starts"][gop])
        f.write(data)
    with open(dst + ".expected_a0", "r+b") as f:
        f.seek(gop * layout["track_chunks"][0])
        f.write(data)


if __name__ == "__main__":
    main()
