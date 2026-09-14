extends "res://tools/boundary_animation/capture.gd"
## 同一真实关卡姿势反复交替开关形变；GPU 计时不包含截图和 PNG 编码。
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0; Engine.time_scale=0.0
	vp=SubViewport.new(); vp.size=Vector2i(1920,1080)
	vp.size_2d_override=Vector2i(1920,1080); vp.size_2d_override_stretch=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	scene=load("res://scenes/stage/stage_root.tscn").instantiate()
	scene.initial_stage=null; scene.auto_start_initial_stage=false; vp.add_child(scene)
	scene.stage_session.external_preview=true; scene.stage_session.pause_on_focus_loss=false
	scene.stage_session.set_process(false); scene.song_clock.set_process(false); scene.set_process(false)
	scene.presentation.set_preview_time_driven(); scene.set_debug_visible(false)
	scene.audio_feedback.preview_muted=true; scene.audio_feedback.preview_strikes_muted=true
	var definition: StageDefinition=root.get_node("ContentCatalog").get_stage("s08").duplicate(true)
	for slot in definition.dependency_paths(): definition.assign_dependency(slot,load(definition.dependency_paths()[slot]))
	if not scene.load_stage(definition,false): quit(1); return
	var controller: ParallaxController=scene.get_parallax_controller()
	var wave: BoundaryWaveScene=controller._background_scenes[0]
	for input: SemanticInputSample in StudioPreviewInputs.build(scene.stage_session.compiled_chart,definition.rule_set):
		if input.timestamp_us>41200000: break
		scene.stage_session.advance_preview(input.timestamp_us,false); scene.gameplay_coordinator.accept_input(input)
	scene.stage_session.advance_preview(41200000)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
	var report:={}
	var flow_only:="--flow" in OS.get_cmdline_user_args()
	var off_key:="flow_off" if flow_only else "static"
	var on_key:="flow_on" if flow_only else "animated"
	for size in [Vector2i(1920,1080),Vector2i(1280,720)]:
		vp.size=size
		var data:={off_key:[],on_key:[]}
		for block in 8:
			var on:=block%2==1
			wave.driver.style.enabled=true if flow_only else on
			wave.driver.style.flow_enabled=on if flow_only else true
			for frame in 90:
				wave.sample_background(41.2+float(frame)/60)
				await process_frame; RenderingServer.force_draw()
				if frame>=30: data[on_key if on else off_key].append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
		var summary:={}
		for key in data:
			data[key].sort()
			summary[key]={"gpu_median_ms":data[key][data[key].size()/2],"gpu_p95_ms":data[key][floori(data[key].size()*.95)],"frames":data[key].size()}
		report[str(size)]=summary; print(size," ",summary)
	FileAccess.open(OUT+("performance-flow.json" if flow_only else "performance.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	scene.queue_free(); await process_frame; vp.queue_free(); await process_frame; quit()
