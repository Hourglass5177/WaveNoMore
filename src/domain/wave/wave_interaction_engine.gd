class_name WaveInteractionEngine
extends RefCounted

## 编钟波与普通音符的纯确定性交互模型。
##
## 这里有意不做 Node2D/Area2D 逐帧碰撞。波前和绑定音符都按同一套公式和绝对时间计算，
## 即使漏绘一帧，接触时刻也不会改变。它只处理普通音符；调频和疾振另有判定器。

## 尚未开始模拟的微秒哨兵值；远离任何合法歌曲时间。
const NEVER_TIME_US: int = -9_000_000_000_000_000
## 一秒的微秒数，用于整数领域时间与像素/秒运动参数换算。
const USEC_PER_SEC: float = 1_000_000.0

## 默认波速，单位设计像素/秒；规则表没有有效值时使用。
const DEFAULT_WAVE_SPEED_PX_SEC: float = 2400.0
## 默认可接触波前半宽，单位设计像素；完整接触带宽为其两倍。
const DEFAULT_WAVE_FRONT_HALF_WIDTH_PX: float = 18.0
## 默认音符入场时长，单位秒；越大音符沿路径运动越慢。
const DEFAULT_APPROACH_DURATION_SEC: float = 2.25
## 默认生钟波源坐标，基于 1920×1080 画布，X 向右、Y 向下。
const DEFAULT_LIFE_WAVE_ORIGIN: Vector2 = Vector2(350.0, 280.0)
## 默认死钟波源坐标，基于 1920×1080 画布，X 向右、Y 向下。
const DEFAULT_DEATH_WAVE_ORIGIN: Vector2 = Vector2(1570.0, 800.0)
## 默认生音符中央判定坐标，单位设计像素。
const DEFAULT_LIFE_NOTE_CUE: Vector2 = Vector2(960.0, 540.0)
## 默认死音符中央判定坐标，单位设计像素。
const DEFAULT_DEATH_NOTE_CUE: Vector2 = Vector2(960.0, 540.0)
## 默认生音符生成坐标，位于设计画布右上外侧。
const DEFAULT_LIFE_NOTE_SPAWN: Vector2 = Vector2(2040.0, 220.0)
## 默认死音符生成坐标，位于设计画布左下外侧。
const DEFAULT_DEATH_NOTE_SPAWN: Vector2 = Vector2(-120.0, 860.0)
## 默认入场曲线外鼓量，单位设计像素；越大弧线越向外弯。
const DEFAULT_CURVE_OUTER_BEND_PX: float = 220.0
## 默认中心控制柄长度，单位设计像素；越大切入中心越舒缓。
const DEFAULT_CURVE_CENTER_HANDLE_PX: float = 360.0
## 灰色无效波的相对强度；小于 1，使乱按仍有物理波但视觉弱于有效彩波。
const INVALID_WAVE_STRENGTH: float = 0.55

## 当前编译谱引用；只从其中建立普通音符物理状态。
var _compiled: CompiledChart
## 当前规则引用；提供波速、路径和设计画布物理合同。
var _rules: GameplayRuleSet
## 最近求解到的歌曲时间，单位微秒；NEVER_TIME_US 表示尚未推进。
var _current_time_us: int = NEVER_TIME_US

## 当前波速，单位设计像素/秒；configure/reset 时从规则表复制。
var _wave_speed_px_sec: float = DEFAULT_WAVE_SPEED_PX_SEC
## 当前波前半宽，单位设计像素；波半径与音符距离差落在此范围即可能接触。
var _wave_front_half_width_px: float = DEFAULT_WAVE_FRONT_HALF_WIDTH_PX
## 当前音符入场时长，单位秒；决定生成微秒与运动进度。
var _approach_duration_sec: float = DEFAULT_APPROACH_DURATION_SEC
## 当前生钟波源坐标，单位设计像素，X 向右、Y 向下。
var _life_wave_origin: Vector2 = DEFAULT_LIFE_WAVE_ORIGIN
## 当前死钟波源坐标，单位设计像素，X 向右、Y 向下。
var _death_wave_origin: Vector2 = DEFAULT_DEATH_WAVE_ORIGIN
## 当前生音符中央判定坐标，单位设计像素。
var _life_note_cue: Vector2 = DEFAULT_LIFE_NOTE_CUE
## 当前死音符中央判定坐标，单位设计像素。
var _death_note_cue: Vector2 = DEFAULT_DEATH_NOTE_CUE
## 当前生音符生成坐标，单位设计像素。
var _life_note_spawn: Vector2 = DEFAULT_LIFE_NOTE_SPAWN
## 当前死音符生成坐标，单位设计像素。
var _death_note_spawn: Vector2 = DEFAULT_DEATH_NOTE_SPAWN
## 当前路径外鼓量，单位设计像素。
var _curve_outer_bend_px: float = DEFAULT_CURVE_OUTER_BEND_PX
## 当前路径中心控制柄长度，单位设计像素。
var _curve_center_handle_px: float = DEFAULT_CURVE_CENTER_HANDLE_PX

## note_id 到音符物理状态的映射；包含路径进度、绑定波和是否已抵达。
var _note_states: Dictionary[String, Dictionary] = {}
## 音符稳定 ID 的确定性遍历顺序，避免直接依赖 Dictionary 顺序。
var _note_ids: Array[String] = []
## wave_id 到实体波状态的映射；包含发射微秒、波源、阵营、强度和绑定目标。
var _waves: Dictionary[String, Dictionary] = {}
## 波稳定 ID 的确定性遍历顺序。
var _wave_ids: Array[String] = []
## 生成唯一 wave_id 的递增序号；reset 时归零以保证 Replay 可复现。
var _launch_serial: int = 0

## 新生成但尚未由上层取走的发波事件。
var _pending_launches: Array[Dictionary] = []
## 已求出接触时刻但尚未由上层取走的波—音符接触事件。
var _pending_contacts: Array[Dictionary] = []
## 未被目标波接触、已抵达钟点且尚未由上层取走的音符事件。
var _pending_arrivals: Array[Dictionary] = []
## 按阵营缓存贝塞尔路径及弧长采样，供确定性位置和接触时间计算复用。
var _motion_profiles: Dictionary[int, Dictionary] = {}
## 到达事件按时间扫描一次；绑定中的音符单独推进，避免每次输入扫描整首歌。
var _arrival_order: Array[String] = []
var _arrival_cursor := 0
var _bound_notes: Dictionary = {}


func configure(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	_compiled = compiled
	_rules = rules
	reset()


func reset() -> void:
	_current_time_us = NEVER_TIME_US
	_launch_serial = 0
	_note_states.clear()
	_note_ids.clear()
	_waves.clear()
	_wave_ids.clear()
	_pending_launches.clear()
	_pending_contacts.clear()
	_pending_arrivals.clear()
	_motion_profiles.clear()
	_arrival_order.clear()
	_arrival_cursor = 0
	_bound_notes.clear()
	_read_rule_contract()

	if _compiled == null:
		return
	for index: int in range(_compiled.notes.size()):
		var note: Dictionary = _compiled.notes[index].duplicate(true)
		var note_id: String = str(note.get("id", note.get("event_id", note.get("unit_id", ""))))
		if note_id.is_empty():
			note_id = "note_%06d" % index
		if _note_states.has(note_id):
			# 正常编译谱已拒绝重复稳定 ID；这里仍给畸形测试数据补一个确定性后缀，
			# 防止后来的音符静默覆盖前一枚。
			note_id = "%s#%06d" % [note_id, index]
		note["id"] = note_id
		var arrival: Dictionary = _build_arrival(note)
		_note_states[note_id] = {
			"note": note,
			"status": &"pending",
			"bound_wave_id": "",
			"contact": {},
			"arrival": arrival,
		}
		_note_ids.append(note_id)
	_note_ids.sort_custom(_sort_note_ids)
	_arrival_order.assign(_note_ids)
	_arrival_order.sort_custom(func(a: String, b: String) -> bool: return int(_note_states[a].arrival.arrival_us) < int(_note_states[b].arrival.arrival_us))


func launch(
		sample: SemanticInputSample,
		valid: bool,
		owner: int,
		bound_note: Dictionary = {}
) -> Dictionary:
	if sample == null or not sample.is_press():
		return {}
	var source_affinity: int = sample.affinity()
	if source_affinity not in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		return {}

	var wave_id: String = "wave:%010d:%d" % [sample.sequence, source_affinity]
	if _waves.has(wave_id):
		wave_id = "%s:%06d" % [wave_id, _launch_serial]
	_launch_serial += 1

	var origin: Vector2 = _origin_for(source_affinity)
	var launch_record: Dictionary = {
		"id": wave_id,
		"wave_id": wave_id,
		"affinity": source_affinity,
		"source_affinity": source_affinity,
		"qualified_affinity": source_affinity if valid else GameplayTypes.Affinity.SU,
		"launch_us": sample.timestamp_us,
		"input_sequence": sample.sequence,
		"owner": owner,
		"valid": valid,
		"strength": 1.0 if valid else INVALID_WAVE_STRENGTH,
		"color_role": _color_role(source_affinity) if valid else &"invalid",
		"origin": origin,
		"speed_px_sec": _wave_speed_px_sec,
		"half_width_px": _wave_front_half_width_px,
		"front_half_width_px": _wave_front_half_width_px,
		"bound_note_id": "",
		"unit_kind": &"",
		"contact_us": -1,
	}

	# 无效灰波只供表现；有效彩波最多绑定一枚仍处于 pending 的同阵营普通音符。
	if valid and not bound_note.is_empty():
		var binding: Dictionary = _try_bind_note(wave_id, sample, bound_note)
		if not binding.is_empty():
			_bound_notes[binding["note_id"]] = true
			launch_record["bound_note_id"] = binding["note_id"]
			launch_record["unit_kind"] = binding["unit_kind"]
			launch_record["contact_us"] = binding["contact_us"]

	_waves[wave_id] = launch_record.duplicate(true)
	_wave_ids.append(wave_id)
	_pending_launches.append(launch_record.duplicate(true))
	return launch_record.duplicate(true)


func advance_to(time_us: int, inclusive: bool = true) -> void:
	if time_us < _current_time_us:
		return
	_current_time_us = time_us

	var due_contacts: Array[Dictionary] = []
	var due_arrivals: Array[Dictionary] = []
	for note_id: String in _bound_notes:
		var state: Dictionary = _note_states[note_id]
		var status: StringName = StringName(state.get("status", &"pending"))
		if status == &"bound":
			var contact: Dictionary = state.get("contact", {})
			if _is_due(int(contact.get("contact_us", NEVER_TIME_US)), time_us, inclusive):
				due_contacts.append(contact.duplicate(true))
	while _arrival_cursor < _arrival_order.size():
		var state: Dictionary = _note_states[_arrival_order[_arrival_cursor]]
		var arrival: Dictionary = state["arrival"]
		if not _is_due(int(arrival["arrival_us"]), time_us, inclusive): break
		_arrival_cursor += 1
		if state["status"] == &"pending": due_arrivals.append(arrival.duplicate(true))

	due_contacts.sort_custom(_sort_contacts)
	due_arrivals.sort_custom(_sort_arrivals)

	for contact: Dictionary in due_contacts:
		var note_id: String = str(contact.get("note_id", ""))
		if not _note_states.has(note_id):
			continue
		var state: Dictionary = _note_states[note_id]
		if StringName(state.get("status", &"")) != &"bound":
			continue
		if str(state.get("bound_wave_id", "")) != str(contact.get("wave_id", "")):
			continue
		state["status"] = &"contacted"
		_bound_notes.erase(note_id)
		_pending_contacts.append(contact.duplicate(true))

	for arrival: Dictionary in due_arrivals:
		var note_id: String = str(arrival.get("note_id", ""))
		if not _note_states.has(note_id):
			continue
		var state: Dictionary = _note_states[note_id]
		if StringName(state.get("status", &"")) != &"pending":
			continue
		state["status"] = &"arrived"
		_pending_arrivals.append(arrival.duplicate(true))


func drain_launches() -> Array[Dictionary]:
	_pending_launches.sort_custom(_sort_launches)
	var result: Array[Dictionary] = []
	for launch_record: Dictionary in _pending_launches:
		result.append(launch_record.duplicate(true))
	_pending_launches.clear()
	return result


func drain_contacts() -> Array[Dictionary]:
	_pending_contacts.sort_custom(_sort_contacts)
	var result: Array[Dictionary] = []
	for contact: Dictionary in _pending_contacts:
		result.append(contact.duplicate(true))
	_pending_contacts.clear()
	return result


func drain_arrivals() -> Array[Dictionary]:
	_pending_arrivals.sort_custom(_sort_arrivals)
	var result: Array[Dictionary] = []
	for arrival: Dictionary in _pending_arrivals:
		result.append(arrival.duplicate(true))
	_pending_arrivals.clear()
	return result


func snapshot() -> Dictionary:
	var wave_records: Array[Dictionary] = []
	for wave_id: String in _wave_ids:
		if _waves.has(wave_id):
			wave_records.append((_waves[wave_id] as Dictionary).duplicate(true))
	wave_records.sort_custom(_sort_launches)

	var note_records: Array[Dictionary] = []
	var status_counts: Dictionary = {
		"pending": 0,
		"bound": 0,
		"contacted": 0,
		"arrived": 0,
	}
	for note_id: String in _note_ids:
		var state: Dictionary = _note_states[note_id]
		var note: Dictionary = state["note"]
		var status: StringName = StringName(state.get("status", &"pending"))
		var status_key: String = String(status)
		status_counts[status_key] = int(status_counts.get(status_key, 0)) + 1
		note_records.append({
			"note_id": note_id,
			"affinity": int(note.get("affinity", GameplayTypes.Affinity.SU)),
			"unit_kind": StringName(note.get("unit_kind", &"tap")),
			"status": status,
			"bound_wave_id": str(state.get("bound_wave_id", "")),
			"contact_us": int((state.get("contact", {}) as Dictionary).get("contact_us", -1)),
			"arrival_us": int((state.get("arrival", {}) as Dictionary).get("arrival_us", -1)),
		})

	return {
		"time_us": _current_time_us,
		"wave_count": wave_records.size(),
		"waves": wave_records,
		"notes": note_records,
		"status_counts": status_counts,
		"queued_launch_count": _pending_launches.size(),
		"queued_contact_count": _pending_contacts.size(),
		"queued_arrival_count": _pending_arrivals.size(),
	}


func wave_count() -> int:
	# 这是每帧可用的轻量查询；完整 snapshot() 面向诊断，不应在渲染循环里反复重建。
	return _waves.size()


func force_finish() -> void:
	var last_event_us: int = NEVER_TIME_US
	for note_id: String in _note_ids:
		var state: Dictionary = _note_states[note_id]
		var status: StringName = StringName(state.get("status", &"pending"))
		if status == &"bound":
			last_event_us = maxi(last_event_us, int((state.get("contact", {}) as Dictionary).get("contact_us", NEVER_TIME_US)))
		elif status == &"pending":
			last_event_us = maxi(last_event_us, int((state.get("arrival", {}) as Dictionary).get("arrival_us", NEVER_TIME_US)))
	if last_event_us == NEVER_TIME_US:
		return
	var target_us: int = last_event_us
	if _current_time_us != NEVER_TIME_US:
		target_us = maxi(target_us, _current_time_us)
	advance_to(target_us, true)


func _try_bind_note(
		wave_id: String,
		sample: SemanticInputSample,
		bound_note: Dictionary
) -> Dictionary:
	var note_id: String = str(bound_note.get("id", bound_note.get("event_id", bound_note.get("unit_id", ""))))
	if note_id.is_empty() or not _note_states.has(note_id):
		return {}
	var state: Dictionary = _note_states[note_id]
	if StringName(state.get("status", &"pending")) != &"pending":
		return {}
	var note: Dictionary = state["note"]
	var affinity: int = int(note.get("affinity", GameplayTypes.Affinity.SU))
	if affinity != sample.affinity():
		return {}
	if bound_note.has("affinity") and int(bound_note["affinity"]) != affinity:
		return {}

	var cue_us: int = int(note.get("start_us", note.get("start_time_us", note.get("time_us", 0))))
	var profile: Dictionary = _motion_profile(affinity)
	var distance_px: float = float(profile["cue_distance_px"])
	var note_speed_px_sec: float = float(profile["note_speed_px_sec"])
	var speed_sum: float = _wave_speed_px_sec + note_speed_px_sec
	if distance_px < 0.0 or note_speed_px_sec <= 0.0 or speed_sum <= 0.0:
		return {}

	# 波前半径 r = wave_speed × (t - launch)；音符距波源的剩余距离
	# = D - note_speed × (t - cue)。令两者相等即可直接求第一次连续接触，
	# 不必读取任何渲染位置。
	var numerator: float = (
		distance_px * USEC_PER_SEC
		+ _wave_speed_px_sec * float(sample.timestamp_us)
		+ note_speed_px_sec * float(cue_us)
	)
	var contact_us: int = roundi(numerator / speed_sum)
	var arrival_us: int = int((state.get("arrival", {}) as Dictionary).get("arrival_us", NEVER_TIME_US))
	if contact_us < sample.timestamp_us or contact_us > arrival_us:
		return {}
	if _current_time_us != NEVER_TIME_US and contact_us < _current_time_us:
		return {}

	var cue: Vector2 = profile["cue"]
	var origin: Vector2 = profile["origin"]
	var direction: Vector2 = (origin - cue).normalized()
	var elapsed_from_cue_sec: float = float(contact_us - cue_us) / USEC_PER_SEC
	var travel_px: float = note_speed_px_sec * elapsed_from_cue_sec
	# 合法输入通常让接触发生在中心提示点与波源之间；下界钳制也让刻意构造的
	# 超早测试数据仍停留在约定的接近方向上。
	var approach_distance_px: float = float(profile["approach_distance_px"])
	travel_px = clampf(travel_px, -approach_distance_px, distance_px)
	var contact_position: Vector2 = cue + direction * travel_px
	var unit_kind: StringName = StringName(note.get("unit_kind", bound_note.get("unit_kind", &"tap")))
	var contact: Dictionary = {
		"wave_id": wave_id,
		"note_id": note_id,
		"affinity": affinity,
		"contact_us": contact_us,
		"position": contact_position,
		"unit_kind": unit_kind,
		"launch_us": sample.timestamp_us,
		"cue_us": cue_us,
		"launch_error_us": sample.timestamp_us - cue_us,
		"input_grade": int(bound_note.get("input_grade", -1)),
		"input_sequence": sample.sequence,
	}
	state["status"] = &"bound"
	state["bound_wave_id"] = wave_id
	state["contact"] = contact
	return contact.duplicate(true)


func _build_arrival(note: Dictionary) -> Dictionary:
	var affinity: int = int(note.get("affinity", GameplayTypes.Affinity.SU))
	var cue_us: int = int(note.get("start_us", note.get("start_time_us", note.get("time_us", 0))))
	var profile: Dictionary = _motion_profile(affinity)
	var note_speed_px_sec: float = maxf(float(profile["note_speed_px_sec"]), 0.001)
	var travel_us: int = roundi(float(profile["cue_distance_px"]) * USEC_PER_SEC / note_speed_px_sec)
	return {
		"note_id": str(note.get("id", note.get("event_id", note.get("unit_id", "")))),
		"affinity": affinity,
		"arrival_us": cue_us + maxi(travel_us, 0),
		"position": profile["origin"],
		"unit_kind": StringName(note.get("unit_kind", &"tap")),
		"cue_us": cue_us,
	}


func _motion_profile(affinity: int) -> Dictionary:
	if _motion_profiles.has(affinity):
		return _motion_profiles[affinity]
	var origin: Vector2 = _origin_for(affinity)
	var cue: Vector2 = _cue_for(affinity)
	var spawn: Vector2 = _spawn_for(affinity)
	var approach_path: Dictionary = NoteApproachPath.build_profile(
		spawn,
		cue,
		origin,
		_curve_outer_bend_px,
		_curve_center_handle_px
	)
	var approach_distance_px: float = NoteApproachPath.length(approach_path)
	var note_speed_px_sec: float = approach_distance_px / maxf(_approach_duration_sec, 0.001)
	if note_speed_px_sec <= 0.0:
		note_speed_px_sec = _wave_speed_px_sec
	var profile: Dictionary = {
		"origin": origin,
		"cue": cue,
		"spawn": spawn,
		"cue_distance_px": cue.distance_to(origin),
		"approach_distance_px": approach_distance_px,
		"note_speed_px_sec": note_speed_px_sec,
	}
	_motion_profiles[affinity] = profile
	return profile


func _read_rule_contract() -> void:
	_wave_speed_px_sec = maxf(_rule_float(&"wave_speed_px_sec", DEFAULT_WAVE_SPEED_PX_SEC), 0.001)
	_wave_front_half_width_px = maxf(_rule_float(&"wave_front_half_width_px", DEFAULT_WAVE_FRONT_HALF_WIDTH_PX), 0.0)
	_approach_duration_sec = maxf(_rule_float(&"approach_duration_sec", DEFAULT_APPROACH_DURATION_SEC), 0.001)
	_life_wave_origin = _rule_vector(&"life_wave_origin", DEFAULT_LIFE_WAVE_ORIGIN)
	_death_wave_origin = _rule_vector(&"death_wave_origin", DEFAULT_DEATH_WAVE_ORIGIN)
	_life_note_cue = _rule_vector(&"life_note_cue", DEFAULT_LIFE_NOTE_CUE)
	_death_note_cue = _rule_vector(&"death_note_cue", DEFAULT_DEATH_NOTE_CUE)
	_life_note_spawn = _rule_vector(&"life_note_spawn", DEFAULT_LIFE_NOTE_SPAWN)
	_death_note_spawn = _rule_vector(&"death_note_spawn", DEFAULT_DEATH_NOTE_SPAWN)
	_curve_outer_bend_px = maxf(_rule_float(&"note_curve_outer_bend_px", DEFAULT_CURVE_OUTER_BEND_PX), 0.0)
	_curve_center_handle_px = maxf(_rule_float(&"note_curve_center_handle_px", DEFAULT_CURVE_CENTER_HANDLE_PX), 0.0)


func _rule_float(property_name: StringName, fallback: float) -> float:
	var value: Variant = _rule_property(property_name, fallback)
	return float(value) if value is float or value is int else fallback


func _rule_vector(property_name: StringName, fallback: Vector2) -> Vector2:
	var value: Variant = _rule_property(property_name, fallback)
	return value if value is Vector2 else fallback


func _rule_property(property_name: StringName, fallback: Variant) -> Variant:
	if _rules == null:
		return fallback
	for property_data: Dictionary in _rules.get_property_list():
		if StringName(property_data.get("name", &"")) == property_name:
			return _rules.get(property_name)
	return fallback


func _origin_for(affinity: int) -> Vector2:
	return _death_wave_origin if affinity == GameplayTypes.Affinity.XUAN else _life_wave_origin


func _cue_for(affinity: int) -> Vector2:
	return _death_note_cue if affinity == GameplayTypes.Affinity.XUAN else _life_note_cue


func _spawn_for(affinity: int) -> Vector2:
	return _death_note_spawn if affinity == GameplayTypes.Affinity.XUAN else _life_note_spawn


func _color_role(affinity: int) -> StringName:
	return &"death" if affinity == GameplayTypes.Affinity.XUAN else &"life"


func _is_due(event_us: int, target_us: int, inclusive: bool) -> bool:
	return event_us < target_us or (inclusive and event_us == target_us)


func _sort_note_ids(a: String, b: String) -> bool:
	var a_note: Dictionary = _note_states[a]["note"]
	var b_note: Dictionary = _note_states[b]["note"]
	var a_time: int = int(a_note.get("start_us", a_note.get("time_us", 0)))
	var b_time: int = int(b_note.get("start_us", b_note.get("time_us", 0)))
	if a_time != b_time:
		return a_time < b_time
	return a < b


func _sort_launches(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("launch_us", 0)) != int(b.get("launch_us", 0)):
		return int(a.get("launch_us", 0)) < int(b.get("launch_us", 0))
	if int(a.get("input_sequence", 0)) != int(b.get("input_sequence", 0)):
		return int(a.get("input_sequence", 0)) < int(b.get("input_sequence", 0))
	return str(a.get("wave_id", "")) < str(b.get("wave_id", ""))


func _sort_contacts(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("contact_us", 0)) != int(b.get("contact_us", 0)):
		return int(a.get("contact_us", 0)) < int(b.get("contact_us", 0))
	if int(a.get("input_sequence", 0)) != int(b.get("input_sequence", 0)):
		return int(a.get("input_sequence", 0)) < int(b.get("input_sequence", 0))
	if str(a.get("wave_id", "")) != str(b.get("wave_id", "")):
		return str(a.get("wave_id", "")) < str(b.get("wave_id", ""))
	return str(a.get("note_id", "")) < str(b.get("note_id", ""))


func _sort_arrivals(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("arrival_us", 0)) != int(b.get("arrival_us", 0)):
		return int(a.get("arrival_us", 0)) < int(b.get("arrival_us", 0))
	if int(a.get("affinity", GameplayTypes.Affinity.SU)) != int(b.get("affinity", GameplayTypes.Affinity.SU)):
		return int(a.get("affinity", GameplayTypes.Affinity.SU)) < int(b.get("affinity", GameplayTypes.Affinity.SU))
	return str(a.get("note_id", "")) < str(b.get("note_id", ""))
