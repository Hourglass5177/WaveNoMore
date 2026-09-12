class_name SuManifestationOverlay
extends Node2D

## 素音目标及原地命中动画。存储坐标全部为 UV，只有绘制时转成画布像素。
## 外部使用 Gameplay 判定时钟推进；查询和绘制不推进生命周期。

@export var canvas_size: Vector2 = Vector2(1920.0, 1080.0):
	set(value):
		if canvas_size == value: return
		canvas_size = value
		queue_redraw()
@export var bone_color: Color = Color("fff1d1")
@export var failure_color: Color = Color("8c8790")
@export_range(0.1, 2.0, 0.01) var lifetime_sec: float = 0.78

var _visual_time_sec: float = 0.0
## 每个事件含多个独立圆形目标；已准备的位置不会被结果快照覆盖。
var _entries: Dictionary[String, Dictionary] = {}


func prepare_targets(event_data: Dictionary) -> void:
	## 为首次预测成功的全部 UV 点创建固定目标；重复快照不重新生成。
	var event_id: String = str(event_data["event_id"])
	if _entries.has(event_id):
		return
	var points_uv := PackedVector2Array()
	for point: Vector2 in event_data.get("points", []):
		points_uv.append(point)
	if points_uv.is_empty():
		return
	var variant: StringName = StringName(event_data.get("target_visual_variant", &""))
	if variant == &"":
		variant = StringName(event_data.get("visual_variant", &"default"))
	_entries[event_id] = {
		"points": points_uv,
		"target_time_sec": float(event_data["time_us"]) / 1_000_000.0,
		"duration_sec": float(event_data.get("target_hold_duration_sec", lifetime_sec)),
		"visual_variant": variant,
		"resolved": false,
		"success": false,
	}
	queue_redraw()


func resolve_targets(result: Dictionary) -> void:
	## 在原目标位置播放一次结果；无合法目标的 Miss 不凭空创建中心 Note。
	var event_id: String = str(result["event_id"])
	if not _entries.has(event_id):
		return
	var entry: Dictionary = _entries[event_id]
	if bool(entry["resolved"]):
		return
	entry["resolved"] = true
	entry["success"] = bool(result["success"])
	queue_redraw()


func set_visual_time(time_sec: float) -> void:
	## 使用绝对判定时间过期；等待目标时不回收，暂停不增长动画年龄。
	_visual_time_sec = time_sec
	var animating := false
	for event_id: String in _entries.keys():
		var entry: Dictionary = _entries[event_id]
		if not bool(entry["resolved"]): continue
		animating = true
		if time_sec >= float(entry["target_time_sec"]) + float(entry["duration_sec"]):
			_entries.erase(event_id)
	# 未结算的目标完全静止，保留已有绘制命令；只重画结果动画或过期帧。
	if animating: queue_redraw()


func clear() -> void:
	## Seek、重试和会话清场时释放全部图案和时钟状态。
	_entries.clear()
	_visual_time_sec = 0.0
	queue_redraw()


func has_active_entries() -> bool:
	## 供父层判断可见性，不依赖当前是否还有载波或调频条。
	return not _entries.is_empty()


func debug_snapshot() -> Dictionary:
	## 仅返回状态摘要，不推进动画。
	return {"time_sec": _visual_time_sec, "active_count": _entries.size(), "event_ids": _entries.keys()}


func _draw() -> void:
	for entry: Dictionary in _entries.values():
		var progress: float = clampf(
			(_visual_time_sec - float(entry["target_time_sec"])) / float(entry["duration_sec"]), 0.0, 1.0
		)
		for uv: Vector2 in entry["points"]:
			var center: Vector2 = uv * canvas_size
			if not bool(entry["resolved"]):
				_draw_target(center)
			elif bool(entry["success"]):
				_draw_hit(center, progress)
			else:
				_draw_miss(center, progress)


func _draw_target(center: Vector2) -> void:
	## 高对比圆形目标：预读期间不移动、不渐隐，区别于载波背景。
	draw_circle(center, 32.0, Color("111827"))
	draw_circle(center, 25.0, bone_color)
	draw_arc(center, 34.0, 0.0, TAU, 64, Color("36e6ff"), 5.0, true)
	draw_circle(center, 7.0, Color.WHITE)


func _draw_hit(center: Vector2, progress: float) -> void:
	## 原地闪亮、收缩和外扩圆环；整个动画始终使用同一个中心。
	var fade: float = 1.0 - progress
	var radius: float = lerpf(30.0, 0.0, smoothstep(0.0, 1.0, progress))
	draw_circle(center, radius, Color(bone_color.lerp(Color.WHITE, fade), fade))
	draw_arc(center, lerpf(34.0, 78.0, progress), 0.0, TAU, 64, Color(0.2, 0.9, 1.0, fade), 5.0, true)


func _draw_miss(center: Vector2, progress: float) -> void:
	## 已有目标但调频组失败时，只在真实目标原位播放断裂圆环。
	for index: int in range(3):
		var start: float = float(index) * TAU / 3.0
		draw_arc(center, lerpf(34.0, 52.0, progress), start, start + PI * 0.45,
			24, Color(failure_color, 1.0 - progress), 4.0, true)
