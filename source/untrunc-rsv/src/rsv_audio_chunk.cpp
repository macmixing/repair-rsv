#include "rsv_audio_chunk.h"

#include <cstring>
#include <map>

using namespace std;

namespace {

bool isRtmdPacket(const uchar* buf, size_t pos, const RsvLayoutPatterns& patterns) {
	return memcmp(buf + pos, patterns.rtmd_prefix, 4) == 0 &&
	       memcmp(buf + pos + 8, patterns.rtmd_tag, 4) == 0;
}

// Walks the NAL units of the GOP's last frame toward the audio region. PCM audio can
// look like a plausible NAL length, so a step only counts as the video/audio boundary
// when its NAL header is valid and the remaining bytes hold whole samples for every track.
off_t measureGop(const uchar* buf, size_t last_frame, size_t next_rtmd, off_t audio_frame_bytes) {
	size_t cursor = last_frame;
	size_t boundary = 0;
	while (cursor + 4 <= next_rtmd) {
		uint nal_size = ((uint)buf[cursor] << 24) | ((uint)buf[cursor + 1] << 16) |
		                ((uint)buf[cursor + 2] << 8) | (uint)buf[cursor + 3];
		if (nal_size == 0 || cursor + 4 + nal_size > next_rtmd) {
			break;
		}
		// forbidden_zero_bit: top bit of the NAL header in both H.264 and HEVC
		if (buf[cursor + 4] & 0x80) {
			break;
		}
		cursor += 4 + nal_size;
		if ((off_t)(next_rtmd - cursor) % audio_frame_bytes == 0) {
			boundary = cursor;
		}
	}
	return boundary > last_frame ? (off_t)(next_rtmd - boundary) : -1;
}

} // namespace

RsvAudioChunkMeasurement measureRsvAudioChunk(const uchar* buf, size_t len, off_t rtmd_packet_size,
                                              const RsvLayoutPatterns& patterns, off_t audio_frame_bytes) {
	RsvAudioChunkMeasurement result;
	if (len <= 12 || rtmd_packet_size <= 0 || audio_frame_bytes <= 0) {
		return result;
	}

	// Audio in any single GOP can mimic a NAL length or an AUD pattern, but the real
	// chunk size repeats in every GOP, so each complete GOP votes for its measurement.
	map<off_t, int> votes;
	vector<off_t> first_seen;
	size_t gop_start = 0;
	while (gop_start + 12 < len) {
		size_t video_start = gop_start;
		int rtmd_count = 0;
		while (video_start + 12 < len && rtmd_count < 100 && isRtmdPacket(buf, video_start, patterns)) {
			rtmd_count++;
			video_start += rtmd_packet_size;
		}
		if (rtmd_count == 0) {
			break;
		}

		size_t next_rtmd = 0;
		for (size_t i = video_start + 500 * 1024; i < len - 12; i++) {
			if (isRtmdPacket(buf, i, patterns)) {
				next_rtmd = i;
				break;
			}
		}
		if (next_rtmd <= video_start) {
			break;
		}
		result.examined_gops++;

		size_t last_frame = 0;
		bool found_frame = false;
		for (size_t i = video_start; i + 5 < next_rtmd; i++) {
			if (memcmp(buf + i, patterns.aud, 5) == 0) {
				last_frame = i;
				found_frame = true;
			}
		}
		if (found_frame) {
			off_t measured = measureGop(buf, last_frame, next_rtmd, audio_frame_bytes);
			if (measured > 0) {
				if (votes[measured]++ == 0) {
					first_seen.push_back(measured);
				}
			}
		}
		gop_start = next_rtmd;
	}

	// Most votes wins; ties go to the earliest GOP's measurement.
	for (off_t value : first_seen) {
		if (votes[value] > result.agreeing_gops) {
			result.agreeing_gops = votes[value];
			result.chunk_size = value;
		}
	}
	return result;
}
