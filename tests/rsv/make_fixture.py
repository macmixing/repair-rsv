"""Build a Sony-layout RSV fixture from an MP4 (H.264 or HEVC video + PCM audio tracks).

Each GOP is written as [rtmd packets][video frames][track 1 audio][track 2 audio]...,
the layout described in source/untrunc-rsv/RSV_FILE_FORMAT.md, followed by an
interrupted trailing GOP. rtmd packets are synthetic (prefix + Sony tag + counter).

Outputs next to <out>: <out>.RSV, <out>.expected_video, <out>.expected_a<N> (the
payloads a correct recovery must reproduce) and <out>.layout.json (GOP layout plus the
expected video packets, keyframes and stream durations).

usage: make_fixture.py <source.mp4> <out-prefix> <frames-per-gop> [samples-per-gop]
samples-per-gop overrides the audio samples each GOP holds per track (default: the GOP
duration's worth), modelling cameras whose real chunk differs from the calculated size.
"""
import json
import subprocess
import sys
from fractions import Fraction

RTMD_PACKET_SIZE = 19456
RTMD_PREFIX = b"\x00\x1c\x01\x00"
RTMD_TAG = b"\xf0\x01\x00\x10"
AUD_PATTERNS = {"h264": b"\x00\x00\x00\x02\x09", "hevc": b"\x00\x00\x00\x03\x46"}


def probe(source, selector, entries):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", selector, "-show_entries", entries, "-of", "json", source],
        check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def stream_payload(source, map_spec):
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", source, "-map", map_spec, "-c", "copy", "-f", "data", "-"],
        check=True, capture_output=True).stdout


def rtmd_packet(counter):
    packet = bytearray(RTMD_PACKET_SIZE)
    packet[0:4] = RTMD_PREFIX
    packet[4:8] = counter.to_bytes(4, "big")
    packet[8:12] = RTMD_TAG
    return bytes(packet)


def main():
    source, out, frames_per_gop = sys.argv[1], sys.argv[2], int(sys.argv[3])
    samples_override = int(sys.argv[4]) if len(sys.argv) > 4 else None

    video_info = probe(source, "v:0", "stream=codec_name,avg_frame_rate")["streams"][0]
    aud = AUD_PATTERNS[video_info["codec_name"]]
    gop_seconds = frames_per_gop / Fraction(video_info["avg_frame_rate"])
    packets = probe(source, "v:0", "packet=size,flags")["packets"]
    packet_sizes = [int(p["size"]) for p in packets]
    video = stream_payload(source, "0:v:0")
    assert sum(packet_sizes) == len(video), "video payload does not match packet sizes"

    audio_streams = probe(source, "a", "stream=index,sample_rate,channels,bits_per_sample")["streams"]
    audio = [stream_payload(source, f"0:a:{t}") for t in range(len(audio_streams))]
    sample_rates = {int(stream["sample_rate"]) for stream in audio_streams}
    assert len(sample_rates) == 1, "all audio tracks must share one sample rate"
    sample_rate = sample_rates.pop()
    samples = Fraction(samples_override) if samples_override else sample_rate * gop_seconds
    assert samples.denominator == 1, "GOP duration must hold a whole number of audio samples"
    track_chunks = [int(samples) * int(stream["channels"]) * int(stream["bits_per_sample"]) // 8
                    for stream in audio_streams]

    gop_count = min(len(packet_sizes) // frames_per_gop,
                    min(len(a) // c for a, c in zip(audio, track_chunks)))
    rsv, expected_video = bytearray(), bytearray()
    expected_audio = [bytearray() for _ in audio]
    audio_starts, video_offset, counter = [], 0, 0
    for gop in range(gop_count + 1):
        for _ in range(frames_per_gop):
            rsv += rtmd_packet(counter)
            counter += 1
        if gop == gop_count:
            break  # interrupted recording: trailing GOP stops after its rtmd block
        size = sum(packet_sizes[gop * frames_per_gop:(gop + 1) * frames_per_gop])
        frames = video[video_offset:video_offset + size]
        video_offset += size
        assert frames.startswith(aud), "every GOP must start with an access unit delimiter"
        rsv += frames
        expected_video += frames
        audio_starts.append(len(rsv))
        for track, chunk in enumerate(track_chunks):
            data = audio[track][gop * chunk:(gop + 1) * chunk]
            rsv += data
            expected_audio[track] += data
    rsv += bytes(4096)

    with open(out + ".RSV", "wb") as f:
        f.write(rsv)
    with open(out + ".expected_video", "wb") as f:
        f.write(expected_video)
    for track, data in enumerate(expected_audio):
        with open(out + f".expected_a{track}", "wb") as f:
            f.write(data)
    with open(out + ".layout.json", "w") as f:
        json.dump({
            "gops": gop_count,
            "track_chunks": track_chunks,
            "audio_starts": audio_starts,
            "video_packets": [[int(p["size"]), "K" in p["flags"]] for p in packets[:gop_count * frames_per_gop]],
            "video_duration_seconds": str(gop_count * gop_seconds),
            "audio_duration_seconds": str(gop_count * samples / sample_rate),
        }, f)
    print(f"{out}.RSV: {gop_count} GOPs, audio chunk {sum(track_chunks)} bytes, {len(track_chunks)} tracks")


if __name__ == "__main__":
    main()
