extends SceneTree
## 图集由实际 Spine 与灰烬 shader 渲染生成，固定 512 画布和原点。
const ACTOR := preload("res://src/tools/pet_animation/pet_study_actor.gd")
const FOLDER := "res://assets/pets/animation_studies/"
const OUT := "res://build/pet-animation/"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("动画素材采样需要 Compatibility 图形渲染。")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var vp := SubViewport.new()
	vp.size = Vector2i(512,512)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var selected_pet := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--pet="): selected_pet = argument.get_slice("=",1)
	for id: String in ["bat", "snake", "sheep"]:
		if not selected_pet.is_empty() and id!=selected_pet: continue
		var actor = ACTOR.new()
		actor.position = Vector2(256,256)
		actor.scale = Vector2.ONE * 4.0
		vp.add_child(actor)
		actor.setup(id)
		if "--death-poses" in OS.get_cmdline_user_args():
			actor.sample_clip("death",1.2)
			await _image(vp, FOLDER+id+"/death_pose.png")
		else:
			var frames := SpriteFrames.new()
			frames.remove_animation("default")
			for clip: String in ["idle", "trigger", "death"]:
				var duration := float(actor.config[clip])
				# 死亡末尾补完全透明帧，非循环播放器停在最后一帧也不会留下灰点。
				var count := ceili(duration*30.0) + (1 if clip=="death" else 0)
				var sheet := Image.create(4096, ceili(float(count)/8)*512, false, Image.FORMAT_RGBA8)
				DirAccess.make_dir_recursive_absolute(OUT+id+"/"+clip)
				for i in count:
					actor.sample_clip(clip,minf(i/30.0,duration))
					var image := await _image(vp, OUT+id+"/"+clip+"/%04d.png" % i)
					sheet.blit_rect(image, Rect2i(0,0,512,512),Vector2i((i%8)*512,(i/8)*512))
				var path := FOLDER+id+"/"+clip+"_sheet.png"
				sheet.save_png(path)
				frames.add_animation(clip)
				frames.set_animation_speed(clip,30.0)
				frames.set_animation_loop(clip,clip=="idle")
				# 输出文本资源，纹理保留 PNG 路径，避免内嵌整个图集副本。
				var texture := ImageTexture.create_from_image(sheet)
				texture.take_over_path(path)
				for i in count:
					var region := AtlasTexture.new()
					region.atlas = texture
					region.region = Rect2((i%8)*512,(i/8)*512,512,512)
					var frame_duration := 1.0
					if clip=="death" and i==count-2: frame_duration = (duration - float(i)/30.0)*30.0
					frames.add_frame(clip,region,frame_duration)
			ResourceSaver.save(frames,FOLDER+id+"/frames.tres")
		actor.free()
		print("Rendered ", id)
	vp.queue_free()
	await process_frame
	quit()

func _image(vp: SubViewport, path: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	# 透明 Viewport 返回预乘 RGB，导出的 PNG 保存直通透明度以避免再导入黑边。
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x,y)
			if c.a > 0.0 and c.a < 1.0:
				image.set_pixel(x,y,Color(c.r/c.a,c.g/c.a,c.b/c.a,c.a))
	image.save_png(path)
	return image
