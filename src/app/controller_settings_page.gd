extends VBoxContainer
## 设置页独立试震；只读取草稿，不修改玩家设置或创建玩法震动源。
var _haptics: ControllerHaptics
var _device_refresh := 0.0

func _ready() -> void:
	%TestHaptics.pressed.connect(_test_haptics)
	Input.joy_connection_changed.connect(_connection_changed)
	set_process(false)

func activate() -> void:
	%HapticsResult.text = ""
	if _haptics == null:
		_haptics = ControllerHaptics.new()
		add_child(_haptics)
	_haptics.set_output_enabled(true)
	_device_refresh = 0.0
	_refresh_device()
	set_process(true)

func deactivate() -> void:
	set_process(false)
	if _haptics != null:
		# 离开分类立即释放设备，避免菜单测试与随后关卡争用输出。
		_haptics.free()
		_haptics = null

func _process(delta: float) -> void:
	_device_refresh += delta
	if _device_refresh >= 1.0:
		_device_refresh = 0.0
		_refresh_device()

func _refresh_device() -> void:
	# 连接事件延迟到UI刷新，期间可能已切换分类。
	if _haptics == null: return
	var devices := _haptics.list_devices()
	var caps := _haptics.get_capabilities()
	var available := bool(caps.get("dual_strength", false)) or bool(caps.get("mono_periodic", false)) or bool(caps.get("mono_strength", false))
	var was_focused: bool = %TestHaptics.has_focus()
	%TestHaptics.disabled = not available
	if was_focused and not available: %Haptics.grab_focus()
	if available:
		var device_name := "手柄"
		for device: Dictionary in devices:
			if int(device.device_id) == int(caps.device_id): device_name = str(device.name)
		%HapticsDevice.text = "震动设备：" + device_name
	elif not ClassDB.class_exists(&"ControllerHapticsBackend"):
		%HapticsDevice.text = "当前平台暂不支持手柄震动。"
	elif devices.is_empty():
		%HapticsDevice.text = "未连接手柄，连接后可测试震动。"
	else:
		%HapticsDevice.text = "当前手柄或连接方式不支持震动。"

func _test_haptics() -> void:
	# 每次按钮操作只保留一段80ms短震，连按不叠加；0%不会产生输出。
	_haptics.clear()
	_haptics.strength_multiplier = %Haptics.value
	if %Haptics.value == 0.0:
		%HapticsResult.text = "震动已关闭。"
	elif _haptics.play_once(ControllerHaptics.MotorSide.BOTH, 1.0, 120.0, 80.0):
		%HapticsResult.text = "已发送测试震动。"
	else:
		%HapticsResult.text = "暂时无法测试，请检查手柄连接。"
		_refresh_device()

func _connection_changed(_device: int, connected: bool) -> void:
	# Godot和原生震动设备ID不同；断连先停止本页短震，再按后端状态刷新。
	if _haptics == null: return
	if not connected: _haptics.clear()
	_refresh_device.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _haptics != null:
		_haptics.clear()

