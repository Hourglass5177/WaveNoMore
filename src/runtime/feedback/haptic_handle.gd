class_name HapticHandle
extends RefCounted

## 外部持有的单侧持续震动源。两端均为弱引用，不通过信号形成强引用环。
## 只能经 ControllerHaptics.create_handle() 创建已注册句柄。
var _manager: WeakRef
var _valid: bool = false
var _enabled: bool = false
var _side: int = 0
var _strength: float = 0.0
var _frequency_hz: float = 120.0


func _configure(manager: Node, side: int, strength: float, frequency_hz: float) -> void:
	## 管理层内部初始化，新句柄默认关闭。
	_manager = weakref(manager)
	_side = side
	_strength = strength
	_frequency_hz = frequency_hz
	_valid = true


func is_valid() -> bool:
	## clear/release 或管理节点销毁后永久失效。
	return _valid and _manager != null and _manager.get_ref() != null


func set_enabled(enabled: bool) -> bool:
	## 只改变本句柄贡献；暂停中也可修改，恢复时采用最新状态。
	if not is_valid():
		return false
	_enabled = enabled
	_notify_changed()
	return true


func set_side(side: int) -> bool:
	## 单个句柄只属于 LEFT 或 RIGHT；改侧立即重算两侧。
	if not is_valid() or side not in [ControllerHaptics.MotorSide.LEFT, ControllerHaptics.MotorSide.RIGHT]:
		return false
	_side = side
	_notify_changed()
	return true


func set_strength(strength: float) -> bool:
	## 强度为 [0,1]；零强度不参与强度或频率合并。
	if not is_valid() or not is_finite(strength) or strength < 0.0 or strength > 1.0:
		return false
	_strength = strength
	_notify_changed()
	return true


func set_frequency(frequency_hz: float) -> bool:
	## 频率必须是有限正数 Hz，非法修改不覆盖原值。
	if not is_valid() or not is_finite(frequency_hz) or frequency_hz <= 0.0:
		return false
	_frequency_hz = frequency_hz
	_notify_changed()
	return true


func release() -> void:
	## 永久移除自身，重复调用无副作用；不停止其他震动源。
	if not is_valid():
		return
	var manager: Node = _manager.get_ref() as Node
	_invalidate()
	manager.call("_on_handle_changed")


func _invalidate() -> void:
	## 管理层批量清理使用，不回调、不在迭代中修改注册表。
	_valid = false
	_enabled = false
	_manager = null


func _notify_changed() -> void:
	## 有效句柄的修改完成后同步通知；没有绑定句柄自身的 Callable。
	var manager: Node = _manager.get_ref() as Node
	manager.call("_on_handle_changed")
