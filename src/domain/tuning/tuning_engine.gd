class_name TuningEngine
extends RefCounted

## 双钟独立调频滑条的确定性判定器。
##
## 调频段只决定“什么时候允许改变频率”；滑条是连续跟随判定，不负责开启波源。
## 玩家可以提前按住钟，开始后直接跟随引导，也不需要在尾点松键。

const NEVER_TIME_US: int = -9_000_000_000_000_000
const USEC_PER_SEC: float = 1_000_000.0
## Replay 的双路输入会量化为 Q15；连续位移累加后可能留下万分位误差。
## 这里只放宽边界比较，不钳制玩家位置，以免越过滑条端点也被误算为命中。
const TRACKING_EPSILON: float = 0.001

var _compiled: CompiledChart
var _rules: GameplayRuleSet
var _slider_states: Array[Dictionary] = []
var _group_members: Dictionary[String, Array] = {}
var _group_grades: Dictionary[String, int] = {}
var _pending_records: Array[JudgmentRecord] = []
var _pending_frequency_changes: Array[Dictionary] = []
var _timeline_events: Array[Dictionary] = []
var _timeline_cursor: int = 0
var _active_field_ids: Dictionary[String, bool] = {}

var _current_time_us: int = NEVER_TIME_US
var _motion_time_us: int = NEVER_TIME_US
## x 为生钟、y 为死钟的摇杆速度意图，两个分量各自保持 -1～1。
var _rate_vector: Vector2 = Vector2.ZERO
## 两口钟在统一频率轴上的归一化位置，0 为最低频、1 为最高频。
var _life_value: float = 0.5
var _death_value: float = 0.5
var _last_life_held: bool = false
var _last_death_held: bool = false
var _paused_for_rearm: bool = false


func configure(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	_compiled = compiled
	_rules = rules
	_slider_states.clear()
	_group_members.clear()
	_group_grades.clear()
	_pending_records.clear()
	_pending_frequency_changes.clear()
	_timeline_events.clear()
	_active_field_ids.clear()
	_timeline_cursor = 0
	_current_time_us = NEVER_TIME_US
	_motion_time_us = NEVER_TIME_US
	_rate_vector = Vector2.ZERO
	_last_life_held = false
	_last_death_held = false
	_paused_for_rearm = false
	_reset_values_to_base()

	if _compiled == null:
		return
	_build_field_timeline()
	_build_slider_states()
	_timeline_events.sort_custom(_sort_timeline_events)


func reset(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	configure(compiled, rules)


func can_consume(sample: SemanticInputSample) -> bool:
	if sample == null:
		return false
	return sample.kind in [
		GameplayTypes.SemanticInputKind.TUNING_RATE_CHANGED,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
	]


func handle_input(sample: SemanticInputSample, life_held: bool, death_held: bool) -> bool:
	if sample == null or not can_consume(sample):
		return false
	_last_life_held = life_held
	_last_death_held = death_held
	_integrate_values_to(sample.timestamp_us, life_held, death_held)
	if not field_active():
		_rate_vector = Vector2.ZERO
		return false

	if sample.kind == GameplayTypes.SemanticInputKind.TUNING_RATE_CHANGED:
		_rate_vector = Vector2(
			clampf(sample.tune_vector.x, -1.0, 1.0) if life_held else 0.0,
			clampf(sample.tune_vector.y, -1.0, 1.0) if death_held else 0.0
		)
	else:
		# 位移已经由设备适配层换算成“整条频率轴的归一化增量”。
		if life_held:
			_life_value = clampf(_life_value + sample.tune_vector.x, 0.0, 1.0)
		if death_held:
			_death_value = clampf(_death_value + sample.tune_vector.y, 0.0, 1.0)
		_queue_frequency_change(sample.timestamp_us)
	return true


func advance_to(time_us: int, inclusive: bool = true, life_held: bool = false, death_held: bool = false) -> void:
	if time_us < _current_time_us:
		return
	_last_life_held = life_held
	_last_death_held = death_held
	if _paused_for_rearm:
		_current_time_us = time_us
		_motion_time_us = time_us
		return

	while _timeline_cursor < _timeline_events.size():
		var event: Dictionary = _timeline_events[_timeline_cursor]
		var event_us: int = int(event["time_us"])
		if event_us > time_us or (event_us == time_us and not inclusive):
			break
		_integrate_values_to(event_us, life_held, death_held)
		_process_timeline_event(event, life_held, death_held)
		_timeline_cursor += 1
	_integrate_values_to(time_us, life_held, death_held)
	_current_time_us = time_us


func cancel_active(time_us: int) -> void:
	_integrate_values_to(time_us, _last_life_held, _last_death_held)
	_rate_vector = Vector2.ZERO
	_last_life_held = false
	_last_death_held = false


func is_active() -> bool:
	return field_active()


func field_active() -> bool:
	return not _active_field_ids.is_empty()


func active_field_id() -> String:
	var ids: Array = _active_field_ids.keys()
	ids.sort()
	return str(ids[0]) if not ids.is_empty() else ""


func begin_pause_rearm() -> Dictionary:
	_paused_for_rearm = true
	_rate_vector = Vector2.ZERO
	return {
		"tuning_required": field_active(),
		"life_required": field_active() and _last_life_held,
		"death_required": field_active() and _last_death_held,
	}


func apply_resume_rearm(rearm_state: Dictionary) -> void:
	_paused_for_rearm = false
	_last_life_held = bool(rearm_state.get("life_held", false))
	_last_death_held = bool(rearm_state.get("death_held", false))
	_rate_vector = Vector2.ZERO


func life_tuning_value() -> float:
	return _life_value


func death_tuning_value() -> float:
	return _death_value


func life_frequency_hz() -> float:
	return _value_to_frequency(_life_value)


func death_frequency_hz() -> float:
	return _value_to_frequency(_death_value)


func active_slider_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for state: Dictionary in _slider_states:
		var slider: Dictionary = state["slider"]
		if _current_time_us < int(slider["start_us"]) or _current_time_us > int(slider["end_us"]):
			continue
		var guide_progress: float = _guide_progress(slider, _current_time_us)
		var band: Vector2 = _guide_band(slider, _current_time_us)
		var player_value: float = _value_for_affinity(int(slider["affinity"]))
		var player_progress: float = _value_to_slider_progress(slider, player_value)
		var total: int = int(state["sample_total"])
		var valid: int = int(state["sample_valid"])
		var snapshot: Dictionary = slider.duplicate(true)
		snapshot["guide_progress"] = guide_progress
		snapshot["guide_value"] = lerpf(float(slider["start_value"]), float(slider["end_value"]), guide_progress)
		snapshot["guide_band_min"] = band.x
		snapshot["guide_band_max"] = band.y
		snapshot["player_progress"] = player_progress
		snapshot["player_value"] = player_value
		snapshot["coverage"] = 1.0 if total == 0 else float(valid) / float(total)
		snapshot["held"] = _last_life_held if int(slider["affinity"]) == GameplayTypes.Affinity.ZHU else _last_death_held
		result.append(snapshot)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["affinity"]) != int(b["affinity"]):
			return int(a["affinity"]) < int(b["affinity"])
		return str(a["event_id"]) < str(b["event_id"])
	)
	return result


func group_grade(group_id: String) -> int:
	return int(_group_grades.get(group_id, GameplayTypes.JudgmentGrade.MISS))


func has_finalized_group(group_id: String) -> bool:
	return _group_grades.has(group_id)


func drain_judgments() -> Array[JudgmentRecord]:
	var result: Array[JudgmentRecord] = _pending_records.duplicate()
	_pending_records.clear()
	return result


func drain_frequency_changes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for change: Dictionary in _pending_frequency_changes:
		result.append(change.duplicate(true))
	_pending_frequency_changes.clear()
	return result


## 调频滑条不接管敲击瞬态；空窗敲击保持灰波，载波仍使用本钟颜色。
func last_press_qualified() -> bool:
	return false


func _build_field_timeline() -> void:
	var step: int = maxi(1, _rule_int(&"tuning_sample_interval_ticks", 30))
	for field: Dictionary in _compiled.tuning_fields:
		var field_id: String = str(field.get("event_id", field.get("id", "")))
		# 同 tick 相邻场域的顺序必须是：旧滑条尾点 → 旧场退出 → 新场进入 → 新滑条起点。
		# 因此 enter 排在 exit 之后，确保新场即使无时间间隔也会重新回到统一基频。
		_timeline_events.append({"time_us": int(field["start_us"]), "priority": 4, "kind": &"field_enter", "field_id": field_id})
		var tick: int = int(field["tick"])
		var end_tick: int = int(field["end_tick"])
		while tick <= end_tick:
			_timeline_events.append({
				"time_us": _compiled.tempo_map.tick_to_us(tick),
				"priority": 2,
				"kind": &"frequency_sample",
				"field_id": field_id,
				"tick": tick,
			})
			tick += step
		_timeline_events.append({"time_us": int(field["end_us"]), "priority": 3, "kind": &"field_exit", "field_id": field_id})


func _build_slider_states() -> void:
	var step: int = maxi(1, _rule_int(&"tuning_sample_interval_ticks", 30))
	for index: int in range(_compiled.tuning_sliders.size()):
		var slider: Dictionary = _compiled.tuning_sliders[index].duplicate(true)
		var event_id: String = str(slider.get("event_id", slider.get("id", "slider_%06d" % index)))
		var group_key: String = str(slider.get("group_id", ""))
		if group_key.is_empty():
			group_key = event_id
		var state: Dictionary = {
			"slider": slider,
			"event_id": event_id,
			"group_key": group_key,
			"sample_total": 0,
			"sample_valid": 0,
			"coverage": 0.0,
			"grade": GameplayTypes.JudgmentGrade.MISS,
			"finished": false,
		}
		_slider_states.append(state)
		if not _group_members.has(group_key):
			_group_members[group_key] = []
		_group_members[group_key].append(index)

		var start_tick: int = int(slider["tick"])
		var tick: int = start_tick
		var end_tick: int = int(slider["end_tick"])
		# 固定步长只生成严格早于尾点的样本，最后再显式补一次精确 end_tick。
		# 这样非 30 tick 整数倍不会漏尾，刚好整除时也不会重复；极短滑条仍有头尾两点。
		while tick < end_tick:
			_timeline_events.append({
				"time_us": _compiled.tempo_map.tick_to_us(tick),
				# 起点需排在 field_enter 后；其余样本（含旧滑条尾点）在场域边界前完成。
				"priority": 5 if tick == start_tick else 1,
				"kind": &"slider_sample",
				"state_index": index,
				"tick": tick,
				"event_id": event_id,
			})
			tick += step
		_timeline_events.append({
			"time_us": _compiled.tempo_map.tick_to_us(end_tick),
			"priority": 1,
			"kind": &"slider_sample",
			"state_index": index,
			"tick": end_tick,
			"event_id": event_id,
		})
		_timeline_events.append({
			"time_us": int(slider["end_us"]),
			"priority": 2,
			"kind": &"slider_finish",
			"state_index": index,
			"event_id": event_id,
		})


func _process_timeline_event(event: Dictionary, life_held: bool, death_held: bool) -> void:
	match StringName(event["kind"]):
		&"field_enter":
			var was_empty: bool = _active_field_ids.is_empty()
			_active_field_ids[str(event["field_id"])] = true
			if was_empty:
				_reset_values_to_base()
				_rate_vector = Vector2.ZERO
				_queue_frequency_change(int(event["time_us"]))
		&"field_exit":
			_active_field_ids.erase(str(event["field_id"]))
			if _active_field_ids.is_empty():
				_reset_values_to_base()
				_rate_vector = Vector2.ZERO
				_queue_frequency_change(int(event["time_us"]))
		&"slider_sample":
			_process_slider_sample(int(event["state_index"]), int(event["time_us"]), life_held, death_held)
		&"frequency_sample":
			if field_active():
				_queue_frequency_change(int(event["time_us"]))
		&"slider_finish":
			_finish_slider(int(event["state_index"]), int(event["time_us"]))


func _process_slider_sample(state_index: int, sample_us: int, life_held: bool, death_held: bool) -> void:
	if state_index < 0 or state_index >= _slider_states.size():
		return
	var state: Dictionary = _slider_states[state_index]
	if bool(state["finished"]):
		return
	var slider: Dictionary = state["slider"]
	var affinity: int = int(slider["affinity"])
	var held: bool = life_held if affinity == GameplayTypes.Affinity.ZHU else death_held
	var player_value: float = _value_for_affinity(affinity)
	var player_progress: float = _value_to_slider_progress(slider, player_value)
	var band: Vector2 = _guide_band(slider, sample_us)
	state["sample_total"] = int(state["sample_total"]) + 1
	if (
		held
		and player_progress >= band.x - TRACKING_EPSILON
		and player_progress <= band.y + TRACKING_EPSILON
	):
		state["sample_valid"] = int(state["sample_valid"]) + 1


func _finish_slider(state_index: int, finalized_at_us: int) -> void:
	if state_index < 0 or state_index >= _slider_states.size():
		return
	var state: Dictionary = _slider_states[state_index]
	if bool(state["finished"]):
		return
	var total: int = int(state["sample_total"])
	var valid: int = int(state["sample_valid"])
	var coverage: float = 0.0 if total <= 0 else float(valid) / float(total)
	state["coverage"] = coverage
	state["grade"] = _grade_coverage(coverage)
	state["finished"] = true
	_try_finalize_group(str(state["group_key"]), finalized_at_us)


func _try_finalize_group(group_key: String, finalized_at_us: int) -> void:
	var members: Array = _group_members.get(group_key, [])
	if members.is_empty():
		return
	for raw_index: Variant in members:
		if not bool(_slider_states[int(raw_index)]["finished"]):
			return

	var record := JudgmentRecord.new()
	record.unit_id = group_key
	record.unit_kind = &"tuning"
	record.group_id = group_key if members.size() > 1 else ""
	record.damage_group_id = group_key
	record.affinity = GameplayTypes.Affinity.SU
	record.start_tick = 9_223_372_036_854_775_807
	record.end_tick = 0
	record.finalized_at_us = finalized_at_us
	var side_data: Dictionary = {}
	for raw_index: Variant in members:
		var state: Dictionary = _slider_states[int(raw_index)]
		var slider: Dictionary = state["slider"]
		var affinity: int = int(slider["affinity"])
		if members.size() == 1:
			record.affinity = affinity
		record.start_tick = mini(record.start_tick, int(slider["tick"]))
		record.end_tick = maxi(record.end_tick, int(slider["end_tick"]))
		var component_kind: StringName = &"life_coverage" if affinity == GameplayTypes.Affinity.ZHU else &"death_coverage"
		var component := JudgmentComponentRecord.value_error(
			component_kind,
			int(slider["tick"]),
			int(slider["start_us"]),
			1.0 - float(state["coverage"]),
			int(state["grade"])
		)
		component.metadata = {
			"event_id": str(state["event_id"]),
			"valid_samples": int(state["sample_valid"]),
			"total_samples": int(state["sample_total"]),
			"coverage": float(state["coverage"]),
		}
		record.components.append(component)
		side_data["life" if affinity == GameplayTypes.Affinity.ZHU else "death"] = component.metadata.duplicate(true)
	record.metadata = {"sides": side_data}
	record.recompute_grade()
	_group_grades[group_key] = record.grade
	_pending_records.append(record)


func _integrate_values_to(time_us: int, life_held: bool, death_held: bool) -> void:
	if _motion_time_us == NEVER_TIME_US:
		_motion_time_us = time_us
		return
	if time_us <= _motion_time_us:
		return
	if field_active():
		var delta_sec: float = float(time_us - _motion_time_us) / USEC_PER_SEC
		var normalized_speed: float = _normalized_cursor_speed_per_sec()
		if life_held:
			_life_value = clampf(_life_value + _rate_vector.x * normalized_speed * delta_sec, 0.0, 1.0)
		if death_held:
			_death_value = clampf(_death_value + _rate_vector.y * normalized_speed * delta_sec, 0.0, 1.0)
	_motion_time_us = time_us


func _guide_progress(slider: Dictionary, time_us: int) -> float:
	var start_tick: int = int(slider["tick"])
	var traversal_ticks: int = maxi(1, int(slider["traversal_ticks"]))
	var traversal_count: int = maxi(1, int(slider["traversal_count"]))
	var total_ticks: int = traversal_ticks * traversal_count
	var current_tick: int = clampi(_compiled.tempo_map.us_to_tick_rounded(time_us), start_tick, start_tick + total_ticks)
	var elapsed: int = current_tick - start_tick
	if elapsed >= total_ticks:
		return 1.0 if traversal_count % 2 == 1 else 0.0
	var leg: int = elapsed / traversal_ticks
	var within: float = float(elapsed % traversal_ticks) / float(traversal_ticks)
	return within if leg % 2 == 0 else 1.0 - within


func _guide_band(slider: Dictionary, time_us: int) -> Vector2:
	var window_us: int = _rule_int(&"tuning_guide_time_window_ms", 180) * 1000
	var lower_us: int = maxi(int(slider["start_us"]), time_us - window_us)
	var upper_us: int = mini(int(slider["end_us"]), time_us + window_us)
	var values: Array[float] = [
		_guide_progress(slider, lower_us),
		_guide_progress(slider, time_us),
		_guide_progress(slider, upper_us),
	]
	var traversal_ticks: int = maxi(1, int(slider["traversal_ticks"]))
	var first_boundary: int = int(slider["tick"]) + traversal_ticks
	var end_tick: int = int(slider["end_tick"])
	var lower_tick: int = _compiled.tempo_map.us_to_tick_rounded(lower_us)
	var upper_tick: int = _compiled.tempo_map.us_to_tick_rounded(upper_us)
	var boundary_tick: int = first_boundary
	while boundary_tick < end_tick:
		if boundary_tick >= lower_tick and boundary_tick <= upper_tick:
			values.append(_guide_progress(slider, _compiled.tempo_map.tick_to_us(boundary_tick)))
		boundary_tick += traversal_ticks
	var margin: float = _rule_float(&"tuning_spatial_margin", 0.08)
	var minimum: float = values[0]
	var maximum: float = values[0]
	for value: float in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return Vector2(clampf(minimum - margin, 0.0, 1.0), clampf(maximum + margin, 0.0, 1.0))


func _value_to_slider_progress(slider: Dictionary, value: float) -> float:
	var start_value: float = float(slider["start_value"])
	var end_value: float = float(slider["end_value"])
	var span: float = end_value - start_value
	if absf(span) <= 0.000001:
		return 0.0
	return (value - start_value) / span


func _value_for_affinity(affinity: int) -> float:
	return _life_value if affinity == GameplayTypes.Affinity.ZHU else _death_value


func _value_to_frequency(value: float) -> float:
	return lerpf(
		_rule_float(&"tuning_min_frequency_hz", 1.8),
		_rule_float(&"tuning_max_frequency_hz", 6.9),
		clampf(value, 0.0, 1.0)
	)


func _base_value() -> float:
	var minimum: float = _rule_float(&"tuning_min_frequency_hz", 1.8)
	var maximum: float = _rule_float(&"tuning_max_frequency_hz", 6.9)
	var base: float = _rule_float(&"tuning_base_frequency_hz", 4.35)
	return clampf(inverse_lerp(minimum, maximum, base), 0.0, 1.0)


func _reset_values_to_base() -> void:
	_life_value = _base_value()
	_death_value = _base_value()


func _normalized_cursor_speed_per_sec() -> float:
	var range_hz: float = maxf(
		_rule_float(&"tuning_max_frequency_hz", 6.9) - _rule_float(&"tuning_min_frequency_hz", 1.8),
		0.001
	)
	var axis_length_px: float = range_hz * maxf(_rule_float(&"tuning_pixels_per_hz", 160.0), 0.001)
	return _rule_float(&"tuning_cursor_speed_px_sec", 720.0) / axis_length_px


func _queue_frequency_change(time_us: int) -> void:
	var change: Dictionary = {
		"time_us": time_us,
		"life_value": _life_value,
		"death_value": _death_value,
		"life_frequency_hz": life_frequency_hz(),
		"death_frequency_hz": death_frequency_hz(),
	}
	if not _pending_frequency_changes.is_empty() and int(_pending_frequency_changes[-1]["time_us"]) == time_us:
		_pending_frequency_changes[-1] = change
	else:
		_pending_frequency_changes.append(change)


func _grade_coverage(coverage: float) -> int:
	if coverage >= _rule_float(&"tuning_perfect_coverage", 0.90):
		return GameplayTypes.JudgmentGrade.PERFECT
	if coverage >= _rule_float(&"tuning_good_coverage", 0.75):
		return GameplayTypes.JudgmentGrade.GOOD
	if coverage >= _rule_float(&"tuning_pass_coverage", 0.60):
		return GameplayTypes.JudgmentGrade.PASS
	return GameplayTypes.JudgmentGrade.MISS


func _sort_timeline_events(a: Dictionary, b: Dictionary) -> bool:
	if int(a["time_us"]) != int(b["time_us"]):
		return int(a["time_us"]) < int(b["time_us"])
	if int(a["priority"]) != int(b["priority"]):
		return int(a["priority"]) < int(b["priority"])
	return str(a.get("event_id", a.get("field_id", ""))) < str(b.get("event_id", b.get("field_id", "")))


func _rule_int(property_name: StringName, fallback: int) -> int:
	var value: Variant = _rule_property(property_name, fallback)
	return int(value) if value is int or value is float else fallback


func _rule_float(property_name: StringName, fallback: float) -> float:
	var value: Variant = _rule_property(property_name, fallback)
	return float(value) if value is float or value is int else fallback


func _rule_property(property_name: StringName, fallback: Variant) -> Variant:
	if _rules == null:
		return fallback
	for property_data: Dictionary in _rules.get_property_list():
		if StringName(property_data.get("name", &"")) == property_name:
			return _rules.get(property_name)
	return fallback
