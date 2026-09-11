class_name GrayboxHoldVisual
extends GrayboxNoteVisual

## Hold 从屏幕外以完整头身尾入场，按住后身体从尾端逐渐被消耗。
##
## Hold 的局部原点始终是头部，局部 +X 指向玩家，身体沿 -X 拖尾。
## 身体使用固定步长动态链；只有消耗进度改变有效长度，Seek 清空运动历史。

const DEFAULT_BODY_SHADER: Shader = preload("res://scenes/presentation/notes/hold_body.gdshader")

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
var _body_mesh: ArrayMesh
var _body_renderer: MeshInstance2D
var _body_glow: MeshInstance2D
var _tail_glow: MeshInstance2D
## 每个 Hold 独占可变材质参数；Inspector 资源只作为模板，不在运行时回写。
var _runtime_body_material: ShaderMaterial
var _body_material_source: ShaderMaterial
var _body_distances := PackedFloat32Array()
var _body_visual_time_sec: float = 0.0

@export_group("Hold Textures")
## 可选头部贴图，局部 +X 朝前；为空时保留程序化头部。
@export var head_texture: Texture2D
## 可沿横向无缝重复的身体贴图；为空时保留程序化身体与纹样。
@export var body_texture: Texture2D
## 可选尾部贴图，局部 +X 指向尾尖；为空时保留程序化尾部。
@export var tail_texture: Texture2D
@export_group("Hold Material")
## 身体纹理沿动态脊线累计弧长重复的像素间距。
@export_range(1.0, 512.0, 1.0, "or_greater") var body_texture_repeat_px: float = 96.0
## 可选身体材质模板；有身体贴图且此项为空时使用内置 Shader。
@export var body_material: ShaderMaterial
## 纹理每秒流过的重复次数；只由视觉时钟推进，暂停和宽限期间冻结。
@export_range(-4.0, 4.0, 0.01) var body_flow_speed: float = 0.0
## 横向柔边的 UV 宽度；也用于尾端一个纹理周期内的淡出，0 关闭柔边。
@export_range(0.0, 0.5, 0.01) var body_edge_softness: float = 0.08

@export_group("Head Control")
## 头部位置的指数响应率（s⁻¹）；沿控制圈的半径和角度平滑。
@export_range(0.1, 60.0, 0.1) var head_position_response: float = 12.0
## 头部朝向的指数响应率（s⁻¹）；总是采用最短转角。
@export_range(0.1, 60.0, 0.1) var head_heading_response: float = 12.0
var _head_control_center: Vector2 = Vector2.ZERO
var _head_position_target: Vector2 = Vector2.ZERO
var _head_heading_target: float = 0.0
var _head_position_controlled: bool = false
var _head_heading_controlled: bool = false

@export_group("Dynamic Body")
## 每段目标长度（px），尾端允许不足一个整段。
@export_range(1.0, 64.0) var segment_length_px: float = 16.0
## 与前段的最大夹角；第一段相对头部后方向。
@export_range(1.0, 90.0) var maximum_bend_deg: float = 15.0
## 夹角达到阈值时的回正角加速度（rad/s²）。
@export_range(0.0, 200.0) var restoring_acceleration: float = 30.0
## 相对角速度阻尼（s⁻¹）。
@export_range(0.0, 60.0) var angular_damping: float = 8.0
## 绝对角速度衰减率（s⁻¹）；越大越快停止甩动，0 关闭这一额外阻力。
@export_range(0.0, 60.0, 0.1) var angular_drag: float = 8.0
## 固定积分步长（秒），默认每秒 120 次。
@export_range(0.001, 0.033333, 0.000001) var integration_step_sec: float = 1.0 / 120.0


func prepare(view_model: Dictionary) -> void:
	## 由持续时间决定完整长度，重新生成时清空上一次动态链。
	super(view_model)
	if _body_glow == null:
		_body_glow = SOFT_GLOW.new()
		_body_glow.name = "BodyGlow"
		add_child(_body_glow)
		_tail_glow = SOFT_GLOW.new()
		_tail_glow.name = "TailGlow"
		add_child(_tail_glow)
	release_head_control()
	_head_control_center = Vector2.ZERO
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
	_clear_body_render_state()
	queue_redraw()


func set_approach_progress(value: float) -> void:
	## 入场仅更新路线阶段相关表现，不执行基础 Note 的渐显或缩放；保留判定反馈缩放。
	approach_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_body_target(length_px: float, frozen: bool = false) -> void:
	## Host 设置身体长度和宽限冻结状态，不在快照更新中积分。
	_target_length = maxf(length_px, 0.0)
	_spine_frozen = frozen


func advance_body(delta_sec: float) -> void:
	## 仅由时钟调用；脊线在画布坐标中模拟，最后变换到本节点绘制坐标。
	if _spine_frozen:
		return
	_body_visual_time_sec += maxf(delta_sec, 0.0)
	_advance_head_control(delta_sec)
	_dynamic_spine.segment_length = segment_length_px
	_dynamic_spine.max_angle = deg_to_rad(maximum_bend_deg)
	_dynamic_spine.stiffness = restoring_acceleration
	_dynamic_spine.damping = angular_damping
	_dynamic_spine.angular_drag = angular_drag
	_dynamic_spine.fixed_step = integration_step_sec
	if not _spine_initialized:
		_dynamic_spine.reset(position, rotation, _target_length)
		_spine_initialized = true
	_dynamic_spine.set_head_target(position, rotation)
	_dynamic_spine.set_length(_target_length)
	_dynamic_spine.advance(delta_sec)
	_update_visible_spine()
	_rebuild_body_mesh()
	_update_body_material()
	queue_redraw()


func reset_for_pool() -> void:
	## 回收同时清除积分余量、身体目标、冻结状态和基础判定反馈。
	release_head_control()
	_head_control_center = Vector2.ZERO
	_path_spine.clear()
	_clear_body_render_state()
	_dynamic_spine.clear()
	_spine_initialized = false
	_target_length = 0.0
	_spine_frozen = false
	super()


func _draw() -> void:
	var color: Color = _hold_color()
	_set_body_glow_amount()

	# 从屏幕外带着完整身体进入；只有命中后的消耗和失败末端回收才收短。
	var visual_state: Dictionary = visual_state_snapshot()
	var head_alpha: float = float(visual_state["head_alpha"])
	var body_reveal: float = float(visual_state["body_reveal"])
	var tail_alpha: float = float(visual_state["tail_alpha"])

	var spine := PackedVector2Array()
	var half_widths := PackedFloat32Array()
	if _path_spine.size() >= 2:
		_build_spine(spine, half_widths)
		if _body_glow != null and _body_glow.visible:
			_body_glow.body(spine, half_widths)
			_glow_visual.attachment(Vector2.ZERO, Vector2.LEFT, half_widths[0])
		# 贴图身体由独立 CanvasItem 绘制，其 Shader 不会覆盖头部与尾部。
		if body_texture == null:
			_draw_body(spine, half_widths, color, body_reveal)
			_draw_body_marks(spine, color)

	# 尾部始终挂在剩余身体的末端，因此按住时会一路向头部靠近，最终
	# 在谱面尾点（持续段结束）抵达头部，而不是把整条 Hold 原地缩放或突然抹除。
	if tail_alpha > 0.0 and body_reveal > 0.0 and spine.size() >= 2:
		var tail_center: Vector2 = spine[-1]
		var tail_direction: Vector2 = (spine[-1] - spine[-2]).normalized()
		if tail_texture != null:
			if _tail_glow != null and _tail_glow.visible:
				_tail_glow.position = tail_center
				_tail_glow.rotation = tail_direction.angle()
				_tail_glow.texture_shape(tail_texture, Rect2(-24.0, -24.0, 48.0, 48.0))
			draw_set_transform(tail_center, tail_direction.angle(), Vector2.ONE)
			draw_texture_rect(tail_texture, Rect2(-24.0, -24.0, 48.0, 48.0), false, Color(color, tail_alpha))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			_draw_tail(tail_center, tail_direction, color, tail_alpha)

	if head_texture != null:
		var source_size := head_texture.get_size()
		var head_extent := Vector2(96.0, 96.0)
		if source_size.x > 0.0 and source_size.y > 0.0:
			head_extent = source_size * (96.0 / maxf(source_size.x, source_size.y))
		# 头部素材与轮廓光共用尺寸和翻转，保留新版美术的方向。
		if _glow_visual != null and _glow_visual.visible:
			_glow_visual.scale = Vector2(1.0, -1.0)
			_glow_visual.texture_shape(head_texture, Rect2(-head_extent * 0.5, head_extent))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, -1.0))
		draw_texture_rect(head_texture, Rect2(-head_extent * 0.5, head_extent), false, Color(1.0, 1.0, 1.0, head_alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		if _glow_visual != null: _glow_visual.scale = Vector2.ONE
		if _glow_visual != null and spine.size() < 2:
			_glow_visual.attachment(Vector2.ZERO, Vector2.LEFT, 0.0)
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


func _update_visible_spine() -> void:
	## 截取绘制用副本；末段不足固定步长时仍精确裁短，不修改动态链的状态。
	var source: PackedVector2Array = _dynamic_spine.get_points()
	_path_spine.clear()
	_body_distances.clear()
	if source.size() < 2 or _target_length <= 0.0:
		return
	_path_spine.append(source[0])
	_body_distances.append(0.0)
	var distance: float = 0.0
	for index: int in range(1, source.size()):
		var segment: Vector2 = source[index] - source[index - 1]
		var segment_length: float = segment.length()
		if segment_length <= 0.0:
			continue
		var remaining: float = _target_length - distance
		if segment_length >= remaining:
			_path_spine.append(source[index - 1] + segment * (remaining / segment_length))
			_body_distances.append(_target_length)
			return
		distance += segment_length
		_path_spine.append(source[index])
		_body_distances.append(distance)


func _ensure_body_renderer() -> void:
	## 场景节点与直接 new() 共用同一渲染入口。材质仅属于身体子节点。
	if _body_renderer == null:
		_body_renderer = get_node_or_null(^"BodyMesh") as MeshInstance2D
		if _body_renderer == null:
			_body_renderer = MeshInstance2D.new()
			_body_renderer.name = "BodyMesh"
			add_child(_body_renderer)
		_body_renderer.show_behind_parent = true
		_body_renderer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if _runtime_body_material == null or _body_material_source != body_material:
		_body_material_source = body_material
		if body_material != null:
			_runtime_body_material = body_material.duplicate() as ShaderMaterial
		else:
			_runtime_body_material = ShaderMaterial.new()
		if _runtime_body_material.shader == null:
			_runtime_body_material.shader = DEFAULT_BODY_SHADER
		_body_renderer.material = _runtime_body_material
	if _runtime_body_material.shader == DEFAULT_BODY_SHADER:
		if not RenderingServer.frame_pre_draw.is_connected(_sync_body_self_modulate):
			RenderingServer.frame_pre_draw.connect(_sync_body_self_modulate)
		_sync_body_self_modulate()
	_body_renderer.texture = body_texture


func _rebuild_body_mesh() -> void:
	## 一个 surface 共用相邻截面的顶点。局部几何与画布弧长分别计算，不混用坐标。
	if body_texture == null or _path_spine.size() < 2:
		if _body_renderer != null:
			_body_renderer.visible = false
		if _body_mesh != null and _body_mesh.get_surface_count() > 0:
			_body_mesh.clear_surfaces()
		return
	_ensure_body_renderer()
	var spine := PackedVector2Array()
	var half_widths := PackedFloat32Array()
	_build_spine(spine, half_widths)
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index: int in range(spine.size()):
		var normal: Vector2 = _spine_normal(spine, index)
		vertices.append(spine[index] + normal * half_widths[index])
		vertices.append(spine[index] - normal * half_widths[index])
		var u: float = _body_distances[index] / maxf(body_texture_repeat_px, 1.0)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
	for index: int in range(spine.size() - 1):
		var base: int = index * 2
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	if _body_mesh == null:
		_body_mesh = ArrayMesh.new()
	else:
		_body_mesh.clear_surfaces()
	_body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_body_renderer.mesh = _body_mesh
	_body_renderer.visible = true


func _update_body_material() -> void:
	## 只同步本实例视觉状态；流动时钟来自 advance_body()，不用 Shader 的全局 TIME。
	if _runtime_body_material == null:
		return
	var color: Color = _hold_color()
	color.a = 0.42 if missed else 1.0
	var visible_length: float = _body_distances[-1] if not _body_distances.is_empty() else 0.0
	_runtime_body_material.set_shader_parameter(&"body_texture", body_texture)
	_runtime_body_material.set_shader_parameter(&"hold_progress", hold_progress)
	_runtime_body_material.set_shader_parameter(&"remaining_ratio", clampf(visible_length / body_length, 0.0, 1.0))
	_runtime_body_material.set_shader_parameter(&"body_flow_speed", body_flow_speed)
	_runtime_body_material.set_shader_parameter(&"body_edge_softness", body_edge_softness)
	_runtime_body_material.set_shader_parameter(&"affinity_color", color)
	_runtime_body_material.set_shader_parameter(&"visual_time_sec", _body_visual_time_sec)
	_runtime_body_material.set_shader_parameter(&"body_uv_length", visible_length / maxf(body_texture_repeat_px, 1.0))


func _sync_body_self_modulate() -> void:
	## 渲染前读取 Tween 更新后的自身调制，宽限冻结时也同步；不推进任何视觉时间或几何。
	## 只服务内置 Shader，不向用户自定义 Shader 强加自身染色抵消。
	if _runtime_body_material != null and _runtime_body_material.shader == DEFAULT_BODY_SHADER:
		_runtime_body_material.set_shader_parameter(&"hold_self_modulate", modulate)


func _clear_body_render_state() -> void:
	## 回收/重新 prepare 清空几何、材质副本和局部时钟；保留 Inspector 的素材模板。
	if RenderingServer.frame_pre_draw.is_connected(_sync_body_self_modulate):
		RenderingServer.frame_pre_draw.disconnect(_sync_body_self_modulate)
	_body_distances.clear()
	_body_visual_time_sec = 0.0
	_body_mesh = null
	_runtime_body_material = null
	_body_material_source = null
	if _body_renderer != null:
		_body_renderer.mesh = null
		_body_renderer.material = null
		_body_renderer.texture = null
		_body_renderer.visible = false


func _hold_color() -> Color:
	## Mesh 与灰盒头身尾共用判定色；不影响领域状态。
	if missed:
		return Color("575b66")
	var color: Color = _affinity_color()
	return color.lightened(0.22) if judgment_grade == GameplayTypes.JudgmentGrade.PERFECT else color


func _spine_normal(spine: PackedVector2Array, index: int) -> Vector2:
	## 两种身体绘制共用截面法线；所有相减的点均属于同一个局部坐标系。
	var tangent: Vector2
	if index == 0:
		tangent = spine[1] - spine[0]
	elif index == spine.size() - 1:
		tangent = spine[index] - spine[index - 1]
	else:
		tangent = spine[index + 1] - spine[index - 1]
	if tangent.is_zero_approx():
		tangent = Vector2.LEFT
	return Vector2(-tangent.y, tangent.x).normalized()


func _build_spine(spine: PackedVector2Array, half_widths: PackedFloat32Array) -> void:
	## 只沿模拟结果绘制宽度，不再移动脊线点或推进角速度。
	var motion_phase: float = _stable_phase + approach_progress * TAU * 0.85 + hold_progress * TAU * 2.2
	var canvas_to_local: Transform2D = transform.affine_inverse()
	for index: int in range(_path_spine.size()):
		var ratio: float = _body_distances[index] / _body_distances[-1]
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
		var normal: Vector2 = _spine_normal(spine, index)
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
	if _tail_glow != null and _tail_glow.visible:
		_tail_glow.transform = Transform2D.IDENTITY
		_tail_glow.polygon(tail)
		_tail_glow.attachment(center, -trail_direction, 10.0)
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
	if _glow_visual != null and _glow_visual.visible:
		_glow_visual.polygon(head)
	draw_colored_polygon(head, Color(color.darkened(0.16), alpha * 0.96))
	draw_polyline(PackedVector2Array([head[0], head[1], head[3], head[5], head[6], head[7], head[0]]), Color(color.lightened(0.32), alpha), 3.0, true)
	var eye_color := Color("f7edcf", alpha * (0.42 if missed else 0.94))
	draw_circle(Vector2(13.0, 0.0), 8.0, Color(0.02, 0.02, 0.03, alpha * 0.86), true, -1.0, true)
	draw_circle(Vector2(16.0, 0.0), 3.2, eye_color, true, -1.0, true)
	draw_line(Vector2(-14.0, -17.0), Vector2(7.0, -7.0), Color("eee3c7", alpha * 0.72), 2.0, true)
	draw_line(Vector2(-14.0, 17.0), Vector2(7.0, 7.0), Color("eee3c7", alpha * 0.72), 2.0, true)


## 全体分件共用同一份过渡强度。
func _set_glow_amount(value: float) -> void:
	super(value)
	_set_body_glow_amount()


func _set_body_glow_amount() -> void:
	# 身体消耗完后不保留上一帧的光晕网格；头部仍按自身生命周期绘制。
	if _body_glow != null:
		var body_amount: float = glow_amount * glow_strength if _path_spine.size() >= 2 else 0.0
		_body_glow.set_light(body_amount, glow_width_px)
		_tail_glow.set_light(body_amount, glow_width_px)


## Host 在首次命中时设置设计画布坐标系中的控制圈心；不改变实际姿态。
func set_head_control_center(center: Vector2) -> void:
	_head_control_center = center


## 只设置设计画布朝向目标；实际姿态只在 advance_body() 的时钟入口变化。
func set_head_heading(angle_rad: float) -> void:
	_head_heading_target = angle_rad
	_head_heading_controlled = true


## 只设置设计画布位置目标；位置采用绕圈心的极坐标插值而非弦上直线插值。
func set_head_position(target_position: Vector2) -> void:
	_head_position_target = target_position
	_head_position_controlled = true


## 忘记旧目标，保留当前插值后的实际位置和朝向；不返回命中锚点。
func release_head_control() -> void:
	_head_position_controlled = false
	_head_heading_controlled = false
	_head_position_target = position
	_head_heading_target = rotation


## 先平滑头部再推进脊线；宽限期由 advance_body() 的冻结入口整体阻止。
func _advance_head_control(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	if _head_heading_controlled:
		rotation = lerp_angle(rotation, _head_heading_target, 1.0 - exp(-head_heading_response * delta_sec))
	if _head_position_controlled:
		var current_offset: Vector2 = position - _head_control_center
		var target_offset: Vector2 = _head_position_target - _head_control_center
		var alpha: float = 1.0 - exp(-head_position_response * delta_sec)
		var current_angle: float = current_offset.angle() if not current_offset.is_zero_approx() else target_offset.angle()
		var radius: float = lerpf(current_offset.length(), target_offset.length(), alpha)
		var angle: float = lerp_angle(current_angle, target_offset.angle(), alpha)
		position = _head_control_center + Vector2.from_angle(angle) * radius
