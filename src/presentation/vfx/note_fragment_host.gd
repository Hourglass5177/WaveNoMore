class_name NoteFragmentHost
extends Node2D

## 一次裂解一个网格。碎片共享贴图与材质程序，独立于音符对象池存活。
const STYLE: NoteEffectStyle = preload("res://content/presentation/note_effect_style.tres")
const SHADER: Shader = preload("res://shaders/notes/note_fragments.gdshader")
static var _templates: Dictionary[String, ArrayMesh] = {}
var _pool: Array[MeshInstance2D] = []
var _active: Dictionary[String, Dictionary] = {}
var clock_sec: float = 0.0
var enabled: bool = true

func _ready() -> void:
	for i: int in 24: _pool.append(_new_visual())
	# 先建立默认模板，运行中只设置事件参数。
	_template(Vector2(96, 96), STYLE.shard_count, STYLE.dust_count)
	_template(Vector2(96, 96), STYLE.hold_shard_count, STYLE.hold_dust_count)
	_template(Vector2(96, 96), 0, 1)

func _new_visual() -> MeshInstance2D:
	var item := MeshInstance2D.new()
	var surface := ShaderMaterial.new()
	surface.shader = SHADER
	item.material = surface
	item.visible = false
	add_child(item)
	return item

func burst(key: String, source: Dictionary, at_sec: float, direction: Vector2, kind: StringName = &"tap") -> void:
	if not enabled or not STYLE.enabled or _active.has(key): return
	var hold := kind == &"hold"
	var dust := kind == &"dust"
	var hit := kind == &"hit"
	var duration := STYLE.hit_sec if hit else (STYLE.hold_finish_sec if hold else STYLE.dust_sec)
	if clock_sec - at_sec >= duration: return
	var item: MeshInstance2D = _pool.pop_back() if not _pool.is_empty() else _new_visual()
	var size: Vector2 = source.get("size", Vector2(96, 96))
	var count := 0 if dust or hit else (STYLE.hold_shard_count if hold else STYLE.shard_count)
	var motes := 1 if dust else (4 if hit else (STYLE.hold_dust_count if hold else STYLE.dust_count))
	item.mesh = _template(size, count, motes)
	item.texture = source.get("texture")
	item.transform = source["transform"]
	item.visible = true
	var surface := item.material as ShaderMaterial
	STYLE.apply_to(surface, int(source["affinity"]))
	surface.set_shader_parameter(&"source_size", size)
	surface.set_shader_parameter(&"has_texture", item.texture != null)
	surface.set_shader_parameter(&"has_eye", source.has("eye"))
	if source.has("eye"):
		surface.set_shader_parameter(&"eye_ball_texture", source.eye)
		surface.set_shader_parameter(&"musk_texture", source.mask)
		surface.set_shader_parameter(&"eye_offset_uv", source.eye_offset)
	surface.set_shader_parameter(&"crack_sec", 0.0 if dust or hit else STYLE.crack_sec)
	surface.set_shader_parameter(&"shard_sec", STYLE.hold_finish_sec if hold else STYLE.shard_sec)
	surface.set_shader_parameter(&"dust_sec", duration)
	surface.set_shader_parameter(&"spread_px", 18.0 if hit or dust else STYLE.spread_px * (0.65 if hold else 1.0))
	surface.set_shader_parameter(&"impact_direction", direction.normalized())
	surface.set_shader_parameter(&"variation", float(absi(key.hash()) % 4096) / 4096.0 * TAU)
	surface.set_shader_parameter(&"age", maxf(0.0, clock_sec - at_sec))
	_active[key] = {"node": item, "time": at_sec, "duration": duration}

func set_time(seconds: float) -> void:
	if clock_sec == seconds: return
	clock_sec = seconds
	for key: String in _active.keys():
		var entry: Dictionary = _active[key]
		var age: float = seconds - float(entry.time)
		var item: MeshInstance2D = entry.node
		if age >= float(entry.duration) or age < 0.0:
			item.visible = false
			_pool.append(item)
			_active.erase(key)
		else:
			(item.material as ShaderMaterial).set_shader_parameter(&"age", age)

func clear() -> void:
	for entry: Dictionary in _active.values():
		var item: MeshInstance2D = entry.node
		item.visible = false
		_pool.append(item)
	_active.clear()
	clock_sec = 0.0

static func _template(size: Vector2, count: int, motes: int) -> ArrayMesh:
	var key := "%s/%d/%d" % [size, count, motes]
	if _templates.has(key): return _templates[key]
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1729 + count
	var seeds := PackedVector2Array()
	for i: int in count:
		var angle := float(i) / count * TAU + rng.randf_range(-0.24, 0.24)
		seeds.append(Vector2.from_angle(angle) * size * rng.randf_range(0.16, 0.39))
	for i: int in count:
		# 固定 Voronoi 薄片共用完整贴图 UV；透明边缘由原素材裁切。
		var polygon := PackedVector2Array([Vector2(-0.5, -0.5) * size, Vector2(0.5, -0.5) * size, size * 0.5, Vector2(-0.5, 0.5) * size])
		for j: int in count:
			if i != j: polygon = _clip(polygon, (seeds[i] + seeds[j]) * 0.5, seeds[j] - seeds[i])
		var center := Vector2.ZERO
		for point: Vector2 in polygon: center += point
		center /= polygon.size()
		var data := Color(center.x / size.x + 0.5, center.y / size.y + 0.5, float(i) / maxi(count, 1), 0.0)
		for j: int in polygon.size():
			for point: Vector2 in [center, polygon[j], polygon[(j + 1) % polygon.size()]]:
				vertices.append(point); uvs.append(point / size + Vector2(0.5, 0.5)); colors.append(data)
		# 断面是与薄片共用运动的窄三角带，最初几十毫秒亮起，随后露出漆片纹理。
		data.a = 0.5
		for j: int in polygon.size():
			var a := polygon[j]
			var b := polygon[(j + 1) % polygon.size()]
			var inner_a := a.move_toward(center, 1.1)
			var inner_b := b.move_toward(center, 1.1)
			for point: Vector2 in [a, b, inner_b, a, inner_b, inner_a]:
				vertices.append(point); uvs.append(point / size + Vector2(0.5, 0.5)); colors.append(data)
	for i: int in motes:
		var center := Vector2.from_angle(float(i) / motes * TAU) * size * (0.06 if count == 0 else rng.randf_range(0.22, 0.45))
		var radius := rng.randf_range(5.0, 8.0) if count == 0 and motes == 4 else rng.randf_range(1.6, 3.0)
		var data := Color(center.x / size.x + 0.5, center.y / size.y + 0.5, float(i) / motes, 1.0)
		for uv: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.ZERO, Vector2.ONE, Vector2.DOWN]:
			vertices.append(center + (uv * 2.0 - Vector2.ONE) * radius); uvs.append(uv); colors.append(data)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.custom_aabb = AABB(Vector3(-250, -250, -1), Vector3(500, 500, 2))
	_templates[key] = result
	return result

static func _clip(points: PackedVector2Array, origin: Vector2, normal: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i: int in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var da := (a - origin).dot(normal)
		var db := (b - origin).dot(normal)
		if da <= 0.0: result.append(a)
		if (da <= 0.0) != (db <= 0.0): result.append(a.lerp(b, da / (da - db)))
	return result
