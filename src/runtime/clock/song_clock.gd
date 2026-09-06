class_name SongClock
extends Node

## 与音频起播对齐的歌曲时钟。玩法时间由单调系统时钟推导，AudioStreamPlayer
## 只用于播放、延迟估计和漂移观察，不能反过来让判定时间跳动。

## 新时间线开始播放后发出；`generation` 可用来作废上一轮异步结果。
signal started(generation: int)
## 暂停完成后发出；`song_time_sec` 是冻结的歌曲时间（秒）。
signal paused(song_time_sec: float)
## 从暂停位置继续播放后发出；参数是恢复处的歌曲时间（秒）。
signal resumed(song_time_sec: float)
## 跳转时间线后发出；同时给出目标歌曲时间（秒）和新的世代号。
signal sought(song_time_sec: float, generation: int)
## 时钟停止并切换世代后发出。
signal stopped(generation: int)
## 任何使旧时间线失效的操作完成后发出新的世代号。
signal generation_changed(generation: int)
## 每次 `sample()` 计算完四条时间轴后发布只读快照。
signal sample_published(sample: ClockSample)

enum State {
	## 尚未播放，歌曲时间保持在最后一次停止位置。
	STOPPED,
	## 正常播放，歌曲时间随单调系统时钟前进。
	PLAYING,
	## 暂停中，歌曲时间冻结但节点仍可在暂停树中取样。
	PAUSED,
}

## 一秒包含的微秒数，用于浮点秒与确定性整数时间戳之间换算。
const USEC_PER_SEC: float = 1_000_000.0

@export_group("Calibration")
## 音频输出校准量，单位为秒。正值表示预计声音更晚到达扬声器，起播原点也相应后移。
@export_range(-0.5, 0.5, 0.0001) var audio_calibration_sec: float = 0.0
## 输入补偿量，单位为秒。正值会从歌曲时间中减去，使较晚收到的按键按更早时刻判定。
@export_range(-0.5, 0.5, 0.0001) var input_compensation_sec: float = 0.0
## 画面提前量，单位为秒。正值会让表现层看到更靠后的时间，从而更早生成和推进音符。
@export_range(-0.5, 0.5, 0.0001) var visual_lead_sec: float = 0.0

## 与时钟绑定的歌曲播放器；允许没有音频流的灰盒关使用纯系统时钟运行。
var audio_player: AudioStreamPlayer
## 音频文件开头到谱面 tick 0 的偏移，单位为秒；正值表示首拍位于文件开头之后。
var first_beat_offset_sec: float = 0.0

## 当前播放状态，决定歌曲时间是继续推进还是保持冻结。
var state: State = State.STOPPED
## 最近一次取样观测到的音频播放位置，单位为秒，仅供漂移诊断。
var audio_time_raw_sec: float = 0.0
## 最近一次对外发布的歌曲主时间，单位为秒，播放期间保证不倒退。
var song_time_sec: float = 0.0
## 最近一次发布的输入判定时间，等于歌曲时间减输入补偿，单位为秒。
var judge_time_sec: float = 0.0
## 最近一次发布的表现时间，等于歌曲时间加画面提前量，单位为秒。
var visual_time_sec: float = 0.0
## 音频观测时间与歌曲主时间之差，单位为秒；只用来发现音频漂移。
var audio_drift_sec: float = 0.0

## 当前时间线世代号；Seek、重新起播或停止后递增，防止沿用旧时间线数据。
var _generation: int = 0
## 系统单调时钟上的播放原点，单位为微秒。
var _system_origin_usec: int = 0
## `_system_origin_usec` 对应的歌曲时间，单位为秒。
var _origin_song_time_sec: float = 0.0
## 暂停或停止时冻结的歌曲时间，单位为秒。
var _frozen_song_time_sec: float = 0.0
## 最近一次已发布的歌曲时间下界，避免帧间时间倒退。
var _last_song_time_sec: float = 0.0
## 最近缓存的音频设备输出延迟，单位为秒；避免每次取样都查询设备。
var _cached_output_latency_sec: float = 0.0
## 最近一次生成快照时的系统单调时间，单位为微秒，供诊断使用。
var _last_sample_usec: int = 0
## Resume/Seek 后启用时间下界的起始系统时刻；-1 表示当前不启用，单位为微秒。
var _mapping_floor_from_usec: int = -1
## 时间下界启用后允许映射到的最小歌曲时间，单位为秒。
var _mapping_floor_song_time_sec: float = 0.0


func configure(
	player: AudioStreamPlayer,
	beat_offset_sec: float
) -> void:
	audio_player = player
	first_beat_offset_sec = beat_offset_sec
	refresh_output_latency()


func set_audio_player(player: AudioStreamPlayer) -> void:
	audio_player = player


func set_offsets(input_offset_sec: float, visual_offset_sec: float) -> void:
	input_compensation_sec = input_offset_sec
	visual_lead_sec = visual_offset_sec


func set_calibration(
	audio_offset_sec: float,
	input_offset_sec: float,
	visual_offset_sec: float
) -> void:
	audio_calibration_sec = audio_offset_sec
	input_compensation_sec = input_offset_sec
	visual_lead_sec = visual_offset_sec


func refresh_output_latency() -> void:
	_cached_output_latency_sec = maxf(AudioServer.get_output_latency(), 0.0)


func get_cached_output_latency_sec() -> float:
	return _cached_output_latency_sec


func get_generation() -> int:
	return _generation


func start(audio_from_sec: float = 0.0, capture_usec: int = -1) -> void:
	var now_usec: int = _resolve_capture_usec(capture_usec)
	refresh_output_latency()
	_bump_generation()

	var has_audio: bool = is_instance_valid(audio_player) and audio_player.stream != null
	var speaker_delay_sec: float = audio_calibration_sec
	if has_audio:
		speaker_delay_sec += AudioServer.get_time_to_next_mix() + _cached_output_latency_sec

	# 把系统原点推迟到预计声音抵达扬声器的时刻；歌曲首拍偏移则放进歌曲时间原点。
	# 两者分开保存，避免音频延迟与谱面首拍重复补偿。
	_system_origin_usec = now_usec + roundi(speaker_delay_sec * USEC_PER_SEC)
	_origin_song_time_sec = maxf(audio_from_sec, 0.0) - first_beat_offset_sec
	_mapping_floor_from_usec = -1
	_last_song_time_sec = _origin_song_time_sec - speaker_delay_sec
	_frozen_song_time_sec = _last_song_time_sec
	_last_sample_usec = now_usec
	state = State.PLAYING

	if has_audio:
		audio_player.stream_paused = false
		audio_player.play(maxf(audio_from_sec, 0.0))

	sample(now_usec)
	started.emit(_generation)


func pause(capture_usec: int = -1) -> void:
	if state != State.PLAYING:
		return
	var now_usec: int = _resolve_capture_usec(capture_usec)
	_frozen_song_time_sec = song_time_at_usec(now_usec)
	_last_song_time_sec = _frozen_song_time_sec
	state = State.PAUSED
	if is_instance_valid(audio_player):
		audio_player.stream_paused = true
	sample(now_usec)
	paused.emit(_frozen_song_time_sec)


func resume(capture_usec: int = -1) -> void:
	if state != State.PAUSED:
		return
	var now_usec: int = _resolve_capture_usec(capture_usec)
	refresh_output_latency()
	var has_audio: bool = is_instance_valid(audio_player) and audio_player.stream != null
	var speaker_delay_sec: float = audio_calibration_sec
	if has_audio:
		speaker_delay_sec += AudioServer.get_time_to_next_mix() + _cached_output_latency_sec
	_system_origin_usec = now_usec + roundi(speaker_delay_sec * USEC_PER_SEC)
	_origin_song_time_sec = _frozen_song_time_sec
	_mapping_floor_from_usec = now_usec
	_mapping_floor_song_time_sec = _frozen_song_time_sec
	_last_song_time_sec = _frozen_song_time_sec
	_last_sample_usec = now_usec
	state = State.PLAYING
	if is_instance_valid(audio_player):
		audio_player.stream_paused = false
	sample(now_usec)
	resumed.emit(_frozen_song_time_sec)


func seek_song_time(target_song_time_sec: float, capture_usec: int = -1) -> void:
	var now_usec: int = _resolve_capture_usec(capture_usec)
	_bump_generation()
	var speaker_delay_sec: float = audio_calibration_sec
	if state == State.PLAYING and is_instance_valid(audio_player) and audio_player.stream != null:
		refresh_output_latency()
		speaker_delay_sec += AudioServer.get_time_to_next_mix() + _cached_output_latency_sec
	elif state != State.PLAYING:
		speaker_delay_sec = 0.0
	_system_origin_usec = now_usec + roundi(speaker_delay_sec * USEC_PER_SEC)
	_origin_song_time_sec = target_song_time_sec
	_mapping_floor_from_usec = now_usec if state == State.PLAYING else -1
	_mapping_floor_song_time_sec = target_song_time_sec
	_frozen_song_time_sec = target_song_time_sec
	_last_song_time_sec = target_song_time_sec
	_last_sample_usec = now_usec

	if is_instance_valid(audio_player) and audio_player.has_stream_playback():
		var audio_position_sec: float = maxf(target_song_time_sec + first_beat_offset_sec, 0.0)
		audio_player.seek(audio_position_sec)

	sample(now_usec)
	sought.emit(target_song_time_sec, _generation)


func stop(capture_usec: int = -1) -> void:
	if state == State.STOPPED:
		if is_instance_valid(audio_player):
			audio_player.stop()
		return
	var now_usec: int = _resolve_capture_usec(capture_usec)
	if state == State.PLAYING:
		_last_song_time_sec = song_time_at_usec(now_usec)
	_frozen_song_time_sec = _last_song_time_sec
	state = State.STOPPED
	_mapping_floor_from_usec = -1
	if is_instance_valid(audio_player):
		audio_player.stop()
	_bump_generation()
	sample(now_usec)
	stopped.emit(_generation)


func reset(capture_usec: int = -1) -> void:
	stop(capture_usec)
	_system_origin_usec = _resolve_capture_usec(capture_usec)
	_origin_song_time_sec = -first_beat_offset_sec
	_frozen_song_time_sec = _origin_song_time_sec
	_last_song_time_sec = _origin_song_time_sec
	_mapping_floor_from_usec = -1
	audio_time_raw_sec = _origin_song_time_sec
	song_time_sec = _origin_song_time_sec
	judge_time_sec = _origin_song_time_sec - input_compensation_sec
	visual_time_sec = _origin_song_time_sec + visual_lead_sec
	audio_drift_sec = 0.0


func song_time_at_usec(capture_usec: int) -> float:
	match state:
		State.PLAYING:
			var elapsed_sec: float = float(capture_usec - _system_origin_usec) / USEC_PER_SEC
			# 历史输入必须按其捕获时刻精确映射。若在这里钳制到上一帧已发布时间，
			# 晚一帧送达的输入会被悄悄改成迟按。
			var mapped_song_time_sec: float = _origin_song_time_sec + elapsed_sec
			if _mapping_floor_from_usec >= 0 and capture_usec >= _mapping_floor_from_usec:
				mapped_song_time_sec = maxf(mapped_song_time_sec, _mapping_floor_song_time_sec)
			return mapped_song_time_sec
		State.PAUSED:
			return _frozen_song_time_sec
		State.STOPPED:
			return _last_song_time_sec
		_:
			return _last_song_time_sec


func judge_time_at_usec(capture_usec: int) -> float:
	return song_time_at_usec(capture_usec) - input_compensation_sec


func sample(capture_usec: int = -1) -> ClockSample:
	var now_usec: int = _resolve_capture_usec(capture_usec)
	var current_song_time: float = song_time_at_usec(now_usec)
	if state == State.PLAYING:
		# 对外发布的连续时间不能倒退，即使调用者传入了更早的捕获时刻；
		# 这不影响 song_time_at_usec 对历史输入的精确映射。
		current_song_time = maxf(current_song_time, _last_song_time_sec)
		_last_song_time_sec = current_song_time
	_last_sample_usec = now_usec

	audio_time_raw_sec = _observe_audio_time(current_song_time)
	song_time_sec = current_song_time
	judge_time_sec = current_song_time - input_compensation_sec
	visual_time_sec = current_song_time + visual_lead_sec
	audio_drift_sec = audio_time_raw_sec - current_song_time

	var clock_sample := ClockSample.new()
	clock_sample.capture_usec = now_usec
	clock_sample.generation = _generation
	clock_sample.state = int(state)
	clock_sample.audio_time_raw_sec = audio_time_raw_sec
	clock_sample.song_time_sec = song_time_sec
	clock_sample.judge_time_sec = judge_time_sec
	clock_sample.visual_time_sec = visual_time_sec
	clock_sample.audio_drift_sec = audio_drift_sec
	sample_published.emit(clock_sample)
	return clock_sample


func is_running() -> bool:
	return state == State.PLAYING


func is_paused() -> bool:
	return state == State.PAUSED


func _observe_audio_time(fallback_song_time_sec: float) -> float:
	if state == State.PAUSED:
		return _frozen_song_time_sec
	if not is_instance_valid(audio_player) or not audio_player.has_stream_playback():
		return fallback_song_time_sec
	return (
		audio_player.get_playback_position()
		+ AudioServer.get_time_since_last_mix()
		- _cached_output_latency_sec
		- audio_calibration_sec
		- first_beat_offset_sec
	)


func _resolve_capture_usec(capture_usec: int) -> int:
	if capture_usec >= 0:
		return capture_usec
	return Time.get_ticks_usec()


func _bump_generation() -> void:
	_generation += 1
	generation_changed.emit(_generation)


## 写谱预览的时钟由 Transport 提供；参数为去掉首拍偏移后的游戏时间。
func publish_external_time(seconds: float, notify_visuals: bool = true) -> void:
	song_time_sec = seconds
	judge_time_sec = seconds
	visual_time_sec = seconds
	if not notify_visuals: return
	var value := ClockSample.new()
	value.song_time_sec = seconds
	value.judge_time_sec = seconds
	value.visual_time_sec = seconds
	sample_published.emit(value)
