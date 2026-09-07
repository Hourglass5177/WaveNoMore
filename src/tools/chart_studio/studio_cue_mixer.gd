class_name StudioCueMixer
extends RefCounted
## 唯一 PCM producer，不访问节点；编辑快照与生命周期通过 mutex 交接。
const QUEUE_SECONDS := 0.1
var events: Array[Dictionary] = []
var samples := {}
var skipped_buffers := 0
var rendered_events := 0
var end_seconds := INF:
	set(value):
		_mutex.lock(); end_seconds = value; _mutex.unlock()
var _playback: AudioStreamGeneratorPlayback
var _origin := 0.0
var _rate := 1.0
var _delay := 0.0
var _sample_rate := 48000.0
var _written := 0
var _cursor := 0
var _voices: Array[Dictionary] = []
var _skip_baseline := 0
var _capacity := 0
var _mutex := Mutex.new()
var _worker := Thread.new()
var _closing := false
var _underrun_pending := false


func start_worker() -> void:
	_worker.start(_produce, Thread.PRIORITY_HIGH)

func shutdown() -> void:
	_mutex.lock(); _closing = true; _playback = null; _mutex.unlock()
	_worker.wait_to_finish()

func detach() -> void:
	_mutex.lock(); _playback = null; _mutex.unlock()

func set_pcm(key: StringName, pcm: PackedVector2Array) -> void:
	_mutex.lock(); samples[key] = pcm; _mutex.unlock()

func has_underrun() -> bool:
	_mutex.lock(); var result := _underrun_pending; _mutex.unlock(); return result

func attach(value: AudioStreamGeneratorPlayback, block: PackedVector2Array) -> void:
	# 主线程双路启动事务：此前必须 detach，producer 此时不会申请驱动锁。
	_mutex.lock()
	_playback = value; _capacity = _playback.get_frames_available()
	_playback.push_buffer(block); _playback.begin_resample()
	_skip_baseline = _playback.get_skips(); _underrun_pending = false
	_mutex.unlock()

func set_events(value: Array[Dictionary]) -> void:
	# 原生数组比较按秒数和原序号排序，避免密集谱每次触发大量脚本比较回调。
	var ordered: Array = []
	for i in value.size(): ordered.append([float(value[i].seconds), i])
	ordered.sort()
	var sorted_events: Array[Dictionary] = []
	for item in ordered: sorted_events.append(value[int(item[1])])
	_mutex.lock()
	events = sorted_events
	# 已经交给音频设备的短队列不回收；新版本只接管尚未写入的部分。
	_cursor = _first_event_index(_written, true)
	_mutex.unlock()

func _first_event_index(minimum: float, in_samples: bool) -> int:
	# 密集谱定位只查有序索引，不逐个重算此前一万条事件的时间。
	var first := 0; var end := events.size()
	while first < end:
		var middle := (first + end) / 2
		var value := float(_event_frame(events[middle])) if in_samples else float(events[middle].seconds)
		if value < minimum: first = middle + 1
		else: end = middle
	return first

func _event_frame(event: Dictionary) -> int:
	return roundi(((float(event.seconds) - _origin) / _rate + _delay) * _sample_rate)

func prepare_segment(origin: float, rate: float, processing_delay: float) -> PackedVector2Array:
	_mutex.lock()
	_origin = origin; _rate = rate; _delay = processing_delay
	_written = 0; _cursor = _first_event_index(origin - 0.000001, false); _voices.clear()
	var block := render_frames(roundi(QUEUE_SECONDS * _sample_rate))
	_mutex.unlock()
	return block

func _produce() -> void:
	while true:
		_mutex.lock()
		if _closing: _mutex.unlock(); return
		if _playback != null and not _underrun_pending: _fill_samples()
		_mutex.unlock()
		OS.delay_msec(5)

func _fill_samples() -> void:
	# 唯一 producer；短驱动锁保护原生 RingBuffer 读写位置，PCM 循环不持驱动锁。
	AudioServer.lock()
	var skips := _playback.get_skips()
	var available := _playback.get_frames_available()
	AudioServer.unlock()
	if skips > _skip_baseline:
		skipped_buffers += skips - _skip_baseline; _skip_baseline = skips
		_underrun_pending = true; return
	var queued := _capacity - available
	var count := mini(available, maxi(0, roundi(QUEUE_SECONDS * _sample_rate) - queued))
	if count > 0:
		var block := render_frames(count)
		AudioServer.lock(); _playback.push_buffer(block); AudioServer.unlock()

func render_frames(count: int) -> PackedVector2Array:
	var block := PackedVector2Array(); block.resize(count)
	var end := _written + count
	while _cursor < events.size() and _event_frame(events[_cursor]) < end:
		# 循环终点后的提示不能提前排进设备队列；终点本身属于下一段。
		if float(events[_cursor].seconds) >= end_seconds: break
		var event := events[_cursor]; _cursor += 1
		var at := _event_frame(event)
		if at < _written: continue
		if samples.has(event.sample):
			_voices.append({"start": at, "data": samples[event.sample]}); rendered_events += 1
	for voice in _voices:
		var data: PackedVector2Array = voice.data
		var first := maxi(_written, int(voice.start))
		var last := mini(end, int(voice.start) + data.size())
		for at in range(first, last): block[at - _written] += data[at - int(voice.start)]
	_voices = _voices.filter(func(v: Dictionary) -> bool: return int(v.start) + v.data.size() > end)
	_written = end
	return block
