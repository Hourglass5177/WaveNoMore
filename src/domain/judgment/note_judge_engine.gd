class_name NoteJudgeEngine
extends RefCounted

## Tap 与 Hold 的确定性判定器。Hold 只判头部和持续过程，到达尾点自动完成；
## 不生成画面；命中的普通音符会把稳定绑定信息交给物理波纹层。

## 本局判定规则；读取头部时间窗与 Hold 断持宽限。
var _rules: GameplayRuleSet
var _pet := PetEffectProfile.new()
## 每个编译音符的运行时状态，按 start_us、类型和稳定 ID 排序。
var _states: Array[Dictionary] = []
## 已编译事件保持原顺序；只把进入判定窗口的状态放入热循环。
var _future_states: Array[Dictionary] = []
var _future_cursor := 0
## 已完成但尚未由 GameplaySimulation 取走的判定记录。
var _pending_records: Array[JudgmentRecord] = []
## 暂停重臂期间为 true；阻止恢复瞬间把旧物理按住状态当成有效续按。
var _paused_for_rearm: bool = false
## 最近推进到的歌曲时间，单位微秒；极小值表示尚未开始。
var _current_time_us: int = -9_000_000_000_000_000
## 最近一次成功按下所绑定音符的只读快照；空字典表示未命中普通音符。
var _last_press_binding: Dictionary = {}


func configure(compiled: CompiledChart, rules: GameplayRuleSet, pet: PetEffectProfile = null) -> void:
	#print("[NoteJudge] configure")
	_rules = rules
	_pet = pet if pet != null else PetEffectProfile.new()
	_states.clear()
	_future_states.clear()
	_future_cursor = 0
	for note in compiled.notes:
		_future_states.append({
			"note": note.duplicate(true),
			"status": &"pending",
			"components": [] as Array[JudgmentComponentRecord],
			"held": false,
			"input_channel": GameplayTypes.BellInputChannel.NONE,
			"gap_started_us": -1,
			"sustain_degraded": false,
		})
	_pending_records.clear()
	_last_press_binding.clear()
	_current_time_us = -9_000_000_000_000_000
	_paused_for_rearm = false


func reset(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	configure(compiled, rules, _pet)


func advance_to(time_us: int, inclusive: bool = true) -> void:
	#print("[NoteJudge] advance_to time=%d inclusive=%s" % [time_us, str(inclusive)])
	if time_us < _current_time_us:
		return
	_current_time_us = time_us
	if _paused_for_rearm:
		return
	_prepare_window(time_us)
	for state in _states:
		var note: Dictionary = state["note"]
		if state["status"] == &"pending":
			var head_deadline: int = int(note["start_us"]) + _window_ms(note, _rules.miss_window_ms) * 1000
			if time_us > head_deadline + 1 or (inclusive and time_us == head_deadline + 1):
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
			var gap_deadline_us: int = gap_started_us + (_rules.hold_sustain_grace_ms + _pet.hold_sustain_bonus_ms) * 1000
			# 大帧步可能同时越过尾点和断持期限。比较两者的绝对时间：尾点仍在
			# 宽限内就先成功；宽限先耗尽则在第一个超时微秒失败，结果不依赖帧率。
			var gap_expires_before_end: bool = gap_started_us >= 0 and gap_deadline_us < end_us
			if gap_expires_before_end and (time_us > gap_deadline_us + 1 or (inclusive and time_us == gap_deadline_us + 1)):
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
	_prepare_window(sample.timestamp_us)
	#print("[NoteJudge] handle_press timestamp=%d" % sample.timestamp_us)
	#print("[NoteJudge] press affinity=%d timestamp=%d" % [sample.affinity(), sample.timestamp_us])
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
		if sample.timestamp_us - int(state["gap_started_us"]) <= (_rules.hold_sustain_grace_ms + _pet.hold_sustain_bonus_ms) * 1000:
			state["gap_started_us"] = -1
			state["held"] = true
			state["input_channel"] = sample.input_channel()
			state["sustain_degraded"] = true
			return true
	# 主动按下只会匹配 PASS 窗内的音符；更宽的 MISS 窗只负责无人命中时自动过期。
	# 因此太晚的按下会先记为乱按，该音符随后仍会产生自己的 Miss。
	var candidates: Array[Dictionary] = []
	for state in _states:
		if state["status"] != &"pending":
			continue
		var note: Dictionary = state["note"]
		if int(note["affinity"]) != affinity:
			continue
		var error_us: int = sample.timestamp_us - int(note["start_us"])
		if absi(error_us) <= _window_ms(note, _rules.pass_window_ms) * 1000:
			candidates.append({"state": state, "absolute_error": absi(error_us), "error": error_us})
	if candidates.is_empty():
		#print("[NoteJudge] press no_candidate")
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
	var grade: int = _grade_tap_error(absi(int(candidates[0]["error"])), chosen_note)
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
		chosen["input_channel"] = sample.input_channel()
		chosen["gap_started_us"] = -1
		chosen["components"] = [component] as Array[JudgmentComponentRecord]
	#print("[NoteJudge] press matched id=%s unit=%s grade=%d" % [str(chosen_note["id"]), str(chosen_note["unit_kind"]), grade])
	return true


func last_press_binding() -> Dictionary:
	return _last_press_binding.duplicate(true)


func handle_release(sample: SemanticInputSample) -> bool:
	#print("[NoteJudge] handle_release timestamp=%d" % sample.timestamp_us)
	#print("[NoteJudge] release affinity=%d timestamp=%d" % [sample.affinity(), sample.timestamp_us])
	var affinity: int = sample.affinity()
	for state in _states:
		if state["status"] != &"holding":
			continue
		var note: Dictionary = state["note"]
		if int(note["affinity"]) != affinity or int(state["input_channel"]) != sample.input_channel():
			continue
		# 同刻尾点由生命周期统一完成，先让释放参与调频端点结算。
		# 此处只更新持续状态；不抢在同刻其他系统之前终结 Hold。
		state["held"] = false
		# 任何尾点前的松开都只开启持续宽限；不再把“接近尾点”误作一次松键判定。
		if int(state["gap_started_us"]) < 0:
			state["gap_started_us"] = sample.timestamp_us
		return true
	return false


func cancel_active(time_us: int) -> void:
	#print("[NoteJudge] cancel_active time=%d" % time_us)
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


func has_perfect_holding_note(affinity: int) -> bool:
	## 只读当前 holding 的原始头判；续按造成的 sustain 降级不改变头判。
	## 同侧重叠时任意一个 Perfect 头判即可，结束、Miss、取消自然退出。
	for state: Dictionary in _states:
		if state["status"] != &"holding" or int(state["note"]["affinity"]) != affinity:
			continue
		for component: JudgmentComponentRecord in state["components"]:
			if component.kind == &"head" and component.grade == GameplayTypes.JudgmentGrade.PERFECT:
				return true
	return false


func begin_pause_rearm() -> Dictionary:
	_paused_for_rearm = true
	var state := {
		"life_required": false,
		"death_required": false,
		"life_a_required": false,
		"life_b_required": false,
		"death_a_required": false,
		"death_b_required": false,
	}
	for note_state in _states:
		if note_state["status"] != &"holding":
			continue
		var life: bool = int(note_state["note"]["affinity"]) == GameplayTypes.Affinity.ZHU
		var channel: int = int(note_state["input_channel"])
		if life:
			state["life_required"] = true
		else:
			state["death_required"] = true
		var channel_name: String = "a" if channel == GameplayTypes.BellInputChannel.A else "b"
		state[("life_" if life else "death_") + channel_name + "_required"] = true
		note_state["held"] = false
	return state


func apply_resume_rearm(rearm_state: Dictionary) -> void:
	for note_state in _states:
		if note_state["status"] != &"holding":
			continue
		var life: bool = int(note_state["note"]["affinity"]) == GameplayTypes.Affinity.ZHU
		var channel: int = int(note_state["input_channel"])
		var channel_name: String = "a" if channel == GameplayTypes.BellInputChannel.A else "b"
		var rearm_key: String = ("life_" if life else "death_") + channel_name + "_held"
		var rearmed: bool = bool(rearm_state.get(rearm_key, false))
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


func _grade_tap_error(absolute_error_us: int, note: Dictionary = {}) -> int:
	if absolute_error_us <= _window_ms(note, _rules.perfect_window_ms) * 1000:
		return GameplayTypes.JudgmentGrade.PERFECT

	if absolute_error_us <= _window_ms(note, _rules.good_window_ms) * 1000:
		return GameplayTypes.JudgmentGrade.GOOD
	if absolute_error_us <= _window_ms(note, _rules.pass_window_ms) * 1000:
		return GameplayTypes.JudgmentGrade.PASS
	return GameplayTypes.JudgmentGrade.MISS


func _prepare_window(time_us: int) -> void:
	_states = _states.filter(func(state: Dictionary) -> bool: return state["status"] != &"judged")
	var horizon := time_us + (maxi(_rules.pass_window_ms, _rules.miss_window_ms) + _pet.hold_head_bonus_ms) * 1000
	while _future_cursor < _future_states.size():
		var state := _future_states[_future_cursor]
		if int(state["note"]["start_us"]) > horizon: break
		_states.append(state)
		_future_cursor += 1


## 只查询领域 holding 状态；松开宽限不排除，完成、Miss 和取消自然退出。
func has_dual_holding_notes() -> bool:
	return has_active_hold(GameplayTypes.Affinity.ZHU) and has_active_hold(GameplayTypes.Affinity.XUAN)


## 返回指定阵营正在持续判定的 Hold ID；没有则返回空字符串。
func holding_note_id(affinity: int) -> String:
	for state: Dictionary in _states:
		if state["status"] == &"holding" and int(state["note"]["affinity"]) == affinity:
			return str(state["note"]["event_id"])
	return ""


## 核心推进时使用此边界，确保较早的 Hold 退出先于较晚的调频端点结算。
func next_holding_transition_us() -> int:
	var result: int = 9223372036854775807
	for state: Dictionary in _states:
		if state["status"] != &"holding":
			continue
		var end_us: int = int(state["note"]["end_us"])
		result = mini(result, end_us)
		if not bool(state["held"]) and int(state["gap_started_us"]) >= 0:
			result = mini(result, int(state["gap_started_us"]) + (_rules.hold_sustain_grace_ms + _pet.hold_sustain_bonus_ms) * 1000 + 1)
	return result


func _window_ms(note: Dictionary, window: int) -> int:
	return window + (_pet.hold_head_bonus_ms if note.get("unit_kind") == &"hold" else 0)

func next_transition_us() -> int:
	# 将头部超时也列为边界，避免大帧步把抵达受伤之后的判定提前计入。
	var result := next_holding_transition_us()
	for state in _states:
		if state.status == &"pending":
			result = mini(result, int(state.note.start_us) + _window_ms(state.note, _rules.miss_window_ms) * 1000 + 1)
	for i in range(_future_cursor, _future_states.size()):
		var note: Dictionary = _future_states[i].note
		if int(note.start_us) > result: break
		result = mini(result, int(note.start_us) + _window_ms(note, _rules.miss_window_ms) * 1000 + 1)
	return result
