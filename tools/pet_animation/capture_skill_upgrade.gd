extends SceneTree
## 在同一画布审看起势、释放、展示和收招，避免只检查最亮的一帧。
const ACTOR := preload("res://src/presentation/pets/animated_pet_visual.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1500,900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var background := ColorRect.new()
	background.size = Vector2(1500,900)
	background.color = Color("302c39")
	vp.add_child(background)
	var times := [0.10,0.30,0.55,0.85,1.12]
	for row in 3:
		for col in times.size():
			var actor := ACTOR.new()
			actor.position = Vector2(150+300*col,155+300*row)
			actor.scale = Vector2.ONE*2.7
			vp.add_child(actor)
			actor.setup(["bat","snake","sheep"][row])
			actor.sample_clip("trigger",times[col])
			var label := Label.new()
			label.text = "%s · %.2f s" % [["蝠漆漆","苹果蛇","羊头仔"][row],times[col]]
			label.position = Vector2(30+300*col,10+300*row)
			vp.add_child(label)
	await process_frame
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("res://build/pet-skill-upgrade")
	vp.get_texture().get_image().save_png("res://build/pet-skill-upgrade/skill-poses.png")
	vp.free()
	quit()
