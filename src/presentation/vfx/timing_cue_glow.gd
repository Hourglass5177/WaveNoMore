class_name TimingCueGlow
extends MeshInstance2D

## 同一提示的所有柔光弧合为一个网格；静止时不重新提交几何。
const SHADER := preload("res://shaders/fields/timing_cue_glow.gdshader")
var _geometry := ArrayMesh.new()
var _key: Array = []
var _vertices := PackedVector2Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var rebuild_count: int = 0
var _ring_extent := -1.0
var _ring_style_key: Array = []

func set_rings(radius: float, outer_radius: float, progress: float, alpha: float, extent: float, style: TimingCueStyle, side: int, direction: float = 1.0) -> void:
	var surface := material as ShaderMaterial
	if _ring_extent != extent:
		# 圆形提示使用固定四边形，所有圆弧由同一个局部 shader 合成。
		_geometry.clear_surfaces()
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-extent, -extent), Vector2(extent, -extent), Vector2(extent, extent), Vector2(-extent, extent)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_ring_extent = extent; rebuild_count += 1
		surface.set_shader_parameter(&"ring_mode", true)
	var halo := style.halo_color(side)
	var glow := Vector4(style.progress_glow_width + style.progress_width * 0.5, style.approach_glow_width + style.approach_width * 0.5, style.progress_glow_strength, style.approach_glow_strength)
	if _ring_style_key != [halo, glow]:
		_ring_style_key = [halo, glow]
		surface.set_shader_parameter(&"halo_color", halo)
		surface.set_shader_parameter(&"glow_data", glow)
	var key := [radius, outer_radius, progress, alpha, direction]
	if _key != key:
		_key = key
		surface.set_shader_parameter(&"ring_data", Vector4(radius, outer_radius, progress, alpha))
		surface.set_shader_parameter(&"sweep_direction", direction)
	visible = true

func _init() -> void:
	mesh = _geometry
	var surface := ShaderMaterial.new()
	surface.shader = SHADER
	material = surface
	show_behind_parent = true
	visible = false

func begin(key: Array) -> bool:
	if key == _key: return false
	_key = key.duplicate()
	_vertices.resize(0); _uvs.resize(0); _colors.resize(0); _indices.resize(0)
	return true

static func arc(center: Vector2, radius: float, from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := maxi(2, ceili(absf(to - from) * radius / 6.0))
	points.resize(count + 1)
	for i: int in count + 1:
		points[i] = center + Vector2.from_angle(lerpf(from, to, float(i) / count)) * radius
	return points

func add_strip(points: PackedVector2Array, half_width: float, color: Color, closed: bool = false) -> void:
	if points.size() < 2: return
	var distances := PackedFloat32Array(); distances.resize(points.size())
	for i: int in range(1, points.size()): distances[i] = distances[i - 1] + points[i].distance_to(points[i - 1])
	var total := distances[-1]
	var base := _vertices.size()
	var index_base := _indices.size()
	var size := base + points.size() * 2
	_vertices.resize(size); _uvs.resize(size); _colors.resize(size)
	_indices.resize(index_base + (points.size() - 1) * 6)
	for i: int in points.size():
		var before: Vector2 = points[i - 1] if i > 0 else (points[-2] if closed else points[0])
		var after: Vector2 = points[i + 1] if i + 1 < points.size() else (points[1] if closed else points[-1])
		var normal := (after - before).normalized().orthogonal() * half_width
		var fade := 1.0 if closed else minf(distances[i], total - distances[i]) / half_width
		var v := base + i * 2
		_vertices[v] = points[i] + normal; _vertices[v + 1] = points[i] - normal
		_uvs[v] = Vector2(fade, 1.0); _uvs[v + 1] = Vector2(fade, -1.0)
		_colors[v] = color; _colors[v + 1] = color
		if i > 0:
			var k := index_base + (i - 1) * 6
			_indices[k] = v - 2; _indices[k + 1] = v - 1; _indices[k + 2] = v
			_indices[k + 3] = v - 1; _indices[k + 4] = v + 1; _indices[k + 5] = v

func finish() -> void:
	_geometry.clear_surfaces()
	visible = not _indices.is_empty()
	if not visible: return
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices; arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = _colors; arrays[Mesh.ARRAY_INDEX] = _indices
	_geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	rebuild_count += 1

func clear() -> void:
	_key.clear()
	visible = false
