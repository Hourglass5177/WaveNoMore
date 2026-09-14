extends SceneTree
## 实际 Compatibility 画面，冻结玩法以便同场对照；--game 则连续推进正式试玩。
const OUT := "res://build/boundary-animation/"
var scene
var vp: SubViewport

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(1); return
	# 对照中的其他背景材质也冻结，三组截图只改变分界线。
	Engine.time_scale=0.0
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
	scene.stage_session.advance_preview(0)
	scene.presentation.get_node("CueCanvas/ShowCueHost/TutorialCanvas").visible=false
	var controller: ParallaxController=scene.get_parallax_controller()
	print("BOUNDARY SCENES ",controller._background_scenes.size())
	var wave: BoundaryWaveScene=controller._background_scenes[0]
	var legacy:=load("res://content/presentation/boundary_motion_material.tres").duplicate()
	controller.boundary_motion.apply(legacy,BoundaryWaveScene.DESIGN_SCALE)
	var args:=OS.get_cmdline_user_args()
	var preview_inputs:=StudioPreviewInputs.build(scene.stage_session.compiled_chart,definition.rule_set)
	var cursor:=0
	var start_frame:=0
	var frame_count:=240
	var fps:=30.0
	var output:=OUT
	for argument in args:
		if argument.begins_with("--start="): start_frame=int(argument.trim_prefix("--start="))
		if argument.begins_with("--count="): frame_count=int(argument.trim_prefix("--count="))
		if argument.begins_with("--fps="): fps=float(argument.trim_prefix("--fps="))
		if argument.begins_with("--folder="): output=argument.trim_prefix("--folder=").trim_suffix("/")+"/"
	var modes: Array=["legacy","new"] if "--full" in args else ["new"]
	if "--game" in args: modes=["game"]
	for argument in args:
		if argument.begins_with("--mode="): modes=[argument.trim_prefix("--mode=")]
	for mode in modes:
		DirAccess.make_dir_recursive_absolute(output+mode)
		wave.driver.style.enabled=mode!="legacy"
		wave.originals.material=legacy if mode=="legacy" else null
		for frame in range(start_frame,start_frame+(1 if mode=="static" else (frame_count if "--full" in args or "--game" in args else 7))):
			var seconds:=float(frame)/fps if "--full" in args or "--game" in args else float(frame)
			if mode=="game":
				var at_us:=roundi((seconds+40.0)*1000000)
				while cursor<preview_inputs.size() and preview_inputs[cursor].timestamp_us<=at_us:
					var input: SemanticInputSample=preview_inputs[cursor]
					scene.stage_session.advance_preview(input.timestamp_us,false)
					scene.gameplay_coordinator.accept_input(input); cursor+=1
				scene.stage_session.advance_preview(at_us)
			else:
				wave.sample_background(seconds)
				if mode=="legacy": BoundaryMotion.sample(legacy,seconds,seconds*2.0)
			await process_frame; RenderingServer.force_draw()
			vp.get_texture().get_image().save_png(output+"%s/%04d.png"%[mode,frame])
			if frame%30==0: print(mode," frame ",frame," RAM MiB ",Performance.get_monitor(Performance.MEMORY_STATIC)/1048576)
		print("CAPTURED ",mode)
	vp.size=Vector2i(1280,720)
	await process_frame; RenderingServer.force_draw()
	vp.get_texture().get_image().save_png(output+str(modes[-1])+"-1280.png")
	scene.queue_free(); await process_frame; vp.queue_free(); await process_frame
	quit()
