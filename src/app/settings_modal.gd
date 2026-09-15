@tool
extends "res://src/app/ui/art_screen.gd"
## 三类设置共用草稿，保存时一次写盘，取消不触碰玩家配置。
signal close_requested
@export_enum("sound", "display", "calibration") var initial_tab: String = "sound"
var _sliders := {}
var _pages: Array[Control]
var _tabs: Array[Button]
var _page_motion: Tween
var _tab_index := 0
var _controls_guide: Control
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	_pages = [%SoundPage, %DisplayPage, %CalibrationPage]
	_tabs = [%Sound, %Display, %Calibration]
	for index in 3:
		_tabs[index].pressed.connect(select_tab.bind(index))
	var fields := {"Music":"music_volume_db", "Sfx":"gameplay_sfx_volume_db", "Ui":"ui_volume_db", "Shake":"screen_shake_scale", "Flash":"flash_scale", "Wave":"tuning_wave_intensity"}
	for key: String in fields:
		var slider: HSlider = get_node("%"+key)
		var field: String = fields[key]
		MenuInteraction.attach(slider)
		_sliders[field] = slider
		slider.value = SettingsService.get(field)
		var caption: Label = get_node("%"+key+"Value")
		var decibels: bool = slider.max_value > 2.0
		slider.value_changed.connect(func(value: float): _show_value(caption,value,decibels))
		_show_value(caption,slider.value,decibels)
	for value: Vector2i in SettingsService.RESOLUTIONS:
		%Resolution.add_item("%d × %d" % [value.x,value.y])
	%Resolution.select(SettingsService.RESOLUTIONS.find(SettingsService.resolution))
	%Fullscreen.button_pressed = SettingsService.fullscreen
	%Debug.button_pressed = SettingsService.debug_hud_enabled
	%Debug.visible = OS.is_debug_build()
	%Save.pressed.connect(_save_and_close)
	%Cancel.pressed.connect(_close)
	%Controls.pressed.connect(_show_controls)
	for field in [%Resolution,%Fullscreen,%Debug]: MenuInteraction.attach(field)
	for field in [%CalibrationPage.get_node("%AudioOffset"),%CalibrationPage.get_node("%InputOffset"),%CalibrationPage.get_node("%VisualOffset")]:
		MenuInteraction.attach(field.get_line_edit())
	var index := ["sound","display","calibration"].find(initial_tab)
	select_tab(maxi(index,0))
	_tabs[maxi(index,0)].grab_focus.call_deferred()
func _show_value(label: Label, value: float, db: bool) -> void:
	label.text = "%+.1f dB" % value if db else "%d%%" % roundi(value*100.0)
func select_tab(index: int) -> void:
	_tab_index = index
	%CalibrationPage.deactivate()
	for i in 3:
		_pages[i].visible = index == i
		_tabs[i].set_pressed_no_signal(index == i)
		_tabs[i].modulate = Color.WHITE if index == i else Color(0.72,0.72,0.72)
	if _page_motion: _page_motion.kill()
	_pages[index].modulate.a = 0.55
	_page_motion = create_tween()
	_page_motion.tween_property(_pages[index],"modulate:a",1.0,0.18).set_trans(Tween.TRANS_SINE)
	%Scroll.scroll_vertical = 0
	if index == 2: %CalibrationPage.set_process(true)
func _save_and_close() -> void:
	%CalibrationPage.deactivate()
	var changes: Dictionary = %CalibrationPage.draft_values()
	for field: String in _sliders: changes[field] = _sliders[field].value
	changes.resolution = SettingsService.RESOLUTIONS[%Resolution.selected]
	changes.fullscreen = %Fullscreen.button_pressed
	changes.debug_hud_enabled = %Debug.button_pressed
	var previous := {}
	for field: String in changes:
		previous[field] = SettingsService.get(field)
		SettingsService.set(field,changes[field])
	if SettingsService.save_settings():
		close_requested.emit()
	else:
		for field: String in previous: SettingsService.set(field,previous[field])
		%Error.text = "设置未能保存，请重试。"
func _close() -> void:
	%CalibrationPage.deactivate()
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
	if _tab_index == 2: %CalibrationPage.set_process(true)
	%Controls.grab_focus()
