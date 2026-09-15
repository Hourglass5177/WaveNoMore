@tool
class_name HorizontalRepeatView
extends Node2D
## 将子层随机布局模型实例化为当前视口所需的横向单元。

var layer: StageBackgroundSubLayer
var layout := HorizontalRepeatLayout.new()
var depth := 1
var camera_origin := Vector2.ZERO
var instances: Dictionary = {}
var song_time := 0.0
var apply_materials := true
var entry_offset := 0
var motion: BoundaryMotion
var entry_visibility: Dictionary = {}

func configure(value: StageBackgroundSubLayer, camera: Vector2, layer_depth: int, materials := true, offset := 0, boundary: BoundaryMotion = null) -> String:
	layer = value; camera_origin = camera; depth = layer_depth; apply_materials = materials; entry_offset = offset; motion = boundary
	layout.configure(layer)
	update_camera(camera)
	return ""

func update_camera(camera: Vector2) -> void:
	position = Vector2.ZERO if depth == 0 else -(camera - camera_origin) / float(depth)
	if not is_inside_tree() or layer == null or layer.entries.is_empty(): return
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var viewport := get_viewport_rect()
	var bounds := Rect2(inverse * viewport.position, Vector2.ZERO)
	for corner in [Vector2(viewport.end.x, viewport.position.y), viewport.end, Vector2(viewport.position.x, viewport.end.y)]: bounds = bounds.expand(inverse * corner)
	_sync_units(layout.visible_units(bounds.position.x - 1024.0, bounds.end.x + 1024.0))

func _sync_units(visible: Array[Dictionary]) -> void:
	var alive := {}
	for unit in visible:
		var index: int = unit.index; alive[index] = true
		if not instances.has(index): instances[index] = _create_unit(unit)
	for index in instances.keys():
		if not alive.has(index): instances[index].queue_free(); instances.erase(index)
	var ordered := instances.keys(); ordered.sort()
	for child_index in ordered.size(): move_child(instances[ordered[child_index]], child_index)

func _create_unit(unit: Dictionary) -> Node2D:
	var entry: StageBackgroundEntry = layer.entries[unit.entry_index]
	var object: Node2D
	if entry.texture != null:
		var sprite := Sprite2D.new(); sprite.texture = entry.texture; sprite.centered = false; object = sprite
	else:
		var sprite := AnimatedSprite2D.new(); sprite.sprite_frames = entry.sprite_frames; sprite.animation = entry.animation; sprite.centered = false; sprite.stop(); object = sprite
	if apply_materials and entry.material != null:
		object.material = entry.material.duplicate(false)
		if motion != null and BoundaryMotion.accepts(object.material): motion.apply(object.material, entry.uniform_scale)
	object.set_meta("background_entry_index", entry_offset + int(unit.entry_index))
	object.visible = entry_visibility.get(entry_offset + int(unit.entry_index), true)
	var size := HorizontalRepeatLayout.entry_size(entry)
	var sx := -entry.uniform_scale if entry.random_flip and unit.flip_h else entry.uniform_scale
	var sy := -entry.uniform_scale if entry.random_flip and unit.flip_v else entry.uniform_scale
	object.scale = Vector2(sx, sy)
	object.position = Vector2(float(unit.left) + (size.x * entry.uniform_scale if sx < 0.0 else 0.0), entry.position.y + (size.y * entry.uniform_scale if sy < 0.0 else 0.0))
	add_child(object)
	_sample_object(object)
	return object

func set_song_time(value: float) -> void:
	song_time = value
	for object: Node2D in instances.values(): _sample_object(object)

func _sample_object(object: Node2D) -> void:
	if object is AnimatedSprite2D: ParallaxController.sample_animation(object, song_time)
	if object.material is ShaderMaterial:
		for uniform in object.material.shader.get_shader_uniform_list():
			if uniform.name == "environment_time": object.material.set_shader_parameter("environment_time", song_time); break

func sample_boundary(seconds: float, beat: float) -> void:
	if motion == null: return
	for object: Node2D in instances.values():
		if BoundaryMotion.accepts(object.material): BoundaryMotion.sample(object.material, seconds, beat)

func objects_for_entry(entry_index: int) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for object: Node2D in instances.values():
		if int(object.get_meta("background_entry_index", -1)) == entry_index: result.append(object)
	return result

func set_entry_visible(entry_index: int, value: bool) -> void:
	entry_visibility[entry_index] = value
	for object in objects_for_entry(entry_index): object.visible = value
