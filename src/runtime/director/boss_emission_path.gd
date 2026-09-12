class_name BossEmissionPath
extends RefCounted
## 提前段只改变视觉，入轨之后完整交还现有路径与真实波接触。
static func build(origin: Vector2, entrance: Vector2, entrance_velocity: Vector2, duration_us: int, handle: Vector2) -> Dictionary:
	var seconds := float(duration_us) / 1000000.0
	var controls := PackedVector2Array([origin, origin + handle, entrance - entrance_velocity * seconds / 3.0, entrance])
	var cumulative := PackedFloat32Array([0.0])
	var previous := origin
	for index in range(1, 97):
		var point := controls[0].bezier_interpolate(controls[1], controls[2], controls[3], float(index) / 96.0)
		cumulative.append(cumulative[-1] + previous.distance_to(point)); previous = point
	return {"controls": controls, "duration_us": duration_us, "lengths": cumulative}

static func sample(path: Dictionary, elapsed_us: int) -> Dictionary:
	var ratio := clampf(float(elapsed_us) / float(path.duration_us), 0, 1)
	var points: PackedVector2Array = path.controls
	var position := points[0].bezier_interpolate(points[1], points[2], points[3], ratio)
	var derivative := 3.0 * (1.0 - ratio) * (1.0 - ratio) * (points[1] - points[0]) + 6.0 * (1.0 - ratio) * ratio * (points[2] - points[1]) + 3.0 * ratio * ratio * (points[3] - points[2])
	var index := ratio * float(path.lengths.size() - 1)
	var lower := floori(index)
	var distance := lerpf(path.lengths[lower], path.lengths[mini(lower + 1, path.lengths.size() - 1)], index - lower)
	return {"position": position, "velocity": derivative / (float(path.duration_us) / 1000000.0), "distance": distance}
