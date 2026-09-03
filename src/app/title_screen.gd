extends Control

## 游戏标题页。这里只组装菜单控件并发送操作意图，页面切换统一交给 AppMain。

## 玩家选择开始游戏时发出，由 AppMain 切换到选关页。
signal start_requested
## 玩家请求打开设置弹窗时发出。
signal settings_requested
## 玩家请求打开音画与输入校准弹窗时发出。
signal calibration_requested


func _ready() -> void:
	MingheUiStyle.add_backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(650, 720)
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	panel.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "楚地 · 生死同构 · 编钟节律"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MingheUiStyle.style_body(eyebrow, 19)
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "冥河，冥河！"
	MingheUiStyle.style_title(title, 66)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "生者自西北来，死者自东南来。\n两钟相向，渡一段不可回头的乐。"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MingheUiStyle.style_body(subtitle, 21)
	column.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 26
	column.add_child(spacer)
	var start_button := _make_button("开始渡河", true)
	start_button.pressed.connect(func() -> void: start_requested.emit())
	column.add_child(start_button)
	var settings_button := _make_button("设置")
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	column.add_child(settings_button)
	var calibration_button := _make_button("音频与输入校准")
	calibration_button.pressed.connect(func() -> void: calibration_requested.emit())
	column.add_child(calibration_button)
	var quit_button := _make_button("离开")
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit_button)
	start_button.grab_focus.call_deferred()


func _make_button(text_value: String, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	MingheUiStyle.style_button(button, accent)
	return button
