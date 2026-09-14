extends SceneTree
## 同一时间的三个材质状态；截帧不依赖屏幕刷新速度。
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var views:Array[SubViewport]=[];var waves:Array[BoundaryWaveScene]=[]
	for mode in ["still","color","full"]:
		var vp:=SubViewport.new();vp.size=Vector2i(1920,1080)
		vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp);views.append(vp)
		var bg:=ColorRect.new();bg.size=Vector2(1920,1080);bg.color=Color("302d3d");vp.add_child(bg)
		var wave:BoundaryWaveScene=load("res://scenes/presentation/boundary_waves.tscn").instantiate()
		vp.add_child(wave);wave.position=Vector2(-49.9,-10.3);wave.scale=Vector2.ONE*BoundaryWaveScene.DESIGN_SCALE
		wave.driver.style.flow_enabled=mode!="still"
		wave.driver.style.streak_strength=BoundaryMotion.DEFAULT_STYLE.streak_strength if mode=="full" else 0.0
		waves.append(wave)
		DirAccess.make_dir_recursive_absolute("res://build/boundary-animation/flow/"+mode)
	var count:=360
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):count=int(arg.trim_prefix("--count="))
	for frame in count:
		for wave in waves:wave.sample_background(frame/60.0)
		await process_frame;RenderingServer.force_draw()
		for index in 3:
			var image:=views[index].get_texture().get_image()
			if index!=2:image=image.get_region(Rect2i(0,300,1920,480))
			image.save_png("res://build/boundary-animation/flow/%s/%04d.png"%[["still","color","full"][index],frame])
		if frame%60==0:print("FLOW FRAME ",frame)
	for vp in views:root.remove_child(vp);vp.free()
	quit()
