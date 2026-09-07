class_name GrayboxHoldVisual
extends GrayboxNoteVisual

## Hold 从屏幕外以完整头身尾入场，按住后身体从尾端逐渐被消耗。
##
## Hold 的局部原点始终是头部，局部 +X 指向玩家，身体沿 -X 拖尾。
## 身体使用固定步长动态链；只有消耗进度改变有效长度，Seek 清空运动历史。

# Hold 身体的目标长度，单位为像素；谱面持续时间越长，prepare() 算出的长度越大。
var body_length: float = 420.0
# 由稳定事件 ID 算出的摆动起始相位，避免所有 Hold 同步扭动。
var _stable_phase: float = 0.0
# 保存模拟后的画布坐标；绘制时才转局部坐标，反馈缩放不会牵动整条身体。
var _path_spine := PackedVector2Array()
var _dynamic_spine := DynamicHoldSpine.new()
var _spine_initialized: bool = false
var _target_length: float = 0.0
var _spine_frozen: bool = false
@export_group("Dynamic Body")
## 每段目标长度（px），尾端允许不足一个整段。
@export_range(1.0, 64.0) var segment_length_px: float = 16.0
## 与前段的最大夹角；第一段相对头部后方向。
@export_range(1.0, 90.0) var maximum_bend_deg: float = 15.0
## 夹角达到阈值时的回正角加速度（rad/s²）。
@export_range(0.0, 200.0) var restoring_acceleration: float = 30.0
## 相对角速度阻尼（s⁻¹）。
@export_range(0.0, 60.0) var angular_damping: float = 8.0
## 固定积分步长（秒），默认每秒 120 次。
@export_range(0.001, 0.033333, 0.000001) var integration_step_sec: float = 1.0 / 120.0


func prepare(view_model: Dictionary) -> void:
	## 由持续时间决定完整长度，重新生成时清空上一次动态链。
	super(view_model)
	var start_us: int = int(view_model.get("start_us", view_model.get("start_time_us", 0)))
	var end_us: int = int(view_model.get("end_us", view_model.get("end_time_us", start_us)))
	var duration_us: int = int(view_model.get("duration_us", end_us - start_us))
	body_length = clampf(260.0 + float(duration_us) / 1_000_000.0 * 105.0, 300.0, 700.0)
	_stable_phase = float(absi(event_id.hash()) % 4096) / 4096.0 * TAU
	_path_spine.clear()
	_dynamic_spine.clear()
	_spine_initialized = false
	_target_length = body_length
	_spine_frozen = false
	queue_redraw()


func set_approach_progress(value: float) -> void:
	## 入场仅更新路线阶段相关表现，不执行基础 Note 的渐显或缩放；保留判定反馈缩放。
	approach_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_body_target(length_px: float, frozen: bool = false) -> void:
	## Host 设置身体长度和宽限冻结状态，不在快照更新中积分。
	_target_length = length_px
	_spine_frozen = frozen


func advance_body(delta_sec: float) -> void:
	## 仅由时钟调用；脊线在画布坐标中模拟，最后变换到本节点绘制坐标。
	if _spine_frozen:
		return
	_dynamic_spine.segment_length = segment_length_px
	_dynamic_spine.max_angle = deg_to_rad(maximum_bend_deg)
	_dynamic_spine.stiffness = restoring_acceleration
	_dynamic_spine.damping = angular_damping
	_dynamic_spine.fixed_step = integration_step_sec
	if not _spine_initialized:
		_dynamic_spine.reset(position, rotation, _target_length)
		_spine_initialized = true
	_dynamic_spine.set_head_target(position, rotation)
	_dynamic_spine.set_length(_target_length)
	_dynamic_spine.advance(delta_sec)
	_path_spine = _dynamic_spine.get_points()
	queue_redraw()


func reset_for_pool() -> void:
	## 回收同时清除积分余量、身体目标、冻结状态和基础判定反馈。
	_path_spine.clear()
	_dynamic_spine.clear()
	_spine_initialized = false
	_target_length = 0.0
	_spine_frozen = false
	super()


func _draw() -> void:
	var color: Color = _affinity_color()
	if missed:
		color = Color("575b66")
	elif judgment_grade == GameplayTypes.JudgmentGrade.PERFECT:
		color = color.lightened(0.22)

	# 从屏幕外带着完整身体进入；只有命中后的消耗和失败末端回收才收短。
	var visual_state: Dictionary = visual_state_snapshot()
	var head_alpha: float = float(visual_state["head_alpha"])
	var body_reveal: float = float(visual_state["body_reveal"])
	var tail_alpha: float = float(visual_state["tail_alpha"])
	var visible_length: float = float(visual_state["visible_length"])

	var spine := PackedVector2Array()
	var half_widths := PackedFloat32Array()
	if visible_length > 2.0 and _path_spine.size() >= 2:
		_build_spine(spine, half_widths)
		_draw_body(spine, half_widths, color, body_reveal)
		_draw_body_marks(spine, color)

	# 尾部始终挂在剩余身体的末端，因此按住时会一路向头部靠近，最终
	# 在谱面尾点（持续段结束）抵达头部，而不是把整条 Hold 原地缩放或突然抹除。
	if tail_alpha > 0.0 and body_reveal > 0.0:
		var tail_center: Vector2 = spine[-1] if not spine.is_empty() else Vector2.ZERO
		var tail_direction := Vector2.LEFT
		if spine.size() >= 2:
			tail_direction = (spine[-1] - spine[-2]).normalized()
		_draw_tail(tail_center, tail_direction, color, tail_alpha)

	_draw_head(color, head_alpha)


func visual_state_snapshot() -> Dictionary:
	# ArtLab 和自动化表现检查会读取这组只读状态；它只描述画面，绝不参与判定。
	var remaining: float = clampf(1.0 - hold_progress, 0.0, 1.0)
	return {
		"head_alpha": 1.0,
		"body_reveal": 1.0,
		"tail_alpha": 1.0,
		"remaining": remaining,
		"visible_length": body_length * remaining,
	}


func _build_spine(spine: PackedVector2Array, half_widths: PackedFloat32Array) -> void:
	## 只沿模拟结果绘制宽度，不再移动脊线点或推进角速度。
	var motion_phase: float = _stable_phase + approach_progress * TAU * 0.85 + hold_progress * TAU * 2.2
	var canvas_to_local: Transform2D = transform.affine_inverse()
	for index: int in range(_path_spine.size()):
		var ratio: float = float(index) / float(_path_spine.size() - 1)
		var envelope: float = sin(ratio * PI)
		var center: Vector2 = canvas_to_local * _path_spine[index]
		var width: float = lerpf(29.0, 10.0, pow(ratio, 0.82))
		width += sin(ratio * TAU * 2.0 + motion_phase) * 3.5 * envelope
		spine.append(center)
		half_widths.append(maxf(width, 7.0))


func _draw_body(spine: PackedVector2Array, half_widths: PackedFloat32Array, color: Color, reveal: float) -> void:
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for index: int in range(spine.size()):
		var tangent: Vector2
		if index == 0:
			tangent = spine[1] - spine[0]
		elif index == spine.size() - 1:
			tangent = spine[index] - spine[index - 1]
		else:
			tangent = spine[index + 1] - spine[index - 1]
		if tangent.is_zero_approx():
			tangent = Vector2.LEFT
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		upper.append(spine[index] + normal * half_widths[index])
		lower.append(spine[index] - normal * half_widths[index])

	var fill_alpha: float = (0.34 + reveal * 0.34) * (0.42 if missed else 1.0)
	# 急弯时整块飘带多边形可能自交，Godot 会拒绝三角化。改用逐段三角带填充，
	# 即使摆幅较大或 Hold 只剩几像素，每一段仍是合法图形。
	var fill_color := Color(color, fill_alpha)
	for index: int in range(upper.size() - 1):
		draw_colored_polygon(PackedVector2Array([
			upper[index], upper[index + 1], lower[index + 1],
		]), fill_color)
		draw_colored_polygon(PackedVector2Array([
			upper[index], lower[index + 1], lower[index],
		]), fill_color)
	draw_polyline(upper, Color(color.lightened(0.28), 0.86), 2.6, true)
	draw_polyline(lower, Color(0.025, 0.022, 0.03, 0.82), 4.0, true)
	draw_polyline(spine, Color("eee4ca", 0.72), 2.0, true)


func _draw_body_marks(spine: PackedVector2Array, color: Color) -> void:
	# 固定比例的菱形节拍纹跟随剩余身体一起向头部收拢，强化“正在被
	# 持续消费”的读感；数量不由帧率或经过时间累积。
	var mark_count: int = clampi(int(body_length / 92.0), 3, 7)
	for mark_index: int in range(1, mark_count + 1):
		var ratio: float = float(mark_index) / float(mark_count + 1)
		var sample_index: int = clampi(roundi(ratio * float(spine.size() - 1)), 0, spine.size() - 1)
		var center: Vector2 = spine[sample_index]
		var tangent := Vector2.LEFT
		if sample_index < spine.size() - 1:
			tangent = (spine[sample_index + 1] - center).normalized()
		elif sample_index > 0:
			tangent = (center - spine[sample_index - 1]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var diamond := PackedVector2Array([
			center + tangent * 7.0,
			center + normal * 6.0,
			center - tangent * 7.0,
			center - normal * 6.0,
		])
		draw_colored_polygon(diamond, Color("f3e8ca", 0.62))
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(color, 0.72), 1.2, true)


func _draw_tail(center: Vector2, trail_direction: Vector2, color: Color, alpha: float) -> void:
	if trail_direction.is_zero_approx():
		trail_direction = Vector2.LEFT
	var normal := Vector2(-trail_direction.y, trail_direction.x)
	var tail := PackedVector2Array([
		center + normal * 12.0,
		center + trail_direction * 32.0 + normal * 19.0,
		center + trail_direction * 20.0,
		center + trail_direction * 32.0 - normal * 19.0,
		center - normal * 12.0,
	])
	draw_colored_polygon(tail, Color(color.darkened(0.24), alpha * 0.90))
	draw_polyline(PackedVector2Array([tail[0], tail[1], tail[2], tail[3], tail[4]]), Color(color.lightened(0.22), alpha), 2.5, true)
	var tail_ring_radius: float = 11.0 + (1.0 - hold_progress) * 4.0
	draw_arc(center, tail_ring_radius, 0.0, TAU, 20, Color("f1e5c8", alpha * 0.76), 2.0, true)


func _draw_head(color: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	# 尖端朝局部 +X，Host 只需按路径切线设置 rotation，整条灵体就会
	# 始终面向生／死玩家，而不需要视觉脚本知道世界坐标。
	var head := PackedVector2Array([
		Vector2(-27.0, -27.0),
		Vector2(5.0, -36.0),
		Vector2(40.0, -8.0),
		Vector2(48.0, 0.0),
		Vector2(40.0, 8.0),
		Vector2(5.0, 36.0),
		Vector2(-27.0, 27.0),
		Vector2(-16.0, 0.0),
	])
	draw_colored_polygon(head, Color(color.darkened(0.16), alpha * 0.96))
	draw_polyline(PackedVector2Array([head[0], head[1], head[3], head[5], head[6], head[7], head[0]]), Color(color.lightened(0.32), alpha), 3.0, true)
	var eye_color := Color("f7edcf", alpha * (0.42 if missed else 0.94))
	draw_circle(Vector2(13.0, 0.0), 8.0, Color(0.02, 0.02, 0.03, alpha * 0.86), true, -1.0, true)
	draw_circle(Vector2(16.0, 0.0), 3.2, eye_color, true, -1.0, true)
	draw_line(Vector2(-14.0, -17.0), Vector2(7.0, -7.0), Color("eee3c7", alpha * 0.72), 2.0, true)
	draw_line(Vector2(-14.0, 17.0), Vector2(7.0, 7.0), Color("eee3c7", alpha * 0.72), 2.0, true)
