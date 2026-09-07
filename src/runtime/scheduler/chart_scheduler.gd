class_name ChartScheduler
extends Node

## 纯表现调度器：按 visual_time 提前生成、按物理结果回收视觉对象，
## 绝不判断输入是否合法，也不计算成绩。

## 某事件进入预见窗口时请求创建视觉对象；`kind` 区分普通音符、调频和疾振。
signal visual_spawn_requested(kind: StringName, event_data: Dictionary)
## 事件离开保留窗口时请求回收对应视觉对象。
signal visual_despawn_requested(kind: StringName, event_id: String)
## 玩家敲击时机已被接受时发出，但此刻音符还要等实体波前接触，不能立即消失。
signal visual_timing_confirmed(event_id: String, grade: int)
## 玩法层正式产出判定等级时发出。
signal visual_judged(event_id: String, grade: int)
## 实体声波与普通音符发生接触时发出，表现层可播放击碎反馈。
signal visual_wave_contacted(event_id: String, contact: Dictionary)
## 未被声波消灭的音符抵达钟位时发出，表现层可播放穿过或 Miss 反馈。
signal visual_note_arrived(event_id: String, arrival: Dictionary)
## 重开或 Seek 清空所有调度状态时发出。
signal scheduler_reset

## 普通 Tap/Hold 视觉轨的内部类型名。
const KIND_NOTE: StringName = &"note"
## 调频区域视觉轨的内部类型名。
const KIND_TUNING: StringName = &"tuning"
## 双钟疾振区域视觉轨的内部类型名。
const KIND_RAPID: StringName = &"rapid"
## 一秒包含的微秒数，用于视觉秒时间和编译谱整数时间戳之间换算。
const USEC_PER_SEC: float = 1_000_000.0

## 事件在命中时刻前多少秒进入画面。数值越大，音符出现越早、飞行越慢。
@export_range(0.1, 10.0, 0.01) var approach_duration_sec: float = 2.25
## 调频和疾振事件结束后继续保留视觉对象的秒数；默认覆盖调频端点的 500ms 晚侧判定窗。
@export_range(0.0, 5.0, 0.01) var visual_tail_sec: float = 0.55
## 普通音符理论结束后最多保留的秒数，需覆盖波前接触或飞到角色的额外路程。
@export_range(0.1, 5.0, 0.01) var note_visual_tail_sec: float = 1.45
## 普通音符已经接触波或抵达角色后再保留的秒数；数值越大，击碎/消散动画越从容。
@export_range(0.05, 1.0, 0.01) var resolved_note_tail_sec: float = 0.22

## 调度器最近推进到的表现时间，单位为秒；它包含 Settings 中的画面提前量。
var visual_time_sec: float = 0.0

## 三类已编译事件轨，键为 KIND_*，数组按开始时间稳定排序。
var _tracks: Dictionary[StringName, Array] = {}
## 各轨下一项尚未生成事件的索引。
var _cursors: Dictionary[StringName, int] = {}
## 当前已生成且尚未回收的事件，键为稳定事件 ID，值含类型和事件数据。
var _active: Dictionary[String, Dictionary] = {}


func configure(compiled_chart: Variant, approach_sec: float = 2.25) -> void:
	approach_duration_sec = maxf(approach_sec, 0.05)
	_tracks = {
		KIND_NOTE: _read_array_member(compiled_chart, &"notes"),
		KIND_TUNING: _read_array_member(compiled_chart, &"tuning_sliders"),
		KIND_RAPID: _read_array_member(compiled_chart, &"rapid_regions"),
	}
	_sort_tracks()
	reset()


func reset() -> void:
	for active_id: String in _active.keys():
		var active_entry: Dictionary = _active[active_id]
		visual_despawn_requested.emit(active_entry["kind"], active_id)
	_active.clear()
	_cursors = {
		KIND_NOTE: 0,
		KIND_TUNING: 0,
		KIND_RAPID: 0,
	}
	visual_time_sec = 0.0
	scheduler_reset.emit()


func seek(target_visual_time_sec: float) -> void:
	# 跳转先彻底清场，再逐轨略过已经结束的事件，并重建仍应出现在目标时刻的对象。
	reset()
	visual_time_sec = target_visual_time_sec
	var target_usec: int = roundi(target_visual_time_sec * USEC_PER_SEC)
	for kind: StringName in _tracks.keys():
		var track: Array = _tracks[kind]
		var cursor: int = 0
		while cursor < track.size():
			var entry: Dictionary = track[cursor]
			var start_usec: int = _event_start_usec(entry)
			var end_usec: int = _event_end_usec(entry)
			if end_usec + _tail_usec_for(kind) < target_usec:
				cursor += 1
				continue
			if start_usec - roundi(approach_duration_sec * USEC_PER_SEC) <= target_usec:
				_spawn(kind, entry, cursor)
				cursor += 1
				continue
			break
		_cursors[kind] = cursor


func advance(target_visual_time_sec: float) -> void:
	visual_time_sec = target_visual_time_sec
	var target_usec: int = roundi(target_visual_time_sec * USEC_PER_SEC)
	var lookahead_usec: int = roundi(approach_duration_sec * USEC_PER_SEC)

	# 第一阶段只向前移动各轨游标，把进入“当前时间 + 预见窗口”的事件生成出来。
	for kind: StringName in _tracks.keys():
		var track: Array = _tracks[kind]
		var cursor: int = int(_cursors.get(kind, 0))
		while cursor < track.size():
			var entry: Dictionary = track[cursor]
			if _event_start_usec(entry) - lookahead_usec > target_usec:
				break
			_spawn(kind, entry, cursor)
			cursor += 1
		_cursors[kind] = cursor

	# 第二阶段统一找出过期对象后再删除，避免遍历字典时修改同一个字典。
	var expired_ids: Array[String] = []
	for active_id: String in _active.keys():
		var active_entry: Dictionary = _active[active_id]
		var event_data: Dictionary = active_entry["data"]
		var expiry_usec: int = _event_end_usec(event_data) + _tail_usec_for(active_entry["kind"])
		var resolved_usec: int = int(active_entry.get("resolved_us", -1))
		if StringName(event_data.get("unit_kind", &"")) == &"hold":
			# Hold 的失败尾部由 Host 沿实际视觉路线送完；成功仍保留结果展示时间。
			if resolved_usec < 0:
				continue
			expiry_usec = resolved_usec + roundi(resolved_note_tail_sec * USEC_PER_SEC)
		if resolved_usec >= 0:
			expiry_usec = mini(expiry_usec, resolved_usec + roundi(resolved_note_tail_sec * USEC_PER_SEC))
		if expiry_usec < target_usec:
			expired_ids.append(active_id)
	for active_id: String in expired_ids:
		var active_entry: Dictionary = _active[active_id]
		visual_despawn_requested.emit(active_entry["kind"], active_id)
		_active.erase(active_id)


func mark_judged(event_id: String, grade: int) -> void:
	visual_judged.emit(event_id, grade)
	if _active.has(event_id) and StringName(_active[event_id].get("kind", &"")) == KIND_NOTE:
		var active_entry: Dictionary = _active[event_id]
		if StringName(active_entry["data"].get("unit_kind", &"")) == &"hold" and grade == GameplayTypes.JudgmentGrade.MISS:
			return
		if int(active_entry.get("resolved_us", -1)) < 0:
			active_entry["resolved_us"] = roundi(visual_time_sec * USEC_PER_SEC)


func mark_timing_confirmed(event_id: String, grade: int) -> void:
	# 时机被接受只用于即时反馈，不能据此解决或删除普通音符。
	# 音符必须继续飞行，直到绑定波前真实接触，或未命中时抵达钟的位置。
	if not _active.has(event_id):
		return
	if StringName(_active[event_id].get("kind", &"")) != KIND_NOTE:
		return
	visual_timing_confirmed.emit(event_id, grade)


func mark_wave_contacted(event_id: String, contact: Dictionary) -> void:
	if _active.has(event_id):
		var active_entry: Dictionary = _active[event_id]
		var event_data: Dictionary = active_entry["data"]
		if StringName(event_data.get("unit_kind", &"tap")) == &"tap":
			active_entry["resolved_us"] = int(contact.get("contact_us", roundi(visual_time_sec * USEC_PER_SEC)))
	visual_wave_contacted.emit(event_id, contact.duplicate(true))


func mark_note_arrived(event_id: String, arrival: Dictionary) -> void:
	if _active.has(event_id):
		# 领域路线没有包含 Hold 视觉暂停，不能用它提前回收或播放视觉抵达。
		if StringName(_active[event_id]["data"].get("unit_kind", &"")) == &"hold":
			return
		_active[event_id]["resolved_us"] = int(arrival.get("arrival_us", roundi(visual_time_sec * USEC_PER_SEC)))
	visual_note_arrived.emit(event_id, arrival.duplicate(true))


func finish_hold_visual(event_id: String) -> void:
	## Host 确认失败 Hold 的尾部抵达路线末端后，请求统一回收。
	if not _active.has(event_id):
		return
	var entry: Dictionary = _active[event_id]
	if StringName(entry["data"].get("unit_kind", &"")) != &"hold":
		return
	_active.erase(event_id)
	visual_despawn_requested.emit(entry["kind"], event_id)


func get_active_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for active_entry: Dictionary in _active.values():
		result.append(active_entry.duplicate(true))
	return result


func _spawn(kind: StringName, source: Dictionary, fallback_index: int) -> void:
	var entry: Dictionary = source.duplicate(true)
	var event_id: String = _event_id(entry, kind, fallback_index)
	entry["event_id"] = event_id
	if _active.has(event_id):
		return
	_active[event_id] = {"kind": kind, "data": entry}
	visual_spawn_requested.emit(kind, entry)


func _sort_tracks() -> void:
	for kind: StringName in _tracks.keys():
		var track: Array = _tracks[kind]
		track.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_time: int = _event_start_usec(a)
			var b_time: int = _event_start_usec(b)
			if a_time != b_time:
				return a_time < b_time
			return str(a.get("id", a.get("event_id", a.get("unit_id", "")))) < str(b.get("id", b.get("event_id", b.get("unit_id", ""))))
		)


func _event_id(entry: Dictionary, kind: StringName, fallback_index: int) -> String:
	var candidate: String = str(entry.get("id", entry.get("event_id", entry.get("unit_id", ""))))
	if not candidate.is_empty():
		return candidate
	return "%s_%06d" % [kind, fallback_index]


func _event_start_usec(entry: Dictionary) -> int:
	return int(entry.get("start_us", entry.get("start_time_us", entry.get("time_us", entry.get("timestamp_us", 0)))))


func _event_end_usec(entry: Dictionary) -> int:
	var start_usec: int = _event_start_usec(entry)
	return int(entry.get("end_us", entry.get("end_time_us", start_usec + int(entry.get("duration_us", 0)))))


func _read_array_member(source: Variant, member_name: StringName) -> Array:
	if source == null:
		return []
	if source is Dictionary:
		var dictionary: Dictionary = source
		var dictionary_value: Variant = dictionary.get(member_name, [])
		return dictionary_value if dictionary_value is Array else []
	if source is Object and _object_has_property(source, member_name):
		var object_value: Variant = source.get(member_name)
		return object_value if object_value is Array else []
	return []


func _tail_usec_for(kind: StringName) -> int:
	var tail_sec: float = note_visual_tail_sec if kind == KIND_NOTE else visual_tail_sec
	return roundi(tail_sec * USEC_PER_SEC)


func _object_has_property(source: Object, member_name: StringName) -> bool:
	for property_data: Dictionary in source.get_property_list():
		if property_data.get("name", &"") == member_name:
			return true
	return false
