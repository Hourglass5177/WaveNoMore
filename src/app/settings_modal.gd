@tool
extends "res://src/app/ui/art_screen.gd"
## 四类设置共用草稿，保存时一次写盘，取消不触碰玩家配置。
signal close_requested
@export_enum("sound", "display", "controller", "calibration") var initial_tab: String = "sound"
var _sliders := {}
var _pages: Array[Control]
var _tabs: Array[Button]
var _page_motion: Tween
var _tab_index := 0
var _controls_guide: Control
var _first_page_control: Control
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	_pages = [%SoundPage, %DisplayPage, %ControllerPage, %CalibrationPage]
	_tabs = [%Sound, %Display, %Controller, %Calibration]
	for index in _tabs.size():
		_tabs[index].pressed.connect(_open_tab.bind(index))
	var fields := {"Music":"music_volume_db", "Sfx":"gameplay_sfx_volume_db", "Ui":"ui_volume_db", "Shake":"screen_shake_scale", "Flash":"flash_scale", "Wave":"tuning_wave_intensity", "Haptics":"controller_haptics_scale"}
	for key: String in fields:
		var slider: HSlider = get_node("%"+key)
		var field: String = fields[key]
		MenuInteraction.attach(slider)
		_sliders[field] = slider
		slider.value = SettingsService.get(field)
		var caption: Label = get_node("%"+key+"Value")
		var decibels: bool = slider.max_value > 2.0
		# 震动保存实际倍率0～2，界面映射到0～100%，默认倍率1显示50%。
		var display_scale := 0.5 if key == "Haptics" else 1.0
		slider.value_changed.connect(func(value: float): _show_value(caption,value * display_scale,decibels))
		_show_value(caption,slider.value * display_scale,decibels)
	for value: Vector2i in SettingsService.RESOLUTIONS:
		%Resolution.add_item("%d × %d" % [value.x,value.y])
	%Resolution.select(SettingsService.RESOLUTIONS.find(SettingsService.resolution))
	%Fullscreen.button_pressed = SettingsService.fullscreen
	if OS.has_feature("web"):
		# 网页画布随浏览器窗口变化，全屏请求留到用户点击保存时执行。
		%Resolution.clear()
		%Resolution.add_item("跟随窗口")
		%Resolution.disabled = true
		%Fullscreen.button_pressed = get_tree().root.mode == Window.MODE_FULLSCREEN
	%Debug.button_pressed = SettingsService.debug_hud_enabled
	%Debug.visible = OS.is_debug_build()
	%Save.pressed.connect(_save_and_close)
	%Cancel.pressed.connect(_close)
	%Controls.pressed.connect(_show_controls)
	%Defaults.pressed.connect(_restore_page_defaults)
	# 校准的归零逻辑复用，入口统一为底部的“恢复本页默认”。
	%CalibrationPage.get_node("%Reset").hide()
	for field in [%Resolution,%Fullscreen,%Debug]: MenuInteraction.attach(field)
	for field in [%CalibrationPage.get_node("%AudioOffset"),%CalibrationPage.get_node("%InputOffset"),%CalibrationPage.get_node("%VisualOffset")]:
		MenuInteraction.attach(field.get_line_edit())
	%Scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	var index := ["sound","display","controller","calibration"].find(initial_tab)
	select_tab(maxi(index,0))
	_tabs[maxi(index,0)].grab_focus.call_deferred()
func _show_value(label: Label, value: float, db: bool) -> void:
	label.text = "%+.1f dB" % value if db else "%d%%" % roundi(value*100.0)
func _open_tab(index: int) -> void:
	select_tab(index)
	_first_page_control.grab_focus()
func select_tab(index: int) -> void:
	_tab_index = index
	%CalibrationPage.deactivate()
	%ControllerPage.deactivate()
	for i in _pages.size():
		_pages[i].visible = index == i
		_tabs[i].set_pressed_no_signal(index == i)
		_tabs[i].modulate = Color.WHITE if index == i else Color(0.72,0.72,0.72)
	if _page_motion: _page_motion.kill()
	_pages[index].modulate.a = 0.55
	_page_motion = create_tween()
	_page_motion.tween_property(_pages[index],"modulate:a",1.0,0.18).set_trans(Tween.TRANS_SINE)
	%Scroll.scroll_vertical = 0
	if index == 2: %ControllerPage.activate()
	if index == 3: %CalibrationPage.set_process(true)
	_rebuild_navigation()
func _save_and_close() -> void:
	%CalibrationPage.deactivate()
	%ControllerPage.deactivate()
	var changes: Dictionary = %CalibrationPage.draft_values()
	for field: String in _sliders: changes[field] = _sliders[field].value
	if not OS.has_feature("web"):
		changes.resolution = SettingsService.RESOLUTIONS[%Resolution.selected]
		changes.fullscreen = %Fullscreen.button_pressed
	changes.debug_hud_enabled = %Debug.button_pressed
	var previous := {}
	for field: String in changes:
		previous[field] = SettingsService.get(field)
		SettingsService.set(field,changes[field])
	if SettingsService.save_settings():
		if OS.has_feature("web"):
			get_tree().root.mode = Window.MODE_FULLSCREEN if %Fullscreen.button_pressed else Window.MODE_WINDOWED
		close_requested.emit()
	else:
		for field: String in previous: SettingsService.set(field,previous[field])
		%Error.text = "设置未能保存，请重试。"
		if _tab_index == 2: %ControllerPage.activate()
func _close() -> void:
	%CalibrationPage.deactivate()
	%ControllerPage.deactivate()
	close_requested.emit()
func _unhandled_input(event: InputEvent) -> void:
	if _controls_guide != null: return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		get_node("/root/MenuAudioService").play_ui(&"cancel")
		_close()

func _input(event: InputEvent) -> void:
	if _controls_guide != null: return
	super._input(event)
	if closing or not is_visible_in_tree(): return
	# 设备可用性与校准状态会改变按钮禁用状态，导航前更新即可，不逐帧寻焦。
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		_rebuild_navigation()
	# 文本框中的 E 仍可输入科学计数法；肩键随时可切分类。
	if event is InputEventKey and get_viewport().gui_get_focus_owner() is LineEdit: return
	for action: StringName in [&"menu_previous", &"menu_next"]:
		if not event.is_action(action): continue
		get_viewport().set_input_as_handled()
		if event.is_action_pressed(action):
			get_node("/root/MenuAudioService").play_ui(&"focus")
			select_tab(posmod(_tab_index + (-1 if action == &"menu_previous" else 1), _pages.size()))
			_tabs[_tab_index].grab_focus()
		return

func _show_controls() -> void:
	# 暂时隔离设置内容，保留未保存的数值与滚动位置。
	$Design.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	%CalibrationPage.set_process(false)
	%ControllerPage.deactivate()
	_controls_guide = preload("res://src/app/ui/instruction_guide.gd").new()
	_controls_guide.name = "ControlsGuide"
	_controls_guide.page = _controls_guide.Page.CONTROLLER
	_controls_guide.navigation_text = "返回"
	_controls_guide.allow_cancel = true
	_controls_guide.dismissed.connect(_hide_controls)
	add_child(_controls_guide)
	_controls_guide.activate()

func _hide_controls() -> void:
	_controls_guide.queue_free()
	_controls_guide = null
	$Design.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	if _tab_index == 2: %ControllerPage.activate()
	if _tab_index == 3: %CalibrationPage.set_process(true)
	%Controls.grab_focus()

func _restore_page_defaults() -> void:
	# 未加入场景树的服务实例只提供脚本初值，不读取或写入玩家配置。
	var defaults: Node = SettingsService.get_script().new()
	for field: String in _sliders:
		if _pages[_tab_index].is_ancestor_of(_sliders[field]):
			_sliders[field].value = defaults.get(field)
	if _tab_index == 1:
		if not OS.has_feature("web"):
			%Resolution.select(SettingsService.RESOLUTIONS.find(defaults.resolution))
		%Fullscreen.button_pressed = defaults.fullscreen
		%Debug.button_pressed = defaults.debug_hud_enabled
	elif _tab_index == 2:
		%ControllerPage.deactivate()
		%ControllerPage.activate()
		%HapticsResult.text = ""
	elif _tab_index == 3:
		%CalibrationPage._reset_values()
	defaults.free()
	%Error.text = "本页已恢复默认，保存后生效。"

func _rebuild_navigation() -> void:
	# 分类区和内容区分别有确定顺序；滑条左右始终调值，不被寻焦吃掉。
	var items: Array[Control] = []
	for node: Node in _pages[_tab_index].find_children("*", "Control", true, false):
		if node is Control and node.focus_mode != Control.FOCUS_NONE and node.is_visible_in_tree():
			if node is BaseButton and node.disabled: continue
			if node is LineEdit and not node.editable: continue
			if node is ScrollBar or node is SpinBox: continue
			items.append(node)
	_first_page_control = items[0] if not items.is_empty() else %Defaults
	var menu: Array[Control] = []
	menu.assign(_tabs)
	menu.append(%Controls)
	for i in menu.size():
		menu[i].focus_neighbor_top = menu[i].get_path_to(menu[posmod(i - 1, menu.size())])
		menu[i].focus_neighbor_bottom = menu[i].get_path_to(menu[(i + 1) % menu.size()])
		menu[i].focus_neighbor_right = menu[i].get_path_to(items[0]) if not items.is_empty() else menu[i].get_path_to(%Defaults)
	var chain: Array[Control] = []
	chain.assign(items)
	chain.append_array([%Defaults, %Save, %Cancel])
	for i in chain.size():
		chain[i].focus_neighbor_top = chain[i].get_path_to(_tabs[_tab_index] if i == 0 else chain[i - 1])
		chain[i].focus_neighbor_bottom = chain[i].get_path_to(_tabs[_tab_index] if i == chain.size() - 1 else chain[i + 1])
		chain[i].focus_previous = chain[i].focus_neighbor_top
		chain[i].focus_next = chain[i].focus_neighbor_bottom
	for tab: Button in _tabs:
		tab.focus_next = tab.get_path_to(chain[0])
