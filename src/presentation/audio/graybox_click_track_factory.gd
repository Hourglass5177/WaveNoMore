class_name GrayboxClickTrackFactory
extends RefCounted

## 为尚无正式音频的灰盒关卡生成节拍器和短促反馈音。
## 这些声音只供人耳参考，玩法时钟从不读取生成的采样来做判定。

# 所有程序音频使用每秒 22050 个采样点，足够灰盒试听且内存开销较低。
const SAMPLE_RATE: int = 22_050
# 生成音轨的最短秒数，避免零长度或过短 WAV。
const MIN_DURATION_SEC: float = 0.25
# 每个节拍点击声写入的秒数；数值固定，防止相邻拍子彼此覆盖过多。
const CLICK_DURATION_SEC: float = 0.065


static func create(
	duration_sec: float,
	bpm: float = 120.0,
	first_beat_offset_sec: float = 0.0,
	beats_per_bar: int = 4
) -> AudioStreamWAV:
	var safe_duration_sec: float = maxf(duration_sec, MIN_DURATION_SEC)
	var safe_bpm: float = clampf(bpm, 20.0, 400.0)
	var safe_beats_per_bar: int = maxi(beats_per_bar, 1)
	var frame_count: int = ceili(safe_duration_sec * float(SAMPLE_RATE))
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)

	var beat_interval_sec: float = 60.0 / safe_bpm
	var beat_time_sec: float = first_beat_offset_sec
	var beat_index: int = 0
	var wrote_click: bool = false
	while beat_time_sec < 0.0:
		beat_time_sec += beat_interval_sec
		beat_index += 1
	while beat_time_sec < safe_duration_sec:
		_write_click(
			pcm,
			roundi(beat_time_sec * float(SAMPLE_RATE)),
			frame_count,
			beat_index % safe_beats_per_bar == 0
		)
		wrote_click = true
		beat_time_sec += beat_interval_sec
		beat_index += 1
	# 即使首拍偏移填错或故意设得很长，也至少在开头写入一次强拍，
	# 否则本应帮助开发者校时的备用音轨会变成静音。
	if not wrote_click:
		_write_click(pcm, 0, frame_count, true)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream


static func create_transient(
	frequency_hz: float,
	duration_sec: float = 0.08,
	amplitude: float = 0.28,
	darkness: float = 0.0
) -> AudioStreamWAV:
	var safe_duration_sec: float = maxf(duration_sec, 0.02)
	var frame_count: int = ceili(safe_duration_sec * float(SAMPLE_RATE))
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	for frame: int in range(frame_count):
		var time_sec: float = float(frame) / float(SAMPLE_RATE)
		var attack: float = clampf(time_sec / 0.003, 0.0, 1.0)
		var decay: float = exp(-time_sec * lerpf(62.0, 34.0, clampf(darkness, 0.0, 1.0)))
		var partials: float = sin(TAU * frequency_hz * time_sec)
		partials += sin(TAU * frequency_hz * 1.618 * time_sec) * 0.31
		partials += sin(TAU * frequency_hz * 2.37 * time_sec) * 0.13
		var grit: float = sin(float(frame * 73 + 19)) * 0.08 * darkness
		_store_pcm16(pcm, frame, clampf((partials + grit) * attack * decay * amplitude, -0.9, 0.9))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream


static func create_sustained_tone(
	frequency_hz: float,
	duration_sec: float = 1.0,
	amplitude: float = 0.10,
	darkness: float = 0.0
) -> AudioStreamWAV:
	## 生成可无缝循环的灰盒钟体底音。这里的可听音高只用于区分两口钟；
	## Gameplay 中 1.8～6.9 Hz 的“发波频率”会通过 pitch_scale 相对映射。
	var safe_duration_sec: float = maxf(duration_sec, 0.25)
	var frame_count: int = ceili(safe_duration_sec * float(SAMPLE_RATE))
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	for frame: int in range(frame_count):
		var time_sec: float = float(frame) / float(SAMPLE_RATE)
		var body: float = sin(TAU * frequency_hz * time_sec)
		body += sin(TAU * frequency_hz * 2.0 * time_sec) * lerpf(0.22, 0.10, darkness)
		body += sin(TAU * frequency_hz * 3.0 * time_sec) * lerpf(0.08, 0.18, darkness)
		_store_pcm16(pcm, frame, clampf(body * amplitude, -0.8, 0.8))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	stream.data = pcm
	return stream


static func _write_click(
	pcm: PackedByteArray,
	start_frame: int,
	total_frames: int,
	accented: bool
) -> void:
	var click_frames: int = roundi(CLICK_DURATION_SEC * float(SAMPLE_RATE))
	var frequency_hz: float = 720.0 if accented else 1060.0
	var amplitude: float = 0.38 if accented else 0.24
	for local_frame: int in range(click_frames):
		var frame: int = start_frame + local_frame
		if frame < 0 or frame >= total_frames:
			continue
		var time_sec: float = float(local_frame) / float(SAMPLE_RATE)
		var decay: float = exp(-time_sec * (43.0 if accented else 56.0))
		var strike: float = sin(TAU * frequency_hz * time_sec)
		var body: float = sin(TAU * frequency_hz * 0.48 * time_sec) * 0.28
		var sample_value: float = clampf((strike + body) * decay * amplitude, -0.92, 0.92)
		_store_pcm16(pcm, frame, sample_value)


static func _store_pcm16(pcm: PackedByteArray, frame: int, sample_value: float) -> void:
	var encoded: int = clampi(roundi(sample_value * 32767.0), -32768, 32767)
	if encoded < 0:
		encoded += 65536
	var byte_index: int = frame * 2
	pcm[byte_index] = encoded & 0xff
	pcm[byte_index + 1] = (encoded >> 8) & 0xff
