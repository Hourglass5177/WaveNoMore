extends SceneTree

## 图形驱动下的人工视觉取样；只保存关键界面，不做脆弱的像素断言。

const OUTPUT_DIR := "res://../tmp/godot_visual_qa"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Visual captures require a graphical display driver; omit --headless.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var app := (load("res://scenes/app/app_main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	await _wait_frames(5)
	_capture("title.png")
	var router := root.get_node("AppRouter")
	router.call("navigate", &"settings", {}, false)
	await _wait_frames(3)
	_capture("settings.png")
	var settings_modal := app.get_node_or_null("ModalHost/SettingsModal")
	if settings_modal != null:
		settings_modal.emit_signal("close_requested")
		await _wait_frames(2)
	router.call("navigate", &"stage_select", {}, false)
	await _wait_frames(5)
	_capture("stage_select.png")

	# s01 没有音符，用来确认自由载波和双钟相纹本身足够稳定、清楚。
	var stage_root := await _open_stage(router, app, "s01")
	if stage_root != null:
		_capture("stage_free_carrier.png")
		var now_us: int = roundi(stage_root.stage_session.song_clock.sample().judge_time_sec * 1_000_000.0)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(now_us, 901, GameplayTypes.SemanticInputKind.LIFE_PRESSED))
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(now_us, 902, GameplayTypes.SemanticInputKind.DEATH_PRESSED))
		await create_timer(1.2).timeout
		_capture("stage_dual_carrier.png")

	# s02 只截 Tap 接近中心和双押接触，避免旧综合谱坐标继续污染取样。
	stage_root = await _open_stage(router, app, "s02")
	if stage_root != null and stage_root.seek_tick(3360):
		await _wait_frames(4)
		_capture("stage_tap_approach.png")
	if stage_root != null and stage_root.seek_tick(26880):
		await _wait_frames(2)
		var chord_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(26880)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(chord_us, 910, GameplayTypes.SemanticInputKind.LIFE_PRESSED))
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(chord_us, 911, GameplayTypes.SemanticInputKind.DEATH_PRESSED))
		await create_timer(0.3).timeout
		_capture("stage_chord_contact.png")

	# s03 专门观察 Hold 的头、身体缩短和无需尾判的持续状态。
	stage_root = await _open_stage(router, app, "s03")
	if stage_root != null and stage_root.seek_tick(11040):
		await _wait_frames(4)
		_capture("stage_hold_approach.png")
	if stage_root != null and stage_root.seek_tick(11520):
		var hold_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(11520)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(hold_us, 920, GameplayTypes.SemanticInputKind.LIFE_PRESSED))
		await create_timer(0.45).timeout
		_capture("stage_hold_sustain.png")

	# s04 检查单侧宽滑条和双侧独立调频。这里只注入语义位移，不模拟硬件摇杆。
	stage_root = await _open_stage(router, app, "s04")
	if stage_root != null and stage_root.seek_tick(6240):
		await _wait_frames(4)
		_capture("stage_tuning_preview_early.png")
	if stage_root != null and stage_root.seek_tick(7200):
		await _wait_frames(4)
		_capture("stage_tuning_preview.png")
	if stage_root != null and stage_root.seek_tick(7680):
		var life_tuning_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(7680)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(life_tuning_us, 930, GameplayTypes.SemanticInputKind.LIFE_PRESSED))
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(life_tuning_us, 931, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, Vector2(0.2, 0.0)))
		await create_timer(0.8).timeout
		_capture("stage_tuning_single_active.png")
	if stage_root != null and stage_root.seek_tick(38400):
		var pair_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(38400)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(pair_us, 940, GameplayTypes.SemanticInputKind.LIFE_PRESSED))
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(pair_us, 941, GameplayTypes.SemanticInputKind.DEATH_PRESSED))
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(pair_us, 942, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, Vector2(0.22, -0.22)))
		await create_timer(1.0).timeout
		_capture("stage_tuning_dual_active.png")
	if stage_root != null and stage_root.seek_tick(54720):
		var chain_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(54720)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(chain_us, 950, GameplayTypes.SemanticInputKind.DEATH_PRESSED))
		await create_timer(0.35).timeout
		_capture("stage_tuning_link_chain.png")

	app.free()
	await _wait_frames(2)
	var art_lab := (load("res://scenes/tools/art_lab/art_lab.tscn") as PackedScene).instantiate()
	root.add_child(art_lab)
	await _wait_frames(5)
	_capture("art_lab.png")
	art_lab.free()
	await _wait_frames(2)
	var editor := (load("res://scenes/tools/chart_editor/standalone_chart_editor.tscn") as PackedScene).instantiate()
	root.add_child(editor)
	await _wait_frames(12)
	_capture("chart_editor.png")
	editor.free()
	await _wait_frames(2)
	print("VISUAL QA CAPTURES: %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _open_stage(router: Node, app: Node, stage_id: String) -> StageRoot:
	router.call("navigate", &"loading", {"stage_id": stage_id}, false)
	for _index: int in 240:
		await process_frame
		if router.get("current_route") == &"stage":
			break
	var stage_root := app.get_node_or_null("ScreenHost/StageRoot") as StageRoot
	if stage_root == null:
		return null
	stage_root.stage_session.pause_on_focus_loss = false
	stage_root.stage_session.resume_countdown_sec = 0.0
	if stage_root.stage_session.state == GameplayTypes.StageState.PAUSED:
		stage_root.stage_session.request_resume()
	await _wait_frames(3)
	return stage_root


func _wait_frames(count: int) -> void:
	for _index: int in count:
		await process_frame


func _capture(file_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))
	var error := image.save_png(path)
	if error != OK:
		printerr("Screenshot failed: %s (%s)" % [path, error_string(error)])
