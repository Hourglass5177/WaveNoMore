extends Node
## 界面设备身份与鼠标显示；不参与玩法采样、按键转换或判定。
signal changed
var family: StringName = &"keyboard"
var active_device := -1
var _window_focused := true
var _gameplay_mouse_capture := false
## 失焦或手柄断开后先交还光标，收到下一次有效操作才恢复设备策略。
var _cursor_released_until_input := false
var _textures: Dictionary[String, Texture2D] = {}
var _glow_textures: Dictionary[String, Texture2D] = {}

func glow_for(action: StringName, radius: int) -> Texture2D:
	## 小键位遮罩只在装载或切换设备时生成；两次一维卷积后全局复用。
	var key := "%s:%d" % [glyph_name(action), radius]
	if _glow_textures.has(key): return _glow_textures[key]
	var source := texture_for(action).get_image()
	source.resize(roundi(source.get_width() * 36.0 / source.get_height()), 36, Image.INTERPOLATE_LANCZOS)
	var size := source.get_size() + Vector2i.ONE * radius * 2
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1, 1, 1, 0))
	mask.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ONE * radius)
	var weights := PackedFloat32Array()
	var total := 0.0
	for offset in range(-radius, radius + 1):
		var weight := exp(-float(offset * offset) / maxf(radius * radius * 0.5, 0.01))
		weights.append(weight); total += weight
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
		var output := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		for y in size.y:
			for x in size.x:
				var alpha := 0.0
				for offset in range(-radius, radius + 1):
					var pixel := Vector2i(x, y) + direction * offset
					if pixel.x >= 0 and pixel.x < size.x and pixel.y >= 0 and pixel.y < size.y:
						alpha += mask.get_pixelv(pixel).a * weights[offset + radius]
				output.set_pixel(x, y, Color(1, 1, 1, alpha / total))
		mask = output
	var texture := ImageTexture.create_from_image(mask)
	_glow_textures[key] = texture
	return texture

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_window_focused = DisplayServer.window_is_focused()
	Input.joy_connection_changed.connect(_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty(): use_device(pads[0])
	# 小图标在载入阶段准备，共用纹理；页面切换不重复栅格化 SVG。
	var sources: Dictionary = preload("res://src/app/ui/input_glyph_data.gd").SVG_SOURCES
	for key: String in sources:
		var image := Image.new()
		image.load_svg_from_string(sources[key], 2.0)
		_textures[key] = ImageTexture.create_from_image(image)

func _input(event: InputEvent) -> void:
	observe(event)

func observe(event: InputEvent) -> void:
	# 会吞掉输入的页面也从自身入口通知；重复通知不会重复发出 changed。
	if event is InputEventJoypadButton and event.pressed:
		_cursor_released_until_input = false
		use_device(event.device)
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.55:
		_cursor_released_until_input = false
		use_device(event.device)
	elif (event is InputEventKey and event.pressed and not event.echo
		or event is InputEventMouseButton and event.pressed
		or event is InputEventMouseMotion and event.relative.length() > 3.0):
		_cursor_released_until_input = false
		_set_family(&"keyboard", -1)

func use_device(device: int) -> void:
	if device == active_device:
		refresh_cursor_visibility()
		return
	# 拔出设备的队列尾部事件，以及工具合成事件，可能已无硬件信息。
	var connected := Input.get_connected_joypads().has(device)
	var info := Input.get_joy_info(device) if connected else {}
	var device_name := Input.get_joy_name(device) if connected else ""
	_set_family(detect_family(device_name + " " + str(info.get("raw_name", "")), int(info.get("vendor_id", 0))), device)

static func detect_family(device_name: String, vendor: int = 0) -> StringName:
	var name_lower := device_name.to_lower()
	if vendor == 0x054c or ["dualsense", "dualshock", "playstation", "ps4", "ps5"].any(func(tag): return tag in name_lower):
		return &"playstation"
	if vendor == 0x057e or ["nintendo", "switch", "joy-con", "joycon"].any(func(tag): return tag in name_lower):
		return &"nintendo"
	if vendor == 0x045e or "xbox" in name_lower or "xinput" in name_lower:
		return &"xbox"
	return &"generic"

func _set_family(value: StringName, device: int) -> void:
	var different := family != value or active_device != device
	family = value
	active_device = device
	refresh_cursor_visibility()
	if different: changed.emit()

func _connection_changed(device: int, connected: bool) -> void:
	if connected:
		if active_device == -1: use_device(device)
	elif device == active_device:
		_cursor_released_until_input = true
		_set_family(&"keyboard", -1)

func set_gameplay_mouse_capture(enabled: bool) -> void:
	# 调频捕获优先；结束后重新按当前设备决定显示，不恢复旧快照。
	_gameplay_mouse_capture = enabled
	refresh_cursor_visibility()

func refresh_cursor_visibility() -> void:
	var mode := Input.MOUSE_MODE_VISIBLE
	if _window_focused and not _cursor_released_until_input:
		if _gameplay_mouse_capture: mode = Input.MOUSE_MODE_CAPTURED
		elif family != &"keyboard": mode = Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != mode: Input.mouse_mode = mode

func mouse_hover_enabled() -> bool:
	return _window_focused and family == &"keyboard" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		_cursor_released_until_input = true
		refresh_cursor_visibility()
		changed.emit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true
		refresh_cursor_visibility()
		changed.emit()

func glyph_name(action: StringName) -> String:
	if action == &"stick_glow": return "stick_glow"
	if action == &"stick_base": return "stick_base"
	if action == &"stick_life": return "stick_right"
	if action == &"stick_death": return "stick_left"
	var slot: int = [&"ui_accept", &"ui_cancel", &"menu_settings", &"menu_pets", &"menu_previous", &"menu_next", &"bell_life", &"bell_death"].find(action)
	if slot < 0: return "enter"
	match family:
		&"keyboard": return ["enter", "esc", "o", "p", "q", "e", "j", "f"][slot]
		&"playstation": return ["cross", "circle", "square", "triangle", "l1", "r1", "r1", "l1"][slot]
		&"nintendo": return ["b", "a", "y", "x", "l", "r", "r", "l"][slot]
		&"xbox": return ["a", "b", "x", "y", "lb", "rb", "rb", "lb"][slot]
	return ["south", "east", "west", "north", "lb", "rb", "rb", "lb"][slot]

func texture_for(action: StringName) -> Texture2D:
	return _textures.get(glyph_name(action))
