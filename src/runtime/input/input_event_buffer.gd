extends Node

## 接收物理输入并维护标准化事件缓冲。
## 同一逻辑帧内，同类查询始终返回该类最老事件；帧尾按策略统一删除。

signal physical_input_emitted(event: PhysicalInputEvent)
signal held_state_changed(life_held: bool, death_held: bool)
signal cancelled(reason: int)
signal pause_requested

@export var pre_input_window_us: int = 0
@export var delete_all_same_kind: bool = true

var _events: Array[PhysicalInputEvent] = []
var _event_counts: PackedInt32Array = PackedInt32Array()
var _requested_flags: PackedByteArray = PackedByteArray()
var _frame_oldest_events: Array[PhysicalInputEvent] = []
var _frame_time_us: int = 0
var _input_enabled: bool = true
var _session_active: bool = false

const TUNING_ARC_GEOMETRY: GDScript = preload("res://src/domain/tuning/tuning_arc_geometry.gd")

enum InputMode {
	DISABLED,
	GAMEPLAY,
	RESUME_REARM,
	REPLAY,
}

enum CancelReason {
	PAUSE,
	FOCUS_LOST,
	DEVICE_DISCONNECTED,
	MODAL_OPENED,
	RETRY,
	SESSION_END,
}

const ACTION_LIFE: StringName = &"bell_life"
const ACTION_DEATH: StringName = &"bell_death"
const ACTION_PAUSE: StringName = &"pause_game"

## 这些动作保留给项目设置和改键界面识别两根摇杆的横轴；旋钮计算会直接读取
## 每根摇杆完整的 X/Y，不能再把横轴动作当成持续速度。
const ACTION_DEATH_TUNE_LEFT: StringName = &"tune_death_left"
const ACTION_DEATH_TUNE_RIGHT: StringName = &"tune_death_right"
const ACTION_LIFE_TUNE_LEFT: StringName = &"tune_life_left"
const ACTION_LIFE_TUNE_RIGHT: StringName = &"tune_life_right"

# 两条滑槽在画面中中心对称：生槽位于上弧，死槽位于下弧。因此相同的视觉
# 顺时针手势在两侧应产生相反的频率变化，玩家才能沿屏幕上的弧线自然转动。
const LIFE_ROTARY_FREQUENCY_SIGN: float = 1.0
const DEATH_ROTARY_FREQUENCY_SIGN: float = -1.0
## 鼠标或触屏每横移一个设计像素，对应多少归一化频率轴位移。
## 它由“频率范围 × 每 Hz 像素数”推导，不能在设备层另设一套手感参数。
var pointer_displacement_per_pixel: float = 0.0
## 自由调频时，摇杆旋转一弧度对应多少归一化频率轴位移。
## 计分滑条改用自身等效圆弧，不读取这个全局倍率。
var rotary_displacement_per_radian: float = 0.0
## 最近一次实际发出的双路调频位移，仅供调试 HUD 查看，不代表持续速度。
var last_tuning_displacement: Vector2 = Vector2.ZERO

var mode: InputMode = InputMode.DISABLED
## 两个布尔值代表所有物理来源合并后的按住状态，而不是某一颗具体按键。
var life_held: bool = false
var death_held: bool = false
var _clock: SongClock
## 当前关卡唯一的调频规则来源；未装载关卡时使用 GameplayRuleSet 的标准默认值。
var _tuning_rules: GameplayRuleSet
var _sequence: int = 0
## 只有谱面声明的调频段会打开此门；门外摇杆和拖动不会改变频率。
var _tuning_capture_requested: bool = false

## 同一口钟可能同时被键盘、鼠标或多根手指按住。使用来源集合可避免松开其中一个
## 就错误地结束另一来源仍在维持的 Hold 或载波。
var _life_sources: Dictionary = {}
var _death_sources: Dictionary = {}
var _touch_affinity_by_index: Dictionary = {}
var _mouse_life_held: bool = false
var _mouse_death_held: bool = false
var _gamepad_life_devices: Dictionary = {}
var _gamepad_death_devices: Dictionary = {}
var _life_rotary_device: int = -1
var _death_rotary_device: int = -1
var _life_rotary_tracker := RotaryStickTracker.new()
var _death_rotary_tracker := RotaryStickTracker.new()
## 生、死两侧当前可操作滑条的精确圆心角。未来预读条只显示，不进入这里。
## 没有计分滑条时退回各自半圆，供自由调频。
var _life_rotary_window_sweep_rad: float = PI
var _death_rotary_window_sweep_rad: float = PI
## 用事件 ID 识别滑条切换；新条出现时重新定锚，不能继承上一条最后一帧的角度。
var _life_rotary_window_event_id: String = ""
var _death_rotary_window_event_id: String = ""
## 非空时表示当前是计分滑条；字典中的起终值负责把 progress 增量还原成频率轴位移。
var _life_rotary_slider: Dictionary = {}
var _death_rotary_slider: Dictionary = {}
## PREVIEW 阶段已经知道滑条几何，但直到权威起点才允许产生位移。
var _life_rotary_input_open: bool = true
var _death_rotary_input_open: bool = true
## 未来滑条只负责画面预读，不会交给摇杆 Tracker；但其预备期仍需阻止鼠标、
## 触屏和自由旋转提前改变这一侧的起始频率。
var _life_tuning_preview_blocked: bool = false
var _death_tuning_preview_blocked: bool = false

var _mouse_captured_by_router: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_event_counts.resize(GameplayTypes.PhysicalInputKind.ENUM_MAX)
	_requested_flags.resize(GameplayTypes.PhysicalInputKind.ENUM_MAX)
	_frame_oldest_events.resize(GameplayTypes.PhysicalInputKind.ENUM_MAX)
	for index in range(GameplayTypes.PhysicalInputKind.ENUM_MAX):
		_event_counts[index] = 0
		_requested_flags[index] = 0
		_frame_oldest_events[index] = null
	if _tuning_rules == null:
		configure_from_rules(GameplayRuleSet.new())
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func begin_frame(current_time_us: int) -> void:
	_frame_time_us = current_time_us
	for index in range(GameplayTypes.PhysicalInputKind.ENUM_MAX):
		_requested_flags[index] = 0
		_frame_oldest_events[index] = null


func query(kind: int) -> Dictionary:
	if kind < 0 or kind >= GameplayTypes.PhysicalInputKind.ENUM_MAX:
		return {"exists": false, "event": null, "count": 0}
	var cached: PhysicalInputEvent = _frame_oldest_events[kind]
	if cached != null:
		return {"exists": true, "event": cached, "count": _event_counts[kind]}
	for sample in _events:
		if sample.kind == kind:
			_frame_oldest_events[kind] = sample
			_requested_flags[kind] = 1
			return {"exists": true, "event": sample, "count": _event_counts[kind]}
	return {"exists": false, "event": null, "count": 0}


func end_frame() -> void:
	for kind in range(GameplayTypes.PhysicalInputKind.ENUM_MAX):
		if _requested_flags[kind] == 0:
			continue
		if delete_all_same_kind:
			var index: int = _events.size() - 1
			while index >= 0:
				if _events[index].kind == kind:
					_remove_event_at(index)
				index -= 1
		else:
			for index in range(_events.size()):
				if _events[index].kind == kind:
					_remove_event_at(index)
					break
		_requested_flags[kind] = 0
		_frame_oldest_events[kind] = null
	var cutoff: int = _frame_time_us - maxi(pre_input_window_us, 0)
	while not _events.is_empty() and _events[0].timestamp_us < cutoff:
		_remove_event_at(0)


func begin_session() -> void:
	clear()
	_session_active = true
	_input_enabled = true


func end_session() -> void:
	clear()
	cancel_all(CancelReason.SESSION_END, false)
	_session_active = false
	_input_enabled = false


func clear() -> void:
	_events.clear()
	for index in range(GameplayTypes.PhysicalInputKind.ENUM_MAX):
		_event_counts[index] = 0
		_requested_flags[index] = 0
		_frame_oldest_events[index] = null


func set_pre_input_window_us(value: int) -> void:
	pre_input_window_us = maxi(value, 0)


func set_delete_all_same_kind(enabled: bool) -> void:
	delete_all_same_kind = enabled


func has_input(kind: int) -> bool:
	return kind >= 0 and kind < _event_counts.size() and _event_counts[kind] > 0


func get_event_count(kind: int) -> int:
	if kind < 0 or kind >= _event_counts.size():
		return 0
	return _event_counts[kind]


func get_buffer_size() -> int:
	return _events.size()


func inject_physical_event(sample: PhysicalInputEvent) -> void:
	if sample == null:
		return
	_enqueue_sample(sample)
	physical_input_emitted.emit(sample)


func _enqueue_sample(sample: PhysicalInputEvent) -> void:
	var index: int = _events.size()
	while index > 0 and PhysicalInputEvent.sort_events(sample, _events[index - 1]):
		index -= 1
	_events.insert(index, sample)
	_event_counts[sample.kind] += 1


func _remove_event_at(index: int) -> void:
	var sample: PhysicalInputEvent = _events[index]
	_events.remove_at(index)
	_event_counts[sample.kind] -= 1


func _process(_delta: float) -> void:
	if mode not in [InputMode.GAMEPLAY, InputMode.RESUME_REARM]:
		return
	# 物理事件偶尔会在失焦、鼠标捕获切换或 UI 抢占时丢失；InputMap 的聚合状态
	# 只负责补齐按住/松开，不会重复触发一次敲击。
	_reconcile_mapped_holds()
	if mode == InputMode.GAMEPLAY and _tuning_capture_requested:
		_poll_gamepad_rotation()


func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)
	_restore_mouse_mode()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_all(CancelReason.FOCUS_LOST)


func bind_clock(clock: SongClock) -> void:
	_clock = clock


func configure_from_rules(rules: GameplayRuleSet) -> void:
	## 设备层与判定层共用同一份频率尺度，最终都输出完整频率轴上的归一化位移。
	if rules == null:
		return
	_tuning_rules = rules
	var frequency_range_hz: float = maxf(
		rules.tuning_max_frequency_hz - rules.tuning_min_frequency_hz,
		0.001
	)
	var frequency_axis_length_px: float = frequency_range_hz * maxf(rules.tuning_pixels_per_hz, 0.001)
	pointer_displacement_per_pixel = 1.0 / frequency_axis_length_px
	rotary_displacement_per_radian = maxf(rules.tuning_hz_per_revolution, 0.001) / (TAU * frequency_range_hz)
	# 规则热重载可能改变同一事件对应的圆心角，强制下一帧按新窗口重新定锚。
	_life_rotary_window_event_id = ""
	_death_rotary_window_event_id = ""
	_life_rotary_window_sweep_rad = PI
	_death_rotary_window_sweep_rad = PI
	_life_rotary_slider.clear()
	_death_rotary_slider.clear()
	_life_rotary_input_open = true
	_death_rotary_input_open = true
	_life_tuning_preview_blocked = false
	_death_tuning_preview_blocked = false
	_life_rotary_tracker.disable_finite_arc()
	_death_rotary_tracker.disable_finite_arc()
	_reset_rotary_trackers()


func set_mode(next_mode: InputMode) -> void:
	if mode == next_mode:
		return
	mode = next_mode
	if mode == InputMode.DISABLED or mode == InputMode.REPLAY:
		cancel_all(CancelReason.MODAL_OPENED, false)
	# 暂停菜单出现时必须把鼠标还给 UI；恢复玩法后，如果仍处于调频场，再重新捕获。
	# RESUME_REARM 期间的按住状态由 _process() 对账，不需要抢走按钮的点击事件。
	_update_mouse_capture()
	set_process_input(mode != InputMode.REPLAY)


func set_tuning_capture_active(active: bool, _initial_value: Vector2 = Vector2.ZERO) -> void:
	if _tuning_capture_requested == active:
		return
	_tuning_capture_requested = active
	# 新调频段不继承门外旋转；首帧只记录当前杆向，必须继续转动才会产生位移。
	_reset_rotary_trackers()
	if active:
		# 场域可能在本帧输入轮询之后开启。立即用当前杆向定锚，避免下一帧才接合
		# 而吞掉玩家刚开始转动的第一小段弧。
		_prime_rotary_trackers()
	last_tuning_displacement = Vector2.ZERO
	_update_mouse_capture()


func set_tuning_gesture_windows(raw_sliders: Variant) -> void:
	## 每侧只把当前可操作事件交给摇杆 Tracker。未来事件可以同时在画面预读，
	## 但绝不能抢走当前事件的手势会话，也不能提前吸收玩家输入。
	var life_slider: Dictionary = {}
	var death_slider: Dictionary = {}
	var life_preview_blocked: bool = false
	var death_preview_blocked: bool = false
	if raw_sliders is Array:
		for raw_state: Variant in raw_sliders:
			if not raw_state is Dictionary:
				continue
			var state: Dictionary = raw_state
			var affinity: int = int(state.get("affinity", GameplayTypes.Affinity.ZHU))
			var is_life: bool = affinity == GameplayTypes.Affinity.ZHU
			if not bool(state.get("interaction_open", true)):
				if is_life:
					life_preview_blocked = true
				else:
					death_preview_blocked = true
				continue
			if (is_life and not life_slider.is_empty()) or (not is_life and not death_slider.is_empty()):
				continue
			var event_id: String = str(state.get("event_id", state.get("id", "")))
			if event_id.is_empty():
				continue
			var slider: Dictionary = state.duplicate(true)
			slider["event_id"] = event_id
			slider["gesture_sweep_rad"] = TUNING_ARC_GEOMETRY.equivalent_sweep_rad(
				float(state.get("start_value", 0.0)),
				float(state.get("end_value", 1.0)),
				_tuning_rules.tuning_min_frequency_hz,
				_tuning_rules.tuning_max_frequency_hz,
				_tuning_rules.tuning_pixels_per_hz,
				_tuning_rules.wave_canvas_size.x
			)
			if is_life:
				life_slider = slider
			else:
				death_slider = slider
	_set_rotary_gesture_window(true, life_slider)
	_set_rotary_gesture_window(false, death_slider)
	_life_tuning_preview_blocked = life_preview_blocked
	_death_tuning_preview_blocked = death_preview_blocked


func tuning_gesture_window_snapshot() -> Dictionary:
	## 仅供调试 HUD 和自动测试检查“画出来的弧”与“实际手势弧”是否一致。
	## capture_start/end 按操作方向排列：前者是起点前的容错边，后者是轨道内的容错边。
	return {
		"life": _rotary_gesture_debug_snapshot(
			GameplayTypes.Affinity.ZHU,
			_life_rotary_window_event_id,
			_life_rotary_window_sweep_rad,
			_life_rotary_slider
		),
		"death": _rotary_gesture_debug_snapshot(
			GameplayTypes.Affinity.XUAN,
			_death_rotary_window_event_id,
			_death_rotary_window_sweep_rad,
			_death_rotary_slider
		),
	}


func _rotary_gesture_debug_snapshot(
		affinity: int,
		event_id: String,
		sweep_rad: float,
		slider: Dictionary
) -> Dictionary:
	var rotation_sign: int = int(slider.get("base_rotation_sign", 0))
	var rotation_offset_rad: float = deg_to_rad(float(slider.get("arc_rotation_deg", 0.0)))
	var directed_angles: Vector2 = TUNING_ARC_GEOMETRY.symmetric_directed_angles(
		affinity,
		rotation_sign,
		sweep_rad,
		rotation_offset_rad
	)
	var capture_angles: Vector2 = TUNING_ARC_GEOMETRY.start_window_angles(
		affinity,
		rotation_sign,
		sweep_rad,
		TUNING_ARC_GEOMETRY.DEFAULT_START_WINDOW_EARLY_RAD,
		TUNING_ARC_GEOMETRY.DEFAULT_START_WINDOW_LATE_RAD,
		rotation_offset_rad
	)
	return {
		"event_id": event_id,
		"center_angle_rad": TUNING_ARC_GEOMETRY.center_angle_rad(affinity, rotation_offset_rad),
		"arc_sweep_rad": sweep_rad,
		"rotation_sign": rotation_sign,
		"start_angle_rad": directed_angles.x,
		"end_angle_rad": directed_angles.y,
		"capture_start_angle_rad": capture_angles.x,
		"capture_end_angle_rad": capture_angles.y,
	}


func get_held_snapshot() -> Dictionary:
	return {
		"life_held": life_held,
		"death_held": death_held,
		"life_a_held": _life_sources.has("bell:life:a"),
		"life_b_held": _life_sources.has("bell:life:b"),
		"death_a_held": _death_sources.has("bell:death:a"),
		"death_b_held": _death_sources.has("bell:death:b"),
		"last_tuning_displacement": last_tuning_displacement,
	}


func reset_for_run() -> void:
	cancel_all(CancelReason.RETRY, false)
	_sequence = 0


func cancel_all(
		reason: CancelReason,
		emit_semantic_cancel: bool = true,
		clear_tuning_capture: bool = true
) -> void:
	var had_state: bool = life_held or death_held or not last_tuning_displacement.is_zero_approx()
	_life_sources.clear()
	_death_sources.clear()
	_touch_affinity_by_index.clear()
	_gamepad_life_devices.clear()
	_gamepad_death_devices.clear()
	_mouse_life_held = false
	_mouse_death_held = false
	life_held = false
	death_held = false
	last_tuning_displacement = Vector2.ZERO
	_reset_rotary_trackers()
	if clear_tuning_capture:
		_tuning_capture_requested = false
		_life_rotary_window_event_id = ""
		_death_rotary_window_event_id = ""
		_life_rotary_window_sweep_rad = PI
		_death_rotary_window_sweep_rad = PI
		_life_rotary_slider.clear()
		_death_rotary_slider.clear()
		_life_rotary_input_open = true
		_death_rotary_input_open = true
		_life_tuning_preview_blocked = false
		_death_tuning_preview_blocked = false
		_life_rotary_tracker.disable_finite_arc()
		_death_rotary_tracker.disable_finite_arc()
		_restore_mouse_mode()
	else:
		# 手柄断连只清设备状态，谱面当前开放的调频场仍然有效；
		# 玩家可立即改用键鼠，或在手柄重连后继续本段调频。
		_update_mouse_capture()
	held_state_changed.emit(false, false)

	if emit_semantic_cancel and mode != InputMode.REPLAY and (_clock != null or had_state):
		_emit_physical_event(GameplayTypes.PhysicalInputKind.FOCUS_CANCELLED)
	cancelled.emit(int(reason))

func _input(event: InputEvent) -> void:
	if not _input_enabled or mode == InputMode.DISABLED or mode == InputMode.REPLAY:
		return

	if event.is_action_pressed(ACTION_PAUSE) and not event.is_echo():
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if mode == InputMode.RESUME_REARM:
		# 暂停层位于 gameplay 之上。鼠标点击必须继续传给 Control/Button，
		# 不能被左右钟的玩法映射提前标记为 handled。
		return
	if _is_cancelled_pointer_event(event):
		# 系统取消不是玩家主动松键，统一走取消语义，避免误判 Hold 尾部。
		cancel_all(CancelReason.FOCUS_LOST)
		get_viewport().set_input_as_handled()
		return

	# 触屏需要按 finger index 保留上下半屏的归属，必须先于通用动作映射处理。
	if _handle_touch_event(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_bell_event(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_tune_event(event):
		get_viewport().set_input_as_handled()


func _handle_bell_event(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_LEFT and key_event.pressed:
			_emit_physical_event(GameplayTypes.PhysicalInputKind.KEY_LEFT_PRESSED, KEY_LEFT, 0.0, Vector2.ZERO, Vector2.ZERO, -1, key_event.device)
			_set_bell_source(false, "bell:death:b", true)
			return true
		if key_event.keycode == KEY_LEFT and not key_event.pressed:
			_emit_physical_event(GameplayTypes.PhysicalInputKind.KEY_LEFT_RELEASED, KEY_LEFT, 0.0, Vector2.ZERO, Vector2.ZERO, -1, key_event.device)
			_set_bell_source(false, "bell:death:b", false)
			return true
		if key_event.keycode == KEY_RIGHT and key_event.pressed:
			_emit_physical_event(GameplayTypes.PhysicalInputKind.KEY_RIGHT_PRESSED, KEY_RIGHT, 0.0, Vector2.ZERO, Vector2.ZERO, -1, key_event.device)
			_set_bell_source(true, "bell:life:b", true)
			return true
		if key_event.keycode == KEY_RIGHT and not key_event.pressed:
			_emit_physical_event(GameplayTypes.PhysicalInputKind.KEY_RIGHT_RELEASED, KEY_RIGHT, 0.0, Vector2.ZERO, Vector2.ZERO, -1, key_event.device)
			_set_bell_source(true, "bell:life:b", false)
			return true

	if event.is_action_pressed(ACTION_LIFE):
		var life_pressed_kind: int = _bell_kind(event, true)
		if life_pressed_kind >= 0:
			_emit_physical_event(life_pressed_kind, _event_code(event), 0.0, Vector2.ZERO, Vector2.ZERO, -1, event.device)
		_set_bell_source(true, _bell_source_key(life_pressed_kind), true)
		# 先建立按住语义，再捕获已经处于起点窗内的摇杆；这样首帧位移不会因
		# 领域层尚未收到对应 A/B 按下语义而丢失。
		_track_device_hold(event, true, true)
		return true
	if event.is_action_released(ACTION_LIFE):
		var life_released_kind: int = _bell_kind(event, false)
		if life_released_kind >= 0:
			_emit_physical_event(life_released_kind, _event_code(event), 0.0, Vector2.ZERO, Vector2.ZERO, -1, event.device)
		_track_device_hold(event, true, false)
		_set_bell_source(true, _bell_source_key(life_released_kind), false)
		return true
	if event.is_action_pressed(ACTION_DEATH):
		var death_pressed_kind: int = _bell_kind(event, true)
		if death_pressed_kind >= 0:
			_emit_physical_event(death_pressed_kind, _event_code(event), 0.0, Vector2.ZERO, Vector2.ZERO, -1, event.device)
		_set_bell_source(false, _bell_source_key(death_pressed_kind), true)
		_track_device_hold(event, false, true)
		return true
	if event.is_action_released(ACTION_DEATH):
		var death_released_kind: int = _bell_kind(event, false)
		if death_released_kind >= 0:
			_emit_physical_event(death_released_kind, _event_code(event), 0.0, Vector2.ZERO, Vector2.ZERO, -1, event.device)
		_track_device_hold(event, false, false)
		_set_bell_source(false, _bell_source_key(death_released_kind), false)
		return true
	return false


func _handle_touch_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var source_key := "touch:%d" % touch.index
		if touch.pressed:
			_emit_physical_event(GameplayTypes.PhysicalInputKind.TOUCH_PRESSED, touch.index, 0.0, touch.position, Vector2.ZERO, touch.index, touch.device)
			var is_life: bool = touch.position.y < get_viewport().get_visible_rect().size.y * 0.5
			_touch_affinity_by_index[touch.index] = GameplayTypes.Affinity.ZHU if is_life else GameplayTypes.Affinity.XUAN
			_set_bell_source(is_life, source_key, true)
		elif _touch_affinity_by_index.has(touch.index):
			_emit_physical_event(GameplayTypes.PhysicalInputKind.TOUCH_RELEASED, touch.index, 0.0, touch.position, Vector2.ZERO, touch.index, touch.device)
			var was_life: bool = int(_touch_affinity_by_index[touch.index]) == GameplayTypes.Affinity.ZHU
			_touch_affinity_by_index.erase(touch.index)
			_set_bell_source(was_life, source_key, false)
		return true

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touch_affinity_by_index.has(drag.index):
			return false
		if not _tuning_capture_requested:
			return true
		_emit_physical_event(
			GameplayTypes.PhysicalInputKind.TOUCH_MOVED,
			drag.index,
			0.0,
			drag.position,
			drag.relative,
			drag.index,
			drag.device
		)
		return true
	return false


func _handle_tune_event(event: InputEvent) -> bool:
	if not _tuning_capture_requested:
		return false

	if event is InputEventMouseMotion:
		var mouse_event := event as InputEventMouseMotion
		var move_life: bool = _mouse_life_held and life_held
		var move_death: bool = _mouse_death_held and death_held
		if not move_life and not move_death:
			return false
		# PC 只有一个鼠标：双键同时按住时，同一相对位移临时作用于两侧。
		if move_life or move_death:
			_emit_physical_event(GameplayTypes.PhysicalInputKind.MOUSE_MOVED, 0, 0.0, mouse_event.position, mouse_event.relative, -1, mouse_event.device)
		return true

	if event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		var death_axis: bool = joy_motion.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]
		var life_axis: bool = joy_motion.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
		# 真正的角度计算在 _process() 中一次读取完整二维向量；单独的轴事件只需截住，
		# 否则先到达的 X 或 Y 会制造不存在的四分之一圈跳变。
		if (
			(death_axis and _gamepad_death_devices.has(joy_motion.device))
			or (life_axis and _gamepad_life_devices.has(joy_motion.device))
		):
			var kind := GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED if death_axis else GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED
			var raw_stick := _read_stick(joy_motion.device, death_axis)
			_emit_joystick_event(kind, joy_motion.device, raw_stick)
			return true
		return false
	return false

func _set_bell_source(is_life: bool, source_key: String, pressed: bool) -> void:
	var sources: Dictionary = _life_sources if is_life else _death_sources
	var was_held: bool = life_held if is_life else death_held
	if pressed:
		sources[source_key] = true
	else:
		sources.erase(source_key)
	var is_held_now: bool = not sources.is_empty()
	if is_life:
		life_held = is_held_now
	else:
		death_held = is_held_now

	if was_held != is_held_now:
		held_state_changed.emit(life_held, death_held)
	_update_mouse_capture()


func _track_device_hold(event: InputEvent, is_life: bool, pressed: bool) -> void:
	if event is InputEventMouseButton:
		if is_life:
			_mouse_life_held = pressed
		else:
			_mouse_death_held = pressed
	elif event is InputEventJoypadButton:
		var joy_button := event as InputEventJoypadButton
		var shoulder: JoyButton = JOY_BUTTON_RIGHT_SHOULDER if is_life else JOY_BUTTON_LEFT_SHOULDER
		var stick_button: JoyButton = JOY_BUTTON_RIGHT_STICK if is_life else JOY_BUTTON_LEFT_STICK
		if joy_button.button_index not in [shoulder, stick_button]:
			return
		var device: int = joy_button.device
		var devices: Dictionary = _gamepad_life_devices if is_life else _gamepad_death_devices
		var was_present: bool = devices.has(device)
		if pressed:
			devices[device] = true
		elif not _gamepad_side_held(device, is_life):
			devices.erase(device)
		# 只在这个设备的持有状态真的改变时切换旋钮所有者。重复按键事件或
		# 非当前手柄的释放不能把正在使用的摇杆重置掉。
		if was_present != pressed:
			_refresh_rotary_owner(is_life)


func _reconcile_mapped_holds() -> void:
	_reconcile_gamepad_devices(_gamepad_life_devices, true)
	_reconcile_gamepad_devices(_gamepad_death_devices, false)
	if _mouse_life_held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_mouse_life_held = false
	if _mouse_death_held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_death_held = false
	_set_bell_source(true, "bell:life:a", Input.is_key_pressed(KEY_J) or _mouse_life_held or _any_joy_button_pressed(JOY_BUTTON_RIGHT_SHOULDER))
	_set_bell_source(true, "bell:life:b", Input.is_key_pressed(KEY_RIGHT) or _any_joy_button_pressed(JOY_BUTTON_RIGHT_STICK))
	_set_bell_source(false, "bell:death:a", Input.is_key_pressed(KEY_F) or _mouse_death_held or _any_joy_button_pressed(JOY_BUTTON_LEFT_SHOULDER))
	_set_bell_source(false, "bell:death:b", Input.is_key_pressed(KEY_LEFT) or _any_joy_button_pressed(JOY_BUTTON_LEFT_STICK))


func _reconcile_gamepad_devices(devices: Dictionary, is_life: bool) -> void:
	# 暂停、失焦或进入关卡前就已按住肩键时，不一定还能收到新的按下事件。
	# 每帧从已连接设备补回真实持有者，下一次摇杆采样先重新定锚，不补算旧旋转。
	for device: int in Input.get_connected_joypads():
		if _gamepad_side_held(device, is_life):
			devices[device] = true
	var removed_current_device: bool = false
	for raw_device: Variant in devices.keys():
		var device: int = int(raw_device)
		if _gamepad_side_held(device, is_life):
			continue
		devices.erase(raw_device)
		removed_current_device = removed_current_device or device == (
			_life_rotary_device if is_life else _death_rotary_device
		)
	if removed_current_device:
		if is_life:
			_life_rotary_tracker.reset()
			_life_rotary_device = -1
		else:
			_death_rotary_tracker.reset()
			_death_rotary_device = -1


func _gamepad_side_held(device: int, is_life: bool) -> bool:
	var shoulder: JoyButton = JOY_BUTTON_RIGHT_SHOULDER if is_life else JOY_BUTTON_LEFT_SHOULDER
	var stick_button: JoyButton = JOY_BUTTON_RIGHT_STICK if is_life else JOY_BUTTON_LEFT_STICK
	return Input.is_joy_button_pressed(device, shoulder) or Input.is_joy_button_pressed(device, stick_button)


func _any_joy_button_pressed(button: JoyButton) -> bool:
	for device: int in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(device, button):
			return true
	return false


func _bell_source_key(kind: int) -> String:
	match kind:
		GameplayTypes.PhysicalInputKind.KEY_J_PRESSED, GameplayTypes.PhysicalInputKind.KEY_J_RELEASED, GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_PRESSED, GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_R1_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_R1_RELEASED:
			return "bell:life:a"
		GameplayTypes.PhysicalInputKind.KEY_RIGHT_PRESSED, GameplayTypes.PhysicalInputKind.KEY_RIGHT_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_R3_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_R3_RELEASED:
			return "bell:life:b"
		GameplayTypes.PhysicalInputKind.KEY_F_PRESSED, GameplayTypes.PhysicalInputKind.KEY_F_RELEASED, GameplayTypes.PhysicalInputKind.MOUSE_LEFT_PRESSED, GameplayTypes.PhysicalInputKind.MOUSE_LEFT_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_L1_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_L1_RELEASED:
			return "bell:death:a"
		GameplayTypes.PhysicalInputKind.KEY_LEFT_PRESSED, GameplayTypes.PhysicalInputKind.KEY_LEFT_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_L3_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_L3_RELEASED:
			return "bell:death:b"
	return ""


func _poll_gamepad_rotation() -> void:
	var life_device: int = _first_held_device(_gamepad_life_devices)
	var death_device: int = _first_held_device(_gamepad_death_devices)
	_process_rotary_sticks(
		life_device,
		_read_stick(life_device, false),
		death_device,
		_read_stick(death_device, true)
	)


func _process_rotary_sticks(
		life_device: int,
		life_stick: Vector2,
		death_device: int,
		death_stick: Vector2
) -> void:
	# _update_rotary_side() 已经把计分弧或自由旋转统一换算成频率轴位移。
	# 两路直接组装，不能再做向量归一化或重复乘一次旋转倍率。
	var displacement := Vector2(
		_update_rotary_side(true, life_device, life_stick),
		_update_rotary_side(false, death_device, death_stick)
	)
	# 摇杆事件已经以绝对 X/Y 向量进入物理缓冲；这里仅维护历史追踪器，
	# 不再把角度变化量合成为调频输入事件。


func _update_rotary_side(is_life: bool, device: int, stick: Vector2) -> float:
	var previous_device: int = _life_rotary_device if is_life else _death_rotary_device
	var tracker: RotaryStickTracker = _life_rotary_tracker if is_life else _death_rotary_tracker
	if device < 0:
		tracker.reset()
		if is_life:
			_life_rotary_device = -1
		else:
			_death_rotary_device = -1
		return 0.0
	if previous_device != device:
		tracker.reset()
		if is_life:
			_life_rotary_device = device
		else:
			_death_rotary_device = device
	if not _side_tuning_input_allowed(is_life):
		# 未来预览只占用这一侧的起始频率，不建立自由旋转或计分手势。
		tracker.reset()
		return 0.0
	var slider: Dictionary = _life_rotary_slider if is_life else _death_rotary_slider
	if not slider.is_empty() and tracker.has_finite_arc():
		var progress_delta: float = tracker.update_finite_arc(stick)
		return progress_delta * (
			float(slider.get("end_value", 1.0))
			- float(slider.get("start_value", 0.0))
		)
	# 自由调频没有可见滑条，仍按每圈 Hz 数换算；两侧的视觉旋向互为镜像。
	var angle_delta: float = tracker.update(stick)
	var frequency_sign: float = LIFE_ROTARY_FREQUENCY_SIGN if is_life else DEATH_ROTARY_FREQUENCY_SIGN
	return angle_delta * rotary_displacement_per_radian * frequency_sign


func _set_rotary_gesture_window(is_life: bool, slider: Dictionary) -> void:
	var event_id: String = str(slider.get("event_id", ""))
	var sweep_rad: float = float(slider.get("gesture_sweep_rad", PI))
	var previous_event_id: String = (
		_life_rotary_window_event_id
		if is_life
		else _death_rotary_window_event_id
	)
	var resolved_sweep: float = clampf(sweep_rad, 0.0, PI)
	var tracker: RotaryStickTracker = _life_rotary_tracker if is_life else _death_rotary_tracker
	if event_id.is_empty():
		if previous_event_id.is_empty():
			return
		if is_life:
			_life_rotary_window_event_id = ""
			_life_rotary_window_sweep_rad = PI
			_life_rotary_slider.clear()
			_life_rotary_input_open = true
		else:
			_death_rotary_window_event_id = ""
			_death_rotary_window_sweep_rad = PI
			_death_rotary_slider.clear()
			_death_rotary_input_open = true
		tracker.disable_finite_arc()
		return

	var start_value: float = float(slider.get("start_value", 0.0))
	var end_value: float = float(slider.get("end_value", 1.0))
	var frequency_sign: int = 1 if end_value > start_value else -1
	var visual_mirror: int = 1 if is_life else -1
	var base_rotation_sign: int = frequency_sign * visual_mirror
	var input_open: bool = bool(slider.get("interaction_open", true))
	var rotation_offset_rad: float = deg_to_rad(float(slider.get("arc_rotation_deg", 0.0)))
	var current_leg_index: int = maxi(0, int(slider.get(
		"current_traversal_index",
		slider.get("current_endpoint_index", 0)
	)))
	var player_progress: float = float(slider.get(
		"raw_player_progress",
		slider.get("player_progress", 0.0)
	))
	slider["base_rotation_sign"] = base_rotation_sign

	var previous_slider: Dictionary = _life_rotary_slider if is_life else _death_rotary_slider
	var same_geometry: bool = (
		previous_event_id == event_id
		and is_equal_approx(float(previous_slider.get("start_value", start_value)), start_value)
		and is_equal_approx(float(previous_slider.get("end_value", end_value)), end_value)
		and is_equal_approx(
			float(previous_slider.get("gesture_sweep_rad", resolved_sweep)),
			resolved_sweep
		)
		and int(previous_slider.get("base_rotation_sign", base_rotation_sign)) == base_rotation_sign
		and is_equal_approx(
			float(previous_slider.get("arc_rotation_deg", 0.0)),
			float(slider.get("arc_rotation_deg", 0.0))
		)
	)
	# 同一个往返事件只同步权威进度。required_rotation_sign 在折返点会翻转，
	# 但固定弧的起终点不能随之重建，否则摇杆会在半途突然丢失接合。
	if same_geometry:
		var was_input_open: bool = _life_rotary_input_open if is_life else _death_rotary_input_open
		if is_life:
			_life_rotary_slider = slider
			_life_rotary_input_open = input_open
		else:
			_death_rotary_slider = slider
			_death_rotary_input_open = input_open
		tracker.sync_authoritative_progress(player_progress)
		tracker.set_leg_index(current_leg_index)
		if was_input_open != input_open:
			tracker.reset()
			if input_open and _tuning_capture_requested:
				_prime_rotary_side(is_life)
		return

	var affinity: int = GameplayTypes.Affinity.ZHU if is_life else GameplayTypes.Affinity.XUAN
	if is_life:
		_life_rotary_window_event_id = event_id
		_life_rotary_window_sweep_rad = resolved_sweep
		_life_rotary_slider = slider
		_life_rotary_input_open = input_open
	else:
		_death_rotary_window_event_id = event_id
		_death_rotary_window_sweep_rad = resolved_sweep
		_death_rotary_slider = slider
		_death_rotary_input_open = input_open
	tracker.configure_finite_arc(
		affinity,
		base_rotation_sign,
		resolved_sweep,
		player_progress,
		rotation_offset_rad
	)
	tracker.set_leg_index(current_leg_index)
	# 肩键已按住时立即尝试首次捕获；只有起点窗口内的杆向会成功。
	if _tuning_capture_requested and input_open:
		_prime_rotary_side(is_life)


func _side_tuning_input_allowed(is_life: bool) -> bool:
	var slider: Dictionary = _life_rotary_slider if is_life else _death_rotary_slider
	if slider.is_empty():
		return not (_life_tuning_preview_blocked if is_life else _death_tuning_preview_blocked)
	return _life_rotary_input_open if is_life else _death_rotary_input_open


func _read_stick(device: int, death_stick: bool) -> Vector2:
	if device < 0:
		return Vector2.ZERO
	var axis_x: JoyAxis = JOY_AXIS_LEFT_X if death_stick else JOY_AXIS_RIGHT_X
	var axis_y: JoyAxis = JOY_AXIS_LEFT_Y if death_stick else JOY_AXIS_RIGHT_Y
	return Vector2(Input.get_joy_axis(device, axis_x), Input.get_joy_axis(device, axis_y))


func _first_held_device(devices: Dictionary) -> int:
	if devices.is_empty():
		return -1
	var ids: Array = devices.keys()
	ids.sort()
	return int(ids[0])


func _reset_rotary_trackers() -> void:
	_life_rotary_tracker.reset()
	_death_rotary_tracker.reset()
	_life_rotary_device = -1
	_death_rotary_device = -1


func _prime_rotary_trackers() -> void:
	_prime_rotary_side(true)
	_prime_rotary_side(false)


func _prime_rotary_side(is_life: bool) -> void:
	var devices: Dictionary = _gamepad_life_devices if is_life else _gamepad_death_devices
	var device: int = _first_held_device(devices)
	if device < 0:
		return
	var displacement: float = _update_rotary_side(
		is_life,
		device,
		_read_stick(device, not is_life)
	)
	# 定锚只更新追踪器，不生成增量调频事件。


func _refresh_rotary_owner(is_life: bool) -> void:
	var devices: Dictionary = _gamepad_life_devices if is_life else _gamepad_death_devices
	var next_device: int = _first_held_device(devices)
	var current_device: int = _life_rotary_device if is_life else _death_rotary_device
	if current_device == next_device:
		return
	if is_life:
		_life_rotary_tracker.reset()
		_life_rotary_device = -1
	else:
		_death_rotary_tracker.reset()
		_death_rotary_device = -1
	if _tuning_capture_requested and next_device >= 0:
		_prime_rotary_side(is_life)


## 生成非摇杆物理事件；设备类别由精确事件枚举确定，device_id 由原始事件传入。
func _emit_physical_event(
		kind: int,
		code: int = 0,
		axis_value: float = 0.0,
		position: Vector2 = Vector2.ZERO,
		relative: Vector2 = Vector2.ZERO,
		touch_id: int = -1,
		device_id: int = 0
) -> PhysicalInputEvent:
	var capture_usec: int = Time.get_ticks_usec()
	var timestamp_us: int = capture_usec
	if is_instance_valid(_clock):
		# 事件抵达时只读取一次判定轴，避免帧缓存给输入额外增加一帧延迟。
		timestamp_us = roundi(_clock.judge_time_at_usec(capture_usec) * 1_000_000.0)
	var sample := PhysicalInputEvent.create(
		timestamp_us,
		_sequence,
		kind,
		_physical_device_type(kind),
		device_id,
		code,
		Vector2(axis_value, 0.0),
		position,
		relative,
		touch_id
	)
	_sequence += 1
	_enqueue_sample(sample)
	physical_input_emitted.emit(sample)
	# print("[InputBuffer] physical kind=%d timestamp=%d sequence=%d code=%d" % [kind, timestamp_us, sample.sequence, code])
	return sample


## 返回物理事件枚举所属的设备类别，未知及系统生命周期事件归入 SYSTEM。
func _physical_device_type(kind: int) -> int:
	match kind:
		GameplayTypes.PhysicalInputKind.KEY_F_PRESSED, GameplayTypes.PhysicalInputKind.KEY_F_RELEASED, GameplayTypes.PhysicalInputKind.KEY_J_PRESSED, GameplayTypes.PhysicalInputKind.KEY_J_RELEASED, GameplayTypes.PhysicalInputKind.KEY_LEFT_PRESSED, GameplayTypes.PhysicalInputKind.KEY_LEFT_RELEASED, GameplayTypes.PhysicalInputKind.KEY_RIGHT_PRESSED, GameplayTypes.PhysicalInputKind.KEY_RIGHT_RELEASED:
			return GameplayTypes.PhysicalDeviceType.KEYBOARD
		GameplayTypes.PhysicalInputKind.MOUSE_LEFT_PRESSED, GameplayTypes.PhysicalInputKind.MOUSE_LEFT_RELEASED, GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_PRESSED, GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_RELEASED, GameplayTypes.PhysicalInputKind.MOUSE_MOVED:
			return GameplayTypes.PhysicalDeviceType.MOUSE
		GameplayTypes.PhysicalInputKind.GAMEPAD_L1_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_L1_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_R1_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_R1_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_L3_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_L3_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_R3_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_R3_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_START_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_START_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_A_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_A_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_B_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_B_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED, GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED:
			return GameplayTypes.PhysicalDeviceType.GAMEPAD
		GameplayTypes.PhysicalInputKind.TOUCH_PRESSED, GameplayTypes.PhysicalInputKind.TOUCH_RELEASED, GameplayTypes.PhysicalInputKind.TOUCH_MOVED:
			return GameplayTypes.PhysicalDeviceType.TOUCHSCREEN
	return GameplayTypes.PhysicalDeviceType.SYSTEM

func _emit_joystick_event(kind: int, device: int, raw_stick: Vector2) -> PhysicalInputEvent:
	var capture_usec: int = Time.get_ticks_usec()
	var timestamp_us: int = capture_usec
	if is_instance_valid(_clock):
		timestamp_us = roundi(_clock.judge_time_at_usec(capture_usec) * 1_000_000.0)
	var sample := PhysicalInputEvent.create(
		timestamp_us,
		_sequence,
		kind,
		GameplayTypes.PhysicalDeviceType.GAMEPAD,
		device,
		0,
		raw_stick
	)
	_sequence += 1
	_enqueue_sample(sample)
	physical_input_emitted.emit(sample)
	# print("[InputBuffer] stick kind=%d device=%d axis=%s timestamp=%d" % [kind, device, str(raw_stick), timestamp_us])
	return sample

func _event_code(event: InputEvent) -> int:
	if event is InputEventKey:
		return (event as InputEventKey).keycode
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index
	return 0

func _bell_kind(event: InputEvent, pressed: bool) -> int:
	if event is InputEventKey:
		var key := (event as InputEventKey).keycode
		if key == KEY_F: return GameplayTypes.PhysicalInputKind.KEY_F_PRESSED if pressed else GameplayTypes.PhysicalInputKind.KEY_F_RELEASED
		if key == KEY_J: return GameplayTypes.PhysicalInputKind.KEY_J_PRESSED if pressed else GameplayTypes.PhysicalInputKind.KEY_J_RELEASED
		if key == KEY_LEFT: return GameplayTypes.PhysicalInputKind.KEY_LEFT_PRESSED if pressed else GameplayTypes.PhysicalInputKind.KEY_LEFT_RELEASED
		if key == KEY_RIGHT: return GameplayTypes.PhysicalInputKind.KEY_RIGHT_PRESSED if pressed else GameplayTypes.PhysicalInputKind.KEY_RIGHT_RELEASED
	if event is InputEventMouseButton:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_LEFT: return GameplayTypes.PhysicalInputKind.MOUSE_LEFT_PRESSED if pressed else GameplayTypes.PhysicalInputKind.MOUSE_LEFT_RELEASED
		if button == MOUSE_BUTTON_RIGHT: return GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_PRESSED if pressed else GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_RELEASED
	if event is InputEventJoypadButton:
		var button := (event as InputEventJoypadButton).button_index
		if button == JOY_BUTTON_LEFT_SHOULDER: return GameplayTypes.PhysicalInputKind.GAMEPAD_L1_PRESSED if pressed else GameplayTypes.PhysicalInputKind.GAMEPAD_L1_RELEASED
		if button == JOY_BUTTON_RIGHT_SHOULDER: return GameplayTypes.PhysicalInputKind.GAMEPAD_R1_PRESSED if pressed else GameplayTypes.PhysicalInputKind.GAMEPAD_R1_RELEASED
		if button == JOY_BUTTON_LEFT_STICK: return GameplayTypes.PhysicalInputKind.GAMEPAD_L3_PRESSED if pressed else GameplayTypes.PhysicalInputKind.GAMEPAD_L3_RELEASED
		if button == JOY_BUTTON_RIGHT_STICK: return GameplayTypes.PhysicalInputKind.GAMEPAD_R3_PRESSED if pressed else GameplayTypes.PhysicalInputKind.GAMEPAD_R3_RELEASED
	return -1


func _update_mouse_capture() -> void:
	# 只有实际游玩时才捕获鼠标。调频场仍在但暂停菜单打开时，光标必须可见且可点击。
	var should_capture: bool = _tuning_capture_requested and mode == InputMode.GAMEPLAY
	if should_capture and not _mouse_captured_by_router:
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_captured_by_router = true
	elif not should_capture:
		_restore_mouse_mode()


func _restore_mouse_mode() -> void:
	if not _mouse_captured_by_router:
		return
	Input.mouse_mode = _previous_mouse_mode
	_mouse_captured_by_router = false


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	var affected_life: bool = _gamepad_life_devices.erase(device)
	var affected_death: bool = _gamepad_death_devices.erase(device)
	if not affected_life and not affected_death:
		return

	# 断开的设备只失去自己的所有权。另一只手柄、键鼠或触屏若仍按住，
	# 就继续维持这口钟，不能把正在进行的 Hold 和载波一并取消。
	if device == _life_rotary_device:
		_life_rotary_tracker.reset()
		_life_rotary_device = -1
	if device == _death_rotary_device:
		_death_rotary_tracker.reset()
		_death_rotary_device = -1
	_reconcile_mapped_holds()
	cancelled.emit(int(CancelReason.DEVICE_DISCONNECTED))


func _is_cancelled_pointer_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).canceled
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).canceled
	return false
