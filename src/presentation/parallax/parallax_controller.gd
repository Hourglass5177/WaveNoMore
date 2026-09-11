## 单关视差控制中心。层对象与重复绘制节点属于内部实现，调用方只提交自身、深度、无限性。
@tool
class_name ParallaxController
extends Node2D

const RepeatView = preload("res://src/presentation/parallax/parallax_repeat.gd")

class DepthLayer extends Node2D:
	var depth: int

class Registration extends RefCounted:
	var object: Node2D
	var original_parent: WeakRef
	var original_z: int
	var original_z_relative: bool
	var view: Node2D
	var depth: int
	var infinite: bool
	var exit_callback: Callable

var _camera_position := Vector2.ZERO
var _background: CanvasLayer
var _foreground: CanvasLayer
var _layers: Dictionary[int, DepthLayer] = {}
var _objects: Dictionary[int, Registration] = {}
var _configured_objects: Array[Node2D] = []
var _animations: Array[AnimatedSprite2D] = []
var _leaving := false


func _ready() -> void:
	_background = CanvasLayer.new()
	_background.name = "Background"
	_background.layer = -1
	add_child(_background)
	_foreground = CanvasLayer.new()
	_foreground.name = "Foreground"
	_foreground.layer = 1
	add_child(_foreground)
	set_process(false)


## 注册或更新对象。失败不改动对象；重复相同参数不改变同层顺序。
func register_object(object: Node2D, depth: int, infinite: bool = false) -> bool:
	if not is_node_ready() or not is_instance_valid(object) or object == self or object.is_ancestor_of(self):
		return false
	if infinite:
		var size := RepeatView.cell_size(object)
		if size.x <= 0.0 or size.y <= 0.0:
			return false
	var id := object.get_instance_id()
	var record: Registration = _objects.get(id)
	if record != null and record.depth == depth and record.infinite == infinite:
		return true
	var pose := _canvas_pose(object)
	if is_zero_approx(pose.determinant()):
		return false
	if record == null:
		record = Registration.new()
		record.object = object
		record.original_parent = weakref(object.get_parent()) if object.get_parent() != null else null
		record.original_z = object.z_index
		record.original_z_relative = object.z_as_relative
	else:
		_disconnect_record(record)
		object.get_parent().remove_child(object)
		_remove_view(record)
	record.depth = depth
	record.infinite = infinite
	var layer := _get_layer(depth)
	var view := RepeatView.new()
	view.name = "Object_%s" % id
	layer.add_child(view)
	record.view = view
	# 登记对象的根排序由注册顺序管理，注销时归还其原有排序设置。
	object.z_index = 0
	object.z_as_relative = true
	view.configure(object, pose, _camera_position, depth, infinite)
	record.exit_callback = _on_object_exiting.bind(id)
	object.tree_exiting.connect(record.exit_callback)
	_objects[id] = record
	set_process(true)
	return true


## 返回最初父节点并保留当前显示变换；原父节点失效则脱离场景树交回调用方。
func unregister_object(object: Node2D) -> void:
	if not is_instance_valid(object):
		return
	var id := object.get_instance_id()
	var record: Registration = _objects.get(id)
	if record == null:
		return
	var pose := object.get_global_transform_with_canvas()
	_disconnect_record(record)
	object.get_parent().remove_child(object)
	var parent: Node = record.original_parent.get_ref() if record.original_parent != null else null
	if is_instance_valid(parent) and not parent.is_queued_for_deletion():
		parent.add_child(object)
		object.transform = Transform2D.IDENTITY
		object.transform = object.get_global_transform_with_canvas().affine_inverse() * pose
	else:
		object.transform = pose
	object.z_index = record.original_z
	object.z_as_relative = record.original_z_relative
	_objects.erase(id)
	_remove_view(record)
	set_process(not _objects.is_empty())


## 设置设计画布中的绝对摄像头位置。不修改真实 Camera2D，也不累计动画时间。
func set_camera_position(position: Vector2) -> void:
	_camera_position = position
	_sync_canvas_transform()
	for record: Registration in _objects.values():
		record.view.update_camera(position)


## 按设计画布位移移动模拟摄像头。
func move_camera(displacement: Vector2) -> void:
	set_camera_position(_camera_position + displacement)


## 返回模拟摄像头绝对位置。
func get_camera_position() -> Vector2:
	return _camera_position


## 按配置数组索引获取真实精灵，供编辑器选框使用；不暴露内部层和重复节点。
func get_configured_object(index: int) -> Node2D:
	if index < 0 or index >= _configured_objects.size():
		return null
	var object := _configured_objects[index]
	return object if is_instance_valid(object) else null


## 装配本关素材。配置错误返回原因；运行实例不写回共享资源。
func configure(definition: StageBackgroundDefinition, apply_materials: bool = true) -> String:
	clear()
	if definition == null:
		return ""
	for index in definition.entries.size():
		var entry := definition.entries[index]
		if entry == null or (entry.texture == null) == (entry.sprite_frames == null):
			clear()
			return "背景条目 %d 必须指定贴图或 SpriteFrames，且只能指定一项。" % (index + 1)
		if not is_finite(entry.uniform_scale) or entry.uniform_scale < 0.01:
			clear()
			return "背景条目 %d 的缩放倍率必须至少为 0.01。" % (index + 1)
		var object: Node2D
		if entry.texture != null:
			var sprite := Sprite2D.new()
			sprite.texture = entry.texture
			sprite.centered = false
			object = sprite
		else:
			if not entry.sprite_frames.has_animation(entry.animation) or entry.sprite_frames.get_frame_count(entry.animation) == 0:
				clear()
				return "背景条目 %d 的动画不存在或没有帧。" % (index + 1)
			var sprite := AnimatedSprite2D.new()
			sprite.sprite_frames = entry.sprite_frames
			sprite.animation = entry.animation
			sprite.centered = false
			sprite.stop()
			_animations.append(sprite)
			object = sprite
		if apply_materials and entry.material != null:
			object.material = entry.material.duplicate(false) as ShaderMaterial
		add_child(object)
		object.position = entry.position
		object.scale = Vector2.ONE * entry.uniform_scale
		_configured_objects.append(object)
		if not register_object(object, entry.depth, entry.infinite):
			clear()
			return "背景条目 %d 无法拼接；请检查素材及动画帧画布尺寸。" % (index + 1)
	set_song_time(0.0)
	return ""


## 仅采样配置创建的动画。外部注册的 AnimatedSprite2D 保留自己的播放控制。
func set_song_time(song_time: float) -> void:
	for sprite: AnimatedSprite2D in _animations:
		if not is_instance_valid(sprite):
			continue
		var frames := sprite.sprite_frames
		var animation := sprite.animation
		var count := frames.get_frame_count(animation)
		var speed := frames.get_animation_speed(animation)
		var duration := 0.0
		for index in count:
			duration += frames.get_frame_duration(animation, index)
		var cursor := maxf(song_time, 0.0) * speed
		if frames.get_animation_loop(animation) and duration > 0.0:
			cursor = fposmod(cursor, duration)
		for index in count:
			var frame_duration := frames.get_frame_duration(animation, index)
			if cursor < frame_duration or index == count - 1:
				sprite.set_frame_and_progress(index, clampf(cursor / frame_duration, 0.0, 1.0))
				break
			cursor -= frame_duration


## 换关/卸载入口：归还外部对象，释放由配置创建的对象，清空摄像头和动画记录。
func clear() -> void:
	for record: Registration in _objects.values():
		unregister_object(record.object)
	for object: Node2D in _configured_objects:
		if is_instance_valid(object):
			if object.get_parent() != null:
				object.get_parent().remove_child(object)
			object.queue_free()
	_configured_objects.clear()
	_animations.clear()
	_camera_position = Vector2.ZERO


func _process(_delta: float) -> void:
	# 不自动移动相机。刷新外部动画的帧尺寸、画布变换与视口覆盖范围。
	_sync_canvas_transform()
	for record: Registration in _objects.values():
		if record.infinite:
			record.view.update_camera(_camera_position)


func _sync_canvas_transform() -> void:
	if _background == null:
		return
	var pose := get_global_transform_with_canvas()
	_background.transform = pose
	_foreground.transform = pose


func _canvas_pose(object: Node2D) -> Transform2D:
	_sync_canvas_transform()
	if object.is_inside_tree():
		return get_global_transform_with_canvas().affine_inverse() * object.get_global_transform_with_canvas()
	return object.transform


func _get_layer(depth: int) -> DepthLayer:
	if _layers.has(depth):
		return _layers[depth]
	var layer := DepthLayer.new()
	layer.depth = depth
	layer.name = "Depth_%s" % depth
	var canvas := _background if depth >= 0 else _foreground
	canvas.add_child(layer)
	_layers[depth] = layer
	var depths: Array = _layers.keys()
	depths.sort()
	depths.reverse()
	var order := 0
	for value: int in depths:
		if _layers[value].get_parent() == canvas:
			canvas.move_child(_layers[value], order)
			order += 1
	return layer


func _disconnect_record(record: Registration) -> void:
	if record.object.tree_exiting.is_connected(record.exit_callback):
		record.object.tree_exiting.disconnect(record.exit_callback)


func _remove_view(record: Registration) -> void:
	var layer: DepthLayer = _layers[record.depth]
	layer.remove_child(record.view)
	record.view.queue_free()
	if layer.get_child_count() == 0:
		_layers.erase(record.depth)
		layer.get_parent().remove_child(layer)
		layer.queue_free()


func _on_object_exiting(id: int) -> void:
	if _leaving:
		return
	var record: Registration = _objects[id]
	_disconnect_record(record)
	record.object.z_index = record.original_z
	record.object.z_as_relative = record.original_z_relative
	_objects.erase(id)
	# tree_exiting 正在修改场景树，帧尾再移除包装节点。
	_remove_exited_view.call_deferred(record)


func _remove_exited_view(record: Registration) -> void:
	if _leaving or not is_instance_valid(record.view) or record.view.is_queued_for_deletion():
		return
	_remove_view(record)
	set_process(not _objects.is_empty())


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_leaving = true
		_objects.clear()
		_layers.clear()
		_configured_objects.clear()
		_animations.clear()
