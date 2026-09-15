extends SceneTree
## 两阶段在正式背景、中心对称和两个分辨率中的审看；白场只合成一次。
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var vp:=SubViewport.new();vp.size=Vector2i(1920,1080);vp.size_2d_override=Vector2i(1920,1080);vp.size_2d_override_stretch=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var review=load("res://tools/boss_animation/review.tscn").instantiate();vp.add_child(review)
	review.playing=false;review.toolbar.hide();review.references=true;review.toggle_background()
	DirAccess.make_dir_recursive_absolute("res://outputs/boss-animation/stage")
	for size: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720)]:
		vp.size=size
		for paired: bool in [false,true]:
			review.paired=paired;review.demonstrate_phases();review.playing=false
			for point in [[2.5,"reveal"],[10.5,"crack"],[12.1,"white"],[13.7,"empty"]]:
				review.sample_at(point[0]);review.queue_redraw()
				await process_frame;RenderingServer.force_draw()
				var picture:=vp.get_texture().get_image()
				assert(picture.get_size()==size)
				if point[1]=="white":
					assert(is_equal_approx(review.flash_rect.color.a,1.))
					assert(picture.get_pixel(0,0).r>.99 and picture.get_pixel(size.x-1,size.y-1).b>.99)
				picture.save_png("res://outputs/boss-animation/stage/goat-%s-%s-%d.png" % [point[1],"pair" if paired else "single",size.x])
	print("GOAT stage: single/paired x 2 resolutions x reveal/crack/white/end")
	quit()
