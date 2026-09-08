extends Control
## 单槽装备页面；资源描述效果，存档管理获得状态，页面不计算技能。
signal close_requested
var _list: HBoxContainer
var _status: Label
var _debug_panel: HBoxContainer
var _back_button: Button

func _ready() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.86)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 680)
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	var title := _label("随从", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", 20)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_list)
	_status = _label("", 20)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)
	_button(actions, "卸下", func() -> void:
		SaveService.equip_pet("")
		_build_list())
	_back_button = _button(actions, "返回", func() -> void: close_requested.emit())
	if OS.is_debug_build():
		_button(actions, "开发", func() -> void: _debug_panel.visible = not _debug_panel.visible)
		_debug_panel = HBoxContainer.new()
		_debug_panel.visible = false
		column.add_child(_debug_panel)
		for pet: PetDefinition in ContentCatalog.data.pets:
			var group := VBoxContainer.new()
			group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_debug_panel.add_child(group)
			group.add_child(_label(pet.display_name, 18))
			for advanced in [false, true]:
				_button(group, "测试进阶" if advanced else "测试基础", func() -> void:
					SaveService.debug_grant_pet(pet.pet_id, advanced)
					_build_list())
		_button(_debug_panel, "结束测试", func() -> void:
			SaveService.debug_pet_tiers.clear()
			_build_list())
	_build_list()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	MingheUiStyle.style_body(label, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	MingheUiStyle.style_button(button)
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _build_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var equipped := SaveService.equipped_pet_id()
	var focus: Button
	for pet: PetDefinition in ContentCatalog.data.pets:
		var state := SaveService.pet_state(pet.pet_id)
		var owned := bool(state.get("owned", false))
		var advanced := bool(state.get("advanced", false))
		var card := VBoxContainer.new()
		card.name = pet.pet_id
		card.tooltip_text = pet.description
		card.custom_minimum_size.x = 320
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_constant_override("separation", 14)
		_list.add_child(card)
		var icon := TextureRect.new()
		icon.texture = pet.icon(advanced)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(128, 160)
		card.add_child(icon)
		var title := _label(pet.display_name, 28)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(title)
		card.add_child(_label("基础 · " + pet.base_description, 20))
		card.add_child(_label("进阶 · " + pet.advanced_description, 20))
		var space := Control.new()
		space.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_child(space)
		card.add_child(_label("进阶已获得" if advanced else ("基础已获得 · AP 进阶" if owned else "未获得 · FC 解锁"), 18))
		var button := _button(card, "已装备" if equipped == pet.pet_id else "装备", func() -> void:
			SaveService.equip_pet(pet.pet_id)
			_build_list())
		button.tooltip_text = pet.description
		button.disabled = not owned
		MingheUiStyle.style_button(button, equipped == pet.pet_id)
		if owned and (focus == null or equipped == pet.pet_id): focus = button
	var selected := ContentCatalog.get_pet(equipped)
	_status.text = "未装备" if selected == null else selected.display_name + (" · 进阶" if SaveService.equipped_pet_advanced() else " · 基础")
	(focus if focus != null else _back_button).grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()
