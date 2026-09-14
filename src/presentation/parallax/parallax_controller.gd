## 单关视差控制中心。顶层只挂子层，所有业务对象由子层内的重复视图挂载。
@tool
class_name ParallaxController
extends Node2D

const RepeatView = preload("res://src/presentation/parallax/parallax_repeat.gd")

class DepthLayer extends Node2D:
	var depth: int
	var canvas: CanvasLayer

class SubLayer extends Node2D:
	var sublayer_id: String
	var velocity := Vector2.ZERO

class Registration extends RefCounted:
	var object: Node2D
	var original_parent: WeakRef
	var original_z: int
	var original_z_relative: bool
	var view: Node2D
	var depth: int
	var sublayer: SubLayer
	var infinite: bool
	var exit_callback: Callable

var _camera_position := Vector2.ZERO
var _background: CanvasLayer
var _foreground: CanvasLayer
var _layers: Dictionary[int, DepthLayer] = {}
var _objects: Dictionary[int, Registration] = {}
var _configured_objects: Array[Node2D] = []
var _animations: Array[AnimatedSprite2D] = []
var boundary_motion := BoundaryMotion.new()
var _boundary_materials: Array[Dictionary] = []
var _background_scenes: Array[Node2D] = []
var _leaving := false
var _song_time := 0.0
var _occlusion := {}

## 独立 Canvas 保留素材内部 z 层次；只排列 Canvas，不让内部 z 越过背景接缝。
## Canvas 的大层级仍是 -1 / 1，不改变玩法、波纹和 HUD 的既有层级。
func set_object_occlusion(object: Node2D, depth: int, order: String, local_order := 0) -> void:
	if not is_instance_valid(object) or order not in ["front", "back"]: return
	var id := object.get_instance_id()
	var record: Dictionary = _occlusion.get(id, {})
	if record.is_empty():
		var canvas := CanvasLayer.new(); canvas.name = "ShowOcclusion"; add_child(canvas)
		record = {"object":object,"parent":weakref(object.get_parent()),"canvas":canvas,"depth":depth,"order":order,"local_order":local_order}
		_occlusion[id] = record
		var pose := object.get_global_transform_with_canvas()
		canvas.transform = _parent_pose(object.get_parent())
		object.reparent(canvas, false); object.transform = canvas.transform.affine_inverse() * pose
	elif record.depth == depth and record.order == order and record.local_order == local_order:
		return
	record.depth=depth; record.order=order; record.local_order=local_order
	_get_layer(depth); _sort_canvases()

func release_object_occlusion(object: Node2D) -> void:
	if not is_instance_valid(object): return
	var id := object.get_instance_id()
	if not _occlusion.has(id): return
	var record: Dictionary = _occlusion[id]; _occlusion.erase(id)
	var parent: Node = record.parent.get_ref()
	var pose := object.get_global_transform_with_canvas()
	object.get_parent().remove_child(object)
	if is_instance_valid(parent) and not parent.is_queued_for_deletion():
		parent.add_child(object); object.transform=_parent_pose(parent).affine_inverse()*pose
	else: object.queue_free()
	record.canvas.queue_free(); _sort_canvases()

static func _parent_pose(parent: Node) -> Transform2D:
	if parent is CanvasItem:return parent.get_global_transform_with_canvas()
	if parent is CanvasLayer:return parent.get_final_transform()
	return Transform2D.IDENTITY

func _sort_canvases() -> void:
	var entries := []
	for layer: DepthLayer in _layers.values(): entries.append({"depth":layer.depth,"slot":1,"order":0,"canvas":layer.canvas})
	for record: Dictionary in _occlusion.values(): entries.append({"depth":record.depth,"slot":0 if record.order=="back" else 2,"order":record.local_order,"canvas":record.canvas})
	entries.sort_custom(func(a,b):
		if a.depth!=b.depth:return a.depth>b.depth
		if a.slot!=b.slot:return a.slot<b.slot
		return a.order<b.order)
	for index in entries.size():
		var entry: Dictionary=entries[index]
		move_child(entry.canvas,index)
		entry.canvas.layer=-1 if entry.depth>=0 else 1
var environment: StageEnvironmentSequence
var environment_views := {}
var environment_only_layer := ""
var environment_time_us := 0
var environment_render_camera:=Vector2.ZERO


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


## 注册或更新对象；省略子层 ID 时挂入该深度的 default 子层。
## 保留注册时的显示变换；之后按所在子层速度和相机变化移动。
## 失败不改动对象；重复相同参数不改变子层内顺序。
func register_object(object: Node2D, depth: int, infinite: bool = false, sublayer_id: String = "default", random_flip: bool = false) -> bool:
	if not is_node_ready() or not is_instance_valid(object) or object == self or object.is_ancestor_of(self):
		return false
	if sublayer_id.is_empty():
		return false
	if infinite:
		var size := RepeatView.cell_size(object)
		if size.x <= 0.0 or size.y <= 0.0:
			return false
	var id := object.get_instance_id()
	var record: Registration = _objects.get(id)
	if record != null and record.depth == depth and record.infinite == infinite and record.sublayer.sublayer_id == sublayer_id:
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
	var layer := _get_sublayer(depth, sublayer_id)
	record.sublayer = layer
	var view := RepeatView.new()
	view.name = "Object_%s" % id
	layer.add_child(view)
	record.view = view
	# 登记对象的根排序由注册顺序管理，注销时归还其原有排序设置。
	object.z_index = 0
	object.z_as_relative = true
	view.configure(object, pose, _camera_position - layer.velocity * _song_time, depth, infinite, random_flip)
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
		record.view.update_camera(position - record.sublayer.velocity * _song_time)


## 设置子层 X/Y 速度（设计像素/秒）。按当前绝对歌曲时间重新采样，不写回资源。
## 非零深度实际位移为 (velocity * time - camera) / depth；零深度静止。
func set_sublayer_velocity(depth: int, sublayer_id: String, velocity: Vector2) -> void:
	_get_sublayer(depth, sublayer_id).velocity = velocity
	set_camera_position(_camera_position)


## 查询子层速度；尚不存在时返回零，不隐式创建层。
func get_sublayer_velocity(depth: int, sublayer_id: String) -> Vector2:
	if _layers.has(depth):
		for sublayer: SubLayer in _layers[depth].get_children():
			if sublayer.sublayer_id == sublayer_id:
				return sublayer.velocity
	return Vector2.ZERO


## 按设计画布位移移动模拟摄像头。
func move_camera(displacement: Vector2) -> void:
	set_camera_position(_camera_position + displacement)


## 返回模拟摄像头绝对位置。
func get_camera_position() -> Vector2:
	return _camera_position


## 按 layers → sublayers → entries 的遍历索引获取真实精灵，供编辑器选框使用。
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
	var depths: Dictionary = {}
	for layer in definition.layers:
		if layer == null or depths.has(layer.depth):
			clear()
			return "背景顶层为空或深度重复。"
		depths[layer.depth] = true
		_get_layer(layer.depth)
		var ids: Dictionary = {}
		for sublayer in layer.sublayers:
			if sublayer == null or sublayer.sublayer_id.is_empty() or ids.has(sublayer.sublayer_id) or not sublayer.velocity.is_finite():
				clear()
				return "背景子层为空、标识重复或速度无效。"
			ids[sublayer.sublayer_id] = true
			_get_sublayer(layer.depth, sublayer.sublayer_id).velocity = sublayer.velocity
			for entry in sublayer.entries:
				var issue := _configure_entry(entry, layer.depth, sublayer.sublayer_id, apply_materials)
				if not issue.is_empty():
					clear()
					return issue
	set_song_time(0.0)
	return ""


func _configure_entry(entry: StageBackgroundEntry, depth: int, sublayer_id: String, apply_materials: bool) -> String:
	var index := _configured_objects.size()
	if entry == null or entry.source_count() != 1:
		return "背景条目 %d 必须指定贴图、SpriteFrames 或场景，且只能指定一项。" % (index + 1)
	if not is_finite(entry.uniform_scale) or entry.uniform_scale < 0.01:
		return "背景条目 %d 的缩放倍率必须至少为 0.01。" % (index + 1)
	var object: Node2D
	if entry.texture != null:
		var sprite := Sprite2D.new()
		sprite.texture = entry.texture
		sprite.centered = false
		object = sprite
	elif entry.scene != null:
		var instance := entry.scene.instantiate()
		if not instance is Node2D or entry.infinite:
			instance.free()
			return "背景场景必须以 Node2D 为根，并使用有限素材。"
		object=instance
		if object.has_method("configure_boundary_scene"): object.configure_boundary_scene(boundary_motion)
		_background_scenes.append(object)
	else:
		if not entry.sprite_frames.has_animation(entry.animation) or entry.sprite_frames.get_frame_count(entry.animation) == 0:
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
		if BoundaryMotion.accepts(object.material):
			boundary_motion.apply(object.material, entry.uniform_scale)
			_boundary_materials.append({"material": object.material, "scale": entry.uniform_scale})
	add_child(object)
	object.position = entry.position
	object.scale = Vector2.ONE * entry.uniform_scale
	_configured_objects.append(object)
	if not register_object(object, depth, entry.infinite, sublayer_id, entry.random_flip):
		return "背景条目 %d 无法拼接；请检查素材及动画帧画布尺寸。" % (index + 1)
	return ""


## 采样子层主动位移和配置动画；同一时间重复调用不会累计位移。
## apply_motion=false 供编辑器布局模式停用主动位移，动画仍采样指定帧。
## 外部注册的 AnimatedSprite2D 保留自己的动画播放控制。
func set_song_time(song_time: float, apply_motion: bool = true) -> void:
	_song_time = maxf(song_time, 0.0) if apply_motion else 0.0
	var beat := boundary_motion.beat_at(song_time)
	for item in _boundary_materials:
		BoundaryMotion.sample(item.material, song_time, beat)
	for object in _background_scenes:
		if object.has_method("sample_background"): object.sample_background(song_time)
	set_camera_position(_camera_position)
	for sprite: AnimatedSprite2D in _animations:
		if not is_instance_valid(sprite):
			continue
		sample_animation(sprite, song_time)

## 一局只装载一次策划值；共享贴图与材质资源不被回写。
func configure_boundary(chart: SongChart, first_beat_offset: float, planning: Dictionary) -> void:
	boundary_motion.tempo_map = TempoMap.from_chart(chart) if chart != null else null
	boundary_motion.meters.clear()
	if chart != null: boundary_motion.meters.append_array(chart.meter_events)
	boundary_motion.meters.sort_custom(func(a, b): return a.tick < b.tick)
	boundary_motion.audio_offset_sec = first_beat_offset
	boundary_motion.style = BoundaryMotion.DEFAULT_STYLE.duplicate()
	PlanningParameters.apply_values(boundary_motion.style, "boundary", planning)
	for item in _boundary_materials: boundary_motion.apply(item.material, item.scale)

static func sample_animation(sprite: AnimatedSprite2D, song_time: float) -> void:
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
	for record: Dictionary in _occlusion.values().duplicate(): release_object_occlusion(record.object)
	clear_environment()
	for record: Registration in _objects.values():
		unregister_object(record.object)
	for object: Node2D in _configured_objects:
		if is_instance_valid(object):
			if object.get_parent() != null:
				object.get_parent().remove_child(object)
			object.queue_free()
	_configured_objects.clear()
	_animations.clear()
	_boundary_materials.clear()
	_background_scenes.clear()
	_camera_position = Vector2.ZERO
	_song_time = 0.0
	for layer: DepthLayer in _layers.values():
		layer.canvas.queue_free()
	_layers.clear()

## 只替换背景配置的显示宿主，真实角色和音符注册项一直保留。
func set_environment(sequence: StageEnvironmentSequence) -> void:
	environment = sequence
	for object in _configured_objects:
		if is_instance_valid(object): object.visible = sequence == null
	if sequence == null:
		clear_environment(); return
	var alive := {}
	for lane in sequence.lanes:
		alive[lane.id] = true
		if environment_views.has(lane.id): continue
		var root := Node2D.new()
		var composite := Sprite2D.new(); composite.centered = false; root.add_child(composite)
		composite.material = ShaderMaterial.new(); composite.material.shader = preload("res://shaders/environment_seam.gdshader")
		root.name = "Environment"
		# 插回原子层位置，尤其不能盖过深度 0 的角色和音符注册项。
		var first: Dictionary = lane.sources.filter(func(source):return not source.record.is_empty())[0].record
		var parent := _get_sublayer(lane.depth, first.resource.sublayer_id)
		parent.add_child(root); parent.move_child(root, 0)
		environment_views[lane.id] = {"root": root, "composite": composite, "slices": {}}
	for key in environment_views.keys():
		if not alive.has(key):
			var root: Node = environment_views[key].root; root.get_parent().remove_child(root); root.queue_free(); environment_views.erase(key)

func clear_environment() -> void:
	for view in environment_views.values():
		view.root.get_parent().remove_child(view.root); view.root.queue_free()
	environment_views.clear(); environment = null

func sample_environment(time_us: int, render_camera := Vector2(INF, INF), song_time_sec := NAN) -> void:
	if environment == null: return
	# 演出坐标是音频位置；正式游戏显式传入未应用画面提前量的歌曲主时钟。
	var seconds := song_time_sec if is_finite(song_time_sec) else float(time_us) / 1000000.0 - boundary_motion.audio_offset_sec
	var beat := boundary_motion.beat_at(seconds)
	environment_time_us = time_us
	environment_render_camera=render_camera if render_camera.is_finite() else environment.camera_at(time_us)
	_sync_canvas_transform()
	for lane in environment.lanes:
		var view: Dictionary = environment_views[lane.id]
		var depth:int=StageEnvironmentSequence.motion_at(lane,time_us).depth
		var parent:=_get_sublayer(depth,lane.sources.filter(func(source):return not source.record.is_empty())[0].record.resource.sublayer_id)
		if view.root.get_parent()!=parent:
			view.root.reparent(parent,false);parent.move_child(view.root,0)
		view.root.visible = environment_only_layer.is_empty() or environment_only_layer == lane.id
		var alive := {}
		var states := environment.visible_sources(lane, time_us,environment_render_camera)
		var render_scale:Vector2=get_viewport().get_meta(&"render_pixel_scale",Vector2.ONE)
		var canvas:=Transform2D.IDENTITY.scaled(render_scale)*get_viewport().get_stretch_transform()*get_global_transform_with_canvas()
		var inverse := canvas.affine_inverse()
		var shader: ShaderMaterial = view.composite.material
		shader.set_shader_parameter("inverse_x", inverse.x); shader.set_shader_parameter("inverse_y", inverse.y); shader.set_shader_parameter("inverse_origin", inverse.origin); shader.set_shader_parameter("direction", lane.direction)
		shader.set_shader_parameter("opacity", 0.0); shader.set_shader_parameter("next_opacity", 0.0)
		var bounds:=StageEnvironmentSequence.projected_frame(lane.direction)
		var direct:bool=states.size()==1 and is_equal_approx(states[0].opacity,1.0) and states[0].low+states[0].low_width*0.5<=bounds.x and states[0].high-states[0].high_width*0.5>=bounds.y
		view.composite.visible=not direct
		for ordinal in states.size():
			var state: Dictionary = states[ordinal]
			alive[state.index] = true
			if view.slices.has(state.index) and view.slices[state.index].source_layer != state.source.record.resource:
				var old: Node = view.slices[state.index]; old.get_parent().remove_child(old); old.queue_free(); view.slices.erase(state.index)
			if not view.slices.has(state.index):
				var slice := StageEnvironmentSlice.new(); view.root.add_child(slice)
				slice.configure(state.source.record.resource, boundary_motion); view.slices[state.index] = slice
			view.slices[state.index].set_direct(view.root,direct,maxf(1.0,canvas.x.length()))
			view.slices[state.index].sample(state, lane.direction, canvas)
			view.slices[state.index].sample_boundary(seconds, beat)
			if ordinal == 0:
				view.composite.texture = view.slices[state.index].texture
				view.composite.scale=Vector2(1920,1080)/Vector2(view.slices[state.index].viewport.size)
			else: shader.set_shader_parameter("next_texture", view.slices[state.index].texture)
			shader.set_shader_parameter("limits" if ordinal == 0 else "next_limits", Vector4(state.low, state.high, state.low_width, state.high_width))
			shader.set_shader_parameter("opacity" if ordinal == 0 else "next_opacity", state.opacity)
		for key in view.slices.keys():
			if not alive.has(key):
				var slice: Node = view.slices[key]; slice.get_parent().remove_child(slice); slice.queue_free(); view.slices.erase(key)


func _process(_delta: float) -> void:
	# 不自动移动相机。刷新外部动画的帧尺寸、画布变换与视口覆盖范围。
	_sync_canvas_transform()
	for record: Registration in _objects.values():
		if record.infinite:
			record.view.update_camera(_camera_position - record.sublayer.velocity * _song_time)


func _sync_canvas_transform() -> void:
	if _background == null:
		return
	var pose := get_global_transform_with_canvas()
	_background.transform = pose
	_foreground.transform = pose
	for layer: DepthLayer in _layers.values(): layer.canvas.transform=pose
	for record: Dictionary in _occlusion.values():
		var parent: Node=record.parent.get_ref()
		if is_instance_valid(parent):record.canvas.transform=_parent_pose(parent)


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
	layer.canvas=CanvasLayer.new();layer.canvas.name="DepthCanvas_%s"%depth
	add_child(layer.canvas); layer.canvas.transform=get_global_transform_with_canvas();layer.canvas.add_child(layer)
	_layers[depth] = layer
	_sort_canvases()
	return layer


func _disconnect_record(record: Registration) -> void:
	if record.object.tree_exiting.is_connected(record.exit_callback):
		record.object.tree_exiting.disconnect(record.exit_callback)


func _remove_view(record: Registration) -> void:
	var layer := record.sublayer
	layer.remove_child(record.view)
	record.view.queue_free()
	# 空子层仍保存速度与绘制顺序，只在 clear 时释放。


func _get_sublayer(depth: int, id: String) -> SubLayer:
	var layer := _get_layer(depth)
	for sublayer: SubLayer in layer.get_children():
		if sublayer.sublayer_id == id:
			return sublayer
	var sublayer := SubLayer.new()
	sublayer.sublayer_id = id
	sublayer.name = "SubLayer_" + id
	layer.add_child(sublayer)
	return sublayer


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
	if what == NOTIFICATION_PREDELETE:
		# 控制器销毁时归还仍由外部播放器拥有的对象。
		for record: Dictionary in _occlusion.values():release_object_occlusion(record.object)
	if what == NOTIFICATION_EXIT_TREE:
		_leaving = true
		_objects.clear()
		_layers.clear()
		_configured_objects.clear()
		_animations.clear()
