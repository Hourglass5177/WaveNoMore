@tool
extends "res://src/app/ui/art_screen.gd"
## 正式标题页只管理展示与输入；切页、设置和退出仍由 AppMain 接管。
signal start_requested
signal settings_requested
signal credits_requested
signal quit_requested
signal menu_revealed

enum Phase { WAITING, REVEALING, MENU, LEAVING, SPLASH }
@export var show_boot_splash := false
@export var skip_prompt := false
@export_group("标题静息")
@export_range(1.0, 10.0, 0.1) var title_period := 4.8
@export_range(0.0, 8.0, 0.1) var title_float_px := 2.0
@export_range(0.0, 1.0, 0.01) var glow_min := 0.18
@export_range(0.0, 1.0, 0.01) var glow_max := 0.26

var phase := Phase.WAITING
var _transition: Tween
var _breath: Tween
var _idle_age := 0.0
var _title_origin := Vector2.ZERO
var _button_origins: Array[Vector2] = []
var _button_tints: Array[Tween] = []
## 保存唤醒键，直到它真正松开；长按跨过入场结束也不能确认菜单。
var _wake_event: InputEvent
@onready var _prompt: TextureRect = %Prompt
@onready var _title: Control = %TitleArt
@onready var _glow: ColorRect = %TitleGlow
@onready var _buttons: Array[Button] = [%Start, %Credits, %Settings, %Quit]

func _ready() -> void:
	_title_origin = _title.position
	super._ready()
	if Engine.is_editor_hint(): return
	for i in _buttons.size():
		var button := _buttons[i]
		_button_origins.append(button.position)
		_button_tints.append(null)
		button.focus_neighbor_left = button.get_path_to(_buttons[posmod(i-1,4)])
		button.focus_neighbor_right = button.get_path_to(_buttons[(i+1)%4])
		button.focus_neighbor_top = button.focus_neighbor_left
		button.focus_neighbor_bottom = button.focus_neighbor_right
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right
		button.focus_entered.connect(_tint_button.bind(i,true))
		button.focus_exited.connect(_tint_button.bind(i,false))
		button.pressed.connect(_activate.bind(i))
		button.disabled = true
	if skip_prompt:
		_prompt.hide()
		_menu_ready()
	else:
		_prompt.show()
		_title.modulate.a = 0.0
		for button in _buttons: button.modulate.a = 0.0
		_breath = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_breath.tween_property(_prompt,"modulate:a",0.8,1.5)
		_breath.tween_property(_prompt,"modulate:a",1.0,1.5)

	if show_boot_splash and not skip_prompt:
		phase = Phase.SPLASH
		var splash := preload("res://scenes/screens/boot_splash.tscn").instantiate()
		splash.finished.connect(func():
			phase = Phase.WAITING
			splash.queue_free()
		)
		add_child(splash)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or phase != Phase.MENU or not is_visible_in_tree(): return
	_idle_age += delta
	var angle := TAU * _idle_age / title_period
	_title.position = _title_origin + Vector2(0.0,sin(angle)*title_float_px)
	_glow.material.set_shader_parameter("strength",lerpf(glow_min,glow_max,(1.0-cos(angle))*0.5))

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	get_node("/root/UiInputHints").observe(event)
	if phase in [Phase.LEAVING, Phase.SPLASH]:
		get_viewport().set_input_as_handled()
		return
	if _wake_event != null and _same_wake_button(event):
		if not event.is_pressed(): _wake_event = null
		get_viewport().set_input_as_handled()
		return
	if phase == Phase.WAITING:
		if _is_wake_press(event):
			_wake_event = event
			_reveal()
		get_viewport().set_input_as_handled()
	elif phase == Phase.REVEALING:
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.relative != Vector2.ZERO and _menu_has_input():
		# 只在实际移动鼠标时转移焦点，启动时停在按钮上的指针不抢默认项。
		for button in _buttons:
			var local_mouse: Vector2 = button.get_global_transform_with_canvas().affine_inverse() * event.position
			if Rect2(Vector2.ZERO,button.size).has_point(local_mouse):
				button.grab_focus()
				break

func _is_wake_press(event: InputEvent) -> bool:
	if event is InputEventKey: return event.pressed and not event.echo
	if event is InputEventJoypadButton: return event.pressed
	if event is InputEventMouseButton:
		return event.pressed and event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]
	return false

func _same_wake_button(event: InputEvent) -> bool:
	if event.get_class() != _wake_event.get_class(): return false
	if event is InputEventKey:
		return event.physical_keycode == _wake_event.physical_keycode and event.keycode == _wake_event.keycode
	return event.device == _wake_event.device and event.button_index == _wake_event.button_index

func _reveal() -> void:
	phase = Phase.REVEALING
	_breath.kill()
	_title.position = _title_origin + Vector2(0,8)
	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(_prompt,"modulate:a",0.0,0.16)
	_transition.tween_property(_title,"modulate:a",1.0,0.40).set_delay(0.12)
	_transition.tween_property(_title,"position",_title_origin,0.40).set_delay(0.12)
	for i in _buttons.size():
		_buttons[i].position = _button_origins[i] + Vector2(0,10)
		_transition.tween_property(_buttons[i],"modulate:a",1.0,0.24).set_delay(0.28+i*0.06)
		_transition.tween_property(_buttons[i],"position",_button_origins[i],0.24).set_delay(0.28+i*0.06)
	_transition.chain().tween_callback(_menu_ready)

func _menu_ready() -> void:
	phase = Phase.MENU
	_prompt.hide()
	for button in _buttons: button.disabled = false
	_buttons[0].grab_focus()
	menu_revealed.emit()

func _menu_has_input() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and is_ancestor_of(focus)

func _tint_button(index: int, selected: bool) -> void:
	if _button_tints[index]: _button_tints[index].kill()
	var motion := create_tween().set_trans(Tween.TRANS_SINE)
	_button_tints[index] = motion
	motion.tween_property(_buttons[index].get_node("Art"),"self_modulate",Color(1.22,1.18,1.12) if selected else Color(0.83,0.81,0.80),0.16)

func _activate(index: int) -> void:
	if phase != Phase.MENU or not _menu_has_input(): return
	match index:
		0,3:
			phase = Phase.LEAVING
			for button in _buttons: button.disabled = true
			await fade_out()
			if index == 0: start_requested.emit()
			else: quit_requested.emit()
		1: credits_requested.emit()
		2: settings_requested.emit()
