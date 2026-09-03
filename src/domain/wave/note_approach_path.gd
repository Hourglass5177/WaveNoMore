class_name NoteApproachPath
extends RefCounted

## 玩法物理与表现层共享的三次贝塞尔路径。通过弧长采样把时间进度映射到路程，
## 避免音符在弯曲处忽快忽慢；位置始终由绝对歌曲时间推导。

## 默认把贝塞尔曲线离散成多少段来近似弧长；越大越平滑，但构建缓存稍慢。
const DEFAULT_SEGMENT_COUNT: int = 48
## 浮点长度比较容差，避免把几乎为零的曲线段拿去做除法。
const EPSILON: float = 0.00001


static func build_profile(
		spawn: Vector2,
		target: Vector2,
		origin: Vector2,
		outer_bend_px: float,
		center_handle_px: float,
		segment_count: int = DEFAULT_SEGMENT_COUNT
) -> Dictionary:
	var safe_segment_count: int = maxi(segment_count, 8)
	var controls: PackedVector2Array = _build_controls(
		spawn,
		target,
		origin,
		outer_bend_px,
		center_handle_px
	)
	var samples := PackedVector2Array()
	var cumulative_lengths := PackedFloat32Array()
	var total_length: float = 0.0
	var previous: Vector2 = controls[0]
	samples.append(previous)
	cumulative_lengths.append(0.0)
	for index: int in range(1, safe_segment_count + 1):
		var parameter: float = float(index) / float(safe_segment_count)
		var point: Vector2 = _cubic_point(controls, parameter)
		total_length += previous.distance_to(point)
		samples.append(point)
		cumulative_lengths.append(total_length)
		previous = point
	return {
		"controls": controls,
		"samples": samples,
		"cumulative_lengths": cumulative_lengths,
		"segment_count": safe_segment_count,
		"length_px": total_length,
	}


static func point_at_ratio(profile: Dictionary, arc_ratio: float) -> Vector2:
	var controls: PackedVector2Array = profile.get("controls", PackedVector2Array())
	if controls.size() != 4:
		return Vector2.ZERO
	return _cubic_point(controls, parameter_at_ratio(profile, arc_ratio))


static func tangent_at_ratio(profile: Dictionary, arc_ratio: float) -> Vector2:
	var controls: PackedVector2Array = profile.get("controls", PackedVector2Array())
	if controls.size() != 4:
		return Vector2.RIGHT
	var tangent: Vector2 = _cubic_tangent(controls, parameter_at_ratio(profile, arc_ratio))
	return tangent.normalized() if not tangent.is_zero_approx() else Vector2.RIGHT


static func parameter_at_ratio(profile: Dictionary, arc_ratio: float) -> float:
	var cumulative: PackedFloat32Array = profile.get("cumulative_lengths", PackedFloat32Array())
	var segment_count: int = int(profile.get("segment_count", 0))
	var total_length: float = float(profile.get("length_px", 0.0))
	if cumulative.size() < 2 or segment_count <= 0 or total_length <= EPSILON:
		return clampf(arc_ratio, 0.0, 1.0)
	var wanted_distance: float = clampf(arc_ratio, 0.0, 1.0) * total_length
	var low: int = 1
	var high: int = cumulative.size() - 1
	while low < high:
		var middle: int = (low + high) >> 1
		if cumulative[middle] + EPSILON < wanted_distance:
			low = middle + 1
		else:
			high = middle
	var upper: int = low
	var previous_distance: float = cumulative[upper - 1]
	var segment_length: float = cumulative[upper] - previous_distance
	var local_ratio: float = 0.0
	if segment_length > EPSILON:
		local_ratio = (wanted_distance - previous_distance) / segment_length
	return (float(upper - 1) + clampf(local_ratio, 0.0, 1.0)) / float(segment_count)


static func length(profile: Dictionary) -> float:
	return maxf(float(profile.get("length_px", 0.0)), 0.0)


static func _build_controls(
		spawn: Vector2,
		target: Vector2,
		origin: Vector2,
		outer_bend_px: float,
		center_handle_px: float
) -> PackedVector2Array:
	var incoming: Vector2 = (target - spawn).normalized()
	if incoming.is_zero_approx():
		incoming = Vector2.LEFT
	var turn_normal := Vector2(-incoming.y, incoming.x)
	var toward_origin: Vector2 = (origin - target).normalized()
	if toward_origin.is_zero_approx():
		toward_origin = incoming
	# 第一个控制柄把两侧路径拉成相反的弧瓣；第二个放在共享中心之后、沿中心到钟的射线，
	# 让未解决音符穿过中心后继续飞向钟时不会突然折向。
	var first_handle: Vector2 = spawn.lerp(target, 0.36) + turn_normal * outer_bend_px
	var second_handle: Vector2 = target - toward_origin * center_handle_px
	return PackedVector2Array([spawn, first_handle, second_handle, target])


static func _cubic_point(controls: PackedVector2Array, parameter: float) -> Vector2:
	var t: float = clampf(parameter, 0.0, 1.0)
	var inverse: float = 1.0 - t
	return (
		controls[0] * inverse * inverse * inverse
		+ controls[1] * 3.0 * inverse * inverse * t
		+ controls[2] * 3.0 * inverse * t * t
		+ controls[3] * t * t * t
	)


static func _cubic_tangent(controls: PackedVector2Array, parameter: float) -> Vector2:
	var t: float = clampf(parameter, 0.0, 1.0)
	var inverse: float = 1.0 - t
	return (
		(controls[1] - controls[0]) * 3.0 * inverse * inverse
		+ (controls[2] - controls[1]) * 6.0 * inverse * t
		+ (controls[3] - controls[2]) * 3.0 * t * t
	)
