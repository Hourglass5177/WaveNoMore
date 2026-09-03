class_name SuManifestationOverlay
extends Node2D

## 素音凝现的轻量表现层。
## 所有动画都由外部传入的绝对视觉时间重算，暂停、Seek 和不同帧率不会改变结果。

@export var bone_color: Color = Color("fff1d1")
@export var failure_color: Color = Color("8c8790")
@export_range(0.1, 2.0, 0.01) var lifetime_sec: float = 0.78

# 当前绝对视觉时间，单位秒。
var _visual_time_sec: float = 0.0
# 每个事件记录创建时刻、候选点和成功状态；键使用谱面的稳定事件 ID。
var _entries: Dictionary[String, Dictionary] = {}


func set_visual_time(value: float) -> void:
	_visual_time_sec = value
	var expired_ids: Array[String] = []
	for event_id: String in _entries:
		var entry: Dictionary = _entries[event_id]
		if _visual_time_sec - float(entry.get("created_at_sec", 0.0)) > lifetime_sec:
			expired_ids.append(event_id)
	for event_id: String in expired_ids:
		_entries.erase(event_id)
	queue_redraw()


func show_manifestation(
	event_id: String,
	points: PackedVector2Array,
	fallback_center: Vector2,
	successful: bool,
	visual_variant: StringName = &"default"
) -> void:
	_entries[event_id] = {
		"created_at_sec": _visual_time_sec,
		"points": points,
		"fallback_center": fallback_center,
		"successful": successful and not points.is_empty(),
		"visual_variant": visual_variant,
	}
	queue_redraw()


func remove_manifestation(event_id: String) -> void:
	_entries.erase(event_id)
	queue_redraw()


func clear() -> void:
	_entries.clear()
	queue_redraw()


func has_active_entries() -> bool:
	return not _entries.is_empty()


func debug_snapshot() -> Dictionary:
	return {
		"visual_time_sec": _visual_time_sec,
		"active_count": _entries.size(),
		"event_ids": _entries.keys(),
	}


func _draw() -> void:
	for event_id: String in _entries:
		var entry: Dictionary = _entries[event_id]
		var age_sec: float = maxf(_visual_time_sec - float(entry.get("created_at_sec", 0.0)), 0.0)
		var progress: float = clampf(age_sec / maxf(lifetime_sec, 0.001), 0.0, 1.0)
		if bool(entry.get("successful", false)):
			var points: PackedVector2Array = entry.get("points", PackedVector2Array())
			for point: Vector2 in points:
				_draw_successful_knot(point, progress)
		else:
			_draw_failed_condensation(Vector2(entry.get("fallback_center", Vector2.ZERO)), progress)


func _draw_successful_knot(center: Vector2, progress: float) -> void:
	# 先迅速凝实，再像被白纹带走一样收束淡出；不加入屏幕震动等强反馈。
	var appear: float = smoothstep(0.0, 0.20, progress)
	var fade: float = 1.0 - smoothstep(0.62, 1.0, progress)
	var alpha: float = appear * fade
	var radius: float = lerpf(30.0, 16.0, smoothstep(0.0, 0.45, progress))
	for petal_index: int in range(4):
		var angle: float = PI * 0.25 + float(petal_index) * PI * 0.5
		var direction := Vector2.from_angle(angle)
		draw_circle(center + direction * radius * 0.48, radius * 0.34, Color(bone_color, alpha * 0.30))
	draw_arc(center, radius, 0.0, TAU, 32, Color(bone_color, alpha * 0.94), 3.5, true)
	draw_circle(center, radius * 0.30, Color(bone_color, alpha * 0.88))
	draw_circle(center, radius * 0.10, Color(Color.WHITE, alpha))


func _draw_failed_condensation(center: Vector2, progress: float) -> void:
	# 失败只留下不能闭合的三段虚环，避免伪装成已经存在的骨白交点。
	var fade: float = 1.0 - smoothstep(0.35, 1.0, progress)
	var radius: float = lerpf(20.0, 54.0, progress)
	for arc_index: int in range(3):
		var start_angle: float = float(arc_index) * TAU / 3.0 + progress * 0.35
		draw_arc(
			center,
			radius + float(arc_index) * 7.0,
			start_angle,
			start_angle + PI * 0.42,
			18,
			Color(failure_color, fade * (0.58 - float(arc_index) * 0.10)),
			3.0,
			true
		)
