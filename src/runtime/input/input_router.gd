class_name InputRouter
extends Node

## 把键鼠、手柄和触屏事件转换为带判定时间的 SemanticInputSample。
## 这里不读取谱面，也不累计调频游标；领域层负责按权威歌曲时间积分摇杆速率。

signal semantic_input_emitted(sample: SemanticInputSample)
signal held_state_changed(life_held: bool, death_held: bool)
signal cancelled(reason: int)
signal pause_requested

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

## 左摇杆横轴控制死钟，右摇杆横轴控制生钟。动作名按“钟的归属”命名，
## 而不是按屏幕方向命名，之后即使视觉布局改变也不必改领域语义。
const ACTION_DEATH_TUNE_LEFT: StringName = &"tune_death_left"
const ACTION_DEATH_TUNE_RIGHT: StringName = &"tune_death_right"
const ACTION_LIFE_TUNE_LEFT: StringName = &"tune_life_left"
const ACTION_LIFE_TUNE_RIGHT: StringName = &"tune_life_right"

## 鼠标或触屏每横移一个设计像素，对应多少归一化频率轴位移。
## 它由“频率范围 × 每 Hz 像素数”推导，不能在设备层另设一套手感参数。
var pointer_displacement_per_pixel: float = 0.0
## 左右摇杆横轴的中心死区，始终取自当前关卡 GameplayRuleSet。
var tune_deadzone: float = 0.0
## 当前规则声明的满幅游标速度。InputRouter只发送 -1～1 的速率意图，
## 真正按歌曲时间积分仍由 TuningEngine 完成；这里保留数值用于检查设备合同。
var tuning_cursor_speed_px_sec: float = 0.0

@export_group("Gamepad Tuning")
## 摇杆速率相比上一样本至少变化多少才上报，用于过滤硬件抖动。
@export_range(0.0001, 0.1, 0.0001) var tune_change_epsilon: float = 0.002

var mode: InputMode = InputMode.DISABLED
## 两个布尔值代表所有物理来源合并后的按住状态，而不是某一颗具体按键。
var life_held: bool = false
var death_held: bool = false
## 当前手柄速率意图；X=生钟，Y=死钟。指针位移是瞬时样本，不保存在这里。
var tune_vector: Vector2 = Vector2.ZERO

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

var _mouse_captured_by_router: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _tuning_rules == null:
		configure_from_rules(GameplayRuleSet.new())
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(_delta: float) -> void:
	if mode != InputMode.GAMEPLAY or not _tuning_capture_requested:
		return
	# JoypadMotion 通常只在轴数值变化时到达。每帧补读一次当前值，才能让玩家在
	# 调频段开始前预先按住肩键和推住摇杆，并在开门后自然接入，而不用故意晃一下摇杆。
	var next_rate: Vector2 = tune_vector
	if not _gamepad_life_devices.is_empty():
		next_rate.x = _strongest_held_axis(_gamepad_life_devices, JOY_AXIS_RIGHT_X)
	if not _gamepad_death_devices.is_empty():
		next_rate.y = _strongest_held_axis(_gamepad_death_devices, JOY_AXIS_LEFT_X)
	_set_tuning_rate(next_rate)


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
	## 设备层与判定层共用同一份规则。摇杆输出仍是无量纲速率，
	## 指针位移则在这里按完整频率轴的设计像素长度换算。
	if rules == null:
		return
	_tuning_rules = rules
	tune_deadzone = clampf(rules.tuning_stick_deadzone, 0.0, 0.999999)
	tuning_cursor_speed_px_sec = maxf(rules.tuning_cursor_speed_px_sec, 0.001)
	var frequency_range_hz: float = maxf(
		rules.tuning_max_frequency_hz - rules.tuning_min_frequency_hz,
		0.001
	)
	var frequency_axis_length_px: float = frequency_range_hz * maxf(rules.tuning_pixels_per_hz, 0.001)
	pointer_displacement_per_pixel = 1.0 / frequency_axis_length_px


func set_mode(next_mode: InputMode) -> void:
	if mode == next_mode:
		return
	mode = next_mode
	if mode == InputMode.DISABLED or mode == InputMode.REPLAY:
		cancel_all(CancelReason.MODAL_OPENED, false)
	set_process_unhandled_input(mode != InputMode.REPLAY)


func set_tuning_capture_active(active: bool, _initial_value: Vector2 = Vector2.ZERO) -> void:
	_tuning_capture_requested = active
	# 新调频段一律从静止速率开始。游标位置由领域层保管，不能把它塞进速度样本。
	if not tune_vector.is_zero_approx():
		tune_vector = Vector2.ZERO
	_update_mouse_capture()


func get_held_snapshot() -> Dictionary:
	return {
		"life_held": life_held,
		"death_held": death_held,
		"tuning_rate": tune_vector,
	}


func reset_for_run() -> void:
	cancel_all(CancelReason.RETRY, false)
	_sequence = 0


func cancel_all(reason: CancelReason, emit_semantic_cancel: bool = true) -> void:
	var had_state: bool = life_held or death_held or not tune_vector.is_zero_approx()
	_life_sources.clear()
	_death_sources.clear()
	_touch_affinity_by_index.clear()
	_gamepad_life_devices.clear()
	_gamepad_death_devices.clear()
	_mouse_life_held = false
	_mouse_death_held = false
	life_held = false
	death_held = false
	tune_vector = Vector2.ZERO
	_tuning_capture_requested = false
	_restore_mouse_mode()
	held_state_changed.emit(false, false)

	if emit_semantic_cancel and mode != InputMode.REPLAY and (_clock != null or had_state):
		_emit_semantic_input(GameplayTypes.SemanticInputKind.FOCUS_CANCELLED, Vector2.ZERO)
	cancelled.emit(int(reason))


func inject_replay_input(sample: SemanticInputSample) -> void:
	if sample == null:
		return
	_sequence = maxi(_sequence, sample.sequence + 1)
	semantic_input_emitted.emit(sample)


func _unhandled_input(event: InputEvent) -> void:
	if mode == InputMode.DISABLED or mode == InputMode.REPLAY:
		return

	if event.is_action_pressed(ACTION_PAUSE) and not event.is_echo():
		pause_requested.emit()
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

	if event.is_action_pressed(ACTION_LIFE):
		_track_device_hold(event, true, true)
		_set_bell_source(true, _bell_source_key(event, true), true)
		_sync_gamepad_rate_after_shoulder(event, true)
		return true
	if event.is_action_released(ACTION_LIFE):
		_track_device_hold(event, true, false)
		_set_bell_source(true, _bell_source_key(event, true), false)
		_stop_released_gamepad_rate(event, true)
		return true
	if event.is_action_pressed(ACTION_DEATH):
		_track_device_hold(event, false, true)
		_set_bell_source(false, _bell_source_key(event, false), true)
		_sync_gamepad_rate_after_shoulder(event, false)
		return true
	if event.is_action_released(ACTION_DEATH):
		_track_device_hold(event, false, false)
		_set_bell_source(false, _bell_source_key(event, false), false)
		_stop_released_gamepad_rate(event, false)
		return true
	return false


func _handle_touch_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var source_key := "touch:%d" % touch.index
		if touch.pressed:
			var is_life: bool = touch.position.y < get_viewport().get_visible_rect().size.y * 0.5
			_touch_affinity_by_index[touch.index] = GameplayTypes.Affinity.ZHU if is_life else GameplayTypes.Affinity.XUAN
			_set_bell_source(is_life, source_key, true)
		elif _touch_affinity_by_index.has(touch.index):
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
		var is_life: bool = int(_touch_affinity_by_index[drag.index]) == GameplayTypes.Affinity.ZHU
		var displacement: float = drag.relative.x * pointer_displacement_per_pixel
		return _emit_pointer_displacement(displacement, is_life, not is_life)
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
		return _emit_pointer_displacement(
			mouse_event.relative.x * pointer_displacement_per_pixel,
			move_life,
			move_death
		)

	if event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		if joy_motion.axis == JOY_AXIS_LEFT_X:
			if not _gamepad_death_devices.has(joy_motion.device):
				return false
			var death_rate: float = _apply_axis_deadzone(joy_motion.axis_value)
			return _set_tuning_rate(Vector2(tune_vector.x, death_rate))
		if joy_motion.axis == JOY_AXIS_RIGHT_X:
			if not _gamepad_life_devices.has(joy_motion.device):
				return false
			var life_rate: float = _apply_axis_deadzone(joy_motion.axis_value)
			return _set_tuning_rate(Vector2(life_rate, tune_vector.y))

	# InputEventAction 分支供自动测试和之后的改键系统使用；真实手柄仍走上面的原始轴事件，
	# 这样左右两根摇杆不会被 Input.get_vector() 合并或单位圆归一化。
	if event.is_action(ACTION_DEATH_TUNE_LEFT) or event.is_action(ACTION_DEATH_TUNE_RIGHT):
		if not death_held:
			return false
		var death_axis: float = Input.get_axis(ACTION_DEATH_TUNE_LEFT, ACTION_DEATH_TUNE_RIGHT)
		return _set_tuning_rate(Vector2(tune_vector.x, _apply_axis_deadzone(death_axis)))
	if event.is_action(ACTION_LIFE_TUNE_LEFT) or event.is_action(ACTION_LIFE_TUNE_RIGHT):
		if not life_held:
			return false
		var life_axis: float = Input.get_axis(ACTION_LIFE_TUNE_LEFT, ACTION_LIFE_TUNE_RIGHT)
		return _set_tuning_rate(Vector2(_apply_axis_deadzone(life_axis), tune_vector.y))
	return false


func _emit_pointer_displacement(amount: float, move_life: bool, move_death: bool) -> bool:
	if is_zero_approx(amount):
		return true
	var displacement := Vector2(amount if move_life else 0.0, amount if move_death else 0.0)
	_emit_semantic_input(GameplayTypes.SemanticInputKind.TUNING_DISPLACED, displacement)
	return true


func _set_tuning_rate(next_rate: Vector2) -> bool:
	# 每个分量独立钳制；(1, 1) 表示双摇杆同时满幅，是合法状态。
	var clamped := Vector2(
		clampf(next_rate.x, -1.0, 1.0),
		clampf(next_rate.y, -1.0, 1.0)
	)
	if (
		absf(clamped.x - tune_vector.x) < tune_change_epsilon
		and absf(clamped.y - tune_vector.y) < tune_change_epsilon
	):
		return true
	tune_vector = clamped
	_emit_semantic_input(GameplayTypes.SemanticInputKind.TUNING_RATE_CHANGED, tune_vector)
	return true


func _apply_axis_deadzone(raw_axis: float) -> float:
	var clamped: float = clampf(raw_axis, -1.0, 1.0)
	if absf(clamped) <= tune_deadzone:
		return 0.0
	return signf(clamped) * inverse_lerp(tune_deadzone, 1.0, absf(clamped))


func _strongest_held_axis(devices: Dictionary, axis: JoyAxis) -> float:
	var strongest: float = 0.0
	for raw_device: Variant in devices.keys():
		var candidate: float = _apply_axis_deadzone(Input.get_joy_axis(int(raw_device), axis))
		if absf(candidate) > absf(strongest):
			strongest = candidate
	return strongest


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
		var kind: int
		if is_life:
			kind = GameplayTypes.SemanticInputKind.LIFE_PRESSED if is_held_now else GameplayTypes.SemanticInputKind.LIFE_RELEASED
		else:
			kind = GameplayTypes.SemanticInputKind.DEATH_PRESSED if is_held_now else GameplayTypes.SemanticInputKind.DEATH_RELEASED
		_emit_semantic_input(kind, Vector2.ZERO)
		held_state_changed.emit(life_held, death_held)
	_update_mouse_capture()


func _bell_source_key(event: InputEvent, is_life: bool) -> String:
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var code: int = int(key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode)
		return "key:%d" % code
	if event is InputEventJoypadButton:
		var joy_event := event as InputEventJoypadButton
		return "joy:%d:%d" % [joy_event.device, joy_event.button_index]
	if event is InputEventAction:
		return "action:%s" % String((event as InputEventAction).action)
	return "semantic:%s" % ("life" if is_life else "death")


func _track_device_hold(event: InputEvent, is_life: bool, pressed: bool) -> void:
	if event is InputEventMouseButton:
		if is_life:
			_mouse_life_held = pressed
		else:
			_mouse_death_held = pressed
	elif event is InputEventJoypadButton:
		var device: int = (event as InputEventJoypadButton).device
		var devices: Dictionary = _gamepad_life_devices if is_life else _gamepad_death_devices
		if pressed:
			devices[device] = true
		else:
			devices.erase(device)


func _sync_gamepad_rate_after_shoulder(event: InputEvent, is_life: bool) -> void:
	if not _tuning_capture_requested or not event is InputEventJoypadButton:
		return
	var device: int = (event as InputEventJoypadButton).device
	var axis: JoyAxis = JOY_AXIS_RIGHT_X if is_life else JOY_AXIS_LEFT_X
	var rate: float = _apply_axis_deadzone(Input.get_joy_axis(device, axis))
	if is_life:
		_set_tuning_rate(Vector2(rate, tune_vector.y))
	else:
		_set_tuning_rate(Vector2(tune_vector.x, rate))


func _stop_released_gamepad_rate(event: InputEvent, is_life: bool) -> void:
	if not _tuning_capture_requested or not event is InputEventJoypadButton:
		return
	if is_life and not is_zero_approx(tune_vector.x):
		_set_tuning_rate(Vector2(0.0, tune_vector.y))
	elif not is_life and not is_zero_approx(tune_vector.y):
		_set_tuning_rate(Vector2(tune_vector.x, 0.0))


func _emit_semantic_input(kind: int, value: Vector2) -> void:
	var capture_usec: int = Time.get_ticks_usec()
	var timestamp_us: int = capture_usec
	if is_instance_valid(_clock):
		# 事件抵达时只读取一次判定轴，避免帧缓存给输入额外增加一帧延迟。
		timestamp_us = roundi(_clock.judge_time_at_usec(capture_usec) * 1_000_000.0)
	var sample := SemanticInputSample.create(timestamp_us, _sequence, kind, value)
	_sequence += 1
	semantic_input_emitted.emit(sample)


func _update_mouse_capture() -> void:
	var should_capture: bool = _tuning_capture_requested and (_mouse_life_held or _mouse_death_held)
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
	if _gamepad_life_devices.has(device) or _gamepad_death_devices.has(device):
		cancel_all(CancelReason.DEVICE_DISCONNECTED)
