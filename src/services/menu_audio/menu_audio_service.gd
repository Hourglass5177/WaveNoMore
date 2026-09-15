extends Node

## 菜单环境、交互与歌曲试听共用此宿主；不参与关卡时钟和判定。
const SOUNDS := preload("res://content/presentation/menu_sound_set.tres")
const MENU_ROUTES := [&"title", &"stage_select", &"local_charts", &"result"]
var _ambient: AudioStreamPlayer
var _ambient_fade: Tween
var _menu_unlocked := false
var _ambient_started := false
var _menu_route := false
var _calibrating := false
var _ui_players: Dictionary[StringName, AudioStreamPlayer] = {}
var _last_cue_usec: Dictionary[StringName, int] = {}
var _last_action_frame := -1
## 供声音接线测试读取；不记录游玩历史。
signal ui_sound_played(cue: StringName)

## 菜单试听专用播放器，固定输出到 Music 总线，不与关卡 SongClock 绑定。
var _player: AudioStreamPlayer
## 限制试听长度的一次性计时器；到时调用 `stop_preview()`。
var _preview_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)
	_player.finished.connect(stop_preview)
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.timeout.connect(stop_preview)
	add_child(_preview_timer)
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "MenuAmbient"
	_ambient.bus = &"Music"
	_ambient.stream = SOUNDS.ambient.duplicate()
	_ambient.stream.loop = true
	_ambient.volume_linear = 0.0
	add_child(_ambient)
	for cue: StringName in [&"focus", &"confirm", &"cancel", &"adjust", &"open"]:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"UI"
		voice.stream = SOUNDS.get(cue)
		voice.max_polyphony = 2
		add_child(voice)
		_ui_players[cue] = voice
	get_node("/root/AppRouter").route_requested.connect(_on_route)


## 标题画面开始显现时入声；任意键只负责展开菜单，不重新启动环境音。
func start_menu_ambient() -> void:
	if _ambient_started: return
	_ambient_started = true
	_menu_route = true
	_refresh_ambient()


func unlock_menu() -> void:
	if _menu_unlocked: return
	_menu_unlocked = true
	play_ui(&"open")


func _on_route(route: StringName, _context: Dictionary) -> void:
	if route in [&"settings", &"calibration", &"pets"]: return
	_menu_route = route in MENU_ROUTES
	if not _menu_route: stop_preview()
	# 加载期间淡出；即使加载很快，进入正式关卡也不留下环境音。
	_refresh_ambient(route == &"stage")


func set_calibrating(value: bool) -> void:
	_calibrating = value
	if value:
		stop_preview()
		for voice in _ui_players.values(): voice.stop()
	_refresh_ambient(value)


func _refresh_ambient(immediate := false) -> void:
	var audible := _ambient_started and _menu_route and not _calibrating and not _player.playing
	if _ambient_fade: _ambient_fade.kill()
	if not audible and _ambient.volume_linear == 0.0:
		_ambient.stream_paused = true
		return
	if audible:
		if not _ambient.playing: _ambient.play()
		_ambient.stream_paused = false
	elif immediate:
		_ambient.volume_linear = 0.0
		_ambient.stream_paused = true
		return
	# 原素材已有较轻的环境底色，沿用 Music 总线，不再重复压低一档音量。
	_ambient_fade = create_tween().set_trans(Tween.TRANS_SINE)
	_ambient_fade.tween_property(_ambient, "volume_linear", 1.0 if audible else 0.0, 0.65 if audible else 0.30)
	if not audible: _ambient_fade.tween_callback(func(): _ambient.stream_paused = true)


func play_ui(cue: StringName) -> void:
	if Engine.is_editor_hint() or _calibrating or cue == &"none": return
	var now := Time.get_ticks_usec()
	# 连续滚动与滑块只给轻触反馈，不堆积长尾；同一次返回由按钮和快捷键共用。
	var quiet := cue in [&"focus", &"adjust"]
	if now - _last_cue_usec.get(cue, -1000000) < (65000 if quiet else 35000): return
	var frame := Engine.get_process_frames()
	if quiet and _last_action_frame == frame: return
	_last_cue_usec[cue] = now
	if not quiet: _last_action_frame = frame
	_ui_players[cue].play()
	ui_sound_played.emit(cue)


func bind_control(control: Control) -> void:
	if control.has_meta("menu_audio_bound"): return
	control.set_meta("menu_audio_bound", true)
	control.mouse_entered.connect(func():
		if _can_sound(control): play_ui(&"focus"))
	control.focus_entered.connect(func():
		# 页面入场、关闭弹窗后的自动恢复焦点不额外发声。
		for action in [&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"ui_focus_next", &"ui_focus_prev"]:
			if Input.is_action_pressed(action) and _can_sound(control):
				play_ui(&"focus")
				break)
	if control is BaseButton:
		# 通用返回控件沿用现有命名，特殊按钮可在 Inspector 元数据 ui_sound 指定。
		var fallback := &"cancel" if control.name in [&"Back", &"Cancel", &"Close", &"Quit"] else &"confirm"
		control.pressed.connect(func(): play_ui(control.get_meta("ui_sound", fallback)))
		if control is OptionButton:
			control.item_selected.connect(func(_index: int): play_ui(&"adjust"))
	elif control is HSlider:
		control.value_changed.connect(func(_value: float):
			if _can_sound(control) and (control.has_focus() or control.get_global_rect().has_point(control.get_global_mouse_position())):
				play_ui(&"adjust"))
	elif control is LineEdit:
		control.text_submitted.connect(func(_text: String): play_ui(&"confirm"))
	elif control is ItemList:
		control.item_selected.connect(func(_index: int): play_ui(&"focus"))


func _can_sound(control: Control) -> bool:
	return control.is_visible_in_tree() and (not control is BaseButton or not control.disabled)


func play_preview(song: SongDefinition) -> void:
	stop_preview()
	if song == null or song.audio_stream == null:
		return
	_player.stream = song.audio_stream
	_player.play(song.preview_start_sec)
	_preview_timer.start(song.preview_duration_sec)
	_refresh_ambient(true)


func stop_preview() -> void:
	if _preview_timer != null:
		_preview_timer.stop()
	if _player != null:
		_player.stop()
		_player.stream = null
	if _ambient != null: _refresh_ambient()
