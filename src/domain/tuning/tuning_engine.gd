class_name TuningEngine
extends RefCounted

## 双钟独立调频滑条的确定性判定器。
##
## 调频段只决定“什么时候允许改变频率”；滑条不负责开启波源。
## 摇杆控制二维速度在游标切线上的分量，指针仍使用位移；点状引导只提示节奏。

const NEVER_TIME_US: int = -9_000_000_000_000_000
const TUNING_ARC_GEOMETRY: GDScript = preload("res://src/domain/tuning/tuning_arc_geometry.gd")
## Replay 的双路输入会量化为 Q15；连续位移累加后可能留下万分位误差。
## 这里只放宽边界比较，不钳制玩家位置，以免越过滑条端点也被误算为命中。
const TRACKING_EPSILON: float = 0.001
## 整数微秒子步严格不超过 1/240 秒；边界处使用剩余时长，不丢时间。
const STICK_MAX_STEP_US: int = 4166

## 时间窗外没有输入时，端点判定使用这个哨兵值表示“尚未到达”。
const NO_ENDPOINT_OBSERVATION_US: int = 9_000_000_000_000_000

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
## 两口钟在统一频率轴上的归一化位置，0 为最低频、1 为最高频。
var _life_value: float = 0.5
var _death_value: float = 0.5
var _last_life_held: bool = false
var _last_death_held: bool = false
var _life_input_channel: int = GameplayTypes.BellInputChannel.NONE
var _death_input_channel: int = GameplayTypes.BellInputChannel.NONE
## 由 Gameplay 核心从 NoteJudgeEngine 的 holding 状态同步，不读取物理键。
var _dual_holding_notes: bool = false
## 指针拖动和摇杆接合分开记录，不互相伪造输入状态。
var _pointer_drags: Dictionary[int, Dictionary] = {}
var _paused_for_rearm: bool = false
var _life_tuning_engaged: bool = false
var _death_tuning_engaged: bool = false
## 最新标准化向量跨帧保存；没有新事件不等于停速，只有回中或中断才清零。
var _life_stick_control: Vector2 = Vector2.ZERO
var _death_stick_control: Vector2 = Vector2.ZERO
var _life_drag_state_index: int = -1
var _death_drag_state_index: int = -1
var _life_drag_traversal_index: int = -1
var _death_drag_traversal_index: int = -1


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
	_last_life_held = false
	_last_death_held = false
	_life_input_channel = GameplayTypes.BellInputChannel.NONE
	_death_input_channel = GameplayTypes.BellInputChannel.NONE
	_paused_for_rearm = false
	_dual_holding_notes = false
	_clear_drag_state(GameplayTypes.Affinity.ZHU)
	_clear_drag_state(GameplayTypes.Affinity.XUAN)
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
	return sample.kind == GameplayTypes.SemanticInputKind.TUNING_DISPLACED


## 记录每侧首次建立调频保持的 A/B 来源；只有匹配释放才归零并解除拖动。
func handle_bell_input(sample: SemanticInputSample) -> void:
	if sample == null or (not sample.is_press() and not sample.is_release()):
		return
	var affinity: int = sample.affinity()
	var channel: int = sample.input_channel()
	if affinity == GameplayTypes.Affinity.ZHU:
		if sample.is_press() and _life_input_channel == GameplayTypes.BellInputChannel.NONE:
			_life_input_channel = channel
			_last_life_held = true
		elif sample.is_release() and _life_input_channel == channel:
			_life_input_channel = GameplayTypes.BellInputChannel.NONE
			_last_life_held = false
			reset_side_progress(affinity, sample.timestamp_us)
	elif affinity == GameplayTypes.Affinity.XUAN:
		if sample.is_press() and _death_input_channel == GameplayTypes.BellInputChannel.NONE:
			_death_input_channel = channel
			_last_death_held = true
		elif sample.is_release() and _death_input_channel == channel:
			_death_input_channel = GameplayTypes.BellInputChannel.NONE
			_last_death_held = false
			reset_side_progress(affinity, sample.timestamp_us)


func handle_input(sample: SemanticInputSample, life_held: bool, death_held: bool) -> bool:
	if sample == null or not can_consume(sample):
		return false
	_last_life_held = life_held
	_last_death_held = death_held
	if not _dual_holding_notes or not field_active():
		return false

	# 位移已由设备层换算成“整条频率轴的归一化增量”。滑条只限制本程
	# 的物理行程，不再根据时间引导放大、阻尼或丢弃玩家的真实旋转。
	if life_held:
		var previous_life_value: float = _life_value
		_life_value = _apply_side_displacement(
			GameplayTypes.Affinity.ZHU,
			_life_value,
			sample.tune_vector.x,
			sample.timestamp_us
		)
		_record_endpoint_entries(
			GameplayTypes.Affinity.ZHU,
			previous_life_value,
			_life_value,
			sample.timestamp_us
		)
	if death_held:
		var previous_death_value: float = _death_value
		_death_value = _apply_side_displacement(
			GameplayTypes.Affinity.XUAN,
			_death_value,
			sample.tune_vector.y,
			sample.timestamp_us
		)
		_record_endpoint_entries(
			GameplayTypes.Affinity.XUAN,
			previous_death_value,
			_death_value,
			sample.timestamp_us
		)

	_queue_frequency_change(sample.timestamp_us)
	return true


## 设置该侧最新速度控制目标；回中只停速，已接合状态与进度保持。
## 调用方必须先 advance_to(timestamp_us, false)，不能把新向量应用于过去时间。
func set_stick_control(affinity: int, control_vector: Vector2, timestamp_us: int) -> void:
	if _paused_for_rearm or timestamp_us < _current_time_us:
		return
	if affinity == GameplayTypes.Affinity.ZHU:
		_life_stick_control = control_vector
	else:
		_death_stick_control = control_vector
	_try_engage_stick(affinity, timestamp_us)


## 中断当前一侧的调频操作，并将活动滑条恢复到其声明的起点值。
## 该操作只改变调频状态，不产生判定、乱按或波事件。
func reset_side_progress(affinity: int, timestamp_us: int) -> bool:
	var state_index: int = _active_slider_state_index(affinity, timestamp_us)
	_clear_drag_state(affinity)
	if state_index < 0:
		return false
	var state: Dictionary = _slider_states[state_index]
	var slider: Dictionary = state["slider"]
	var start_value: float = clampf(float(slider.get("start_value", 0.0)), 0.0, 1.0)
	var previous_value: float = _value_for_affinity(affinity)
	if affinity == GameplayTypes.Affinity.ZHU:
		_life_value = start_value
	else:
		_death_value = start_value
	for endpoint_value: Variant in state["endpoint_states"]:
		var endpoint: Dictionary = endpoint_value
		endpoint["inside"] = false
	var changed: bool = not is_equal_approx(previous_value, start_value)
	if changed:
		_queue_frequency_change(timestamp_us)
	return changed


func _try_engage_stick(affinity: int, timestamp_us: int) -> bool:
	## 无角度窗口；资格满足后从本程起点接合。零向量不新建接合，但不解除旧接合。
	var life: bool = affinity == GameplayTypes.Affinity.ZHU
	var held: bool = _last_life_held if life else _last_death_held
	if not _dual_holding_notes or not held or not field_active() or _paused_for_rearm:
		return false
	var state_index: int = _active_slider_state_index(affinity, timestamp_us)
	if state_index < 0:
		return false
	var state: Dictionary = _slider_states[state_index]
	if not bool(state["started"]) or float(state["arc_length_px"]) <= 0.000001:
		return false
	var leg: int = int(state["traversal_index"])
	var engaged: bool = _life_tuning_engaged if life else _death_tuning_engaged
	var previous_index: int = _life_drag_state_index if life else _death_drag_state_index
	var previous_leg: int = _life_drag_traversal_index if life else _death_drag_traversal_index
	if engaged and previous_index == state_index and previous_leg == leg:
		return true
	var control: Vector2 = _life_stick_control if life else _death_stick_control
	if control == Vector2.ZERO:
		return false
	if life:
		_life_tuning_engaged = true
		_life_drag_state_index = state_index
		_life_drag_traversal_index = leg
	else:
		_death_tuning_engaged = true
		_death_drag_state_index = state_index
		_death_drag_traversal_index = leg
	var slider: Dictionary = state["slider"]
	var initial_value: float = float(slider["start_value"] if leg % 2 == 0 else slider["end_value"])
	if _set_stick_side_value(affinity, initial_value, timestamp_us):
		_queue_frequency_change(timestamp_us)
	return true


func _advance_stick_motion_to(time_us: int) -> void:
	## 时间线边界之间用中点法推进；两侧共享时间步但各自计算控制、几何和进度。
	var life_active: bool = _try_engage_stick(GameplayTypes.Affinity.ZHU, _current_time_us)
	var death_active: bool = _try_engage_stick(GameplayTypes.Affinity.XUAN, _current_time_us)
	var speed: float = maxf(_rules.tuning_stick_max_speed_px_sec, 0.0)
	if speed == 0.0 or not (
		(life_active and _life_stick_control != Vector2.ZERO)
		or (death_active and _death_stick_control != Vector2.ZERO)
	):
		# 没有运动时直接跨过空窗，不能从 NEVER_TIME_US 循环几万亿个子步。
		_current_time_us = time_us
		return
	while _current_time_us < time_us:
		var next_us: int = mini(time_us, _current_time_us + STICK_MAX_STEP_US)
		var delta_sec: float = float(next_us - _current_time_us) / 1_000_000.0
		var changed: bool = false
		if life_active:
			changed = _integrate_stick_side(GameplayTypes.Affinity.ZHU, delta_sec, next_us, speed)
		if death_active:
			changed = _integrate_stick_side(GameplayTypes.Affinity.XUAN, delta_sec, next_us, speed) or changed
		_current_time_us = next_us
		if changed:
			_queue_frequency_change(next_us)


func _integrate_stick_side(affinity: int, delta_sec: float, timestamp_us: int, speed: float) -> bool:
	## p 属于 start_value → end_value；真实圆弧单位切线只投影一次，不乘往返方向。
	var life: bool = affinity == GameplayTypes.Affinity.ZHU
	var control: Vector2 = _life_stick_control if life else _death_stick_control
	if control == Vector2.ZERO:
		return false
	var index: int = _life_drag_state_index if life else _death_drag_state_index
	var state: Dictionary = _slider_states[index]
	var slider: Dictionary = state["slider"]
	var length_px: float = float(state["arc_length_px"])
	var traversal_index: int = int(state["traversal_index"])
	var ticks: int = maxi(1, int(slider["traversal_ticks"]))
	var leg_start_us: int = _compiled.tempo_map.tick_to_us(int(slider["tick"]) + traversal_index * ticks)
	var leg_end_us: int = _compiled.tempo_map.tick_to_us(int(slider["tick"]) + (traversal_index + 1) * ticks)
	var duration_sec: float = float(leg_end_us - leg_start_us) / 1000000.0
	var tolerance_sec: float = float(_rule_int(&"tuning_speed_tolerance_ms", 500)) / 1000.0
	speed = length_px / maxf(duration_sec - tolerance_sec, 0.001)
	var global_progress: float = clampf(_value_to_slider_progress(slider, _value_for_affinity(affinity)), 0.0, 1.0)
	var progress: float = global_progress if traversal_index % 2 == 0 else 1.0 - global_progress
	var velocity: Vector2 = control * speed
	var tangent: Vector2 = TUNING_ARC_GEOMETRY.slider_tangent(
		progress, affinity, float(slider["start_value"]), float(slider["end_value"]),
		float(state["sweep_rad"]), float(state["rotation_rad"])
	)
	var traversal_sign: float = 1.0 if traversal_index % 2 == 0 else -1.0
	tangent *= traversal_sign
	var midpoint: float = clampf(progress + velocity.dot(tangent) * delta_sec * 0.5 / length_px, 0.0, 1.0)
	var midpoint_tangent: Vector2 = TUNING_ARC_GEOMETRY.slider_tangent(
		midpoint, affinity, float(slider["start_value"]), float(slider["end_value"]),
		float(state["sweep_rad"]), float(state["rotation_rad"])
	)
	midpoint_tangent *= traversal_sign
	var next_progress: float = clampf(progress + velocity.dot(midpoint_tangent) * delta_sec / length_px, 0.0, 1.0)
	var next_global_progress: float = next_progress if traversal_index % 2 == 0 else 1.0 - next_progress
	var next_value: float = lerpf(float(slider["start_value"]), float(slider["end_value"]), next_global_progress)
	return _set_stick_side_value(affinity, next_value, timestamp_us)


func _set_stick_side_value(affinity: int, next_value: float, timestamp_us: int) -> bool:
	## 只提交真实频率位置和端点观察，不锁存成绩、不读取视觉磁吸进度。
	var previous_value: float = _value_for_affinity(affinity)
	# 低速积分不能每步用近似相等截掉，否则刚离开死区时永远不积累位移。
	if previous_value == next_value:
		return false
	if affinity == GameplayTypes.Affinity.ZHU:
		_life_value = next_value
	else:
		_death_value = next_value
	_record_endpoint_entries(affinity, previous_value, next_value, timestamp_us)
	return true


func advance_to(time_us: int, inclusive: bool = true, life_held: bool = false, death_held: bool = false) -> void:
	if time_us < _current_time_us:
		return
	_last_life_held = life_held
	_last_death_held = death_held
	if _paused_for_rearm:
		_current_time_us = time_us
		return

	while _timeline_cursor < _timeline_events.size():
		var event: Dictionary = _timeline_events[_timeline_cursor]
		var event_us: int = int(event["time_us"])
		if event_us > time_us or (event_us == time_us and not inclusive):
			break
		_advance_stick_motion_to(event_us)
		_process_timeline_event(event)
		_timeline_cursor += 1
	_advance_stick_motion_to(time_us)


func cancel_active(time_us: int) -> void:
	_dual_holding_notes = false
	_current_time_us = maxi(_current_time_us, time_us)
	_last_life_held = false
	_last_death_held = false
	_life_input_channel = GameplayTypes.BellInputChannel.NONE
	_death_input_channel = GameplayTypes.BellInputChannel.NONE
	_clear_drag_state(GameplayTypes.Affinity.ZHU)
	_clear_drag_state(GameplayTypes.Affinity.XUAN)


func is_active() -> bool:
	return field_active()


func _clear_drag_state(affinity: int, clear_control: bool = true) -> void:
	## 中断清除持续速度；换条/换程只清接合，当前物理向量可用于重新接合。
	_pointer_drags.erase(affinity)
	_clear_stick_drag_state(affinity, clear_control)


func _clear_stick_drag_state(affinity: int, clear_control: bool = true) -> void:
	## 摇杆换程只清理摇杆接合，不抹掉同刻指针刚建立的新程拖动。
	if affinity == GameplayTypes.Affinity.ZHU:
		_life_tuning_engaged = false
		_life_drag_state_index = -1
		_life_drag_traversal_index = -1
		if clear_control:
			_life_stick_control = Vector2.ZERO
	else:
		_death_tuning_engaged = false
		_death_drag_state_index = -1
		_death_drag_traversal_index = -1
		if clear_control:
			_death_stick_control = Vector2.ZERO


func field_active() -> bool:
	# 调频只在谱面场域或尚未走到原定尾点的滑条内开放；不再追加晚到窗口。
	return not _active_field_ids.is_empty() or _has_pending_slider_window(_current_time_us)


func active_field_id() -> String:
	var ids: Array = _active_field_ids.keys()
	ids.sort()
	if not ids.is_empty():
		return str(ids[0])
	var pending: Array[Dictionary] = []
	for state: Dictionary in _slider_states:
		if bool(state["finished"]):
			continue
		var slider: Dictionary = state["slider"]
		if (
			_current_time_us >= int(slider["start_us"])
			and _current_time_us <= int(state["judgment_end_us"])
		):
			pending.append(slider)
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["start_us"]) != int(b["start_us"]):
			return int(a["start_us"]) < int(b["start_us"])
		return str(a["event_id"]) < str(b["event_id"])
	)
	return str(pending[0].get("field_id", "")) if not pending.is_empty() else ""


func begin_pause_rearm() -> Dictionary:
	_paused_for_rearm = true
	_life_stick_control = Vector2.ZERO
	_death_stick_control = Vector2.ZERO
	return {
		"tuning_required": field_active(),
		"life_required": field_active() and _last_life_held,
		"death_required": field_active() and _last_death_held,
		"life_input_channel": _life_input_channel,
		"death_input_channel": _death_input_channel,
	}


func apply_resume_rearm(rearm_state: Dictionary) -> void:
	_paused_for_rearm = false
	_life_input_channel = _matching_rearm_channel(rearm_state, true, _life_input_channel)
	_death_input_channel = _matching_rearm_channel(rearm_state, false, _death_input_channel)
	_last_life_held = _life_input_channel != GameplayTypes.BellInputChannel.NONE
	_last_death_held = _death_input_channel != GameplayTypes.BellInputChannel.NONE
	# 暂停后的重臂不继承旧接合，下一次有效输入重新建立拖动与视觉控制。
	reset_side_progress(GameplayTypes.Affinity.ZHU, _current_time_us)
	reset_side_progress(GameplayTypes.Affinity.XUAN, _current_time_us)


func _matching_rearm_channel(rearm_state: Dictionary, life: bool, required_channel: int) -> int:
	if required_channel == GameplayTypes.BellInputChannel.NONE:
		return GameplayTypes.BellInputChannel.NONE
	var prefix: String = "life" if life else "death"
	var suffix: String = "a" if required_channel == GameplayTypes.BellInputChannel.A else "b"
	return required_channel if bool(rearm_state.get(prefix + "_" + suffix + "_held", false)) else GameplayTypes.BellInputChannel.NONE


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
	var preview_lead_us: int = roundi(
		maxf(_rule_float(&"approach_duration_sec", 2.25), 0.0) * 1_000_000.0
	)
	for state: Dictionary in _slider_states:
		if bool(state["finished"]):
			continue
		var slider: Dictionary = state["slider"]
		var start_us: int = int(slider["start_us"])
		var input_open: bool = (
			_current_time_us >= start_us
			and _current_time_us <= int(state["judgment_end_us"])
		)
		if (
			_current_time_us < start_us - preview_lead_us
			or _current_time_us > int(state["judgment_end_us"])
		):
			continue
		var guide_progress: float = _guide_progress(slider, _current_time_us) if input_open else 0.0
		var band: Vector2 = _guide_band(slider, _current_time_us) if input_open else Vector2.ZERO
		# PREVIEW 阶段只展示谱面起点，既不读取全局自由调频值，也不允许预填。
		var player_value: float = (
			_value_for_affinity(int(slider["affinity"]))
			if input_open
			else float(slider["start_value"])
		)
		var player_progress: float = _value_to_slider_progress(slider, player_value) if input_open else 0.0
		var snapshot: Dictionary = slider.duplicate(true)
		snapshot["phase"] = &"active" if input_open else &"preview"
		snapshot["interaction_open"] = input_open
		snapshot["dragging"] = input_open and _is_slider_dragging(slider)
		snapshot["guide_progress"] = guide_progress
		snapshot["guide_value"] = lerpf(float(slider["start_value"]), float(slider["end_value"]), guide_progress)
		snapshot["guide_band_min"] = band.x
		snapshot["guide_band_max"] = band.y
		snapshot["player_progress"] = player_progress
		snapshot["raw_player_progress"] = player_progress
		snapshot["player_value"] = player_value
		snapshot["held"] = _last_life_held if int(slider["affinity"]) == GameplayTypes.Affinity.ZHU else _last_death_held
		snapshot["required_rotation_sign"] = _required_rotation_sign(
			slider,
			_current_time_us if input_open else start_us
		)
		var endpoint_snapshots: Array[Dictionary] = _endpoint_snapshots(state)
		snapshot["endpoint_states"] = endpoint_snapshots
		var endpoint_index: int = _endpoint_index_for_time(
			state,
			maxi(_current_time_us, start_us)
		)
		snapshot["current_endpoint_index"] = endpoint_index
		# 视觉填充的奇偶方向必须与领域换程在同一时刻切换，因此这里直接使用
		# 精确微秒时间线维护的 traversal_index，不再用四舍五入 tick 反推，
		# 避免折返点前后一帧把填充画在错误的一端。
		snapshot["current_traversal_index"] = int(state["traversal_index"])
		snapshot["turnaround_pending"] = (
			input_open
			and endpoint_index >= 0
			and endpoint_index < maxi(1, int(slider["traversal_count"])) - 1
		)
		if endpoint_index >= 0 and endpoint_index < endpoint_snapshots.size():
			var endpoint: Dictionary = endpoint_snapshots[endpoint_index]
			snapshot["endpoint_target_progress"] = float(endpoint["target_progress"])
			snapshot["endpoint_inside"] = bool(endpoint["inside"])
			snapshot["endpoint_captured"] = bool(endpoint["captured"])
			snapshot["endpoint_grade"] = int(endpoint["grade"])
			snapshot["endpoint_best_error_us"] = int(endpoint["best_error_us"])
			snapshot["endpoint_window_active"] = bool(endpoint["window_active"])
			var side_held: bool = bool(snapshot["held"])
			var magnetized: bool = (
				side_held
				and bool(endpoint["inside"])
				and not bool(endpoint["finalized"])
			)
			snapshot["endpoint_magnetized"] = magnetized
			if magnetized:
				# 磁吸只修饰最后几格填充，不改真实频率值。松键会立刻露出真实
				# 位置，反向旋转离开端点区后也能自然把填充拉回来。
				# target_progress 与 player_progress 同为曲线坐标；奇数程的
				# 反向换算由视觉层按本程方向完成。
				snapshot["player_progress"] = float(endpoint["target_progress"])
		result.append(snapshot)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["affinity"]) != int(b["affinity"]):
			return int(a["affinity"]) < int(b["affinity"])
		if bool(a.get("interaction_open", false)) != bool(b.get("interaction_open", false)):
			return bool(a.get("interaction_open", false))
		if int(a.get("start_us", 0)) != int(b.get("start_us", 0)):
			return int(a.get("start_us", 0)) < int(b.get("start_us", 0))
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
	for field: Dictionary in _compiled.tuning_fields:
		var field_id: String = str(field.get("event_id", field.get("id", "")))
		# 同 tick 相邻场域的顺序必须是：旧滑条尾点 → 旧场退出 → 新场进入 → 新滑条起点。
		# 因此 enter 排在 exit 之后，确保新场即使无时间间隔也会重新回到统一基频。
		_timeline_events.append({"time_us": int(field["start_us"]), "priority": 4, "kind": &"field_enter", "field_id": field_id})
		_timeline_events.append({"time_us": int(field["end_us"]), "priority": 3, "kind": &"field_exit", "field_id": field_id})


func _build_slider_states() -> void:
	for index: int in range(_compiled.tuning_sliders.size()):
		var slider: Dictionary = _compiled.tuning_sliders[index].duplicate(true)
		var event_id: String = str(slider.get("event_id", slider.get("id", "slider_%06d" % index)))
		var group_key: String = str(slider.get("group_id", ""))
		if group_key.is_empty():
			group_key = event_id
		# 仅缓存运行时几何，不写入 CompiledChart 或谱面字段。
		var chord_px: float = TUNING_ARC_GEOMETRY.chord_length_px(
			float(slider["start_value"]), float(slider["end_value"]),
			_rule_float(&"tuning_min_frequency_hz", 1.0), _rule_float(&"tuning_max_frequency_hz", 7.0),
			_rule_float(&"tuning_pixels_per_hz", 160.0)
		)
		var sweep: float = TUNING_ARC_GEOMETRY.equivalent_sweep_from_chord_rad(
			chord_px, TUNING_ARC_GEOMETRY.equivalent_center_distance_px(_rules.wave_canvas_size.x)
		)
		var radius: float = TUNING_ARC_GEOMETRY.equivalent_radius_from_chord_px(chord_px, sweep)
		var endpoint_states: Array[Dictionary] = _build_endpoint_states(slider)
		var judgment_end_us: int = (
			int(endpoint_states[-1]["deadline_us"])
			if not endpoint_states.is_empty()
			else int(slider["end_us"])
		)
		var state: Dictionary = {
			"slider": slider,
			"event_id": event_id,
			"group_key": group_key,
			"grade": GameplayTypes.JudgmentGrade.MISS,
			"finished": false,
			"started": false,
			# 由精确微秒时间线推进，不用四舍五入后的 tick 提前切换积分方向。
			"traversal_index": 0,
			"sweep_rad": sweep,
			"arc_length_px": radius * sweep,
			"rotation_rad": deg_to_rad(float(slider.get("arc_rotation_deg", 0.0))),
			"endpoint_states": endpoint_states,
			"judgment_end_us": judgment_end_us,
		}
		_slider_states.append(state)
		if not _group_members.has(group_key):
			_group_members[group_key] = []
		_group_members[group_key].append(index)

		_timeline_events.append({
			"time_us": int(slider["start_us"]),
			# 场域先进入并重置基频，随后把这一侧精确放到谱面声明的滑条起点。
			"priority": 5,
			"kind": &"slider_begin",
			"state_index": index,
			"event_id": "%s:begin" % event_id,
		})
		_timeline_events.append({
			"time_us": judgment_end_us,
			"priority": 2,
			"kind": &"slider_finish",
			"state_index": index,
			"event_id": event_id,
		})
		for endpoint_index: int in range(endpoint_states.size()):
			var endpoint: Dictionary = endpoint_states[endpoint_index]
			_timeline_events.append({
				"time_us": int(endpoint["leg_start_us"]),
				# 在场域进入及起点采样之后初始化实时端点位置；这里只更新
				# inside，是否成功仍由 target_us 的最终位置和按住状态决定。
				"priority": 6,
				"kind": &"endpoint_open",
				"state_index": index,
				"endpoint_index": endpoint_index,
				"event_id": "%s:endpoint:%d" % [event_id, endpoint_index],
			})
			_timeline_events.append({
				"time_us": int(endpoint["deadline_us"]),
				"priority": 1,
				"kind": &"endpoint_finalize",
				"state_index": index,
				"endpoint_index": endpoint_index,
				"event_id": "%s:endpoint:%d" % [event_id, endpoint_index],
			})


func _build_endpoint_states(slider: Dictionary) -> Array[Dictionary]:
	## 每个单程都有自己的节奏端点。往返滑条因此会产生两个独立分项，
	## 最终成绩自然取所有行程、所有阵营中最差的一项。
	var result: Array[Dictionary] = []
	var traversal_ticks: int = maxi(1, int(slider["traversal_ticks"]))
	var traversal_count: int = maxi(1, int(slider["traversal_count"]))
	for leg_index: int in range(traversal_count):
		var leg_start_tick: int = int(slider["tick"]) + leg_index * traversal_ticks
		var target_tick: int = leg_start_tick + traversal_ticks
		var target_us: int = _compiled.tempo_map.tick_to_us(target_tick)
		result.append({
			"leg_index": leg_index,
			"leg_start_tick": leg_start_tick,
			"leg_start_us": _compiled.tempo_map.tick_to_us(leg_start_tick),
			"target_tick": target_tick,
			"target_us": target_us,
			# 玩家可以提前抵达，但成绩仍在原定端点时刻统一结算。
			"deadline_us": target_us,
			"target_progress": 1.0 if leg_index % 2 == 0 else 0.0,
			"opened": false,
			"inside": false,
			"captured": false,
			"entry_count": 0,
			"best_observed_us": NO_ENDPOINT_OBSERVATION_US,
			"best_error_us": NO_ENDPOINT_OBSERVATION_US,
			"grade": GameplayTypes.JudgmentGrade.MISS,
			"finalized": false,
		})
	return result


func _process_timeline_event(event: Dictionary) -> void:
	match StringName(event["kind"]):
		&"field_enter":
			var was_empty: bool = _active_field_ids.is_empty()
			_active_field_ids[str(event["field_id"])] = true
			if was_empty:
				_reset_values_to_base()
				_queue_frequency_change(int(event["time_us"]))
		&"field_exit":
			_active_field_ids.erase(str(event["field_id"]))
			if (
				_active_field_ids.is_empty()
				and not _has_pending_slider_window(int(event["time_us"]))
			):
				_reset_values_to_base()
				_queue_frequency_change(int(event["time_us"]))
		&"slider_begin":
			_begin_slider(int(event["state_index"]), int(event["time_us"]))
		&"slider_finish":
			_finish_slider(int(event["state_index"]), int(event["time_us"]))
		&"endpoint_open":
			_open_endpoint(int(event["state_index"]), int(event["endpoint_index"]))
		&"endpoint_finalize":
			_finalize_endpoint(int(event["state_index"]), int(event["endpoint_index"]))


func _begin_slider(state_index: int, time_us: int) -> void:
	if state_index < 0 or state_index >= _slider_states.size():
		return
	var slider: Dictionary = _slider_states[state_index]["slider"]
	_slider_states[state_index]["started"] = true
	_clear_drag_state(int(slider["affinity"]), false)
	var start_value: float = clampf(float(slider["start_value"]), 0.0, 1.0)
	if int(slider["affinity"]) == GameplayTypes.Affinity.XUAN:
		_death_value = start_value
	else:
		_life_value = start_value
	_queue_frequency_change(time_us)


func _open_endpoint(state_index: int, endpoint_index: int) -> void:
	if state_index < 0 or state_index >= _slider_states.size():
		return
	var state: Dictionary = _slider_states[state_index]
	var endpoints: Array = state["endpoint_states"]
	if endpoint_index < 0 or endpoint_index >= endpoints.size():
		return
	var endpoint: Dictionary = endpoints[endpoint_index]
	var slider: Dictionary = state["slider"]
	state["traversal_index"] = int(endpoint["leg_index"])
	if endpoint_index > 0:
		# 旧程 endpoint_finalize 优先执行；此后才解除旧接合，再由当前向量接合新程。
		# 每程等价于独立条：频率值重置到本程起点，进度从 0 重新开始；摇杆为零
		# 时保持未接合，非零向量可立即接合新程，不要求先回中。
		_clear_stick_drag_state(int(slider["affinity"]), false)
		var traversal_start_value: float = float(slider["start_value"]) if int(endpoint["leg_index"]) % 2 == 0 else float(slider["end_value"])
		_set_stick_side_value(int(slider["affinity"]), traversal_start_value, int(endpoint["leg_start_us"]))
	# _record_endpoint_entries 可能在边界输入时提前建立 inside 观察。
	# 观察是否已打开不能阻止微秒时间线切换 traversal 和清理旧接合。
	if bool(endpoint["opened"]):
		return
	var player_progress: float = _value_to_slider_progress(
		slider,
		_value_for_affinity(int(slider["affinity"]))
	)
	endpoint["opened"] = true
	endpoint["inside"] = _inside_endpoint_capture(player_progress, float(endpoint["target_progress"]))


func _finalize_endpoint(state_index: int, endpoint_index: int) -> void:
	if state_index < 0 or state_index >= _slider_states.size():
		return
	var state: Dictionary = _slider_states[state_index]
	var endpoints: Array = state["endpoint_states"]
	if endpoint_index < 0 or endpoint_index >= endpoints.size():
		return
	var endpoint: Dictionary = endpoints[endpoint_index]
	var slider: Dictionary = state["slider"]
	var affinity: int = int(slider["affinity"])
	var player_progress: float = _value_to_slider_progress(
		slider,
		_value_for_affinity(affinity)
	)
	var is_inside: bool = _inside_endpoint_capture(
		player_progress,
		float(endpoint["target_progress"])
	)
	var is_held: bool = _last_life_held if affinity == GameplayTypes.Affinity.ZHU else _last_death_held
	var qualified: bool = is_inside and is_held
	endpoint["inside"] = is_inside
	endpoint["captured"] = qualified
	endpoint["grade"] = (
		GameplayTypes.JudgmentGrade.PERFECT
		if qualified
		else GameplayTypes.JudgmentGrade.MISS
	)
	if qualified:
		endpoint["best_observed_us"] = int(endpoint["target_us"])
		endpoint["best_error_us"] = 0
	else:
		endpoint["best_observed_us"] = NO_ENDPOINT_OBSERVATION_US
		endpoint["best_error_us"] = NO_ENDPOINT_OBSERVATION_US
	endpoint["finalized"] = true


func _record_endpoint_entries(
		affinity: int,
		previous_value: float,
		current_value: float,
		time_us: int
) -> void:
	## 行程中只维护玩家是否位于端点区以及进入次数；成功与否只在 target_us 结算。
	for state: Dictionary in _slider_states:
		if bool(state["finished"]):
			continue
		var slider: Dictionary = state["slider"]
		if int(slider["affinity"]) != affinity:
			continue
		var previous_progress: float = _value_to_slider_progress(slider, previous_value)
		var current_progress: float = _value_to_slider_progress(slider, current_value)
		var endpoints: Array = state["endpoint_states"]
		for endpoint_value: Variant in endpoints:
			var endpoint: Dictionary = endpoint_value
			if bool(endpoint["finalized"]):
				continue
			if time_us < int(endpoint["leg_start_us"]) or time_us > int(endpoint["target_us"]):
				continue
			if not bool(endpoint["opened"]):
				endpoint["opened"] = true
				endpoint["inside"] = _inside_endpoint_capture(
					previous_progress,
					float(endpoint["target_progress"])
				)
			var is_inside: bool = _inside_endpoint_capture(
				current_progress,
				float(endpoint["target_progress"])
			)
			if is_inside and not bool(endpoint["inside"]):
				_record_endpoint_entry_transition(endpoint)
			endpoint["inside"] = is_inside


func _record_endpoint_entry_transition(endpoint: Dictionary) -> void:
	## 提前进入只作为运行时观察信息，不能锁存判定成绩或命中时间。
	endpoint["entry_count"] = int(endpoint["entry_count"]) + 1


func _inside_endpoint_capture(player_progress: float, target_progress: float) -> bool:
	return absf(player_progress - target_progress) <= (
		_rule_float(&"tuning_endpoint_capture_ratio", 0.03) + TRACKING_EPSILON
	)


func _endpoint_snapshots(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for endpoint_value: Variant in state["endpoint_states"]:
		var endpoint: Dictionary = endpoint_value
		var has_observation: bool = int(endpoint["best_observed_us"]) != NO_ENDPOINT_OBSERVATION_US
		result.append({
			"leg_index": int(endpoint["leg_index"]),
			"target_tick": int(endpoint["target_tick"]),
			"target_us": int(endpoint["target_us"]),
			"deadline_us": int(endpoint["deadline_us"]),
			"target_progress": float(endpoint["target_progress"]),
			"inside": bool(endpoint["inside"]),
			"captured": bool(endpoint["captured"]),
			"qualified": has_observation and int(endpoint["grade"]) != GameplayTypes.JudgmentGrade.MISS,
			"entry_count": int(endpoint["entry_count"]),
			"has_observation": has_observation,
			"best_observed_us": int(endpoint["best_observed_us"]) if has_observation else 0,
			"best_error_us": int(endpoint["best_error_us"]) if has_observation else 0,
			"grade": int(endpoint["grade"]),
			"finalized": bool(endpoint["finalized"]),
			"window_active": (
				_current_time_us >= int(endpoint["leg_start_us"])
				and _current_time_us <= int(endpoint["target_us"])
			),
		})
	return result


func _endpoint_index_for_time(state: Dictionary, time_us: int) -> int:
	var slider: Dictionary = state["slider"]
	return clampi(
		_slider_leg_at(slider, time_us),
		0,
		maxi(0, (state["endpoint_states"] as Array).size() - 1)
	)


func _finish_slider(state_index: int, finalized_at_us: int) -> void:
	if state_index < 0 or state_index >= _slider_states.size():
		return
	var state: Dictionary = _slider_states[state_index]
	if bool(state["finished"]):
		return
	state["grade"] = GameplayTypes.JudgmentGrade.PERFECT
	for endpoint_value: Variant in state["endpoint_states"]:
		var endpoint: Dictionary = endpoint_value
		state["grade"] = maxi(int(state["grade"]), int(endpoint["grade"]))
	state["finished"] = true
	_clear_drag_state(int(state["slider"]["affinity"]), false)
	_try_finalize_group(str(state["group_key"]), finalized_at_us)
	if _active_field_ids.is_empty() and not _has_pending_slider_window(finalized_at_us):
		_reset_values_to_base()
		_queue_frequency_change(finalized_at_us)


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
		var side_metadata: Dictionary = {
			"event_id": str(state["event_id"]),
		}

		var endpoint_metadata: Array[Dictionary] = []
		for endpoint_value: Variant in state["endpoint_states"]:
			var endpoint: Dictionary = endpoint_value
			var observed_us: int = int(endpoint["best_observed_us"])
			if observed_us == NO_ENDPOINT_OBSERVATION_US:
				observed_us = int(endpoint["deadline_us"]) + 1
			var endpoint_kind: StringName = (
				&"life_endpoint"
				if affinity == GameplayTypes.Affinity.ZHU
				else &"death_endpoint"
			)
			var endpoint_component := JudgmentComponentRecord.timing(
				endpoint_kind,
				int(endpoint["target_tick"]),
				int(endpoint["target_us"]),
				observed_us,
				int(endpoint["grade"])
			)
			endpoint_component.metadata = {
				"event_id": str(state["event_id"]),
				"leg_index": int(endpoint["leg_index"]),
				"captured": bool(endpoint["captured"]),
				"entry_count": int(endpoint["entry_count"]),
			}
			record.components.append(endpoint_component)
			endpoint_metadata.append(endpoint_component.to_dictionary())

		var side_key: String = "life" if affinity == GameplayTypes.Affinity.ZHU else "death"
		side_metadata["endpoints"] = endpoint_metadata
		side_data[side_key] = side_metadata
	record.metadata = {"sides": side_data}
	record.recompute_grade()
	_group_grades[group_key] = record.grade
	_pending_records.append(record)


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


func _required_rotation_sign(slider: Dictionary, time_us: int) -> int:
	if time_us < int(slider["start_us"]):
		return 0
	var value_delta: float = float(slider["end_value"]) - float(slider["start_value"])
	if is_zero_approx(value_delta):
		return 0
	var traversal_ticks: int = maxi(1, int(slider["traversal_ticks"]))
	var traversal_count: int = maxi(1, int(slider["traversal_count"]))
	var current_tick: int = _compiled.tempo_map.us_to_tick_rounded(time_us)
	var elapsed_ticks: int = maxi(0, current_tick - int(slider["tick"]))
	var traversal_index: int = mini(
		traversal_count - 1,
		floori(float(elapsed_ticks) / float(traversal_ticks))
	)
	var frequency_direction: int = 1 if value_delta > 0.0 else -1
	# required_rotation_sign 描述玩家看到的物理摇杆旋向，而不是频率轴正负。
	# 生槽是上弧：顺时针向右即升频；死槽是中心对称的下弧：顺时针向左即降频。
	var visual_mirror: int = -1 if int(slider["affinity"]) == GameplayTypes.Affinity.XUAN else 1
	var direction: int = frequency_direction * visual_mirror
	return direction if traversal_index % 2 == 0 else -direction


func _guide_band(slider: Dictionary, time_us: int) -> Vector2:
	var window_us: int = _rule_int(&"tuning_guide_time_window_ms", 250) * 1000
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
	var margin: float = _rule_float(&"tuning_spatial_margin", 0.12)
	var minimum: float = values[0]
	var maximum: float = values[0]
	for value: float in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return Vector2(clampf(minimum - margin, 0.0, 1.0), clampf(maximum + margin, 0.0, 1.0))


## 对一侧的真实旋转只做有限行程和端点捕获。
## 点状时间引导不参与这段计算，因此相同角位移在任何时刻都会产生相同频率变化。
func _apply_side_displacement(
		affinity: int,
		current_value: float,
		raw_delta: float,
		time_us: int
) -> float:
	if is_zero_approx(raw_delta):
		return current_value
	var state_index: int = _active_slider_state_index(affinity, time_us)
	if state_index < 0:
		# 计分滑条已进入缩圈预备期时，这一侧暂停自由调频。另一侧若没有
		# 预备目标，仍可在同一场域内独立调频。
		if _has_preview_slider_for_side(affinity, time_us):
			return current_value
		return clampf(current_value + raw_delta, 0.0, 1.0)

	var slider: Dictionary = _slider_states[state_index]["slider"]
	_pointer_drags[affinity] = {
		"event_id": str(slider["event_id"]),
		"traversal": _slider_leg_at(slider, time_us),
	}
	var start_value: float = float(slider["start_value"])
	var end_value: float = float(slider["end_value"])
	var span: float = end_value - start_value
	if absf(span) <= 0.000001:
		return current_value

	# 自由调频可能让频率在滑条开始前落到本条行程之外。只能按真实位移
	# 逐步转回；向更外侧旋转会被挡住，绝不能直接吸到最近边界。
	var lower_value: float = minf(start_value, end_value)
	var upper_value: float = maxf(start_value, end_value)
	if current_value < lower_value - TRACKING_EPSILON:
		if raw_delta <= 0.0:
			return current_value
		return clampf(current_value + raw_delta, 0.0, upper_value)
	if current_value > upper_value + TRACKING_EPSILON:
		if raw_delta >= 0.0:
			return current_value
		return clampf(current_value + raw_delta, lower_value, 1.0)

	# 端点最后 3% 只负责记录到达，不再磁吸或篡改真实旋转量。
	return clampf(current_value + raw_delta, lower_value, upper_value)


func _active_slider_state_index(affinity: int, time_us: int) -> int:
	# 同侧谱面不应真实重叠；如果预览数据仍有重叠，稳定地取编译排序后的第一条。
	for index: int in range(_slider_states.size()):
		var state: Dictionary = _slider_states[index]
		if bool(state["finished"]):
			continue
		var slider: Dictionary = state["slider"]
		if int(slider["affinity"]) != affinity:
			continue
		if time_us >= int(slider["start_us"]) and time_us <= int(state["judgment_end_us"]):
			return index
	return -1


func _has_pending_slider_window(time_us: int) -> bool:
	for state: Dictionary in _slider_states:
		if bool(state["finished"]):
			continue
		var slider: Dictionary = state["slider"]
		if time_us >= int(slider["start_us"]) and time_us <= int(state["judgment_end_us"]):
			return true
	return false


func _has_preview_slider_for_side(affinity: int, time_us: int) -> bool:
	var preview_lead_us: int = roundi(
		maxf(_rule_float(&"approach_duration_sec", 2.25), 0.0) * 1_000_000.0
	)
	for state: Dictionary in _slider_states:
		if bool(state["finished"]):
			continue
		var slider: Dictionary = state["slider"]
		if int(slider["affinity"]) != affinity:
			continue
		var start_us: int = int(slider["start_us"])
		if time_us >= start_us - preview_lead_us and time_us < start_us:
			return true
	return false


func _slider_leg_at(slider: Dictionary, time_us: int) -> int:
	var traversal_ticks: int = maxi(1, int(slider["traversal_ticks"]))
	var traversal_count: int = maxi(1, int(slider["traversal_count"]))
	var total_ticks: int = traversal_ticks * traversal_count
	var current_tick: int = clampi(
		_compiled.tempo_map.us_to_tick_rounded(time_us),
		int(slider["tick"]),
		int(slider["tick"]) + total_ticks
	)
	var elapsed_ticks: int = current_tick - int(slider["tick"])
	# 折返完全由谱面强拍决定：一旦跨过行程边界，就不再接受旧旋向“补走”。
	return mini(traversal_count - 1, elapsed_ticks / traversal_ticks)


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
		_rule_float(&"tuning_min_frequency_hz", 1.0),
		_rule_float(&"tuning_max_frequency_hz", 7.0),
		clampf(value, 0.0, 1.0)
	)


func _base_value() -> float:
	var minimum: float = _rule_float(&"tuning_min_frequency_hz", 1.0)
	var maximum: float = _rule_float(&"tuning_max_frequency_hz", 7.0)
	var base: float = _rule_float(&"tuning_base_frequency_hz", 3.0)
	return clampf(inverse_lerp(minimum, maximum, base), 0.0, 1.0)


func _reset_values_to_base() -> void:
	_life_value = _base_value()
	_death_value = _base_value()


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


## 同步双 Hold 运行时前置条件；失效只中断调频，不修改 Hold 判定。
func set_dual_holding_notes(active: bool, timestamp_us: int) -> void:
	if _dual_holding_notes == active:
		return
	_dual_holding_notes = active
	if not active:
		reset_side_progress(GameplayTypes.Affinity.ZHU, timestamp_us)
		reset_side_progress(GameplayTypes.Affinity.XUAN, timestamp_us)


## 拖动资格来源于实际接合/指针操作，保持静止仍为 true；换条换程不继承。
func _is_slider_dragging(slider: Dictionary) -> bool:
	if not _dual_holding_notes or _paused_for_rearm:
		return false
	var affinity: int = int(slider["affinity"])
	var life: bool = affinity == GameplayTypes.Affinity.ZHU
	var traversal: int = _slider_leg_at(slider, _current_time_us)
	var pointer: Dictionary = _pointer_drags.get(affinity, {})
	if str(pointer.get("event_id", "")) == str(slider["event_id"]) and int(pointer.get("traversal", -1)) == traversal:
		return true
	var index: int = _life_drag_state_index if life else _death_drag_state_index
	var engaged: bool = _life_tuning_engaged if life else _death_tuning_engaged
	var leg: int = _life_drag_traversal_index if life else _death_drag_traversal_index
	return engaged and index >= 0 and str(_slider_states[index]["slider"]["event_id"]) == str(slider["event_id"]) and leg == int(_slider_states[index]["traversal_index"])
