extends SceneTree
## 光效审看应保留眼罩，并且切回完整视图后原画恢复。
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var vp:=SubViewport.new();vp.size=Vector2i(1920,1080);vp.transparent_bg=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var review=load("res://tools/boss_animation/review.tscn").instantiate();vp.add_child(review)
	review.playing=false;review.toolbar.hide();review.selected=3;review.rebuild();review.request("start")
	var samples: Array[Image]=[]
	for mode in [0,2,1,0]:
		review.display_mode=mode;review.sample_at(1.4)
		await process_frame;RenderingServer.force_draw()
		samples.append(vp.get_texture().get_image())
	assert(samples[0].get_data()==samples[3].get_data(),"切换图层后原画没有完整恢复")
	var eye_count:=0;var lower_count:=0
	for y in range(1080):
		for x in range(1920):
			if samples[1].get_pixel(x,y).a>.05:
				eye_count+=1
				if y>740:lower_count+=1
	assert(eye_count>1000 and lower_count==0,"仅光效视图缺少眼罩或包含手部")
	DirAccess.make_dir_recursive_absolute("res://outputs/boss-animation/layers")
	for i in 3:samples[i].save_png("res://outputs/boss-animation/layers/goat-eye-%d.png" % i)
	# 觉醒时独立白眼轨道也必须服从审看图层开关。
	review.selected=2;review.rebuild();review.request("phase_break");samples.clear()
	for mode in [0,2,1,0]:
		review.display_mode=mode;review.sample_at(2.)
		await process_frame;RenderingServer.force_draw();samples.append(vp.get_texture().get_image())
	assert(samples[0].get_data()==samples[3].get_data(),"觉醒图层切回后未恢复")
	for y in range(740,1080):
		for x in range(1920):assert(samples[1].get_pixel(x,y).a<.05,"觉醒光效视图包含手部")
	assert(review.actors[0].side_eye_glow>.99,"觉醒侧眼没有恢复")
	samples[0].save_png("res://outputs/boss-animation/layers/goat-awaken-full.png")
	samples[1].save_png("res://outputs/boss-animation/layers/goat-awaken-effects.png")
	print("Review layers: eye mask visible; body restored; lower body clear")
	quit()
