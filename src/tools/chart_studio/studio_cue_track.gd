class_name StudioCueTrack
extends Node
## 场景播放器归主线程，常驻 mixer 补样本不等待 UI 帧。
signal underrun
var mixer := StudioCueMixer.new()
var _player := AudioStreamPlayer.new()
var _generator := AudioStreamGenerator.new()
var events: Array[Dictionary]:
	get: return mixer.events
var samples: Dictionary:
	get: return mixer.samples
var skipped_buffers: int:
	get:
		mixer._mutex.lock(); var result := mixer.skipped_buffers; mixer._mutex.unlock(); return result
var rendered_events: int:
	get:
		mixer._mutex.lock(); var result := mixer.rendered_events; mixer._mutex.unlock(); return result
var end_seconds: float:
	get: return mixer.end_seconds
	set(value): mixer.end_seconds = value

func _ready() -> void:
	mixer._sample_rate = AudioServer.get_mix_rate()
	# PCM 和事件位置共用固定源采样率；换设备后由引擎重采样，不改变样本时间。
	_generator.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	_generator.mix_rate = mixer._sample_rate; _generator.buffer_length = 0.12
	_player.stream = _generator; _player.bus = &"StudioCues"; add_child(_player)
	var factory = preload("res://src/presentation/audio/graybox_click_track_factory.gd")
	set_sample(&"life", factory.create_transient(470, 0.085, 0.25, 0.30))
	set_sample(&"death", factory.create_transient(315, 0.095, 0.27, 0.55))
	set_sample(&"beat", factory.create_transient(1400, 0.035, 0.2))
	set_sample(&"strong", factory.create_transient(1800, 0.035, 0.24))
	mixer.start_worker()

func _exit_tree() -> void:
	mixer.shutdown(); _player.stop()

func set_sample(key: StringName, stream: AudioStream) -> void:
	if stream == null: return
	var decoder := stream.instantiate_playback(); decoder.start()
	var pcm := decoder.mix_audio(AudioServer.get_mix_rate() / mixer._sample_rate, ceili(stream.get_length() * mixer._sample_rate)); decoder.stop()
	mixer.set_pcm(key, pcm)

func set_events(value: Array[Dictionary]) -> void:
	mixer.set_events(value)

func prepare_segment(origin: float, rate: float, processing_delay: float) -> PackedVector2Array:
	return mixer.prepare_segment(origin, rate, processing_delay)

func start_prepared(block: PackedVector2Array) -> void:
	# 调用方在驱动锁外 stop 后进入启动事务；锁内不等待 producer 或渲染 PCM。
	_player.play()
	mixer.attach(_player.get_stream_playback() as AudioStreamGeneratorPlayback, block)

func stop() -> void:
	mixer.detach(); _player.stop()

func fill() -> void:
	if mixer.has_underrun(): underrun.emit()

func render_frames(count: int) -> PackedVector2Array:
	return mixer.render_frames(count)
