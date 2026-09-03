## 写谱器右侧属性面板。它按字段实际类型生成控件，再用信号请求 Workspace 完成可撤销修改。
@tool
class_name MingheChartPropertyPanel
extends ScrollContainer

## 面板不直接改 Resource，只把用户确认后的字段修改请求交给 Workspace 记入 Undo。
signal property_change_requested(event_id: String, property_name: StringName, value: Variant)

## 动态字段控件的纵向容器；每次换选事件都会清空并重建。
var _content: VBoxContainer
## 当前展示的事件 Resource；为空时面板显示提示文本。
var _event: Resource
## 当前事件所属轨道名，用来选择 FIELDS 白名单和调频专用控件。
var _track: String = ""
## 重建控件时会触发部分控件信号，用此标记阻止它们被误当成用户编辑。
var _building := false

## 各轨允许谱师直接修改的字段白名单；未列字段不会出现在属性面板。
const FIELDS := {
	"notes": ["event_id", "group_id", "damage_group_id", "tick", "duration_ticks", "kind", "affinity", "tail_requires_release", "visual_variant"],
	"tuning_fields": ["event_id", "tick", "duration_ticks"],
	"tuning_sliders": ["event_id", "field_id", "group_id", "affinity", "tick", "traversal_ticks", "traversal_count", "start_value", "end_value"],
	"su_manifestations": ["event_id", "group_id", "tick", "count", "spawn_region_normalized", "visual_variant"],
	"rapid": ["event_id", "damage_group_id", "tick", "duration_ticks", "required_strikes", "debounce_ms", "must_alternate", "visual_variant"],
	"show": ["event_id", "tick", "duration_ticks", "track", "cue_id", "target_slot", "parameters"],
}


func _ready() -> void:
	custom_minimum_size = Vector2(270.0, 300.0)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	add_child(_content)
	show_empty()


func show_empty(message: String = "选择一个事件以编辑属性") -> void:
	_event = null
	_track = ""
	_clear_content()
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.72, 0.74, 0.78)
	_content.add_child(label)


func edit_event(event: Resource, track: String) -> void:
	_event = event
	_track = track
	_clear_content()
	if _event == null:
		show_empty()
		return
	_building = true
	var title := Label.new()
	title.text = "%s · %s" % [track, String(event.get("event_id"))]
	title.add_theme_font_size_override("font_size", 18)
	_content.add_child(title)
	_content.add_child(HSeparator.new())
	for field_name in FIELDS.get(track, []):
		_add_field(StringName(field_name), event.get(field_name))
	_building = false


func _add_field(property_name: StringName, value: Variant) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = String(property_name)
	label.modulate = Color(0.83, 0.82, 0.76)
	group.add_child(label)
	var editor := _make_editor(property_name, value)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(editor)
	_content.add_child(group)


func _make_editor(property_name: StringName, value: Variant) -> Control:
	# 根据当前值类型选择编辑控件，保证写回值仍符合 Resource 字段类型。
	if value is bool:
		var check := CheckButton.new()
		check.button_pressed = value
		check.toggled.connect(func(next_value: bool) -> void: _emit_change(property_name, next_value))
		return check
	if value is int:
		if property_name in [&"kind", &"affinity", &"track"]:
			return _make_enum_editor(property_name, int(value))
		var spin := SpinBox.new()
		spin.allow_greater = true
		spin.allow_lesser = property_name == &"tick"
		spin.min_value = -1000000.0 if property_name == &"tick" else 0.0
		spin.max_value = 10000000.0
		spin.step = 1.0
		spin.value = int(value)
		spin.value_changed.connect(func(next_value: float) -> void: _emit_change(property_name, roundi(next_value)))
		return spin
	if value is float:
		var spin := SpinBox.new()
		spin.allow_greater = true
		spin.allow_lesser = true
		if property_name in [&"start_value", &"end_value"]:
			spin.min_value = 0.0
			spin.max_value = 1.0
		else:
			spin.min_value = -100000.0
			spin.max_value = 100000.0
		spin.step = 0.001
		spin.value = float(value)
		spin.value_changed.connect(func(next_value: float) -> void: _emit_change(property_name, next_value))
		return spin
	if value is Vector2:
		var line := LineEdit.new()
		line.text = "%.3f, %.3f" % [value.x, value.y]
		line.text_submitted.connect(func(text: String) -> void:
			var pieces := text.split(",")
			if pieces.size() == 2 and pieces[0].strip_edges().is_valid_float() and pieces[1].strip_edges().is_valid_float():
				_emit_change(property_name, Vector2(pieces[0].to_float(), pieces[1].to_float()))
		)
		return line
	if value is Rect2:
		# Rect2 用四个数显式编辑，顺序固定为 x、y、宽、高；适合直接填写 0～1 归一化区域。
		var box := GridContainer.new()
		box.columns = 2
		var labels := PackedStringArray(["x", "y", "宽", "高"])
		var values := [value.position.x, value.position.y, value.size.x, value.size.y]
		var spins: Array[SpinBox] = []
		for index in 4:
			var label := Label.new()
			label.text = labels[index]
			box.add_child(label)
			var spin := SpinBox.new()
			spin.min_value = 0.0
			spin.max_value = 1.0
			spin.step = 0.01
			spin.value = values[index]
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spins.append(spin)
			box.add_child(spin)
		for spin in spins:
			spin.value_changed.connect(func(_next_value: float) -> void:
				_emit_change(property_name, Rect2(spins[0].value, spins[1].value, spins[2].value, spins[3].value))
			)
		return box
	if value is Dictionary:
		var box := VBoxContainer.new()
		var text := TextEdit.new()
		text.custom_minimum_size.y = 110.0
		text.text = JSON.stringify(value, "  ", true)
		box.add_child(text)
		var apply := Button.new()
		apply.text = "应用 JSON 参数"
		apply.pressed.connect(func() -> void:
			var parsed: Variant = JSON.parse_string(text.text)
			if parsed is Dictionary:
				_emit_change(property_name, parsed)
		)
		box.add_child(apply)
		return box
	var line := LineEdit.new()
	line.text = String(value)
	line.text_submitted.connect(func(text: String) -> void:
		_emit_change(property_name, StringName(text) if value is StringName else text)
	)
	line.focus_exited.connect(func() -> void:
		_emit_change(property_name, StringName(line.text) if value is StringName else line.text)
	)
	return line


func _make_enum_editor(property_name: StringName, current: int) -> Control:
	var options := OptionButton.new()
	var labels: PackedStringArray
	match property_name:
		&"kind":
			labels = PackedStringArray(["Tap", "Hold"])
		&"affinity":
			labels = PackedStringArray(["朱", "玄"])
		&"track":
			labels = PackedStringArray(["角色", "世界", "镜头", "VFX", "音频", "教程"])
		_:
			labels = PackedStringArray(["0", "1"])
	for index in labels.size():
		options.add_item(labels[index], index)
	options.select(clampi(current, 0, labels.size() - 1))
	options.item_selected.connect(func(index: int) -> void: _emit_change(property_name, index))
	return options


func _emit_change(property_name: StringName, value: Variant) -> void:
	if _building or _event == null:
		return
	property_change_requested.emit(String(_event.get("event_id")), property_name, value)


func _clear_content() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		child.queue_free()
