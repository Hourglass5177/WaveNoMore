class_name NoteJudgeEngine
extends RefCounted

## Tap 与 Hold 的确定性判定器。Hold 只判头部和持续过程，到达尾点自动完成；
## 不生成画面；命中的普通音符会把稳定绑定信息交给物理波纹层。

## 本局判定规则；读取头部时间窗与 Hold 断持宽限。
var _rules: GameplayRuleSet
## 每个编译音符的运行时状态，按 start_us、类型和稳定 ID 排序。
var _states: Array[Dictionary] = []
## 已完成但尚未由 GameplaySimulation 取走的判定记录。
var _pending_records: Array[JudgmentRecord] = []
## 暂停重臂期间为 true；阻止恢复瞬间把旧物理按住状态当成有效续按。
var _paused_for_rearm: bool = false
## 最近推进到的歌曲时间，单位微秒；极小值表示尚未开始。
var _current_time_us: int = -9_000_000_000_000_000
## 最近一次成功按下所绑定音符的只读快照；空字典表示未命中普通音符。
var _last_press_binding: Dictionary = {}


func configure(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	_rules = rules
	_states.clear()
	for note in compiled.notes:
		_states.append({
			"note": note.duplicate(true),
			"status": &"pending",
			"components": [] as Array[JudgmentComponentRecord],
			"held": false,
			"gap_started_us": -1,
			"sustain_degraded": false,
		})
	_pending_records.clear()
	_last_press_binding.clear()
	_current_time_us = -9_000_000_000_000_000
	_paused_for_rearm = false


func reset(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	configure(compiled, rules)


func advance_to(time_us: int, inclusive: bool = true) -> void:
	if time_us < _current_time_us:
		return
	_current_time_us = time_us
	if _paused_for_rearm:
		return
	for state in _states:
		var note: Dictionary = state["note"]
		if state["status"] == &"pending":
			var head_deadline: int = int(note["start_us"]) + _rules.miss_window_ms * 1000
			if time_us > head_deadline:
				var component := JudgmentComponentRecord.timing(
					&"head" if note["unit_kind"] == &"hold" else &"tap",
					int(note["tick"]), int(note["start_us"]), head_deadline + 1,
					GameplayTypes.JudgmentGrade.MISS
				)
				_finalize_state(state, [component], head_deadline + 1)
		elif state["status"] == &"holding":
			var end_us: int = int(note["end_us"])
			var reaches_end: bool = end_us < time_us or (inclusive and end_us == time_us)
			var gap_started_us: int = int(state["gap_started_us"])
			var gap_deadline_us: int = gap_started_us + _rules.hold_sustain_grace_ms * 1000
			# 大帧步可能同时越过尾点和断持期限。比较两者的绝对时间：尾点仍在
			# 宽限内就先成功；宽限先耗尽则在第一个超时微秒失败，结果不依赖帧率。
			var gap_expires_before_end: bool = gap_started_us >= 0 and gap_deadline_us < end_us
			if gap_expires_before_end and time_us > gap_deadline_us:
				var failure_us: int = gap_deadline_us + 1
				var gap_component := JudgmentComponentRecord.timing(
					&"sustain", int(note["tick"]), int(note["start_us"]), failure_us,
					GameplayTypes.JudgmentGrade.MISS
				)
				var failed_components: Array[JudgmentComponentRecord] = state["components"].duplicate()
				failed_components.append(gap_component)
				_finalize_state(state, failed_components, failure_us)
				continue
			if reaches_end:
				_finish_hold(state, end_us)


func handle_press(sample: SemanticInputSample) -> bool:
	# binding 只描述本次敲击被哪一枚普通音符接受。GameplaySimulation 会把它
	# 交给物理波纹层；Hold 续按或区域机制敲击虽然有效，却不绑定新音符。
	_last_press_binding.clear()
	var affinity: int = sample.affinity()
	for state in _states:
		if state["status"] != &"holding":
			continue
		var note: Dictionary = state["note"]
		if int(note["affinity"]) != affinity or int(state["gap_started_us"]) < 0:
			continue
		if sample.timestamp_us - int(state["gap_started_us"]) <= _rules.hold_sustain_grace_ms * 1000:
			state["gap_started_us"] = -1
			state["held"] = true
			state["sustain_degraded"] = true
			return true
	# 主动按下只会匹配 PASS 窗内的音符；更宽的 MISS 窗只负责无人命中时自动过期。
	# 因此太晚的按下会先记为乱按，该音符随后仍会产生自己的 Miss。
	var candidates: Array[Dictionary] = []
	var pass_us: int = _rules.pass_window_ms * 1000
	for state in _states:
		if state["status"] != &"pending":
			continue
		var note: Dictionary = state["note"]
		if int(note["affinity"]) != affinity:
			continue
		var error_us: int = sample.timestamp_us - int(note["start_us"])
		if absi(error_us) <= pass_us:
			candidates.append({"state": state, "absolute_error": absi(error_us), "error": error_us})
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["absolute_error"]) != int(b["absolute_error"]):
			return int(a["absolute_error"]) < int(b["absolute_error"])
		var a_note: Dictionary = a["state"]["note"]
		var b_note: Dictionary = b["state"]["note"]
		if int(a_note["start_us"]) != int(b_note["start_us"]):
			return int(a_note["start_us"]) < int(b_note["start_us"])
		return String(a_note["id"]) < String(b_note["id"])
	)
	var chosen: Dictionary = candidates[0]["state"]
	var chosen_note: Dictionary = chosen["note"]
	var grade: int = _grade_tap_error(absi(int(candidates[0]["error"])))
	var component_kind: StringName = &"head" if chosen_note["unit_kind"] == &"hold" else &"tap"
	var component := JudgmentComponentRecord.timing(component_kind, int(chosen_note["tick"]), int(chosen_note["start_us"]), sample.timestamp_us, grade)
	_last_press_binding = chosen_note.duplicate(true)
	_last_press_binding["input_us"] = sample.timestamp_us
	_last_press_binding["input_grade"] = grade
	if chosen_note["unit_kind"] == &"tap":
		_finalize_state(chosen, [component], sample.timestamp_us)
	else:
		chosen["status"] = &"holding"
		chosen["held"] = true
		chosen["gap_started_us"] = -1
		chosen["components"] = [component] as Array[JudgmentComponentRecord]
	return true


func last_press_binding() -> Dictionary:
	return _last_press_binding.duplicate(true)


func handle_release(sample: SemanticInputSample) -> bool:
	var affinity: int = sample.affinity()
	for state in _states:
		if state["status"] != &"holding":
			continue
		var note: Dictionary = state["note"]
		if int(note["affinity"]) != affinity:
			continue
		# 尾点不再判松键。恰好在尾点收到 RELEASE 时，advance_to(..., false)
		# 尚未包含该端点，因此在这里仍按“已持续到尾点”自动完成。
		if sample.timestamp_us >= int(note["end_us"]):
			_finish_hold(state, int(note["end_us"]))
			return true
		state["held"] = false
		# 任何尾点前的松开都只开启持续宽限；不再把“接近尾点”误作一次松键判定。
		if int(state["gap_started_us"]) < 0:
			state["gap_started_us"] = sample.timestamp_us
		return true
	return false


func cancel_active(time_us: int) -> void:
	for state in _states:
		if state["status"] != &"holding":
			continue
		var note: Dictionary = state["note"]
		var component := JudgmentComponentRecord.timing(&"focus_cancel", int(note["end_tick"]), int(note["end_us"]), time_us, GameplayTypes.JudgmentGrade.MISS)
		var components: Array[JudgmentComponentRecord] = state["components"].duplicate()
		components.append(component)
		_finalize_state(state, components, time_us)


func has_active_hold(affinity: int = -1) -> bool:
	for state in _states:
		if state["status"] != &"holding":
			continue
		if affinity < 0 or int(state["note"]["affinity"]) == affinity:
			return true
	return false


func active_hold_ids(held_only: bool = false) -> PackedStringArray:
	# 表现层可以查询哪些 Hold 头已被真实接受，但不能根据视觉时间自行推断。
	# 这里只暴露基于稳定 ID 的只读视图，使美术表现与判定决策保持解耦。
	var result := PackedStringArray()
	for state in _states:
		if state["status"] != &"holding":
			continue
		if held_only and not bool(state["held"]):
			continue
		result.append(str(state["note"].get("id", state["note"].get("event_id", ""))))
	result.sort()
	return result


func begin_pause_rearm() -> Dictionary:
	_paused_for_rearm = true
	var state := {"life_required": false, "death_required": false}
	for note_state in _states:
		if note_state["status"] != &"holding":
			continue
		if int(note_state["note"]["affinity"]) == GameplayTypes.Affinity.ZHU:
			state["life_required"] = true
		else:
			state["death_required"] = true
		note_state["held"] = false
	return state


func apply_resume_rearm(rearm_state: Dictionary) -> void:
	for note_state in _states:
		if note_state["status"] != &"holding":
			continue
		var life: bool = int(note_state["note"]["affinity"]) == GameplayTypes.Affinity.ZHU
		var rearmed: bool = bool(rearm_state.get("life_held" if life else "death_held", false))
		note_state["held"] = rearmed
		note_state["gap_started_us"] = -1 if rearmed else _current_time_us
	_paused_for_rearm = false


func drain_judgments() -> Array[JudgmentRecord]:
	var result: Array[JudgmentRecord] = _pending_records.duplicate()
	_pending_records.clear()
	return result


func _finish_hold(state: Dictionary, finalized_at_us: int) -> void:
	var components: Array[JudgmentComponentRecord] = state["components"].duplicate()
	var sustain_grade: int = GameplayTypes.JudgmentGrade.PASS if bool(state["sustain_degraded"]) else GameplayTypes.JudgmentGrade.PERFECT
	var note: Dictionary = state["note"]
	components.append(JudgmentComponentRecord.value_error(&"sustain", int(note["tick"]), int(note["start_us"]), 0.0, sustain_grade))
	_finalize_state(state, components, finalized_at_us)


func _finalize_state(state: Dictionary, components: Array[JudgmentComponentRecord], finalized_at_us: int) -> void:
	if state["status"] == &"judged":
		return
	state["status"] = &"judged"
	state["held"] = false
	var note: Dictionary = state["note"]
	var record := JudgmentRecord.new()
	record.unit_id = String(note["id"])
	record.unit_kind = StringName(note["unit_kind"])
	record.affinity = int(note["affinity"])
	record.start_tick = int(note["tick"])
	record.end_tick = int(note["end_tick"])
	record.finalized_at_us = finalized_at_us
	record.group_id = String(note["group_id"])
	record.damage_group_id = String(note["damage_group_id"])
	record.components = components
	record.recompute_grade()
	_pending_records.append(record)


func _grade_tap_error(absolute_error_us: int) -> int:
	if absolute_error_us <= _rules.perfect_window_ms * 1000:
		return GameplayTypes.JudgmentGrade.PERFECT
	if absolute_error_us <= _rules.good_window_ms * 1000:
		return GameplayTypes.JudgmentGrade.GOOD
	if absolute_error_us <= _rules.pass_window_ms * 1000:
		return GameplayTypes.JudgmentGrade.PASS
	return GameplayTypes.JudgmentGrade.MISS
