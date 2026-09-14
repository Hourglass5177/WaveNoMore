class_name GameplayFrameProfile
extends RefCounted
## 专项测量时才计时；数据留在内存，由测试入口在结束后统一写出。
static var enabled := false
static var totals: Dictionary[StringName, float] = {}
static var calls: Dictionary[StringName, int] = {}

static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0

static func end(key: StringName, started: int) -> void:
	if not enabled: return
	totals[key] = totals.get(key, 0.0) + float(Time.get_ticks_usec() - started) / 1000.0
	calls[key] = calls.get(key, 0) + 1

static func clear() -> void:
	totals.clear()
	calls.clear()
