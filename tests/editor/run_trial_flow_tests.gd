extends SceneTree
## 不传 --chart-editor；通过 --play-chart 隔离玩家存档，仍使用正式输入和游戏应用。
var failures := 0
var app
var test_root := "user://chart_studio/tests/trial_flow_" + str(Time.get_ticks_usec())
func _initialize() -> void: run.call_deferred()
func check(value: bool, text: String) -> void:
	print("PASS " if value else "FAIL ", text)
	if not value: failures += 1
func frames(count := 4) -> void:
	for i in count: await process_frame
func wait_stage() -> bool:
	var until := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < until:
		if is_instance_valid(app._current_screen) and app._current_screen.has_method("load_stage"): return true
		await process_frame
	return false

func run() -> void:
	var fixture := ChartProjectLoader.inspect_package("res://tests/editor/fixtures/tuning/song.json")
	check(ChartPackageWriter.write(fixture.song, fixture.charts, "res://tests/editor/fixtures/tuning", "res://builds/trial-flow-input.zip").is_empty(), "准备独立试玩包")
	var saves = root.get_node("SaveService")
	saves.configure_storage_paths(test_root.path_join("player.json"), test_root.path_join("player.tmp"), test_root.path_join("player.bak"))
	saves.data = saves.default_data()
	saves.debug_grant_pet("nu_tu_fu", false)
	app = load("res://scenes/app/app_main.tscn").instantiate()
	root.add_child(app)
	app._library = LocalChartLibrary.new(); app._library.directory = test_root.path_join("library")
	check(await wait_stage(), "启动参数直接装配正式游戏")
	if not app._current_screen.has_method("load_stage"): quit(1); return
	var stage = app._current_screen
	check(stage.active_pet == null and stage.gameplay_coordinator.simulation.pet_effect.perfect_score_bonus == 0, "写谱器一键试玩忽略已装备随从")
	check(stage.stage_session.state == GameplayTypes.StageState.READY and not stage.song_player.playing, "三秒准备时音乐和判定尚未启动")
	await create_timer(3.2).timeout
	check(stage.song_player.playing and not stage.stage_session.external_preview, "倒计时后真人模式播放音乐")
	check(root.get_node("InputEventBuffer").mode == root.get_node("InputEventBuffer").InputMode.GAMEPLAY, "正式输入已启用，无自动演示")
	stage.stage_session.request_pause()
	await frames()
	app._add_trial_to_library()
	await create_timer(0.5).timeout
	check(app._library.data.songs.size() == 1, "暂停中仍能检查并加入本地谱面")
	var modal = app.modal_host.get_child(0).get_child(0)
	modal._back(); await frames()
	stage.pause_overlay._on_retry_pressed()
	check(await wait_stage(), "暂停重试仍使用外部谱面")
	check(app._current_screen.stage_session.state == GameplayTypes.StageState.READY, "重试再次准备倒计时")
	await create_timer(3.2).timeout
	app._on_stage_finished({"score": 17, "success": true})
	await frames()
	check(app._library.data.scores.is_empty(), "临时试玩不保存成绩，即使已加入本地库")
	check(app._current_screen._select.text == "结束试玩", "临时结算提供结束试玩")
	var song_id: String = app._library.data.songs.keys()[0]
	var chart_id: String = app._library.data.songs[song_id].charts.keys()[0]
	app._local_selection = {"song_id": song_id, "chart_id": chart_id}
	root.get_node("AppRouter").navigate(&"local_charts")
	await frames()
	var page = app._current_screen
	check(page.selected_song == song_id and page.selected_chart == chart_id, "本地列表恢复歌曲和难度")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://builds/trial-review")
		for resolution in [Vector2i(1280,720), Vector2i(1440,900), Vector2i(1920,1080)]:
			root.size = resolution; await frames()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://builds/trial-review/local-%d.png" % resolution.x)
	# 请求返回后取消页面，再到达的后台结果不能把用户送回关卡。
	root.get_node("AppRouter").navigate(&"external_loading", app._library.context(song_id, chart_id))
	root.get_node("AppRouter").navigate(&"local_charts")
	await create_timer(0.5).timeout
	check(app._current_screen.has_method("import_path"), "取消加载后旧结果不覆盖当前页面")
	page = app._current_screen
	page.get_node("%Play").pressed.emit()
	check(await wait_stage(), "本地页面试玩按钮加载所选难度")
	check(app._current_screen.active_pet.pet_id == "nu_tu_fu", "本地谱面使用当前装备")
	await create_timer(3.2).timeout
	app._on_stage_finished({"score": 23, "success": true})
	await frames()
	check(app._library.data.scores.size() == 1, "本地试玩独立保存成绩")
	var key: String = app._library.data.scores.keys()[0]
	check(not (JSON.parse_string(key) as Array)[2].is_empty(), "成绩使用实际编译内容标识")
	app._current_screen._select.pressed.emit(); await frames()
	check(app._current_screen.selected_chart == chart_id, "本地结算返回原难度")
	app._current_screen.get_node("%Back").pressed.emit(); await frames()
	check(app._current_screen.has_signal("stage_selected"), "返回内置选关入口")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720); await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/trial-review/select-1280.png")
	# 内置成绩也使用隔离存档，验证路由回归而不触碰玩家进度。
	var builtin_id: String = root.get_node("ContentCatalog").all_stages()[0].stage_id
	root.get_node("AppRouter").navigate(root.get_node("AppRouter").ROUTE_LOADING, {"stage_id": builtin_id})
	check(await wait_stage(), "内置关卡仍可通过 Catalog 载入")
	check(app._run_context.is_empty(), "内置关卡清除外部运行上下文")
	check(not app._current_screen.pet_advanced, "内置关卡冻结基础形态")
	saves.debug_grant_pet("nu_tu_fu", true)
	app._on_stage_finished({"score": 31, "success": true})
	await frames()
	check(not saves.stage_result(builtin_id).is_empty(), "内置成绩仍走原存档入口")
	app._current_screen._retry.pressed.emit()
	check(await wait_stage(), "内置结算重试仍通过内置 ID 载入")
	check(not app._current_screen.pet_advanced and app._current_screen.gameplay_coordinator.simulation.pet_effect.perfect_score_bonus == 0.02, "局外存档改变后重试仍保留开局配置")
	app._on_stage_finished({"score": 32, "success": true})
	await frames()
	app._current_screen._select.pressed.emit(); await frames()
	check(app._current_screen.has_signal("stage_selected"), "内置结算返回选关")
	root.get_node("AppRouter").navigate(root.get_node("AppRouter").ROUTE_LOADING, {"stage_id": builtin_id})
	check(await wait_stage(), "退出后重新进入关卡")
	check(app._current_screen.pet_advanced, "重新进入读取新的进阶装备")
	app.queue_free(); await frames()
	print("TRIAL FLOW TESTS: ", failures)
	quit(1 if failures else 0)
