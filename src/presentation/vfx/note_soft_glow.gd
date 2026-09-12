extends MeshInstance2D

## 局部光晕覆盖层。几何来自音符自身，不读取屏幕，也不保存玩法状态。
const SHAPE_SHADER = preload("res://shaders/notes/note_soft_glow.gdshader")
const BODY_SHADER = preload("res://shaders/notes/hold_soft_glow.gdshader")
var _shader_material := ShaderMaterial.new()
var _quad := QuadMesh.new()
var _strip := ArrayMesh.new()
var width_px := 30.0
var _amount := -1.0
var _glow_color := Color.WHITE
var _edge_only := false
var _bounds := Rect2()
var _polygon := PackedVector2Array()
var _texture_source: Texture2D
var _texture_bounds := Rect2()
var _attachment := Vector4(INF, INF, INF, INF)
var _attachment_width := -1.0
var _vertices := PackedVector2Array()
var _attributes := PackedByteArray()

func _init() -> void:
	material = _shader_material
	_shader_material.shader = SHAPE_SHADER
	_shader_material.set_shader_parameter(&"radius_px", width_px)
	visible = false

func set_light(amount: float, width: float) -> void:
	if _amount != amount:
		_amount = amount
		visible = amount > 0.0
		_shader_material.set_shader_parameter(&"strength", amount)
	if width_px != width:
		width_px = width
		_shader_material.set_shader_parameter(&"radius_px", width)


func configure_style(color: Color, edge_only: bool) -> void:
	## 设置光效颜色与绘制范围；材质始终属于当前实例，不会回写共享资源。
	_glow_color = color
	_edge_only = edge_only
	_shader_material.set_shader_parameter(&"glow_color", color)
	_shader_material.set_shader_parameter(&"edge_only", edge_only)


func clear_geometry() -> void:
	## 对象池回收时丢弃上一个音符的轮廓，避免重新启用后显示旧网格。
	mesh = null
	_bounds = Rect2()
	_polygon.clear()
	_texture_source = null
	_texture_bounds = Rect2()
	_attachment = Vector4(INF, INF, INF, INF)
	_attachment_width = -1.0
	_vertices.clear()
	_attributes.clear()
	_strip.clear_surfaces()


func polygon(points: PackedVector2Array) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points: bounds = bounds.expand(point)
	_set_bounds(bounds.grow(width_px))
	var was_textured: bool = _texture_source != null
	_texture_source = null
	if not was_textured and _polygon == points: return
	_polygon = points
	_shader_material.set_shader_parameter(&"textured", false)
	_shader_material.set_shader_parameter(&"point_count", points.size())
	var padded := points.duplicate()
	padded.resize(16)
	_shader_material.set_shader_parameter(&"points", padded)

func texture_shape(source: Texture2D, bounds: Rect2) -> void:
	_set_bounds(bounds.grow(width_px))
	if source == _texture_source and bounds == _texture_bounds: return
	_texture_source = source
	_texture_bounds = bounds
	_shader_material.set_shader_parameter(&"textured", true)
	_shader_material.set_shader_parameter(&"silhouette", source)
	_shader_material.set_shader_parameter(&"texture_rect", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))

func attachment(origin: Vector2, direction: Vector2, half_width: float) -> void:
	var key := Vector4(origin.x, origin.y, direction.x, direction.y)
	if key == _attachment and half_width == _attachment_width: return
	_attachment = key
	_attachment_width = half_width
	_shader_material.set_shader_parameter(&"attached", half_width > 0.0)
	_shader_material.set_shader_parameter(&"attachment_origin", origin)
	_shader_material.set_shader_parameter(&"attachment_direction", direction)
	_shader_material.set_shader_parameter(&"attachment_width", half_width)

func _set_bounds(bounds: Rect2) -> void:
	if mesh != _quad: mesh = _quad
	if _bounds == bounds: return
	_bounds = bounds
	_quad.size = bounds.size
	_quad.center_offset = Vector3(bounds.get_center().x, bounds.get_center().y, 0.0)

func body(spine: PackedVector2Array, widths: PackedFloat32Array) -> void:
	if _shader_material.shader != BODY_SHADER:
		_shader_material.shader = BODY_SHADER
		_shader_material.set_shader_parameter(&"radius_px", width_px)
		_shader_material.set_shader_parameter(&"strength", _amount)
		_shader_material.set_shader_parameter(&"glow_color", _glow_color)
		_shader_material.set_shader_parameter(&"edge_only", _edge_only)
	var rebuild: bool = _vertices.size() != spine.size() * 2
	if rebuild:
		_vertices.resize(spine.size() * 2)
		# 未压缩颜色为 RGBA8，后跟两个 float32 UV；顶点坐标单独更新。
		_attributes.resize(_vertices.size() * 12)
		_attributes.fill(255)
	var distance := 0.0
	var total := 0.0
	for i: int in range(1, spine.size()): total += spine[i].distance_to(spine[i - 1])
	for i: int in spine.size():
		if i > 0: distance += spine[i].distance_to(spine[i - 1])
		var tangent: Vector2 = spine[mini(i + 1, spine.size() - 1)] - spine[maxi(i - 1, 0)]
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		# 常驻边缘光必须覆盖身体收束出的尖尾；判定白光仍在头尾连接处渐隐。
		var cap_alpha: float = 1.0 if _edge_only else smoothstep(12.0, 38.0, distance) * smoothstep(0.0, 12.0, total - distance)
		for side_index: int in 2:
			var side: float = -1.0 if side_index == 0 else 1.0
			var vertex_index: int = i * 2 + side_index
			_vertices[vertex_index] = spine[i] + normal * (widths[i] + width_px) * side
			_attributes[vertex_index * 12 + 3] = roundi(cap_alpha * 255.0)
			_attributes.encode_float(vertex_index * 12 + 4, side)
			_attributes.encode_float(vertex_index * 12 + 8, widths[i])
	if rebuild:
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for i: int in _vertices.size():
			uvs.append(Vector2(-1.0 if i % 2 == 0 else 1.0, widths[i / 2]))
			colors.append(Color(1, 1, 1, float(_attributes[i * 12 + 3]) / 255.0))
		for i: int in range(spine.size() - 1):
			var base: int = i * 2
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		arrays[Mesh.ARRAY_COLOR] = colors
		_strip.clear_surfaces()
		_strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		# 动态更新不自动重算包围盒；按身体长度覆盖弯曲和反馈缩放范围。
		var extent: float = total * 2.0 + width_px
		_strip.custom_aabb = AABB(Vector3(-extent, -extent, -1), Vector3(extent * 2, extent * 2, 2))
		mesh = _strip
	else:
		_strip.surface_update_vertex_region(0, 0, _vertices.to_byte_array())
		_strip.surface_update_attribute_region(0, 0, _attributes)
