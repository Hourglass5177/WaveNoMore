class_name LevelUI
extends RefCounted
## 关卡工具通用表单控件；文本在提交或离开输入框时形成一条编辑命令。
static func label(parent: Node, text: String, size := 14) -> Label:
	var control := Label.new(); control.text = text; control.add_theme_font_size_override("font_size", size)
	if text.length() > 26: control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(control); return control

static func button(parent: Node, text: String, action: Callable, hint := "") -> Button:
	var control := Button.new(); control.text = text; control.tooltip_text = hint
	parent.add_child(control); control.pressed.connect(action); return control

static func row(parent: Node, caption: String) -> HBoxContainer:
	var box := HBoxContainer.new(); parent.add_child(box)
	var name := label(box, caption, 12); name.custom_minimum_size.x = 40 if parent is HFlowContainer else 80
	return box

static func text_field(parent: Node, caption: String, value: String, commit: Callable) -> LineEdit:
	var box := row(parent, caption); var edit := LineEdit.new(); edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_child(edit)
	var last := [value]
	var submit := func():
		if edit.get_meta("mixed_value",false) and edit.text.is_empty(): return
		if edit.text != last[0]: last[0] = edit.text; commit.call(edit.text)
	edit.text_submitted.connect(func(_text): submit.call()); edit.focus_exited.connect(submit)
	return edit

static func number(parent: Node, caption: String, value: float, commit: Callable, step := 1.0, low := -100000.0, high := 100000.0) -> SpinBox:
	var box := row(parent, caption); var spin := SpinBox.new()
	spin.min_value = low; spin.max_value = high; spin.step = step; spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_child(spin)
	_number_session(spin, parent, commit); return spin

static func toggle(parent: Node, caption: String, value: bool, commit: Callable) -> CheckBox:
	var control := CheckBox.new(); control.text = caption; control.button_pressed = value
	parent.add_child(control); control.toggled.connect(commit); return control

static func choice(parent: Node, caption: String, values: Array, current: Variant, commit: Callable, captions: Array = []) -> OptionButton:
	var box := row(parent, caption); var select := OptionButton.new()
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL; select.fit_to_longest_item = false; box.add_child(select)
	for index in values.size(): select.add_item(str(captions[index] if captions.size() > index else values[index]))
	var index := values.find(current)
	if index<0:
		select.add_item("未选择" if str(current).is_empty() else "缺失："+str(current)); index=select.item_count-1
	select.select(index)
	select.item_selected.connect(func(chosen):
		if chosen<values.size():commit.call(values[chosen]))
	return select

static func vector(parent: Node, caption: String, value: Vector2, commit: Callable, step := 1.0) -> void:
	var box := row(parent, caption)
	var x := SpinBox.new(); var y := SpinBox.new()
	for spin in [x,y]:
		spin.min_value = -100000; spin.max_value = 100000; spin.step = step; spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_child(spin)
	x.value = value.x; y.value = value.y
	_number_session(x,parent,func(next): commit.call([next,y.value]))
	_number_session(y,parent,func(next): commit.call([x.value,next]))

static func color(parent: Node, caption: String, value: String, commit: Callable) -> ColorPickerButton:
	var box := row(parent, caption); var picker := ColorPickerButton.new(); picker.color = Color(value)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_child(picker)
	var doc := edit_document(parent)
	var before := [picker.color]
	picker.picker_created.connect(func():
		picker.get_popup().about_to_popup.connect(func():
			before[0]=picker.color
			if doc != null: doc.begin_edit())
		picker.get_popup().window_input.connect(func(event):
			if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
				picker.color=before[0]
				if doc != null: doc.end_edit(true)))
	picker.color_changed.connect(func(next):
		if doc != null: doc.begin_edit()
		commit.call(next.to_html()))
	picker.popup_closed.connect(func():
		if doc != null: doc.end_edit())
	return picker

static func clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

static func edit_document(parent: Node) -> LevelDocument:
	var node := parent
	while node != null:
		if node.has_method("edit_document"): return node.edit_document()
		node=node.get_parent()
	return null

static func _number_session(spin: SpinBox, parent: Node, commit: Callable) -> void:
	var doc := edit_document(parent)
	var timer := Timer.new(); timer.one_shot=true; timer.wait_time=0.35; spin.add_child(timer)
	var finish := func():
		timer.stop()
		if doc != null: doc.end_edit()
	spin.set_meta("finish_edit",finish)
	spin.value_changed.connect(func(value):
		if doc != null: doc.begin_edit()
		commit.call(value)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): timer.start())
	timer.timeout.connect(finish)
	spin.get_line_edit().focus_exited.connect(finish)
	spin.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed: finish.call())

static func finish_fields(parent: Node) -> void:
	for child in parent.get_children():
		if child is SpinBox and child.get_line_edit().has_focus() and not child.get_line_edit().text.is_empty(): child.apply()
		if child is LineEdit and child.has_focus(): child.release_focus()
		if child.has_meta("finish_edit"): child.get_meta("finish_edit").call()
		finish_fields(child)
