class_name GrayboxHoldVisual
extends GrayboxNoteVisual

## Hold 音符的程序绘制占位实现：头、身体、尾依次显露，按住后身体沿路径逐渐被消耗。
##
## Hold 的局部原点始终是头部，局部 +X 指向玩家，身体沿 -X 拖尾。
## 所有形变只由 approach_progress / hold_progress 计算，Seek、Replay 与不同
## 帧率会得到完全相同的轮廓。

# Hold 身体固定采样 36 个截面。固定数量可让暂停、回放和不同帧率得到同一轮廓。
const BODY_SAMPLE_COUNT: int = 36
# 以下比例都基于 approach_progress 的 0～1 进场进度，控制头、身体、尾依次出现。
const HEAD_REVEAL_END: float = 0.10
# Hold 身体在接近过程的 8% 处开始显现。
const BODY_REVEAL_START: float = 0.08
# Hold 身体到接近过程的 80% 时完全显现。
const BODY_REVEAL_END: float = 0.80
# Hold 尾部在接近过程的 76% 处开始显现，略早于身体完全展开。
const TAIL_REVEAL_START: float = 0.76
# Hold 尾部到接近过程的 96% 时完全显现。
const TAIL_REVEAL_END: float = 0.96

# Hold 身体的目标长度，单位为像素；谱面持续时间越长，prepare() 算出的长度越大。
var body_length: float = 420.0
# 由稳定事件 ID 算出的摆动起始相位，避免所有 Hold 同步扭动。
var _stable_phase: float = 0.0
# Host 预先采样的世界路径转换为局部脊线；为空时退回直线身体。
var _path_spine := PackedVector2Array()


func prepare(view_model: Dictionary) -> void:
	super(view_model)
	var start_us: int = int(view_model.get("start_us", view_model.get("start_time_us", 0)))
	var end_us: int = int(view_model.get("end_us", view_model.get("end_time_us", start_us)))
	var duration_us: int = int(view_model.get("duration_us", end_us - start_us))
	body_length = clampf(260.0 + float(duration_us) / 1_000_000.0 * 105.0, 300.0, 700.0)
	_stable_phase = float(absi(event_id.hash()) % 4096) / 4096.0 * TAU
	_path_spine.clear()
	queue_redraw()


func set_path_spine(points: PackedVector2Array) -> void:
	_path_spine = points.duplicate()
	queue_redraw()


func reset_for_pool() -> void:
	_path_spine.clear()
	super()


func _draw() -> void:
	var color: Color = _affinity_color()
	if missed:
		color = Color("575b66")
	elif judgment_grade == GameplayTypes.JudgmentGrade.PERFECT:
		color = color.lightened(0.22)

	# 进场时先显头，再从头部后方长出躯干，最后显露尾端。命中后不再
	# 依赖进场动画，而是让剩余躯干随 Hold 进度持续送向头部并缩短。
	var visual_state: Dictionary = visual_state_snapshot()
	var head_alpha: float = float(visual_state["head_alpha"])
	var body_reveal: float = float(visual_state["body_reveal"])
	var tail_alpha: float = float(visual_state["tail_alpha"])
	var visible_length: float = float(visual_state["visible_length"])

	var spine := PackedVector2Array()
	var half_widths := PackedFloat32Array()
	if visible_length > 2.0:
		_build_spine(spine, half_widths, visible_length)
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
	var head_alpha: float = smoothstep(0.0, HEAD_REVEAL_END, approach_progress)
	var body_reveal: float = smoothstep(BODY_REVEAL_START, BODY_REVEAL_END, approach_progress)
	var tail_alpha: float = smoothstep(TAIL_REVEAL_START, TAIL_REVEAL_END, approach_progress)
	var remaining: float = clampf(1.0 - hold_progress, 0.0, 1.0)
	return {
		"head_alpha": head_alpha,
		"body_reveal": body_reveal,
		"tail_alpha": tail_alpha,
		"remaining": remaining,
		"visible_length": body_length * body_reveal * remaining,
	}


func _build_spine(spine: PackedVector2Array, half_widths: PackedFloat32Array, visible_length: float) -> void:
	# phase 只来自两个规范化进度和稳定 ID；它让飘带在进场与持续期间
	# 看似游动，却不会因为累计 delta 而产生 Replay 漂移。
	var motion_phase: float = _stable_phase + approach_progress * TAU * 0.85 + hold_progress * TAU * 2.2
	for index: int in range(BODY_SAMPLE_COUNT):
		var ratio: float = float(index) / float(BODY_SAMPLE_COUNT - 1)
		var envelope: float = sin(ratio * PI)
		var center := Vector2(-visible_length * ratio, 0.0)
		var tangent := Vector2.LEFT
		if _path_spine.size() == BODY_SAMPLE_COUNT:
			center = _path_spine[index]
			if index == 0:
				tangent = _path_spine[1] - _path_spine[0]
			elif index == BODY_SAMPLE_COUNT - 1:
				tangent = _path_spine[index] - _path_spine[index - 1]
			else:
				tangent = _path_spine[index + 1] - _path_spine[index - 1]
		if tangent.is_zero_approx():
			tangent = Vector2.LEFT
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		# 大弧度由路线本身提供，这里只叠加克制且可重放的细小摆动，避免飘带难以辨认。
		var primary_wave: float = sin(ratio * TAU * 1.65 + motion_phase) * (9.0 if not _path_spine.is_empty() else 25.0)
		var secondary_wave: float = sin(ratio * TAU * 3.3 - motion_phase * 0.55) * (3.0 if not _path_spine.is_empty() else 6.0)
		center += normal * (primary_wave + secondary_wave) * envelope
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
