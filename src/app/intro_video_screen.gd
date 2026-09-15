extends Control
## 每次启动首次唤醒后的 PV。视频缺失时直接进入选关，便于未复制本地素材的队友运行。
signal finished
const VIDEO_PATH := "res://assets/pv.ogv"
const Guide = preload("res://src/app/ui/instruction_guide.gd")
var wake_event: InputEvent
var _video := VideoStreamPlayer.new()
var _design := Control.new()
var _skip := Button.new()
var _transition: Tween
var _leaving := false
var _active := false

func _ready() -> void:
	name = "IntroVideo"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.bus = &"Music"
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.modulate.a = 0.0
	_video.volume = 0.0
	add_child(_video)
	_design.size = Vector2(1920,1080)
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_design)
	_skip.text = "跳过"
	_skip.position = Vector2(1650,951)
	_skip.size = Vector2(150,58)
	_skip.flat = true
	_skip.disabled = true
	_skip.modulate.a = 0.0
	_skip.add_theme_font_override("font", Guide.FONT)
	_skip.add_theme_font_size_override("font_size", 30)
	_skip.add_theme_color_override("font_color", Guide.INK)
	_skip.add_theme_constant_override("outline_size", 3)
	_skip.add_theme_color_override("font_outline_color", Color(0,0,0,0.8))
	_design.add_child(_skip)
	var glyph := preload("res://src/app/ui/shortcut_glyph.gd").new()
	glyph.action = &"ui_accept"
	glyph.position = Vector2(-42,13)
	glyph.size = Vector2(32,32)
	_skip.add_child(glyph)
	_skip.pressed.connect(_finish)
	MenuInteraction.attach(_skip)
	resized.connect(_fit)
	_fit()
	# 不 preload 被 Git 忽略的视频，否则素材缺失会让整个应用脚本无法装载。
	if not ResourceLoader.exists(VIDEO_PATH):
		push_warning("未找到开场视频：" + VIDEO_PATH)
		finished.emit.call_deferred()
		return
	_video.stream = load(VIDEO_PATH)
	_video.finished.connect(_finish)
	if not _wake_is_held(): wake_event = null
	_video.play()
	_fit()
	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_transition.tween_property(_video, "modulate:a", 1.0, 0.45)
	_transition.tween_property(_video, "volume", 1.0, 0.45)
	_transition.tween_property(_skip, "modulate:a", 1.0, 0.45)
	_transition.chain().tween_callback(func():
		_active = true
		_skip.disabled = false
		_skip.grab_focus())

func _fit() -> void:
	var factor := minf(size.x/1920.0, size.y/1080.0)
	_design.scale = Vector2.ONE*factor
	_design.position = (size-_design.size*factor)*0.5
	var texture := _video.get_video_texture()
	var source := texture.get_size() if texture != null else Vector2(1920,1080)
	if source.x <= 0 or source.y <= 0: source = Vector2(1920,1080)
	_video.size = source*minf(size.x/source.x, size.y/source.y)
	_video.position = (size-_video.size)*0.5

func _wake_is_held() -> bool:
	if wake_event is InputEventKey:
		return Input.is_physical_key_pressed(wake_event.physical_keycode) if wake_event.physical_keycode else Input.is_key_pressed(wake_event.keycode)
	if wake_event is InputEventJoypadButton: return Input.is_joy_button_pressed(wake_event.device, wake_event.button_index)
	if wake_event is InputEventMouseButton: return Input.is_mouse_button_pressed(wake_event.button_index)
	return false

func _input(event: InputEvent) -> void:
	get_node("/root/UiInputHints").observe(event)
	# 唤醒键必须先释放；之后的再次确认才是跳过，不让长按贯穿两个页面。
	if wake_event != null:
		if not _wake_is_held(): wake_event = null
		get_viewport().set_input_as_handled()
		return
	if _active and not _leaving:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_finish()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var point: Vector2 = _skip.get_global_transform_with_canvas().affine_inverse()*event.position
			if Rect2(Vector2.ZERO,_skip.size).has_point(point): _finish()
	# 所有输入由本页消费，不能提前确认选关或触发下面的菜单。
	get_viewport().set_input_as_handled()

func _finish() -> void:
	if _leaving: return
	_leaving = true
	_active = false
	_skip.disabled = true
	if _transition: _transition.kill()
	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_transition.tween_property(_video,"modulate:a",0.0,0.3)
	_transition.tween_property(_video,"volume",0.0,0.3)
	_transition.tween_property(_skip,"modulate:a",0.0,0.3)
	await _transition.finished
	_video.stop()
	finished.emit()

func _exit_tree() -> void:
	_video.stop()
