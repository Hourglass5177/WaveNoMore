extends "res://src/app/level_carousel.gd"
## 正式选关沿用美术轮播，宿主负责加载、存档和弹窗。
signal stage_selected(stage_id: String)
signal back_requested
signal settings_requested
signal local_charts_requested
signal pets_requested
var selected_stage_id := ""

func _ready() -> void:
	super._ready()
	for index in _levels.size():
		if _levels[index].stage_id == selected_stage_id:
			set_levels(_levels,index)
			break
	stage_requested.connect(func(id: String): stage_selected.emit(id))
	$Design/Actions/Back.pressed.connect(func(): back_requested.emit())
	$Design/Actions/Local.pressed.connect(func(): local_charts_requested.emit())
	$Design/Actions/Pets.pressed.connect(func(): pets_requested.emit())
	$Design/Actions/Settings.pressed.connect(func(): settings_requested.emit())
	for arrow: Button in [$Design/Left,$Design/Right]:
		arrow.focus_mode = Control.FOCUS_NONE
		arrow.pressed.connect(grab_focus)
	grab_focus.call_deferred()

func _gui_input(event: InputEvent) -> void:
	# 焦点在卡片区时左右选关；下移到功能栏，功能栏上移回到卡片。
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		super._unhandled_input(event)
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	# 弹窗禁用底层焦点后，摇杆和返回也不能穿透。
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or (focused != self and not is_ancestor_of(focused)): return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
	elif has_focus():
		super._unhandled_input(event)

func _process(delta: float) -> void:
	if not has_focus(): _set_held_direction(0)
	super._process(delta)

func _input(event: InputEvent) -> void:
	get_node("/root/UiInputHints").observe(event)

func _shortcut_input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or (focused != self and not is_ancestor_of(focused)): return
	for action: StringName in [&"menu_pets", &"menu_settings", &"menu_previous", &"menu_next"]:
		if not event.is_action(action): continue
		get_viewport().set_input_as_handled()
		if not event.is_action_pressed(action): return
		_set_held_direction(0)
		if action == &"menu_previous" or action == &"menu_next":
			grab_focus()
			step(-1 if action == &"menu_previous" else 1)
		else:
			# 快捷键与点击共用按钮信号，关闭弹窗后自然恢复到对应入口。
			var button: Button = $Design/Actions/Pets if action == &"menu_pets" else $Design/Actions/Settings
			button.grab_focus()
			button.pressed.emit()
		return
