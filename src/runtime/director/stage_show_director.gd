class_name StageShowDirector
extends Node

## StageShow 的确定性演出调度器。它使用编译谱共享的 TempoMap 把 tick 换成时间，
## 只发布演出 Cue，不读取或修改判定、分数和血量。

## 任意演出 Cue 到达起点时发出；瞬时 Cue 通常只监听这个信号。
signal cue_triggered(cue: Dictionary)
## 有持续时间的 Cue 开始时发出。
signal cue_started(cue: Dictionary)
## 持续 Cue 存活期间逐次发出；`progress` 为从 0 到 1 的归一化进度。
signal cue_updated(cue: Dictionary, progress: float)
## 持续 Cue 到达终点时发出。
signal cue_ended(cue: Dictionary)
## 重置或跳转导致现有演出状态失效时发出，宿主应清理临时效果。
signal director_reset

## 尚未开始推进时使用的极小微秒时间，确保第一个合法 Cue 不会被误认为已经过去。
const UNSTARTED_TIME_US: int = -9_000_000_000_000_000

## 当前关卡的演出资源，保存谱面 tick 上的 Cue 原始数据。
var show: StageShow
## 与玩法谱面共用的拍速映射，负责把 Cue 的 tick 换算成确定性微秒时间。
var tempo_map: TempoMap
## 导演已推进到的歌曲时间，单位为微秒。
var current_time_us: int = UNSTARTED_TIME_US
## 是否响应 SongClock 快照；手动 Seek 时会暂时关闭，避免同一帧重复推进。
var clock_updates_enabled: bool = true

## 已编译并按开始时间排序的 Cue；每项同时含 tick、start_us、end_us 和参数副本。
var _compiled_cues: Array[Dictionary] = []
## `_compiled_cues` 中下一个尚未触发元素的索引。
var _cursor: int = 0
## 当前仍在持续的 Cue，键为稳定 `event_id`，值为其编译数据。
var _active: Dictionary[String, Dictionary] = {}


func bind(clock: SongClock, session: StageSession) -> void:
	if not clock.sample_published.is_connected(_on_clock_sample):
		clock.sample_published.connect(_on_clock_sample)
	if not session.run_started.is_connected(_on_run_started):
		session.run_started.connect(_on_run_started)
	if not session.result_ready.is_connected(_on_result_ready):
		session.result_ready.connect(_on_result_ready)


func configure(stage_show: StageShow, shared_tempo_map: TempoMap) -> void:
	show = stage_show
	tempo_map = shared_tempo_map
	_compile_cues()
	reset()


func set_clock_updates_enabled(enabled: bool) -> void:
	clock_updates_enabled = enabled


func reset() -> void:
	_cursor = 0
	_active.clear()
	current_time_us = UNSTARTED_TIME_US
	director_reset.emit()


func advance_to(song_time_sec: float) -> void:
	advance_to_us(roundi(song_time_sec * 1_000_000.0))


func advance_to_us(target_time_us: int) -> void:
	if target_time_us < current_time_us:
		seek_us(target_time_us)
		return
	while _cursor < _compiled_cues.size():
		var cue: Dictionary = _compiled_cues[_cursor]
		if int(cue["start_us"]) > target_time_us:
			break
		_cursor += 1
		_trigger(cue, target_time_us)
	_update_active(target_time_us)
	current_time_us = target_time_us


func seek(song_time_sec: float) -> void:
	seek_us(roundi(song_time_sec * 1_000_000.0))


func seek_us(target_time_us: int) -> void:
	# Seek 后只重建仍跨越目标时刻的持续 Cue；已经过去的一次性 Cue 不重放，
	# 因而需要持久状态的演出应使用持续 Cue 或由宿主自行按目标时间恢复。
	_cursor = 0
	_active.clear()
	current_time_us = target_time_us
	director_reset.emit()
	for cue: Dictionary in _compiled_cues:
		var start_us: int = int(cue["start_us"])
		if start_us > target_time_us:
			break
		_cursor += 1
		var end_us: int = int(cue["end_us"])
		if end_us > start_us and end_us > target_time_us:
			_active[String(cue["event_id"])] = cue
			cue_triggered.emit(cue.duplicate(true))
			cue_started.emit(cue.duplicate(true))
			cue_updated.emit(cue.duplicate(true), _progress(cue, target_time_us))
		elif start_us == target_time_us and end_us == start_us:
			cue_triggered.emit(cue.duplicate(true))


func get_compiled_cues() -> Array[Dictionary]:
	return _compiled_cues.duplicate(true)


func get_active_cues() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cue: Dictionary in _active.values():
		result.append(cue.duplicate(true))
	return result


func _trigger(cue: Dictionary, target_time_us: int) -> void:
	var payload: Dictionary = cue.duplicate(true)
	cue_triggered.emit(payload)
	var start_us: int = int(cue["start_us"])
	var end_us: int = int(cue["end_us"])
	if end_us <= start_us:
		return
	cue_started.emit(payload)
	if end_us <= target_time_us:
		cue_updated.emit(payload, 1.0)
		cue_ended.emit(payload)
		return
	_active[String(cue["event_id"])] = cue


func _update_active(target_time_us: int) -> void:
	var ended_ids: Array[String] = []
	for event_id: String in _active.keys():
		var cue: Dictionary = _active[event_id]
		var progress: float = _progress(cue, target_time_us)
		cue_updated.emit(cue.duplicate(true), progress)
		if target_time_us >= int(cue["end_us"]):
			cue_ended.emit(cue.duplicate(true))
			ended_ids.append(event_id)
	for event_id: String in ended_ids:
		_active.erase(event_id)


func _progress(cue: Dictionary, target_time_us: int) -> float:
	var start_us: int = int(cue["start_us"])
	var end_us: int = int(cue["end_us"])
	if end_us <= start_us:
		return 1.0
	return clampf(float(target_time_us - start_us) / float(end_us - start_us), 0.0, 1.0)


func _compile_cues() -> void:
	_compiled_cues.clear()
	if show == null or tempo_map == null:
		return
	var seen_ids: Dictionary[String, bool] = {}
	for source: ShowCue in show.cues:
		if source == null or source.event_id.is_empty():
			push_warning("StageShowDirector skipped a cue without stable event_id.")
			continue
		if seen_ids.has(source.event_id):
			push_warning("StageShowDirector skipped duplicate event_id: %s" % source.event_id)
			continue
		seen_ids[source.event_id] = true
		var end_tick: int = source.tick + maxi(source.duration_ticks, 0)
		var start_us: int = tempo_map.tick_to_us(source.tick)
		var end_us: int = tempo_map.tick_to_us(end_tick)
		_compiled_cues.append({
			"event_id": source.event_id,
			"cue_id": source.cue_id,
			"track": source.track,
			"target_slot": source.target_slot,
			"parameters": source.parameters.duplicate(true),
			"tick": source.tick,
			"duration_ticks": maxi(source.duration_ticks, 0),
			"end_tick": end_tick,
			"start_us": start_us,
			"end_us": end_us,
		})
	_compiled_cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["start_us"]) != int(b["start_us"]):
			return int(a["start_us"]) < int(b["start_us"])
		if int(a["track"]) != int(b["track"]):
			return int(a["track"]) < int(b["track"])
		return String(a["event_id"]) < String(b["event_id"])
	)


func _on_clock_sample(sample: ClockSample) -> void:
	if clock_updates_enabled:
		advance_to(sample.song_time_sec)


func _on_run_started(_run_id: int) -> void:
	reset()


func _on_result_ready(_result: Dictionary) -> void:
	reset()
