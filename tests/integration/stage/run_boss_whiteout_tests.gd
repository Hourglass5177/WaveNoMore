extends Node
## 使用正式 StageRoot 和结算页面检查白场；不播放整首歌，不写正式成绩。
var failures := 0
var checks := 0
var stage_root: StageRoot
var results: Array[Dictionary] = []
var viewport: SubViewport
var output := "res://builds/boss-whiteout"
@onready var root := get_tree().root

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr(label)

func _ready() -> void: run.call_deferred()

func settle() -> void:
	for frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> Image:
	await settle()
	var image := viewport.get_texture().get_image()
	image.save_png(output.path_join(name + ".png"))
	return image

func all_white(image: Image) -> bool:
	# 同时覆盖画面四角、中心及 HUD 区域，不能只验证一个透明度变量。
	for x in [0, image.get_width()/4, image.get_width()/2, image.get_width()-1]:
		for y in [0, image.get_height()/4, image.get_height()/2, image.get_height()-1]:
			var color := image.get_pixel(x, y)
			if minf(color.r, minf(color.g, color.b)) < 0.995: return false
	return true

func prepare_ending(stage_id := "level3", hp := 0, success := true, origin_us := 3000000, outro_us := 0, preview := false) -> void:
	results.clear()
	stage_root._level_run_started(0)
	stage_root.stage_session.stage_definition.stage_id = stage_id
	stage_root.stage_session.external_preview = preview
	stage_root._level.outro_us = outro_us
	stage_root.gameplay_coordinator.simulation.current_time_us = origin_us
	for state: Dictionary in stage_root.level_show_player.boss_battle.states.values():
		state.hp = hp; state.phase_us = 0; state.finish_us = 3000000; state.hits = []
	stage_root.stage_session.result_ready.emit({"success":success,"score":1234})

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,540)
	viewport.size_2d_override = Vector2i(1920,1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage_root = load("res://scenes/stage/stage_root.tscn").instantiate()
	viewport.add_child(stage_root)
	var stage: StageDefinition = load("res://content/stages/level3/stage_definition.tres").duplicate(true)
	# 关卡装载入口接收已经解析的正式资源。
	stage.song = load(stage.song_resource_path)
	stage.chart = load(stage.chart_resource_path)
	stage.stage_show = load(stage.stage_show_resource_path)
	stage.visual_theme = load(stage.visual_theme_resource_path)
	stage.background = load(stage.background_resource_path)
	stage.rule_set = load(stage.rule_set_resource_path)
	check(stage_root.load_stage(stage, false), "第三关正式资源能够装载")
	stage_root.set_process(false)
	stage_root.stage_finished.connect(func(result: Dictionary): results.append(result))
	var white: ColorRect = stage_root.get_node("BossFlashLayer/White")
	check(stage_root.get_node("BossFlashLayer").layer > stage_root.hud.layer, "白场覆盖正式 HUD")
	check(stage_root.get_node("BossFlashLayer").layer < stage_root.pause_overlay.layer, "暂停菜单仍可见")
	prepare_ending()
	check(results.is_empty(), "收到最终判定后仍等待死亡演出")
	stage_root._process(2.1)
	check(is_zero_approx(white.color.a), "碎裂初期不遮白")
	await capture("01-fracture")
	stage_root._process(2.0)
	await capture("02-rays")
	stage_root._process(0.875)
	check(white.color.a > 0.0 and white.color.a < 1.0, "爆光渐满")
	await capture("03-burst")
	stage_root._process(0.175)
	check(all_white(await capture("04-white")), "爆裂后整个视口纯白")
	stage_root._process(0.499)
	check(results.is_empty(), "全白不足半秒不能结算")
	stage_root._process(0.002)
	check(results.size() == 1 and stage_root.is_ending_in_white(), "约5.65秒在白场中交接")
	check(not results[0].has("whiteout"), "表现状态不写入成绩")
	stage_root._process(2.0)
	check(results.size() == 1, "收尾只发送一次结果")
	stage_root._level_run_started(0)
	check(not stage_root.is_ending_in_white() and is_zero_approx(white.color.a), "重试清除白场")
	# 极低帧率直接越过素材退白时间，也必须保持结算白场。
	for driver in stage_root.level_show_player.drivers.values(): driver.root.glow_strength = 0.1
	prepare_ending()
	stage_root._process(8.0)
	check(stage_root.is_ending_in_white() and results.size() == 1, "掉帧和低发光倍率不丢白场")
	for size in [Vector2i(1280,720), Vector2i(1200,600), Vector2i(700,700)]:
		viewport.size = size
		check(all_white(await capture("white-%dx%d" % [size.x,size.y])), "改变视口尺寸仍铺满白场")
	prepare_ending("level3", 0, true, 3000000, 8000000)
	stage_root._process(6.7)
	check(results.is_empty() and is_equal_approx(white.color.a, 1.0), "曲后演出更长时保持白场")
	stage_root._process(1.3)
	check(results.size() == 1, "曲后演出结束才结算")
	prepare_ending("level3", 0, true, 10000000)
	stage_root._process(0.49)
	check(results.is_empty() and stage_root.is_ending_in_white(), "死亡早于曲终时仍保留白场")
	stage_root._process(0.02)
	check(results.size() == 1, "曲终后半秒交接")
	prepare_ending("level3", 100)
	stage_root._process(0.7)
	check(results.size() == 1 and not stage_root.is_ending_in_white(), "未击败仍按撤退结算")
	prepare_ending("level3", 0, false)
	check(results.size() == 1 and not stage_root.is_ending_in_white(), "失败不进入死亡白场结算")
	prepare_ending("level2")
	stage_root._process(5.7)
	check(results.is_empty() and not stage_root.is_ending_in_white(), "其他关卡不提前裁掉死亡动画")
	stage_root._process(1.3)
	check(results.size() == 1, "其他关卡保持完整死亡时长")
	prepare_ending("level3", 0, true, 0, 0, true)
	check(results.size() == 1 and not stage_root.is_ending_in_white(), "编辑预览不进入正式白场结算")
	await test_app_handoff()
	viewport.queue_free()
	await settle()
	print("BOSS WHITEOUT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(failures)

func test_app_handoff() -> void:
	viewport.size = Vector2i(960,540)
	var app: Control = load("res://scenes/app/app_main.tscn").instantiate()
	# 替换测试脚本会重建成员，先释放原脚本尚未挂载的任务节点。
	app._jobs.free()
	app.set_script(load("res://tests/integration/stage/boss_whiteout_app.gd"))
	viewport.add_child(app)
	stage_root.reparent(app.screen_host)
	app._current_screen = stage_root
	app._current_stage = stage_root.stage_session.stage_definition
	prepare_ending()
	# 只在此处启用应用路由；开发成绩不会写到用户正式存档。
	root.get_node("SaveService").developer_run = true
	var saved_before: Dictionary = root.get_node("SaveService").data.duplicate(true)
	stage_root.stage_finished.connect(app._on_stage_finished)
	stage_root._process(5.651)
	check(is_instance_valid(app._result_white) and app._result_white.color.a == 1.0, "卸载关卡前接住纯白")
	check(app._current_screen.scene_file_path == "res://scenes/screens/result_screen.tscn", "白场下已经挂载真实结算页")
	await RenderingServer.frame_post_draw
	check(all_white(viewport.get_texture().get_image()), "切换首帧没有露底")
	await get_tree().create_timer(0.5).timeout
	check(not is_instance_valid(app._result_white), "0.4秒后移除结算覆盖层")
	check(not all_white(await capture("05-result")), "白场后显出结算页面")
	check(saved_before == root.get_node("SaveService").data, "测试不修改正式成绩存档")
	app._hold_result_white()
	app._reveal_result_from_white()
	app._on_route_requested(root.get_node("AppRouter").ROUTE_TITLE, {})
	await settle()
	check(not is_instance_valid(app._result_white), "退出路由清除等待中的白场")
	app.queue_free()
