"""Read each track's stored timing from an MP4's moov box: handler type, media timescale
and duration (mdhd), and the total of its sample durations (stts).

These are the values the file records, unlike demuxer-reported durations, which can be
stretched to the movie duration when a track has no edit list.
"""
import struct

CONTAINERS = {b"moov", b"trak", b"mdia", b"minf", b"stbl"}


def _boxes(data, start, end):
    offset = start
    while offset + 8 <= end:
        size, kind = struct.unpack(">I4s", data[offset:offset + 8])
        header = 8
        if size == 1:
            size = struct.unpack(">Q", data[offset + 8:offset + 16])[0]
            header = 16
        elif size == 0:
            size = end - offset
        if size < header or offset + size > end:
            raise ValueError(f"malformed {kind!r} box at {offset}")
        yield kind, offset + header, offset + size
        offset += size


def read_tracks(path):
    """Return one dict per trak, in file order: handler, timescale, duration, stts_total."""
    with open(path, "rb") as f:
        data = f.read()
    tracks = []

    def visit(start, end, track):
        for kind, body, box_end in _boxes(data, start, end):
            if kind == b"trak":
                new_track = {}
                visit(body, box_end, new_track)
                tracks.append(new_track)
            elif kind in CONTAINERS:
                visit(body, box_end, track)
            elif track is None:
                continue
            elif kind == b"hdlr":
                track["handler"] = data[body + 8:body + 12].decode("ascii")
            elif kind == b"mdhd":
                if data[body] == 1:
                    track["timescale"], track["duration"] = struct.unpack(">IQ", data[body + 20:body + 32])
                else:
                    track["timescale"], track["duration"] = struct.unpack(">II", data[body + 12:body + 20])
            elif kind == b"stts":
                count = struct.unpack(">I", data[body + 4:body + 8])[0]
                entries = struct.iter_unpack(">II", data[body + 8:body + 8 + count * 8])
                track["stts_total"] = sum(samples * delta for samples, delta in entries)

    visit(0, len(data), None)
    return tracks
