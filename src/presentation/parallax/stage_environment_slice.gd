@tool
class_name StageEnvironmentSlice
extends Node
## 一个来源子层的可见片段。原材质先照常绘制，再在合成时施加接缝权重。
const Repeat = preload("res://src/presentation/parallax/parallax_repeat.gd")
const HorizontalView = preload("res://src/presentation/parallax/horizontal_repeat_view.gd")
var direct_container: Node2D
var direct_mode := false
var source_layer: StageBackgroundSubLayer
var texture: ViewportTexture
var viewport: SubViewport
var views: Array[Node2D] = []
var animations: Array[AnimatedSprite2D] = []
var timed_materials: Array[ShaderMaterial] = []
var boundary_materials: Array[ShaderMaterial] = []
var background_scenes: Array[Node2D] = []

func configure(layer: StageBackgroundSubLayer, motion: BoundaryMotion = null) -> void:
	source_layer = layer
	viewport = SubViewport.new(); viewport.size = Vector2i(1920, 1080); viewport.transparent_bg = true
	viewport.size_2d_override=Vector2i(1920,1080);viewport.size_2d_override_stretch=true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(viewport)
	texture = viewport.get_texture()
	if layer.horizontal_random_repeat:
		var horizontal := HorizontalView.new(); viewport.add_child(horizontal)
		horizontal.configure(layer, Vector2.ZERO, 1, true, 0, motion)
		views.append(horizontal)
		return
	for entry in layer.entries:
		var object: Node2D
		if entry.texture != null:
			var sprite := Sprite2D.new(); sprite.texture = entry.texture; sprite.centered = false; object = sprite
		elif entry.sprite_frames != null:
			var sprite := AnimatedSprite2D.new(); sprite.sprite_frames = entry.sprite_frames; sprite.animation = entry.animation; sprite.centered = false; sprite.stop(); object = sprite; animations.append(sprite)
		elif entry.scene != null:
			object=entry.scene.instantiate()
			if object.has_method("configure_boundary_scene"): object.configure_boundary_scene(motion if motion != null else BoundaryMotion.new())
			background_scenes.append(object)
		else: continue
		if entry.material != null:
			object.material = entry.material.duplicate(false)
			if BoundaryMotion.accepts(object.material):
				(motion if motion != null else BoundaryMotion.new()).apply(object.material, entry.uniform_scale)
				boundary_materials.append(object.material)
			for uniform in entry.material.shader.get_shader_uniform_list():
				if uniform.name == "environment_time": timed_materials.append(object.material); break
		viewport.add_child(object)
		var view := Repeat.new(); viewport.add_child(view)
		view.configure(object, Transform2D(0.0, Vector2.ONE * entry.uniform_scale, 0.0, entry.position), Vector2.ZERO, 1, entry.infinite, entry.random_flip)
		views.append(view)

func sample(state: Dictionary, axis: Vector2, canvas: Transform2D) -> void:
	if not direct_mode:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	for view in views:
		view.update_camera(-state.shift)
		if view.has_method("set_song_time"): view.set_song_time(state.local_sec)
	for sprite in animations: ParallaxController.sample_animation(sprite, state.local_sec)
	for shader in timed_materials: shader.set_shader_parameter("environment_time", state.local_sec)

func sample_boundary(seconds: float, beat: float) -> void:
	for view in views:
		if view.has_method("sample_boundary"): view.sample_boundary(seconds, beat)
	for shader in boundary_materials: BoundaryMotion.sample(shader, seconds, beat)
	for object in background_scenes:
		if object.has_method("sample_background"): object.sample_background(seconds)

## 只有接缝穿过画面时才离屏合成；纯单层直接绘制，避免全程增加渲染通道。
func set_direct(parent:Node2D, enabled:bool, resolution_scale:=1.0) -> void:
	if direct_container==null:
		direct_container=Node2D.new();parent.add_child(direct_container)
	var width:=ceili(1920.0*resolution_scale/16.0)*16
	viewport.size=Vector2i(2,2) if enabled else Vector2i(width,width*9/16)
	if direct_mode==enabled:return
	direct_mode=enabled;direct_container.visible=enabled
	for view in views:view.reparent(direct_container if enabled else viewport,false)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED if enabled else SubViewport.UPDATE_ALWAYS

func _exit_tree() -> void:
	if is_instance_valid(direct_container) and not direct_container.is_queued_for_deletion():direct_container.queue_free()
