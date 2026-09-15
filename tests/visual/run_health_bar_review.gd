extends SceneTree
## 真实 Compatibility 绘制与状态检查；不写玩家存档、不改变伤害规则。
var failures := 0
var checks := 0
const OUT := "res://builds/health-bar-review"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func capture(viewport: Viewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT + "/" + name + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var settings := root.get_node("SettingsService")
	settings.resolution = Vector2i(1280,720)
	settings.fullscreen = false
	settings.apply_display_settings()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/image/background/background-fire-deathbk.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = Vector2(1920,1080)
	viewport.add_child(bg)
	var hud = load("res://scenes/ui/hud/stage_hud.tscn").instantiate()
	viewport.add_child(hud)
	for i in 3: await process_frame
	var bar = hud._soul_fire_bar
	hud._on_health_changed(100,100)
	check(bar.value == 100 and bar._trail_ratio == 1.0,"首帧满血直接呈现")
	await capture(viewport,"hud-full")
	hud._on_health_changed(62,100)
	check(bar.value == 62 and bar._trail_ratio == 1.0,"真实血量即时扣减、保留受伤残影")
	var feedback: Tween = bar._feedback
	hud._on_health_changed(62,100)
	check(bar._feedback == feedback,"重复血量通知不重启动画")
	await create_timer(0.12).timeout
	await capture(viewport,"hud-damage")
	paused = true
	var frozen: float = bar._trail_ratio
	await create_timer(0.18).timeout
	check(is_equal_approx(bar._trail_ratio,frozen),"暂停冻结受伤残影")
	paused = false
	await create_timer(0.6).timeout
	check(is_equal_approx(bar._trail_ratio,0.62),"受伤残影收回至当前血量")
	await capture(viewport,"hud-partial")
	var nodes: int = bar.get_child_count()
	for hp in range(61,15,-1): hud._on_health_changed(hp,100)
	check(bar.get_child_count() == nodes,"连续扣血没有新增节点")
	hud._settle_health_feedback(12.0)
	check(is_equal_approx(bar._trail_ratio,0.16),"定位清理受伤残影")
	await capture(viewport,"hud-low")
	hud._on_health_changed(0,100)
	bar.settle_feedback()
	check(bar.ratio == 0 and bar._trail_ratio == 0,"归零关闭血量亮线")
	await capture(viewport,"hud-empty")
	hud._on_health_changed(-20,100)
	check(bar.value == 0 and hud._soul_fire_value.text == "-20 / 100","非致死测试负数保持数值，几何不反向")
	hud._on_health_changed(200,200)
	check(bar.ratio == 1 and bar._trail_ratio == 1,"重试与上限变化立即复位")
	var second = load("res://scenes/ui/hud/soul_fire_bar.tscn").instantiate()
	viewport.add_child(second)
	check(second._ink != bar._ink,"多条血条材质独立")
	second.queue_free()
	# 只调 HUD 画布缩放，验证设计坐标和光晕留边。
	for resolution in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160)]:
		viewport.size = resolution
		hud.scale = Vector2.ONE * float(resolution.x)/1920.0
		bg.size = Vector2(resolution)
		await capture(viewport,"hud-%dx%d" % [resolution.x,resolution.y])
		check(bar.size.x == 520.0,"分辨率变化不改变血条设计宽度")
	var boss_hud = load("res://scenes/presentation/boss_hud.tscn").instantiate()
	viewport.add_child(boss_hud)
	var battle := BossBattleEngine.new()
	battle.states["test"] = {"maximum":200,"hp":200,"phase_us":-1,"finish_us":-1,"name":"鬼金羊"}
	boss_hud.display(battle,0,0.0)
	var boss_bar = boss_hud.rows.test.bar
	check(boss_bar.value == 200 and boss_bar._ink != bar._ink,"BOSS 接入同款组件且材质独立")
	battle.states.test.hp = 100
	boss_hud.display(battle,1000000,0.0)
	check(boss_bar.value == 100 and boss_bar._trail_ratio == 1.0,"BOSS 扣血同步残影")
	boss_hud.display(battle,500000,0.0)
	check(boss_bar._trail_ratio == 0.5,"BOSS 时间回退清除残影")
	viewport.queue_free()
	await process_frame
	# 最后在正式教程关中检查挂接与实际构图。
	var stage = load("res://scenes/stage/stage_root.tscn").instantiate()
	root.add_child(stage)
	stage.stage_session.pause_on_focus_loss = false
	var definition = load("res://content/stages/tutorial2/stage_definition.tres").duplicate(false)
	definition.debug_nonlethal = true
	check(definition.resolve_dependencies_sync() and stage.load_stage(definition,false),"正式关卡加载")
	stage.set_debug_visible(false)
	stage.start_level(true)
	await create_timer(0.25).timeout
	await capture(root,"ingame")
	root.get_texture().get_image().get_region(Rect2i(20,12,440,56)).save_png(OUT+"/ingame-detail.png")
	stage.hud._on_health_changed(63,100)
	await create_timer(0.12).timeout
	await capture(root,"ingame-damage")
	root.get_texture().get_image().get_region(Rect2i(20,12,440,56)).save_png(OUT+"/ingame-damage-detail.png")
	stage.teardown()
	stage.queue_free()
	await process_frame
	print("HEALTH BAR: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
