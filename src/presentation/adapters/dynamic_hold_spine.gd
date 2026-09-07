class_name DynamicHoldSpine
extends RefCounted

## 设计画布坐标中的单向动态链。目标更新不积分；advance 是唯一推进入口。
var segment_length: float = 16.0
var max_angle: float = deg_to_rad(15.0)
var stiffness: float = 30.0
var damping: float = 8.0
## 画布坐标中的绝对角速度衰减率（s⁻¹），耗散整链同向摆动。
var angular_drag: float = 8.0
var fixed_step: float = 1.0 / 120.0
var _points := PackedVector2Array()
var _angles := PackedFloat64Array()
var _velocities := PackedFloat64Array()
var _head := Vector2.ZERO
var _heading: float = 0.0
var _target_head := Vector2.ZERO
var _target_heading: float = 0.0
var _length: float = 0.0
var _remainder: float = 0.0


func reset(head_position: Vector2, heading_rad: float, length_px: float) -> void:
	## 从头后方初始化，不继承上一次对象池使用的运动状态。
	clear()
	_head = head_position
	_heading = heading_rad
	set_head_target(head_position, heading_rad)
	set_length(length_px)
	_resize_chain()


func set_head_target(head_position: Vector2, heading_rad: float) -> void:
	## 设置下次时钟推进的画布位置/弧度朝向，不在此搬动身体或累计时间。
	_target_head = head_position
	_target_heading = heading_rad


func set_length(length_px: float) -> void:
	## 只更改有效长度；推进时从尾端增删段，保留前段状态。
	_length = maxf(length_px, 0.0)


func advance(delta_sec: float) -> void:
	## 固定步长推进，子步间插值目标位置与最短转角。
	if delta_sec <= 0.0:
		return
	_remainder += delta_sec
	var count: int = floori(_remainder / fixed_step)
	if count == 0:
		return
	_remainder -= float(count) * fixed_step
	# 指数衰减不会因增大阻尼而把角速度反向；仅在固定模拟子步中生效。
	var drag_factor: float = exp(-angular_drag * fixed_step)
	var initial_head: Vector2 = _head
	var initial_heading: float = _heading
	for step_index: int in range(count):
		var ratio: float = float(step_index + 1) / float(count)
		var next_heading: float = lerp_angle(initial_heading, _target_heading, ratio)
		var reference_velocity: float = wrapf(next_heading - _heading, -PI, PI) / fixed_step
		_heading = next_heading
		_head = initial_head.lerp(_target_head, ratio)
		_resize_chain()
		var reference_angle: float = _heading + PI
		for index: int in range(_angles.size()):
			var prediction: Vector2 = _points[index + 1] - _points[index]
			var angle: float = prediction.angle() if not prediction.is_zero_approx() else _angles[index]
			var theta: float = wrapf(angle - reference_angle, -PI, PI)
			# 头部瞬间转向或平移后，预测角也先满足硬限位，避免远超阈值的三次力爆增。
			if absf(theta) > max_angle:
				angle = reference_angle + clampf(theta, -max_angle, max_angle)
				theta = clampf(theta, -max_angle, max_angle)
			var x: float = theta / max_angle
			var velocity: float = _velocities[index]
			velocity += (-stiffness * x * x * x - damping * (velocity - reference_velocity)) * fixed_step
			# 相对阻尼控制段间摆动，绝对阻力消耗整链的残余角速度。
			velocity *= drag_factor
			angle += velocity * fixed_step
			theta = wrapf(angle - reference_angle, -PI, PI)
			if absf(theta) > max_angle:
				angle = reference_angle + clampf(theta, -max_angle, max_angle)
				if (velocity - reference_velocity) * theta > 0.0:
					velocity = reference_velocity
			_angles[index] = angle
			_velocities[index] = velocity
			var length_px: float = minf(segment_length, _length - float(index) * segment_length)
			_points[index + 1] = _points[index] + Vector2.from_angle(angle) * length_px
			reference_angle = angle
			reference_velocity = velocity


func get_points() -> PackedVector2Array:
	## 返回只读用途的副本，不推进模拟。
	return _points.duplicate()


func clear() -> void:
	## 会话、Seek、对象回收均清空积累的运动状态与时间余量。
	_points.clear()
	_angles.clear()
	_velocities.clear()
	_remainder = 0.0
	_length = 0.0
	_head = Vector2.ZERO
	_target_head = Vector2.ZERO
	_heading = 0.0
	_target_heading = 0.0


func _resize_chain() -> void:
	## 固定段长，最后一段承担不足整段的有效长度。
	var count: int = ceili(_length / segment_length)
	if count == 0:
		_points.clear()
		_angles.clear()
		_velocities.clear()
		return
	if _points.is_empty():
		_points.append(_head)
	_points[0] = _head
	while _angles.size() < count:
		var angle: float = _angles[-1] if not _angles.is_empty() else _heading + PI
		_angles.append(angle)
		_velocities.append(0.0)
		var new_length: float = minf(segment_length, _length - float(_angles.size() - 1) * segment_length)
		_points.append(_points[-1] + Vector2.from_angle(angle) * new_length)
	_angles.resize(count)
	_velocities.resize(count)
	_points.resize(count + 1)
