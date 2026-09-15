extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1920,1080)
	viewport.size_2d_override=Vector2i(1920,1080);viewport.size_2d_override_stretch=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var review=load("res://tools/boss_animation/review.tscn").instantiate();viewport.add_child(review)
	review.playing=false;review.toolbar.hide();review.paired=true;review.references=true;review.toggle_background()
	DirAccess.make_dir_recursive_absolute("res://outputs/boss-animation/stage")
	for size: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720)]:
		viewport.size=size
		await process_frame;await process_frame
		for i in 4:
			review.selected=i;review.rebuild();review.request("start");review.sample_at(1.4);review.queue_redraw()
			await process_frame;RenderingServer.force_draw()
			var image:=viewport.get_texture().get_image()
			assert(image.get_size()==size,"审看截图尺寸必须与目标一致")
			image.save_png("res://outputs/boss-animation/stage/%s-%d.png" % [review.IDS[i],size.x])
			# 暂停只检查 BOSS；背景原有独立粒子材质可能使用自己的时间。
	print("BOSS review: 4 forms x 2 resolutions")
	quit()
