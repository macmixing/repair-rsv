#ifndef RSV_AUDIO_CHUNK_H
#define RSV_AUDIO_CHUNK_H

#include "common.h"

// Byte patterns that mark the Sony RSV GOP layout: [rtmd packets][video frames][audio].
struct RsvLayoutPatterns {
	const uchar* rtmd_prefix;  // 4 bytes at packet offset 0
	const uchar* rtmd_tag;     // 4 bytes at packet offset 8
	const uchar* aud;          // 5-byte length-prefixed access unit delimiter
};

struct RsvAudioChunkMeasurement {
	off_t chunk_size = -1;   // combined audio bytes per GOP for all tracks, -1 if unmeasured
	int agreeing_gops = 0;   // GOPs that measured chunk_size
	int examined_gops = 0;   // complete GOPs found in the buffer
};

// Measures the per-GOP audio chunk in every complete GOP of buf and returns the
// size most GOPs agree on. audio_frame_bytes is one sample for every audio track.
RsvAudioChunkMeasurement measureRsvAudioChunk(const uchar* buf, size_t len, off_t rtmd_packet_size,
                                              const RsvLayoutPatterns& patterns, off_t audio_frame_bytes);

#endif // RSV_AUDIO_CHUNK_H
