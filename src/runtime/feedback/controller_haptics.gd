class_name ControllerHaptics
extends Node

## 关卡共享震动管理层：合并持续句柄与单次震动，独占原生输出，不读取 Gameplay。
## 所有公开接口在主线程调用，没有 Autoload、句柄级相位或输入注入。
enum MotorSide { LEFT, RIGHT, BOTH }

const DEVICE_POLL_INTERVAL_US: int = 1_000_000

@export_group("Haptic Multipliers")
## 合并后由原生层统一应用频率倍率，强度后端忽略此值。
@export_range(0.0, 100.0, 0.01, "or_greater") var frequency_multiplier: float = 1.0:
	set(value):
		if not is_finite(value) or value < 0.0:
			return
		frequency_multiplier = value
		_refresh_multipliers()
## 合并后统一乘算并由原生层钳制的强度倍率。
@export_range(0.0, 1.0, 0.01, "or_greater") var strength_multiplier: float = 1.0:
	set(value):
		if not is_finite(value) or value < 0.0:
			return
		strength_multiplier = value
		_refresh_multipliers()

var _backend: RefCounted
var _handles: Array[WeakRef] = []
var _one_shots: Array[Dictionary] = []
var _focused: bool = false
var _output_enabled: bool = true
var _device_available: bool = false
var _device_id: int = -1
var _next_device_poll_us: int = 0
var _interface_error: String = ""
## 使用 double 精度的 float 数组，不先量化为 Vector4 单精度分量。
var _merged_output: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _last_output: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _has_submission: bool = false
var _force_resubmit: bool = true


func _init() -> void:
	## 暂停通知必须抵达，不能继承宿主的 ALWAYS 模式。
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	## 自动选设备留到帧更新或显式启用；StageRoot 可在首帧前关闭预览输出。
	_focused = DisplayServer.window_is_focused()


func create_handle(side: int, strength: float = 0.0, frequency_hz: float = 120.0) -> HapticHandle:
	## 无设备或暂停时仍可创建；默认关闭，非法参数返回 null。
	if side not in [MotorSide.LEFT, MotorSide.RIGHT] or not _valid_source(strength, frequency_hz):
		return null
	var handle := HapticHandle.new()
	handle._configure(self, side, strength, frequency_hz)
	_handles.append(weakref(handle))
	return handle


func play_once(side: int, strength: float, frequency_hz: float, duration_ms: float) -> bool:
	## 独立临时源立即参与合并；true 表示软件接受，不是机械震动测量。
	if side not in [MotorSide.LEFT, MotorSide.RIGHT, MotorSide.BOTH] or not _valid_source(strength, frequency_hz):
		return false
	if not is_finite(duration_ms) or duration_ms <= 0.0 or not _can_output():
		return false
	var now_us: int = Time.get_ticks_usec()
	if not _ensure_device(now_us):
		return false
	_one_shots.append({"side": side, "strength": strength, "frequency_hz": frequency_hz,
		"until_us": now_us + maxi(1, roundi(duration_ms * 1000.0))})
	return _refresh_output()


func set_output_enabled(enabled: bool) -> void:
	## 外部门控关闭时仅丢弃单次震动，保留持续句柄；不绕过暂停/失焦。
	_output_enabled = enabled
	if not enabled:
		_suspend_output()
	elif _can_output():
		_ensure_device(Time.get_ticks_usec())
		_refresh_output()


func clear() -> void:
	## Seek、新局、结束及销毁：全部旧句柄永久失效，保留当前设备绑定。
	for reference: WeakRef in _handles:
		var handle: HapticHandle = reference.get_ref() as HapticHandle
		if handle != null:
			handle._invalidate()
	_handles.clear()
	_one_shots.clear()
	_merged_output = [0.0, 0.0, 0.0, 0.0]
	_stop_native_output(true)


func list_devices() -> Array[Dictionary]:
	## 显式枚举本模块设备，不试震；ID 不与 Godot Input ID 通用。
	var devices: Array[Dictionary] = []
	if _ensure_backend():
		devices.assign(_backend.call("list_devices"))
	return devices


func bind_device(device_id: int) -> bool:
	## 先停旧设备、丢弃临时源，再检测能力；持续句柄在新设备可用时恢复。
	_suspend_output()
	var bound: bool = _bind_native_device(device_id)
	_next_device_poll_us = Time.get_ticks_usec() + DEVICE_POLL_INTERVAL_US
	_refresh_output()
	return bound


func get_capabilities() -> Dictionary:
	## 查询原生能力，不把句柄数推断为硬件能力。
	if not _ensure_backend():
		return {"device_id": -1, "available": false, "reason": _interface_error}
	return _backend.call("get_capabilities")


func get_output_status() -> Dictionary:
	## 原生 requested/submitted 之外提供倍率前目标；查询不推进或提交输出。
	var result: Dictionary = {"device_id": -1, "mode": "unbound", "output_active": false,
		"has_request": false, "hardware_measurement": false}
	if _backend != null:
		result = _backend.call("get_output_status")
	result["merged_target"] = {"left_frequency_hz": _merged_output[0], "left_strength": _merged_output[1],
		"right_frequency_hz": _merged_output[2], "right_strength": _merged_output[3]}
	result["suspended"] = not _can_output()
	result["output_enabled"] = _output_enabled
	result["interface_error"] = _interface_error
	return result


func set_phase_reference(left_unwrapped_phase_rad: float, right_unwrapped_phase_rad: float) -> void:
	## 保留整体相位入口，不创建震动源、不新增句柄级相位、不读取 Gameplay。
	if _can_output() and _ensure_backend():
		_backend.call("set_phase_reference", left_unwrapped_phase_rad, right_unwrapped_phase_rad)


func _process(_delta: float) -> void:
	## 到期、弱引用清理和连接维护；只在目标变化或恢复时提交，不逐帧重发。
	if _can_output():
		_ensure_device(Time.get_ticks_usec())
	_refresh_output()


func _notification(what: int) -> void:
	## 暂停保留句柄开关；恢复留给帧入口，以同时检查全部禁止条件。
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			_suspend_output()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			_force_resubmit = true
		NOTIFICATION_PAUSED:
			_suspend_output()
		NOTIFICATION_UNPAUSED:
			_force_resubmit = true


func _exit_tree() -> void:
	## 清空句柄再释放设备；外部存活的旧句柄不能重新注册。
	clear()
	if _backend != null:
		_backend.call("unbind_device")
		_backend = null
	_device_available = false
	_device_id = -1
	_focused = false


func _on_handle_changed() -> void:
	## 句柄修改或 release 后同步重算；暂停中只更新软件目标。
	_refresh_output()


func _valid_source(strength: float, frequency_hz: float) -> bool:
	## 创建和单次请求共享单位校验，不悄悄钳制上层配置。
	return is_finite(strength) and strength >= 0.0 and strength <= 1.0 and is_finite(frequency_hz) and frequency_hz > 0.0


func _can_output() -> bool:
	## 外部门控、焦点和树暂停独立生效；写谱器由 StageRoot 关闭门控。
	return _output_enabled and _focused and is_inside_tree() and not Engine.is_editor_hint() and not get_tree().paused


func _merge_source(output: Array[float], side: int, strength: float, frequency_hz: float) -> void:
	## 分别取最大值，可来自不同源；零强度不参与任何一项。
	if strength <= 0.0:
		return
	if side in [MotorSide.LEFT, MotorSide.BOTH]:
		output[0] = maxf(output[0], frequency_hz)
		output[1] = maxf(output[1], strength)
	if side in [MotorSide.RIGHT, MotorSide.BOTH]:
		output[2] = maxf(output[2], frequency_hz)
		output[3] = maxf(output[3], strength)


func _collect_sources() -> Array[float]:
	## 反向清理过期源及弱引用；只临时持有句柄，不延长到下一帧。
	var output: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for index: int in range(_handles.size() - 1, -1, -1):
		var handle: HapticHandle = _handles[index].get_ref() as HapticHandle
		if handle == null or not handle.is_valid():
			_handles.remove_at(index)
		elif handle._enabled:
			_merge_source(output, handle._side, handle._strength, handle._frequency_hz)
	var now_us: int = Time.get_ticks_usec()
	for index: int in range(_one_shots.size() - 1, -1, -1):
		var source: Dictionary = _one_shots[index]
		if now_us >= int(source["until_us"]):
			_one_shots.remove_at(index)
		else:
			_merge_source(output, int(source["side"]), float(source["strength"]), float(source["frequency_hz"]))
	return output


func _refresh_output() -> bool:
	## 唯一四参数提交入口；原生继续负责倍率、量化、降级和续期。
	_merged_output = _collect_sources()
	if not _can_output() or not _device_available:
		_stop_native_output()
		return false
	if _merged_output[1] == 0.0 and _merged_output[3] == 0.0:
		_stop_native_output()
		return true
	if _has_submission and not _force_resubmit and _merged_output == _last_output:
		return true
	var accepted: bool = bool(_backend.call("set_output", _merged_output[0], _merged_output[1],
		_merged_output[2], _merged_output[3], frequency_multiplier, strength_multiplier))
	if accepted:
		_last_output = _merged_output.duplicate()
		_has_submission = true
		_force_resubmit = false
		_interface_error = ""
	else:
		var status: Dictionary = _backend.call("get_output_status")
		_interface_error = str(status.get("last_error", status.get("reason", "Output rejected.")))
		_lose_device()
	return accepted


func _stop_native_output(force: bool = false) -> void:
	## 日常零输出不重复 stop；生命周期强制清除仅同步过相位的原生状态。
	if (_has_submission or force) and _backend != null:
		_backend.call("stop")
	_has_submission = false
	_last_output = [0.0, 0.0, 0.0, 0.0]
	_force_resubmit = true


func _suspend_output() -> void:
	## 临时中断：单次不补播，持续句柄恢复后重新合并。
	_one_shots.clear()
	_merged_output = _collect_sources()
	_stop_native_output(true)


func _lose_device() -> void:
	## 断开/驱动拒绝只移除临时源，持续开关保持；下一秒重选设备。
	_suspend_output()
	_device_available = false
	_device_id = -1
	_next_device_poll_us = Time.get_ticks_usec() + DEVICE_POLL_INTERVAL_US


func _ensure_device(now_us: int) -> bool:
	## 有绑定时查询状态；无可用绑定每秒枚举一次，不执行探测震动。
	if _device_available:
		var status: Dictionary = _backend.call("get_output_status")
		if int(status.get("device_id", -1)) == _device_id and str(status.get("mode", "")) != "unsupported":
			return true
		_lose_device()
	if now_us < _next_device_poll_us:
		return false
	_next_device_poll_us = now_us + DEVICE_POLL_INTERVAL_US
	for device: Dictionary in list_devices():
		if _bind_native_device(int(device["device_id"])) and _device_available:
			return true
	return false


func _bind_native_device(device_id: int) -> bool:
	## 原生绑定负责先停止旧设备；仅查询能力，不用播放效果测试。
	_device_available = false
	_device_id = -1
	if not _ensure_backend() or not bool(_backend.call("bind_device", device_id)):
		return false
	_device_id = device_id
	var caps: Dictionary = _backend.call("get_capabilities")
	_device_available = bool(caps.get("dual_strength", false)) or bool(caps.get("mono_periodic", false)) or bool(caps.get("mono_strength", false))
	_force_resubmit = true
	return true


func _ensure_backend() -> bool:
	## 原生类惰性实例化；扩展缺失时明确不可用，不模拟不存在的能力。
	if _backend != null:
		return true
	if not ClassDB.class_exists(&"ControllerHapticsBackend"):
		_interface_error = "ControllerHaptics native extension is unavailable."
		return false
	_backend = ClassDB.instantiate(&"ControllerHapticsBackend") as RefCounted
	return _backend != null


func _refresh_multipliers() -> void:
	## 倍率变化强制重新提交当前合并目标，不重置句柄或物理相位。
	_force_resubmit = true
	if _backend != null:
		_refresh_output()
