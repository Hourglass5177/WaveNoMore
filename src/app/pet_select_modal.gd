extends Control

## 随从选择弹窗。它只允许装备已获得的随从，实际奖励与加成在存档和结算流程处理。

## 请求关闭随从弹窗，由 AppMain 负责真正移除节点。
signal close_requested

## 随从按钮的纵向容器；刷新装备状态时会重建其中的按钮。
var _list: VBoxContainer
## 显示“已装备”或“已卸下”等本次操作结果。
var _status: Label


func _ready() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.86)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(850, 700)
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	var title := Label.new()
	title.text = "随从"
	MingheUiStyle.style_title(title, 44)
	column.add_child(title)
	var help := Label.new()
	help.text = "每次渡河只携带一名随从。FC 获得基础形态，AP 使其进阶；随从只修正结算收益，不改变原始判定。"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MingheUiStyle.style_body(help, 19)
	column.add_child(help)
	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	column.add_child(_list)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MingheUiStyle.style_body(_status, 18)
	column.add_child(_status)
	var close := Button.new()
	close.text = "返回"
	MingheUiStyle.style_button(close)
	close.pressed.connect(func() -> void: close_requested.emit())
	column.add_child(close)
	_build_list()


func _build_list() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	var none := Button.new()
	none.text = "不携带随从"
	MingheUiStyle.style_button(none, SaveService.equipped_pet_id().is_empty())
	none.pressed.connect(func() -> void:
		SaveService.equip_pet("")
		_status.text = "已卸下随从。"
		_build_list()
	)
	_list.add_child(none)
	var preferred_focus: Button = none
	for pet: PetDefinition in ContentCatalog.data.pets:
		var state := SaveService.pet_state(pet.pet_id)
		var owned := bool(state.get("owned", false))
		var advanced := bool(state.get("advanced", false))
		var equipped := SaveService.equipped_pet_id() == pet.pet_id
		var button := Button.new()
		button.text = "%s%s  —  %s" % [pet.display_name, "·进阶" if advanced else "", pet.description if owned else "尚未获得（本关 FC）"]
		button.disabled = not owned
		MingheUiStyle.style_button(button, equipped)
		button.pressed.connect(func() -> void:
			if SaveService.equip_pet(pet.pet_id):
				_status.text = "已装备：%s" % pet.display_name
				_build_list()
		)
		_list.add_child(button)
		if equipped:
			preferred_focus = button
	preferred_focus.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()
