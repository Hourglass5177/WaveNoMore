extends Node
## 只负责界面提示的设备身份，不参与玩法采样、按键转换或判定。
signal changed
var family: StringName = &"keyboard"
var active_device := -1
var _textures: Dictionary[String, Texture2D] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		use_device(event.device)
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.55:
		use_device(event.device)
	elif (event is InputEventKey and event.pressed and not event.echo
		or event is InputEventMouseButton and event.pressed
		or event is InputEventMouseMotion and event.relative.length() > 3.0):
		_set_family(&"keyboard", -1)

func use_device(device: int) -> void:
	if device == active_device: return
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
	if different: changed.emit()

func _connection_changed(device: int, connected: bool) -> void:
	if connected:
		if active_device == -1: use_device(device)
	elif device == active_device:
		var pads := Input.get_connected_joypads()
		_set_family(&"keyboard", -1)
		if not pads.is_empty(): use_device(pads[0])

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
