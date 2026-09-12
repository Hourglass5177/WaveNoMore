@tool
class_name StageEnvironmentSlice
extends Node
## 一个来源子层的可见片段。原材质先照常绘制，再在合成时施加接缝权重。
const Repeat = preload("res://src/presentation/parallax/parallax_repeat.gd")
var direct_container: Node2D
var direct_mode := false
var source_layer: StageBackgroundSubLayer
var texture: ViewportTexture
var viewport: SubViewport
var views: Array[Node2D] = []
var animations: Array[AnimatedSprite2D] = []
var timed_materials: Array[ShaderMaterial] = []

func configure(layer: StageBackgroundSubLayer) -> void:
	source_layer = layer
	viewport = SubViewport.new(); viewport.size = Vector2i(1920, 1080); viewport.transparent_bg = true
	viewport.size_2d_override=Vector2i(1920,1080);viewport.size_2d_override_stretch=true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(viewport)
	texture = viewport.get_texture()
	for entry in layer.entries:
		var object: Node2D
		if entry.texture != null:
			var sprite := Sprite2D.new(); sprite.texture = entry.texture; sprite.centered = false; object = sprite
		elif entry.sprite_frames != null:
			var sprite := AnimatedSprite2D.new(); sprite.sprite_frames = entry.sprite_frames; sprite.animation = entry.animation; sprite.centered = false; sprite.stop(); object = sprite; animations.append(sprite)
		else: continue
		if entry.material != null:
			object.material = entry.material.duplicate(false)
			for uniform in entry.material.shader.get_shader_uniform_list():
				if uniform.name == "environment_time": timed_materials.append(object.material); break
		viewport.add_child(object)
		var view := Repeat.new(); viewport.add_child(view)
		view.configure(object, Transform2D(0.0, Vector2.ONE * entry.uniform_scale, 0.0, entry.position), Vector2.ZERO, 1, entry.infinite, entry.random_flip)
		views.append(view)

func sample(state: Dictionary, axis: Vector2, canvas: Transform2D) -> void:
	if not direct_mode:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	for view in views: view.update_camera(-state.shift)
	for sprite in animations: ParallaxController.sample_animation(sprite, state.local_sec)
	for shader in timed_materials: shader.set_shader_parameter("environment_time", state.local_sec)

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
