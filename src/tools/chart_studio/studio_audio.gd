class_name StudioAudio
extends Node
## 唯一音乐播放器。时钟以源音频秒数计，改变倍率时重设单调时钟锚点。
signal position_changed(seconds: float)
signal waveform_ready(peaks: PackedVector2Array, duration: float)
signal error_reported(message: String)
## 控件订阅播放意图和循环参数，包含快捷键、恢复工作区与自然结束。
signal state_changed
signal discontinuity(seconds: float, reason: StringName)
signal loop_wrapping(end_seconds: float)
var playing := false
var suspended := false
var rate := 1.0
var position := 0.0
var loop_enabled := false:
	set(value):
		if loop_enabled == value: return
		loop_enabled = value
		state_changed.emit()
var loop_start := 0.0:
	set(value):
		if loop_start == value: return
		loop_start = value
		state_changed.emit()
var loop_end := 4.0:
	set(value):
		if loop_end == value: return
		loop_end = value
		state_changed.emit()
var processing_latency := 0.0
var device_compensation_ms := 0.0
var _anchor := 0
var _origin := 0.0
var _player: AudioStreamPlayer
var _effect := AudioEffectPitchShift.new()
var _bus := -1
var _wave_thread: Thread
var _wave_path := ""
var _requested_path := ""
var _wave_cancel: Array[bool] = [false]
var _wave_request := 0
var _wave_running := 0
var backward_samples := 0
var cues := StudioCueTrack.new()
var cached_output_latency := 0.0
var _cue_bus := -1
var _output_device := ""
var _start_delay := 0.0
var _cue_restart_pending := false
var _last_underrun_notice_usec := -10000000

func _ready() -> void:
	# 工作区父节点随后消费本帧时间；避免预览再使用上一帧位置。
	process_priority = -100
	var settings := ConfigFile.new()
	if settings.load("user://chart_studio/settings.cfg") == OK: device_compensation_ms = float(settings.get_value("audio", "device_compensation_ms", 0))
	_bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(_bus, "StudioMusic")
	_effect.fft_size = AudioEffectPitchShift.FFT_SIZE_1024
	_effect.oversampling = 4
	AudioServer.add_bus_effect(_bus, _effect)
	AudioServer.set_bus_effect_enabled(_bus, 0, false)
	_cue_bus = AudioServer.bus_count
	AudioServer.add_bus(); AudioServer.set_bus_name(_cue_bus, &"StudioCues")
	_player = AudioStreamPlayer.new()
	_player.bus = "StudioMusic"
	add_child(_player)
	add_child(cues)
	cues.underrun.connect(func() -> void: _cue_restart_pending = true)
	refresh_output_latency()

func refresh_output_latency() -> void:
	cached_output_latency = maxf(0, AudioServer.get_output_latency())
	_output_device = AudioServer.output_device

func _cue_end_seconds(segment_origin: float) -> float:
	var end := _player.stream.get_length() if _player.stream != null else INF
	if loop_enabled and loop_end > loop_start: end = minf(end, loop_end)
	# 预滚不能提前提交下一播放段的零点提示，否则跨零重启时会敲两次。
	return minf(end, 0) if segment_origin < 0 else end

func _start_streams() -> void:
	refresh_output_latency()
	processing_latency = 0.0 if is_equal_approx(rate, 1.0) else 512.0 / AudioServer.get_mix_rate()
	# 先让样本 producer 停止接触旧 playback，随后才能进入双路启动的驱动锁。
	cues.stop()
	cues.end_seconds = _cue_end_seconds(position)
	var first := cues.prepare_segment(position, rate, processing_latency)
	var fresh_effect := AudioEffectPitchShift.new()
	fresh_effect.fft_size = AudioEffectPitchShift.FFT_SIZE_1024; fresh_effect.oversampling = 4; fresh_effect.pitch_scale = 1.0 / rate
	# 只在锁内注册/复位播放器，不计算 PCM 或等待下一帧。
	AudioServer.lock()
	_player.stop()
	AudioServer.remove_bus_effect(_bus, 0)
	_effect = fresh_effect
	AudioServer.add_bus_effect(_bus, _effect, 0)
	AudioServer.set_bus_effect_enabled(_bus, 0, not is_equal_approx(rate, 1.0))
	_origin = position; _anchor = Time.get_ticks_usec()
	_start_delay = AudioServer.get_time_to_next_mix() + cached_output_latency + processing_latency + device_compensation_ms / 1000.0
	# 负时间也保留编钟提示；到音乐零点再建立两路共同起点。
	if _player.stream != null and position >= 0: _player.play(position)
	cues.start_prepared(first)
	AudioServer.unlock()
	_cue_restart_pending = false

func _exit_tree() -> void:
	_wave_cancel[0] = true
	if _wave_thread != null: _wave_thread.wait_to_finish()
	cues.stop(); _player.stop()
	if _cue_bus >= 0: AudioServer.remove_bus(_cue_bus)
	if _bus >= 0: AudioServer.remove_bus(_bus)
	var settings := ConfigFile.new()
	settings.load("user://chart_studio/settings.cfg")
	settings.set_value("audio", "device_compensation_ms", device_compensation_ms)
	DirAccess.make_dir_recursive_absolute("user://chart_studio")
	settings.save("user://chart_studio/settings.cfg")

func set_stream(stream: AudioStream) -> void:
	set_playing(false)
	_player.stream = stream
	seek(0.0)

func set_playing(value: bool) -> void:
	if value == playing: return
	playing = value
	_origin = position
	_anchor = Time.get_ticks_usec()
	if playing and not suspended:
		_start_streams()
	else:
		_player.stop(); cues.stop(); _start_delay = 0.0
	state_changed.emit()

func seek(seconds: float, reason: StringName = &"seek") -> void:
	position = seconds
	_origin = seconds
	_anchor = Time.get_ticks_usec()
	_player.stop(); cues.stop(); _start_delay = 0.0
	if playing and not suspended: _start_streams()
	position_changed.emit(position)
	discontinuity.emit(position, reason)

func set_rate(value: float) -> void:
	rate = value
	_origin = position
	_anchor = Time.get_ticks_usec()
	_player.pitch_scale = rate
	_effect.pitch_scale = 1.0 / rate
	AudioServer.set_bus_effect_enabled(_bus, 0, not is_equal_approx(rate, 1.0))
	# 1024 FFT 实测比旁路多约 11ms；该量作用于试听时钟，不写入歌曲偏移。
	processing_latency = 0.0 if is_equal_approx(rate, 1.0) else 512.0 / AudioServer.get_mix_rate()
	seek(position, &"rate")
	state_changed.emit()

func _read_clock_position() -> float:
	if _player.playing:
		var audible := _player.get_playback_position() + AudioServer.get_time_since_last_mix() * rate
		audible -= (cached_output_latency + processing_latency + device_compensation_ms / 1000.0) * rate
		return maxf(_origin, audible)
	return _origin + (float(Time.get_ticks_usec() - _anchor) / 1000000.0 - _start_delay) * rate

func sample_position() -> float:
	# 输入回调早于本帧 _process，录入必须当场取样，不能沿用上一帧播放头。
	return maxf(position, _read_clock_position()) if playing and not suspended else position

func _process(_delta: float) -> void:
	if playing and not suspended:
		var previous := position
		position = _read_clock_position()
		if position < previous: backward_samples += 1
		position = maxf(previous, position)
		if position >= 0 and _origin < 0:
			# 负时间预滚跨过零点时，从样本零开始，不能漏掉开头第一拍。
			if previous < 0: position = 0.0
			_start_streams()
		cues.end_seconds = _cue_end_seconds(_origin)
		cues.fill()
		if _cue_restart_pending or AudioServer.output_device != _output_device:
			# 欠载已填入静音，旧样本编号失效；重新对齐两路，不累计迟响。
			if _cue_restart_pending and Time.get_ticks_usec() - _last_underrun_notice_usec > 2000000:
				_last_underrun_notice_usec = Time.get_ticks_usec()
				error_reported.emit("试听缓冲不足，已重新同步音乐与提示音")
			_start_streams()
		if loop_enabled and loop_end > loop_start and position >= loop_end:
			loop_wrapping.emit(loop_end)
			seek(loop_start, &"loop")
		elif _player.stream != null and position >= _player.stream.get_length():
			set_playing(false)
		position_changed.emit(position)
	if _wave_thread != null and not _wave_thread.is_alive():
		var result: Dictionary = _wave_thread.wait_to_finish()
		_wave_thread = null
		if _wave_running == _wave_request and not result.has("cancelled"):
			if result.has("error"): error_reported.emit(result.error)
			else: waveform_ready.emit(result.peaks, result.duration)
		elif not _requested_path.is_empty(): _start_waveform()

func set_suspended(value: bool) -> void:
	if suspended == value: return
	suspended = value
	_origin = position; _anchor = Time.get_ticks_usec()
	_player.stop(); cues.stop()
	if not suspended and playing: _start_streams()

func build_waveform(path: String) -> void:
	_wave_request += 1
	_requested_path = path
	if _wave_thread != null:
		_wave_cancel[0] = true
		return
	if not path.is_empty(): _start_waveform()

func _start_waveform() -> void:
	_wave_path = _requested_path
	_wave_running = _wave_request
	_wave_cancel = [false]
	_wave_thread = Thread.new()
	_wave_thread.start(StudioAudio.decode_peaks.bind(_wave_path, _wave_cancel))

static func decode_peaks(path: String, cancelled: Array[bool] = []) -> Dictionary:
	var cache_path := "user://chart_studio/cache/%s_%d.wave" % [path.get_file(), path.hash()]
	var modified := FileAccess.get_modified_time(path)
	if FileAccess.file_exists(cache_path):
		var cache := FileAccess.open(cache_path, FileAccess.READ)
		var value: Variant = cache.get_var()
		if value is Dictionary and value.get("modified") == modified: return value
	var stream := ChartJsonCodec.load_audio(path)
	if stream == null: return {"error": "波形音频无法解码"}
	# 解码实例只归后台任务所有，不影响前台音乐播放进度。
	var playback := stream.instantiate_playback()
	playback.start()
	var sample_rate := AudioServer.get_mix_rate()
	var count := ceili(stream.get_length() * sample_rate)
	var peaks := PackedVector2Array()
	for start in range(0, count, 256):
		if not cancelled.is_empty() and cancelled[0]: playback.stop(); return {"cancelled": true}
		var samples := playback.mix_audio(1.0, mini(256, count - start))
		var low := 0.0
		var high := 0.0
		for sample in samples:
			low = minf(low, minf(sample.x, sample.y))
			high = maxf(high, maxf(sample.x, sample.y))
		peaks.append(Vector2(low, high))
	playback.stop()
	var result := {"peaks": peaks, "duration": stream.get_length(), "modified": modified}
	DirAccess.make_dir_recursive_absolute(cache_path.get_base_dir())
	var cache := FileAccess.open(cache_path, FileAccess.WRITE)
	if cache != null: cache.store_var(result)
	return result
