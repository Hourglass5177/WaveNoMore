@tool
extends "res://src/app/ui/art_screen.gd"
## 单只随从静息预览；动画只消费 UI 时间，不发送领域技能事件。
signal close_requested
@export var entries: Array[PetPreviewEntry] = [preload("res://content/ui/nu_tu_fu_preview.tres"), preload("res://content/ui/gui_jin_yang_preview.tres"), preload("res://content/ui/yi_huo_she_preview.tres")]
var _index := 0
var _clock := 0.0
var _locked := true
var _actor: PetVisual
var _selection_motion: Tween
var _shadow_motion: Tween
var _stick_direction := 0
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	SaveService.developer_mode_changed.connect(_show_pet)
	for name in ["Left","Right","Preview"]:
		var button: Button = get_node("%"+name)
		for state in ["normal","hover","pressed","disabled"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	%Left.pressed.connect(step.bind(-1))
	%Right.pressed.connect(step.bind(1))
	# 箭头由实际换页播放选择音，不再同时叠加确认音。
	%Left.set_meta("ui_sound", &"none")
	%Right.set_meta("ui_sound", &"none")
	%Preview.pressed.connect(play_skill)
	%Equip.pressed.connect(_equip)
	%Back.pressed.connect(func(): close_requested.emit())
	%Developer.hide()
	%DevPanel.hide()
	for i in entries.size():
		if entries[i].pet_id == SaveService.equipped_pet_id(): _index = i
	_show_pet()
	if _locked: %Back.grab_focus.call_deferred()
	else: %Preview.grab_focus.call_deferred()
func step(direction: int) -> void:
	get_node("/root/MenuAudioService").play_ui(&"focus")
	_index = posmod(_index+direction,entries.size())
	_show_pet(direction)
	# 切到未获得随从时装备按钮会禁用，把焦点移回可操作的预览。
	if get_viewport().gui_get_focus_owner() == null:
		if _locked: %Back.grab_focus()
		else: %Preview.grab_focus()
func _show_pet(direction: int = 0) -> void:
	if is_instance_valid(_actor):
		%Actor.remove_child(_actor)
		_actor.queue_free()
	_clock = 0.0
	var entry := entries[_index]
	var pet := ContentCatalog.get_pet(entry.pet_id)
	var state := SaveService.pet_state(entry.pet_id)
	_locked = not bool(state.get("owned",false))
	%Preview.disabled = _locked
	%Preview.tooltip_text = "获得随从后可预览技能" if _locked else ""
	%Heading.texture = entry.heading
	%Heading.visible = not _locked
	%UnknownName.visible = _locked
	%Base.text = pet.base_description if state.get("owned",false) else "？？？"
	%Base.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if state.get("owned",false) else HORIZONTAL_ALIGNMENT_CENTER
	%Advanced.text = pet.advanced_description if state.get("advanced",false) else "？？？"
	%Advanced.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if state.get("advanced",false) else HORIZONTAL_ALIGNMENT_CENTER
	%Description.scroll_vertical = 0
	%Status.text = "已获得" if state.get("owned",false) else "未获得"
	%Equip.disabled = not state.get("owned",false)
	%Equip.text = "卸下" if SaveService.equipped_pet_id() == entry.pet_id else "装备"
	# 在局部副本选择快照场景，不改共享随从资源和它的局内位置。
	var display_pet := pet.duplicate() as PetDefinition
	display_pet.base_scene = entry.scene
	display_pet.advanced_scene = entry.scene
	_actor = display_pet.visual_scene(state.get("advanced",false)).instantiate() as PetVisual
	%Actor.add_child(_actor)
	_actor.scale = Vector2.ONE*entry.preview_scale
	_actor.position = entry.preview_offset
	_actor.bind(display_pet,state.get("advanced",false))
	_actor.set_world(GameplayTypes.Affinity.ZHU)
	_actor.set_state(0.0)
	# 锁定只显示首帧黑色轮廓，关闭呼吸、亮光及后续时间采样。
	if _actor.has_method("set_locked_preview"): _actor.set_locked_preview(_locked)
	_actor.modulate = Color.BLACK if _locked else Color.WHITE
	_actor.process_mode = Node.PROCESS_MODE_DISABLED if _locked else Node.PROCESS_MODE_INHERIT
	%GroundGlow.visible = not _locked
	# 投影颜色取原画的主色，仅配置菜单展示资源，不改局内角色或技能。
	if _shadow_motion: _shadow_motion.kill()
	%GroundGlow.size = entry.shadow_size
	%GroundGlow.position = entry.shadow_position-entry.shadow_size*0.5
	%GroundGlow.pivot_offset = entry.shadow_size*0.5
	%GroundGlow.scale = Vector2.ONE
	%GroundGlow.material.set_shader_parameter("glow_color",entry.shadow_color)
	%GroundGlow.material.set_shader_parameter("strength",entry.shadow_strength)
	if _selection_motion: _selection_motion.kill()
	%Actor.position.x = 960.0+direction*18.0
	%Actor.modulate.a = 0.0
	%GroundGlow.modulate.a = 0.0
	%Heading.modulate.a = 0.45
	_selection_motion = create_tween().set_parallel(true)
	_selection_motion.tween_property(%Actor,"position:x",960.0,0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for item in [%Actor,%GroundGlow,%Heading]:
		_selection_motion.tween_property(item,"modulate:a",1.0,0.22).set_trans(Tween.TRANS_SINE)
func play_skill() -> void:
	if _locked: return
	if not _actor.trigger(_clock): return
	# 技能被播放器接受时投影只舒展一次；连按不会反复点亮。
	if _shadow_motion: _shadow_motion.kill()
	_shadow_motion = create_tween()
	_shadow_motion.tween_property(%GroundGlow,"scale",Vector2(1.08,1.04),0.12).set_trans(Tween.TRANS_SINE)
	_shadow_motion.tween_property(%GroundGlow,"scale",Vector2.ONE,0.32).set_trans(Tween.TRANS_SINE)
func _process(delta: float) -> void:
	if _locked or Engine.is_editor_hint() or not is_visible_in_tree() or not is_instance_valid(_actor): return
	_clock += delta
	_actor.set_state(_clock)
func _equip() -> void:
	var id := entries[_index].pet_id
	SaveService.equip_pet("" if SaveService.equipped_pet_id() == id else id)
	%Equip.text = "卸下" if SaveService.equipped_pet_id() == id else "装备"
func _grant(advanced: bool) -> void:
	SaveService.debug_grant_pet(entries[_index].pet_id,advanced)
	_show_pet()
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		get_node("/root/MenuAudioService").play_ui(&"cancel")
		close_requested.emit()

func _input(event: InputEvent) -> void:
	super._input(event)
	if closing: return
	# 预览页方向键切换随从，避免被 Button 的默认寻焦先吃掉。
	if not is_visible_in_tree(): return
	for action: StringName in [&"menu_previous", &"menu_next"]:
		if event.is_action(action):
			get_viewport().set_input_as_handled()
			if event.is_action_pressed(action): step(-1 if action == &"menu_previous" else 1)
			return
	# 一次摇杆偏转只切一只；回中后再触发，避开轴噪声造成的连翻。
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		get_viewport().set_input_as_handled()
		if absf(event.axis_value) < 0.30: _stick_direction = 0
		elif absf(event.axis_value) >= 0.55:
			var direction := int(signf(event.axis_value))
			if direction != _stick_direction:
				_stick_direction = direction
				step(direction)
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		step(-1 if event.is_action_pressed("ui_left") else 1)
