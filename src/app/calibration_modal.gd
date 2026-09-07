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
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.86)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 830)
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var title := Label.new()
	title.text = "校准"
	MingheUiStyle.style_title(title, 40)
	column.add_child(title)
	_device = _label(column, "", 18)
	_update_device()
	_label(column, "先听 4 拍，再跟着编钟声按 F 或 J，共 24 拍。手柄可用左右肩键。\n跟拍时不播放按键声；请听参考音，不要等进度文字变化再按。", 20)
	_progress = _label(column, "准备好后开始。更换外放、耳机或蓝牙设备后，请重新测量。", 20)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	column.add_child(actions)
	_start_button = _button(actions, "开始跟拍", _start_test)
	_stop_button = _button(actions, "停止测量", _cancel_test)
	_stop_button.disabled = true
	_apply_button = _button(actions, "应用输入补偿建议", _apply_suggestion)
	_apply_button.disabled = true
	_summary = _label(column, "测量结果会显示早晚偏差与波动。建议只修改输入补偿，不修改歌曲。", 20)
	_audio_offset = _add_spin(column, "音频输出偏移（ms）", SettingsService.audio_output_offset_ms)
	_input_offset = _add_spin(column, "输入补偿（ms）", SettingsService.input_offset_ms)
	_visual_offset = _add_spin(column, "画面提前量（ms）", SettingsService.visual_offset_ms)
	_label(column, "输出正值：让歌曲时钟更晚。输入正值：把迟到的按键映射到更早时刻。\n画面正值：提前显示音符。校准不能消除按键之后的蓝牙传输时间。", 18)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	column.add_child(footer)
	_button(footer, "恢复默认值", _reset_values)
	_button(footer, "保存校准", _save)
	_button(footer, "取消", _close)
	_reference.bus = &"UI"
	_reference.stream = CalibrationTapSession.create_reference()
	add_child(_reference)
	_reference.finished.connect(func() -> void:
		if _running: _finish_test())
	_start_button.grab_focus.call_deferred()

func _label(parent: Node, value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 820
	MingheUiStyle.style_body(label, font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	MingheUiStyle.style_button(button)
	button.custom_minimum_size = Vector2(0, 54)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _add_spin(parent: VBoxContainer, caption: String, current: int) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 430
	MingheUiStyle.style_body(label, 22)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = -300; spin.max_value = 300; spin.step = 1
	spin.value = current
	spin.custom_minimum_size.x = 220
	spin.add_theme_font_size_override("font_size", 22)
	row.add_child(spin)
	return spin

func _start_test() -> void:
	_commit_fields()
	MenuAudioService.stop_preview()
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
	Input.use_accumulated_input = _previous_accumulated_input
	_running = false; _reference.stop()
	_set_controls_running(false)
	_result = _session.result()
	var error_ms: float = _result.median_error_ms
	var direction := "偏晚" if error_ms >= 0.0 else "偏早"
	_summary.text = "%s %.1f ms · 波动（中位绝对偏差）%.1f ms\n有效 %d / 24 次，排除 %d 次离群输入；建议输入补偿 %d ms。" % [direction, absf(error_ms), _result.mad_ms, _result.used, _result.excluded, _result.suggested_input_ms]
	_apply_button.disabled = not _result.can_apply
	if _result.used < CalibrationTapSession.MIN_SAMPLES:
		_progress.text = "有效跟拍不足 12 次，请重测；未修改任何设置。"
	elif not _result.can_apply:
		_progress.text = "建议值超出可调范围，请检查输出设置后重测。"
	elif _result.mad_ms > 40.0:
		_progress.text = "跟拍波动较大，建议重测后再应用。"
	else:
		_progress.text = "测量完成。应用建议后，可再次跟拍核对；最后点击保存。"

func _cancel_test() -> void:
	if _running: Input.use_accumulated_input = _previous_accumulated_input
	_running = false; _reference.stop()
	_result.clear()
	_set_controls_running(false)
	_progress.text = "测量已停止，可以重新开始。"
	_summary.text = "本次没有应用补偿。"

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
	_progress.text = "建议已填入输入补偿，尚未保存。可以重测，也可以保存校准。"

func _reset_values() -> void:
	_cancel_test()
	for spin in [_audio_offset, _input_offset, _visual_offset]: spin.value = 0
	_progress.text = "已恢复为 0 ms，点击保存后生效。"

func _commit_fields() -> void:
	# 保存和开始测量都提交尚未按回车的数字，避免沿用 SpinBox 的旧值。
	for spin in [_audio_offset, _input_offset, _visual_offset]: spin.apply()

func _update_device() -> void:
	_device.text = "当前输出：%s · 驱动：%s\n系统默认设备切换后也需要重测；本次结果只适用于当前设备与连接方式。" % [AudioServer.output_device, AudioServer.get_driver_name()]

func _save() -> void:
	_cancel_test(); _commit_fields()
	SettingsService.audio_output_offset_ms = int(_audio_offset.value)
	SettingsService.input_offset_ms = int(_input_offset.value)
	SettingsService.visual_offset_ms = int(_visual_offset.value)
	SettingsService.save_settings()
	close_requested.emit()

func _close() -> void:
	_cancel_test()
	close_requested.emit()

func _exit_tree() -> void:
	if _running: Input.use_accumulated_input = _previous_accumulated_input
	_reference.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _running: _cancel_test()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
