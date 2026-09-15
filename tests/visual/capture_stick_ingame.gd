extends SceneTree
## 正式教程谱段录帧；只合成两次按住钟的输入，不替换滑条或提示节点。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var settings := root.get_node("SettingsService")
	settings.resolution = Vector2i(1280,720)
	settings.fullscreen = false
	settings.apply_display_settings()
	var stage: Node = load("res://scenes/stage/stage_root.tscn").instantiate()
	root.add_child(stage)
	stage.stage_session.pause_on_focus_loss = false
	var definition: Resource = load("res://content/stages/tutorial2/stage_definition.tres").duplicate(false)
	# 仅为录制定位启用非致死回放，让此前未演奏的音符正常结算完。
	definition.debug_nonlethal = true
	if not definition.resolve_dependencies_sync() or not stage.load_stage(definition, false):
		push_error("教程2装载失败")
		quit(1)
		return
	stage.set_debug_visible(false)
	stage.start_level(true)
	await process_frame
	if not stage.seek_tick(148200):
		push_error("教程2定位失败")
		quit(1)
		return
	# 定位完成后恢复满血，避免把前段测试漏击带进展示。
	stage.gameplay_coordinator.simulation.health_engine.reset()
	var time_us: int = stage.stage_session.compiled_chart.tempo_map.tick_to_us(148200)
	stage.gameplay_coordinator.accept_input(SemanticInputSample.create(time_us, 9001, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	stage.gameplay_coordinator.accept_input(SemanticInputSample.create(time_us, 9002, GameplayTypes.SemanticInputKind.DEATH_A_PRESSED))
	root.get_node("UiInputHints")._set_family(&"xbox", 0)
	var frames: Array[Image] = []
	var times: Array[int] = []
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2500:
		await create_timer(1.0 / 30.0).timeout
		await RenderingServer.frame_post_draw
		frames.append(root.get_texture().get_image())
		times.append(Time.get_ticks_msec() - start)
	var out := "res://builds/controller-review/ingame-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for i in frames.size():
		frames[i].save_png(out + "/%03d.png" % i)
	var file := FileAccess.open(out + "/times.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(times))
	file.close()
	stage.teardown()
	stage.queue_free()
	await process_frame
	print("INGAME STICK: %d frames, tutorial2, actual 1280x720 render" % frames.size())
	quit()
