extends SceneTree
## 正式装配与图形采样：布局、双侧挥槌、暂停和定位共用同一表现入口。
const OUT := "res://builds/bell-review/"
var checks := 0
var failures := 0
var stage_root
var presentation
var canvas: SubViewport

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _step(time: float, life := true, death := false) -> void:
	presentation._update_actor_snapshot({"time_us": roundi(time * 1000000.0),
		"life_held": life, "death_held": death, "life_frequency_hz": 3.0, "death_frequency_hz": 3.0})

func _save(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(OUT + name + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	canvas = SubViewport.new()
	canvas.size = Vector2i(1920, 1080)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	stage_root = load("res://scenes/stage/stage_root.tscn").instantiate()
	stage_root.auto_start_initial_stage = false
	stage_root.initial_stage = null
	canvas.add_child(stage_root)
	stage_root.stage_session.external_preview = true
	stage_root.stage_session.set_process(false)
	stage_root.song_clock.set_process(false)
	stage_root.set_debug_visible(false)
	stage_root.set_pet(load("res://content/pets/pet_gui_jin_yang.tres"))
	presentation = stage_root.presentation
	presentation.handheld_camera_enabled = false
	presentation.set_preview_time_driven()
	var stage := (load("res://content/stages/tutorial2/stage_definition.tres") as StageDefinition).duplicate(true)
	stage.resolve_dependencies_sync()
	check(stage_root.load_stage(stage, false), "正式关卡与策划参数可装载")
	if failures:
		quit(1)
		return
	stage_root.stage_session.reset_preview()
	stage_root.stage_session.advance_preview(0)
	var actor: Node2D = presentation._life_actor
	var life: BellVisual = actor.get_node("Bell")
	var death: BellVisual = presentation._death_actor.get_node("Bell")
	check(is_equal_approx(presentation._life_actor_slot.to_local(actor.global_position).x, -105.0), "人物右移 36 设计 px，视差挂载保留世界位置")
	check(is_equal_approx(life.position.x * actor.scale.x, 204.0), "人钟间距从 228 收至 204 px")
	for view in stage_root._pet_views:
		check(view.get_parent().position == Vector2(-196, 70), "宠物锚点向外移 60 px")
		check(view.get_parent().scale.is_equal_approx(Vector2.ONE * 1.275), "宠物缩为原来的 85%")
	check(life._surface != death._surface and life._halo_material != death._halo_material, "两侧独立材质，共用 shader")
	check(life._surface.get_shader_parameter("faction_color") != death._surface.get_shader_parameter("faction_color"), "两侧使用各自阵营色")
	check(stage.rule_set.life_wave_origin == presentation.stage_definition.rule_set.life_wave_origin, "布局不改变玩法波源")
	await _save("01-layout")
	# 对照只恢复旧装配位置，不改资源或用户配置。
	actor.position.x -= 36.0
	presentation._death_actor.position.x -= 36.0
	for bell in [life, death]:
		bell.position.x += 24.0 / 0.32
		bell.material = null
		bell._halo.visible = false
	for view in stage_root._pet_views:
		view.get_parent().position.x += 60.0
		view.get_parent().scale /= 0.85
	await _save("00-before")
	actor.position.x += 36.0
	presentation._death_actor.position.x += 36.0
	for bell in [life, death]:
		bell.material = bell._surface
		bell._halo.visible = true
		bell.reset_pose()
	for view in stage_root._pet_views:
		view.get_parent().position.x -= 60.0
		view.get_parent().scale *= 0.85
	_step(0.0)
	_step(0.08)
	check(life.strike_light == 0.0, "挥槌接触之前不闪光")
	_step(0.12)
	check(life.strike_light > 0.9 and death.strike_light == 0.0, "仅实际敲击一侧提亮")
	await _save("02-strike")
	var pose := life.transform
	var light := life.strike_light
	await process_frame
	await process_frame
	check(life.transform == pose and life.strike_light == light, "暂停冻结钟体和光效")
	_step(0.12)
	check(life.transform == pose and life.strike_light == light, "重复快照不重新触发")
	_step(0.20)
	await _save("03-settle")
	_step(0.43, false)
	check(life.strike_light == 0.0, "敲击高光短暂结束")
	await _save("04-rest")
	presentation._reset_preview_actors()
	_step(0.0)
	_step(0.12)
	check(life.transform.is_equal_approx(pose) and is_equal_approx(life.strike_light, light), "定位重演恢复同一受力姿态和亮度")
	presentation._reset_preview_actors()
	_step(0.0, true, true)
	_step(0.12, true, true)
	check(death.strike_light > 0.9, "死侧接触也触发")
	await _save("05-both")
	var count := life.get_child_count()
	for i in 600: _step(0.12 + float(i) / 60.0, true, true)
	check(life.get_child_count() == count and count == 1, "连续敲击复用唯一光晕节点")
	presentation._reset_preview_actors()
	check(life.strike_light == 0.0 and death.strike_light == 0.0, "重试清除敲击反馈")
	life.set_visual_time(0.9)
	check(is_equal_approx((life.position.y - life._base_position.y) * 0.32, 4.0), "浮动幅度使用设计像素")
	canvas.queue_free()
	await process_frame
	print("BELL VISUAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
