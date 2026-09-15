extends Control
## 编钟参考音与跟拍校准。测量只给出输入补偿建议，保存前不改玩家设置。

signal close_requested

var _audio_offset: SpinBox
var _input_offset: SpinBox
var _visual_offset: SpinBox
var _device: Label
var _progress: Label
var _summary: Label
var _start_button: Button
var _stop_button: Button
var _apply_button: Button
var _reference := AudioStreamPlayer.new()
var _session := CalibrationTapSession.new()
var _running := false
var _result: Dictionary = {}
var _output_latency := 0.0
var _audio_offset_at_start := 0.0
var _output_device_at_start := ""
var _device_timer := 0.0
var _last_display_time := -INF
var _previous_accumulated_input := true
## 可选开发诊断只在内存保留当前一次校准的时间，不自动输出或写玩家文件。
var diagnostics_enabled := false
var diagnostic_inputs: Array[Dictionary] = []

func _ready() -> void:
	_audio_offset = %AudioOffset
	_input_offset = %InputOffset
	_visual_offset = %VisualOffset
	_device = %Device
	_progress = %Progress
	_summary = %Summary
	_start_button = %Start
	_stop_button = %Stop
	_apply_button = %Apply
	_audio_offset.value = SettingsService.audio_output_offset_ms
	_input_offset.value = SettingsService.input_offset_ms
	_visual_offset.value = SettingsService.visual_offset_ms
	_start_button.pressed.connect(_start_test)
	_stop_button.pressed.connect(_cancel_test)
	_apply_button.pressed.connect(_apply_suggestion)
	%Reset.pressed.connect(_reset_values)
	_stop_button.disabled = true
	_apply_button.disabled = true
	_reference.bus = &"UI"
	_reference.stream = CalibrationTapSession.create_reference()
	add_child(_reference)
	_reference.finished.connect(func():
		if _running: _finish_test())
	_update_device()

## 嵌入设置页后只提供草稿；唯一写盘入口在外层设置。
func draft_values() -> Dictionary:
	_commit_fields()
	return {"audio_output_offset_ms": int(_audio_offset.value), "input_offset_ms": int(_input_offset.value), "visual_offset_ms": int(_visual_offset.value)}

func deactivate() -> void:
	if _running: _cancel_test()
	set_process(false)

func _start_test() -> void:
	_commit_fields()
	MenuAudioService.stop_preview()
	MenuAudioService.set_calibrating(true)
	_session.begin(_input_offset.value)
	_audio_offset_at_start = _audio_offset.value / 1000.0
	_output_device_at_start = AudioServer.output_device
	_output_latency = AudioServer.get_output_latency()
	_last_display_time = -INF
	_result.clear(); diagnostic_inputs.clear()
	_running = true
	# 与正式游玩采用相同的输入递送方式，校准不额外包含一帧积累等待。
	_previous_accumulated_input = Input.use_accumulated_input
	Input.use_accumulated_input = false
	_set_controls_running(true)
	_summary.text = "正在测量；每一拍只记第一次按键。"
	_reference.play()

func _process(delta: float) -> void:
	_device_timer += delta
	if _device_timer >= 1.0:
		_device_timer = 0.0
		_update_device()
		if _running and AudioServer.output_device != _output_device_at_start:
			_cancel_test()
			_progress.text = "输出设备已改变，请重新开始测量。"
	if not _running: return
	var seconds := maxf(_last_display_time, _audio_seconds())
	_last_display_time = seconds
	var beat := floori((seconds - CalibrationTapSession.LEAD_SECONDS) / CalibrationTapSession.BEAT_SECONDS)
	if beat < 0: _progress.text = "参考音即将开始…"
	elif beat < CalibrationTapSession.PREPARE_BEATS: _progress.text = "准备：%d / 4 拍，请先听节奏" % (beat + 1)
	else:
		_progress.text = "跟拍：%d / 24 拍 · 已收到 %d 次" % [mini(beat - 3, 24), _session.taps.size()]
	if seconds >= _session.finish_seconds(): _finish_test()

func _audio_seconds() -> float:
	# 使用实际播放位置，不把按钮按下到真正起播的时间当作已经听到的音乐。
	return _reference.get_playback_position() + AudioServer.get_time_since_last_mix() - _output_latency - _audio_offset_at_start

func _input(event: InputEvent) -> void:
	if not _running or event.is_echo(): return
	var tap: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_F, KEY_J]
	if event is InputEventJoypadButton:
		tap = event.pressed and (event.is_action_pressed("bell_life") or event.is_action_pressed("bell_death"))
	if not tap: return
	var captured_usec := Time.get_ticks_usec()
	var seconds := _audio_seconds()
	var accepted := _session.add_tap(seconds)
	if diagnostics_enabled and diagnostic_inputs.size() < 128:
		diagnostic_inputs.append({"captured_usec": captured_usec, "audio_seconds": seconds, "accepted": accepted})
	get_viewport().set_input_as_handled()

func _finish_test() -> void:
	MenuAudioService.set_calibrating(false)
	Input.use_accumulated_input = _previous_accumulated_input
	_running = false; _reference.stop()
	_set_controls_running(false)
	_result = _session.result()
	var error_ms: float = _result.median_error_ms
	var direction := "偏晚" if error_ms >= 0.0 else "偏早"
	_summary.text = "%s %.1f ms · 波动（中位绝对偏差）%.1f ms\n有效 %d / 24 次，排除 %d 次离群输入；建议输入补偿 %d ms。" % [direction, absf(error_ms), _result.mad_ms, _result.used, _result.excluded, _result.suggested_input_ms]
	_apply_button.disabled = not _result.can_apply
	if _result.used < CalibrationTapSession.MIN_SAMPLES:
		_progress.text = "有效跟拍不足 12 次，请重测。"
	elif not _result.can_apply:
		_progress.text = "建议值超出可调范围，请检查输出设置后重测。"
	elif _result.mad_ms > 40.0:
		_progress.text = "跟拍波动较大，建议重测后再应用。"
	else:
		_progress.text = "测量完成。应用建议后，可再次跟拍核对；最后点击保存。"

func _cancel_test() -> void:
	MenuAudioService.set_calibrating(false)
	if _running: Input.use_accumulated_input = _previous_accumulated_input
	_running = false; _reference.stop()
	_result.clear()
	_set_controls_running(false)
	_progress.text = "测量已停止，可以重新开始。"
	_summary.text = ""

func _set_controls_running(value: bool) -> void:
	_start_button.disabled = value
	_start_button.text = "重新测量" if not value else "正在跟拍…"
	_stop_button.disabled = not value
	_apply_button.disabled = true
	for spin in [_audio_offset, _input_offset, _visual_offset]: spin.editable = not value

func _apply_suggestion() -> void:
	if not _result.get("can_apply", false): return
	_input_offset.value = int(_result.suggested_input_ms)
	_apply_button.disabled = true
	_progress.text = "建议已填入输入补偿。"

func _reset_values() -> void:
	_cancel_test()
	for spin in [_audio_offset, _input_offset, _visual_offset]: spin.value = 0
	_progress.text = "已恢复为 0 ms，点击保存后生效。"

func _commit_fields() -> void:
	# 保存和开始测量都提交尚未按回车的数字，避免沿用 SpinBox 的旧值。
	for spin in [_audio_offset, _input_offset, _visual_offset]:
		# 隐藏分类的文字可能尚未刷新；只有正在编辑的输入框需要提交文本。
		if spin.get_line_edit().has_focus(): spin.apply()

func _update_device() -> void:
	_device.text = "当前输出：%s · %s" % [AudioServer.output_device, AudioServer.get_driver_name()]

func _exit_tree() -> void:
	if _running:
		Input.use_accumulated_input = _previous_accumulated_input
		MenuAudioService.set_calibrating(false)
	_reference.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _running: _cancel_test()
