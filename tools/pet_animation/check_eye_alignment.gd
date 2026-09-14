extends SceneTree
## 从原画中三眼内部取样，验证整个亮眼阶段在实际渲染中跟随头骨。
const ACTOR := preload("res://src/presentation/pets/animated_pet_visual.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(800,440)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.size = vp.size
	bg.color = Color("302c39")
	vp.add_child(bg)
	var actors: Array[Node2D] = []
	for side in 2:
		var actor := ACTOR.new()
		actor.position = Vector2(210+380*side,220)
		actor.scale = Vector2.ONE*3.0
		actor.rotation = PI if side==1 else 0.0
		vp.add_child(actor)
		actor.setup("sheep")
		actor.set_world(GameplayTypes.Affinity.XUAN if side==1 else GameplayTypes.Affinity.ZHU)
		actors.append(actor)
	var checks := 0
	var failures := 0
	for frame in range(9,28):
		for actor in actors: actor.sample_clip("trigger",float(frame)/30.0)
		await process_frame
		RenderingServer.force_draw()
		var shot := vp.get_texture().get_image()
		for side in 2:
			var bone = actors[side].skeleton.get_skeleton().find_bone("head")
			for point in [Vector2(209,220),Vector2(254,143),Vector2(330,187)]:
				var at: Vector2 = bone.get_global_transform()*(point-Vector2(270,290))
				var pixel := shot.get_pixelv(Vector2i(at))
				checks += 1
				if minf(pixel.r,minf(pixel.g,pixel.b)) < (.55 if side==1 else .88):
					failures += 1
					push_error("眼罩未覆盖原眼睛：帧 %d，侧 %d，原图点 %s" % [frame,side,point])
		if frame==16: shot.save_png("res://build/pet-skill-upgrade/eyes-aligned-both-worlds.png")
	# 除了独立帧，还核对带 0.08 秒混合的播放、暂停和回拖所得像素。
	for actor in actors:
		actor.clear_events()
		actor.trigger(.5)
	for frame in 32:
		for actor in actors: actor.sample(float(frame)/30.0)
	for actor in actors: actor.sample(1.05)
	await process_frame
	RenderingServer.force_draw()
	var continuous := vp.get_texture().get_image().get_data()
	for target in [1.05,1.16,1.05]:
		for actor in actors: actor.sample(target)
		await process_frame
		RenderingServer.force_draw()
		if target!=1.05: continue
		var current := vp.get_texture().get_image().get_data()
		var largest := 0
		for i in current.size(): largest = maxi(largest,absi(int(current[i])-int(continuous[i])))
		checks += 1
		if largest>1:
			failures += 1
			push_error("暂停/回拖的眼部画面不同，最大通道差 %d" % largest)
	print("EYE ALIGNMENT: %d rendered eye samples, %d failures" % [checks,failures])
	vp.free()
	quit(1 if failures else 0)
