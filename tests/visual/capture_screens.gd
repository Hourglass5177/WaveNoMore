extends SceneTree

## 视觉取样脚本。
## 它需要图形驱动，只负责保存关键界面截图，不做自动像素比对。

## 截图输出到项目外层临时目录，避免被 Godot 当成游戏资源导入。
const OUTPUT_DIR := "res://../tmp/godot_visual_qa"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Visual captures require a graphical display driver; omit --headless.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	# 第一阶段沿正式路由依次截图标题、设置、选关和关卡，不绕过应用外壳。
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
	router.call("navigate", &"loading", {"stage_id": "s01"}, false)
	for _index: int in 240:
		await process_frame
		if router.current_route == &"stage":
			break
	var stage_root := app.get_node_or_null("ScreenHost/StageRoot") as StageRoot
	if stage_root != null:
		stage_root.stage_session.pause_on_focus_loss = false
		stage_root.stage_session.resume_countdown_sec = 0.0
		if stage_root.stage_session.state == GameplayTypes.StageState.PAUSED:
			stage_root.stage_session.request_resume()
	# 等待预备拍进入音符提前生成（lookahead）窗口，截图里才会有玩法对象，而不只是背景。
	await create_timer(2.4).timeout
	_capture("stage_graybox.png")
	# 第二阶段跳到固定 tick 并注入语义输入，稳定捕捉双押、Hold 与疾振的关键状态。
	if stage_root != null and stage_root.seek_tick(1920):
		await _wait_frames(2)
		var chord_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(1920)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
			chord_us,
			997,
			GameplayTypes.SemanticInputKind.LIFE_PRESSED
		))
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
			chord_us,
			998,
			GameplayTypes.SemanticInputKind.DEATH_PRESSED
		))
		await _wait_frames(2)
		_capture("stage_chord_confirm.png")
		await create_timer(0.32).timeout
		_capture("stage_chord_contact.png")
	if stage_root != null and stage_root.seek_tick(2400):
		await _wait_frames(4)
		_capture("stage_hold_approach.png")
	if stage_root != null and stage_root.seek_tick(2880):
		await _wait_frames(2)
		var hold_start_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(2880)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
			hold_start_us,
			999,
			GameplayTypes.SemanticInputKind.LIFE_PRESSED
		))
		await create_timer(0.46).timeout
		_capture("stage_hold_sustain.png")
	if stage_root != null and stage_root.seek_tick(8160):
		await _wait_frames(4)
		_capture("stage_rapid_idle.png")
		var rapid_start_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(8160)
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
			rapid_start_us + 120_000,
			1100,
			GameplayTypes.SemanticInputKind.DEATH_PRESSED
		))
		stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
			rapid_start_us + 132_000,
			1101,
			GameplayTypes.SemanticInputKind.DEATH_RELEASED
		))
		await create_timer(0.22).timeout
		_capture("stage_rapid_single_source.png")
		for strike_index: int in range(1, 10):
			var press_kind: int = (
				GameplayTypes.SemanticInputKind.DEATH_PRESSED
				if strike_index % 2 == 0
				else GameplayTypes.SemanticInputKind.LIFE_PRESSED
			)
			var release_kind: int = (
				GameplayTypes.SemanticInputKind.DEATH_RELEASED
				if strike_index % 2 == 0
				else GameplayTypes.SemanticInputKind.LIFE_RELEASED
			)
			var strike_us: int = rapid_start_us + 260_000 + (strike_index - 1) * 70_000
			stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
				strike_us,
				1100 + strike_index * 2,
				press_kind
			))
			stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
				strike_us + 12_000,
				1101 + strike_index * 2,
				release_kind
			))
		await create_timer(0.72).timeout
		_capture("stage_rapid_interwoven.png")

	# 单独截取调频试验关，方便在没有普通音符干扰时检查中心引导。
	router.call("navigate", &"loading", {"stage_id": "s02"}, false)
	for _index: int in 240:
		await process_frame
		if router.current_route == &"stage":
			break
	stage_root = app.get_node_or_null("ScreenHost/StageRoot") as StageRoot
	if stage_root != null:
		stage_root.stage_session.pause_on_focus_loss = false
		stage_root.stage_session.resume_countdown_sec = 0.0
		if stage_root.stage_session.state == GameplayTypes.StageState.PAUSED:
			stage_root.stage_session.request_resume()
		if stage_root.seek_tick(1920):
			await _wait_frames(4)
			_capture("stage_tuning_preview.png")
		if stage_root.seek_tick(2880):
			var tuning_start_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(2880)
			stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
				tuning_start_us,
				1001,
				GameplayTypes.SemanticInputKind.LIFE_PRESSED
			))
			stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
				tuning_start_us,
				1002,
				GameplayTypes.SemanticInputKind.DEATH_PRESSED
			))
			stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
				tuning_start_us,
				1003,
				GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
				Vector2(0.25, 0.0)
			))
			await create_timer(1.0).timeout
			_capture("stage_tuning_active.png")
		if stage_root.seek_tick(8640):
			var follow_start_us: int = stage_root.stage_session.compiled_chart.tempo_map.tick_to_us(8640)
			stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
				follow_start_us,
				1004,
				GameplayTypes.SemanticInputKind.LIFE_PRESSED
			))
			stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
				follow_start_us,
				1005,
				GameplayTypes.SemanticInputKind.DEATH_PRESSED
			))
			stage_root.gameplay_coordinator.accept_input(SemanticInputSample.create(
				follow_start_us,
				1006,
				GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
				Vector2(0.35, -0.35)
			))
			await create_timer(1.2).timeout
			_capture("stage_tuning_follow_active.png")
	app.free()
	await _wait_frames(2)

	# 最后单独实例化开发工具，避免它们与游戏主界面的节点和输入状态互相影响。
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


func _wait_frames(count: int) -> void:
	for _index: int in count:
		await process_frame


func _capture(file_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))
	var error := image.save_png(path)
	if error != OK:
		printerr("Screenshot failed: %s (%s)" % [path, error_string(error)])
