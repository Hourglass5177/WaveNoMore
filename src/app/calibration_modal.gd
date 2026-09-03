extends Control

## 音游校准弹窗。音频输出、输入补偿和画面提前量分开保存，避免混成一个含义不清的偏移。

## 请求关闭弹窗。AppMain 收到后负责释放弹窗并恢复底层页面的鼠标输入。
signal close_requested

## “音频输出偏移”输入框，单位为毫秒；正值让谱面时钟相对声音更晚。
var _audio_offset: SpinBox
## “输入补偿”输入框，单位为毫秒；正值把收到的按键时间映射得更早。
var _input_offset: SpinBox
## “画面提前量”输入框，单位为毫秒；正值让音符相对判定时刻更早显示。
var _visual_offset: SpinBox


func _ready() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.86)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 650)
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	panel.add_child(column)
	var title := Label.new()
	title.text = "校准"
	MingheUiStyle.style_title(title, 44)
	column.add_child(title)
	var help := Label.new()
	help.text = "三类偏移彼此独立：输出、输入和画面不能相加成一个数。\n输出正值让谱面时钟更晚；输入正值把迟到的按键映射回更早时刻；画面正值让音符提前显示。"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MingheUiStyle.style_body(help, 20)
	column.add_child(help)
	_audio_offset = _add_spin(column, "音频输出偏移（ms）", SettingsService.audio_output_offset_ms)
	_input_offset = _add_spin(column, "输入补偿（ms）", SettingsService.input_offset_ms)
	_visual_offset = _add_spin(column, "画面提前量（ms）", SettingsService.visual_offset_ms)
	var save := Button.new()
	save.text = "保存校准"
	MingheUiStyle.style_button(save, true)
	save.pressed.connect(_save)
	column.add_child(save)
	var cancel := Button.new()
	cancel.text = "取消"
	MingheUiStyle.style_button(cancel)
	cancel.pressed.connect(func() -> void: close_requested.emit())
	column.add_child(cancel)
	_audio_offset.grab_focus.call_deferred()


func _add_spin(parent: VBoxContainer, text_value: String, current: int) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size.x = 430
	MingheUiStyle.style_body(label, 22)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = -300
	spin.max_value = 300
	spin.step = 1
	spin.value = current
	spin.custom_minimum_size.x = 220
	spin.add_theme_font_size_override("font_size", 22)
	row.add_child(spin)
	return spin


func _save() -> void:
	SettingsService.audio_output_offset_ms = int(_audio_offset.value)
	SettingsService.input_offset_ms = int(_input_offset.value)
	SettingsService.visual_offset_ms = int(_visual_offset.value)
	SettingsService.save_settings()
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()
