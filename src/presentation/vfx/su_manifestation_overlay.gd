class_name SuManifestationOverlay
extends Node2D

## Ghost 的眼睛与原地结果反馈；一个事件共用一份材质、一个静态网格。
## 时钟推进只提交 phase，定位与暂停无需 Tween 或逐帧重建几何。
@export var style: GhostNoteStyle = preload("res://content/presentation/ghost_note_style.tres")
@export var canvas_size := Vector2(1920.0, 1080.0):
	set(value):
		if canvas_size == value: return
		canvas_size = value
		for entry: Dictionary in _entries.values(): _build_mesh(entry)
@export_range(0.1, 2.0, 0.01) var lifetime_sec := 0.78

const EYE_SHADER = preload("res://shaders/notes/ghost_eye.gdshader")
var _fragments := NoteFragmentHost.new()
var _visual_time_sec := 0.0
var _entries: Dictionary[String, Dictionary] = {}
var _pool: Array[MeshInstance2D] = []

func _ready() -> void:
	add_child(_fragments)
	_fragments.z_index = 1
	# 加载阶段准备常用数量；超过既有峰值才扩容，后续批次复用。
	for i in maxi(0, 8 - get_child_count()): _pool.append(_create_view())

func _create_view() -> MeshInstance2D:
	var view := MeshInstance2D.new()
	view.mesh = ArrayMesh.new()
	var surface := ShaderMaterial.new()
	surface.shader = EYE_SHADER
	view.material = surface
	view.visible = false
	add_child(view)
	return view

func prepare_targets(event_data: Dictionary) -> void:
	var event_id := str(event_data["event_id"])
	if _entries.has(event_id): return
	var points := PackedVector2Array()
	for point: Vector2 in event_data.get("points", []): points.append(point)
	if points.is_empty(): return
	var target := float(event_data["time_us"]) / 1000000.0
	var view: MeshInstance2D = _pool.pop_back() if not _pool.is_empty() else _create_view()
	var entry := {"points": points, "target_time_sec": target,
		"visible_from_sec": float(event_data.get("visible_from_us", roundi((target - 2.7) * 1000000.0))) / 1000000.0,
		"duration_sec": float(event_data.get("target_hold_duration_sec", lifetime_sec)),
		"resolved": false, "success": false, "view": view}
	_entries[event_id] = entry
	var surface := view.material as ShaderMaterial
	surface.set_shader_parameter("closed_eye", style.closed_texture)
	surface.set_shader_parameter("open_eye", style.open_texture)
	surface.set_shader_parameter("closed_distance", style.closed_glow)
	surface.set_shader_parameter("open_distance", style.open_glow)
	surface.set_shader_parameter("bone_color", style.bone_color)
	surface.set_shader_parameter("eye_anchor", style.eye_anchor_uv)
	surface.set_shader_parameter("body_width", style.width_px)
	surface.set_shader_parameter("halo_width", style.halo_width_px)
	surface.set_shader_parameter("surface_light", Vector2(style.closed_surface_light, style.open_surface_light))
	var source_size := style.open_texture.get_size()
	surface.set_shader_parameter("mask_content_size", (source_size * (192.0 / maxf(source_size.x, source_size.y))).round())
	surface.set_shader_parameter("result_kind", 0.0)
	_build_mesh(entry)
	_update_entry(entry)
	view.visible = true

func _build_mesh(entry: Dictionary) -> void:
	var scale_px := minf(canvas_size.x / 1920.0, canvas_size.y / 1080.0)
	var source_size := style.open_texture.get_size()
	var size := source_size * (style.width_px / source_size.x) * scale_px
	var pad := Vector2.ONE * style.halo_width_px * scale_px
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for point: Vector2 in entry.points:
		var start := vertices.size()
		var origin := point * canvas_size - style.eye_anchor_uv * size
		for corner: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
			var offset := corner * (size + 2.0 * pad) - pad
			vertices.append(origin + offset)
			uvs.append(offset / size)
		for index: int in [0, 1, 2, 0, 2, 3]: indices.append(start + index)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = entry.view.mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func resolve_targets(result: Dictionary) -> void:
	var event_id := str(result["event_id"])
	if not _entries.has(event_id): return
	var entry: Dictionary = _entries[event_id]
	if entry.resolved: return
	entry.resolved = true
	entry.success = int(result.hit_count) > 0 if result.has("hit_count") else bool(result.success)
	if entry.success:
		# 同一歌曲时钟驱动裂解，暂停与定位不会继续播放残留粒子。
		var size := style.open_texture.get_size() * (style.width_px / style.open_texture.get_width()) * minf(canvas_size.x / 1920.0, canvas_size.y / 1080.0)
		for i in entry.points.size():
			var center: Vector2 = entry.points[i] * canvas_size + (Vector2(0.5, 0.5) - style.eye_anchor_uv) * size
			_fragments.burst(event_id + "/" + str(i), {"texture": style.open_texture, "size": size, "transform": Transform2D(0.0, center), "affinity": 0}, float(entry.target_time_sec), Vector2.UP, &"ghost")
	entry.view.material.set_shader_parameter("result_kind", 1.0 if entry.success else -1.0)
	_update_entry(entry)

func visual_phase(entry: Dictionary) -> Vector4:
	var open_start := float(entry.target_time_sec) - style.open_before_sec
	var opening := smoothstep(open_start, open_start + style.open_duration_sec, _visual_time_sec)
	var opacity := smoothstep(float(entry.visible_from_sec), float(entry.visible_from_sec) + style.appear_sec, _visual_time_sec)
	var glow := lerpf(style.closed_glow_strength, style.open_glow_strength, opening)
	var result_progress := 0.0
	if entry.resolved:
		result_progress = clampf((_visual_time_sec - float(entry.target_time_sec)) / float(entry.duration_sec), 0.0, 1.0)
		opacity *= 1.0 - smoothstep(0.0, 0.15 if entry.success else 1.0, result_progress)
		glow = lerpf(1.1, 0.0, result_progress) if entry.success else 0.0
	return Vector4(opening, opacity, glow, result_progress)

func _update_entry(entry: Dictionary) -> void:
	entry.view.material.set_shader_parameter("phase", visual_phase(entry))

func set_visual_time(time_sec: float) -> void:
	if _visual_time_sec == time_sec: return
	_visual_time_sec = time_sec
	_fragments.set_time(time_sec)
	for event_id: String in _entries.keys():
		var entry: Dictionary = _entries[event_id]
		if entry.resolved and time_sec >= float(entry.target_time_sec) + float(entry.duration_sec):
			_recycle(entry)
			_entries.erase(event_id)
		else: _update_entry(entry)

func _recycle(entry: Dictionary) -> void:
	var view: MeshInstance2D = entry.view
	view.visible = false
	_pool.append(view)

func clear() -> void:
	_fragments.clear()
	for entry: Dictionary in _entries.values(): _recycle(entry)
	_entries.clear()
	_visual_time_sec = 0.0

func has_active_entries() -> bool:
	return not _entries.is_empty()

func debug_snapshot() -> Dictionary:
	return {"time_sec": _visual_time_sec, "active_count": _entries.size(), "event_ids": _entries.keys()}
