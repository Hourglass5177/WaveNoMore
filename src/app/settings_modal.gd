extends Control

## 设置弹窗。修改先停留在控件中，只有“保存并返回”才写入 SettingsService。

## 保存完成或玩家取消时请求关闭弹窗。
signal close_requested

## 音乐总线音量滑块，数值单位为 dB。
var _music: HSlider
## 关卡内敲钟和判定音效总线音量滑块，数值单位为 dB。
var _sfx: HSlider
## 菜单与按钮音效总线音量滑块，数值单位为 dB。
var _ui: HSlider
## 屏幕震动强度系数，0 表示关闭，1 表示完整强度。
var _shake: HSlider
## 闪光强度系数，0 表示关闭，1 表示完整强度。
var _flash: HSlider
## 调频相纹的视觉强度；不改变真实波前或玩法判定。
var _tuning_wave_intensity: HSlider
## 是否使用全屏窗口的开关。
var _fullscreen: CheckButton
## 是否在关卡中显示开发调试 HUD 的开关。
var _debug: CheckButton


func _ready() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.82)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 820)
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var title := Label.new()
	title.text = "设置"
	MingheUiStyle.style_title(title, 42)
	column.add_child(title)
	_music = _add_slider(column, "音乐", -40.0, 6.0, SettingsService.music_volume_db)
	_sfx = _add_slider(column, "敲钟与判定音效", -40.0, 6.0, SettingsService.gameplay_sfx_volume_db)
	_ui = _add_slider(column, "界面音效", -40.0, 6.0, SettingsService.ui_volume_db)
	_shake = _add_slider(column, "画面震动", 0.0, 1.0, SettingsService.screen_shake_scale)
	_flash = _add_slider(column, "闪光强度", 0.0, 1.0, SettingsService.flash_scale)
	_tuning_wave_intensity = _add_tuning_wave_intensity_slider(column)
	var wave_help := Label.new()
	wave_help.text = "调整骨白叠加纹的明度与辉光；不会删减波纹，也不会改变频率、波速或判定。"
	wave_help.custom_minimum_size.x = 700
	MingheUiStyle.style_body(wave_help, 17)
	column.add_child(wave_help)
	_fullscreen = CheckButton.new()
	_fullscreen.text = "全屏"
	_fullscreen.button_pressed = SettingsService.fullscreen
	_fullscreen.add_theme_font_size_override("font_size", 22)
	column.add_child(_fullscreen)
	_debug = CheckButton.new()
	_debug.text = "显示调试 HUD"
	_debug.button_pressed = SettingsService.debug_hud_enabled
	_debug.add_theme_font_size_override("font_size", 22)
	column.add_child(_debug)
	var save := Button.new()
	save.text = "保存并返回"
	MingheUiStyle.style_button(save, true)
	save.pressed.connect(_save_and_close)
	column.add_child(save)
	_music.grab_focus.call_deferred()


func _add_slider(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, current: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 260
	MingheUiStyle.style_body(label, 21)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.5 if maximum > 2.0 else 0.05
	slider.value = current
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	return slider


func _add_tuning_wave_intensity_slider(parent: VBoxContainer) -> HSlider:
	var slider := _add_slider(
		parent,
		"相纹强度（仅画面）",
		SettingsService.MIN_TUNING_WAVE_INTENSITY,
		SettingsService.MAX_TUNING_WAVE_INTENSITY,
		SettingsService.tuning_wave_intensity
	)
	slider.name = "TuningWaveIntensitySlider"
	var value_label := Label.new()
	value_label.name = "TuningWaveIntensityValue"
	value_label.custom_minimum_size.x = 72
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	MingheUiStyle.style_body(value_label, 19)
	slider.get_parent().add_child(value_label)
	_update_frequency_value_label(value_label, slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		_update_frequency_value_label(value_label, value)
	)
	return slider


func _update_frequency_value_label(label: Label, value: float) -> void:
	label.text = "%d%%" % roundi(value * 100.0)


func _save_and_close() -> void:
	SettingsService.music_volume_db = _music.value
	SettingsService.gameplay_sfx_volume_db = _sfx.value
	SettingsService.ui_volume_db = _ui.value
	SettingsService.screen_shake_scale = _shake.value
	SettingsService.flash_scale = _flash.value
	SettingsService.tuning_wave_intensity = _tuning_wave_intensity.value
	SettingsService.fullscreen = _fullscreen.button_pressed
	SettingsService.debug_hud_enabled = _debug.button_pressed
	SettingsService.save_settings()
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()
