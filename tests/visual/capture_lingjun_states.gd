extends SceneTree
## 使用实际 Spine 渲染采样动作，供检查支撑、裙面及生死两侧的最终显示。
const OUT := "res://build/lingjun/states/"
const ACTOR := preload("res://scenes/presentation/actors/lingjun_actor.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _actor(canvas: SubViewport, origin: Vector2, clip: String, time: float, size := 0.42) -> SpineSprite:
	var actor := ACTOR.instantiate() as SpineSprite
	actor.position = origin
	actor.scale = Vector2.ONE * size
	canvas.add_child(actor)
	actor.set_update_mode(SpineConstant.UpdateMode_Manual)
	actor.get_animation_state().clear_tracks()
	actor.get_skeleton().set_to_setup_pose()
	actor.get_animation_state().set_animation(clip, false, 0).set_track_time(time)
	actor.update_skeleton(0.0)
	return actor

func _canvas(size: Vector2i) -> SubViewport:
	var canvas := SubViewport.new()
	canvas.size = size
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var bg := ColorRect.new()
	bg.size = size
	bg.color = Color("242330")
	canvas.add_child(bg)
	return canvas

func _save(canvas: SubViewport, path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(OUT + path)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var canvas := _canvas(Vector2i(1600, 900))
	for i in 8:
		var t: float = [0.0, 0.12, 0.25, 0.4, 0.6, 0.8, 0.95, 1.2][i]
		var origin := Vector2((i % 4) * 400, (i / 4) * 450)
		var actor := _actor(canvas, origin + Vector2(120, 425), "death", t)
		var label := Label.new()
		label.position = origin + Vector2(15, 10)
		label.text = "Death %.2f s" % t
		canvas.add_child(label)
		if i == 7:
			print("skirt deform floats: ", actor.get_skeleton().get_slots()[9].get_pose().get_deform().size())
			for name: String in ["bone3", "8", "5", "y", "target", "cl_wuqi"]:
				var pose = actor.get_skeleton().find_bone(name).get_applied_pose()
				print(name, ": ", Vector2(pose.get_world_x(), pose.get_world_y()))
	await _save(canvas, "death-poses.png")
	canvas.queue_free()
	for width in [1280, 1920]: await _twins(width)
	if "--movie" in OS.get_cmdline_user_args(): await _movie()
	if "--rest-movie" in OS.get_cmdline_user_args(): await _rest_movie()
	if "--stage" in OS.get_cmdline_user_args(): await _stage_samples()
	quit()

func _movie() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "frames")
	var canvas := _canvas(Vector2i(1200, 510))
	var actors: Array[SpineSprite] = []
	for index in 3:
		actors.append(_actor(canvas, Vector2(100 + index * 400, 470), "idle", 0.0))
		var label := Label.new()
		label.position = Vector2(20 + index * 400, 15)
		label.text = ["静息", "攻击中受击", "支槌屈膝"][index]
		canvas.add_child(label)
	var presentation = load("res://src/presentation/adapters/graybox_stage_presentation.gd").new()
	presentation._life_actor = actors[1]
	presentation._death_actor = actors[2]
	presentation._preview_time_driven = true
	presentation._reset_preview_actors()
	for frame in 150:
		var time := float(frame) / 30.0
		actors[0].get_animation_state().get_track(0).set_track_time(time)
		actors[0].update_skeleton(0.0)
		if frame in [30, 54, 78, 102]:
			var damage := DamageRecord.create("visual", "visual", roundi(time * 1000000.0), 1, GameplayTypes.Affinity.ZHU)
			damage.actual_damage = 1
			presentation._queue_actor_damage(damage)
		if frame == 48: presentation._queue_actor_death(time, GameplayTypes.Affinity.XUAN)
		presentation._update_actor_snapshot({"time_us": roundi(time * 1000000.0), "life_held": time >= 0.4 and time < 3.8, "death_held": false})
		await _save(canvas, "frames/%04d.png" % frame)
	presentation.free()
	canvas.queue_free()

func _rest_movie() -> void:
	# 同时展示无伤静息、静息受击和攻击受击，避免用攻击画面代替静息反馈检查。
	DirAccess.make_dir_recursive_absolute(OUT + "rest-frames")
	var canvas := _canvas(Vector2i(1440, 640))
	var actors: Array[SpineSprite] = []
	for index in 3:
		actors.append(_actor(canvas, Vector2(140 + index * 480, 540), "idle", 0.0))
		var label := Label.new()
		label.position = Vector2(25 + index * 480, 20)
		label.text = ["静息", "静息受击", "攻击受击"][index]
		label.add_theme_font_size_override("font_size", 24)
		canvas.add_child(label)
	var presentation = load("res://src/presentation/adapters/graybox_stage_presentation.gd").new()
	presentation._life_actor = actors[1]
	presentation._death_actor = actors[2]
	presentation._preview_time_driven = true
	presentation._reset_preview_actors()
	# 两轮完整呼吸，循环动图的首尾姿势自然接回。
	for frame in 240:
		var time := float(frame) / 30.0
		actors[0].get_animation_state().get_track(0).set_track_time(time)
		actors[0].update_skeleton(0.0)
		if frame in [30, 81, 123]:
			var damage := DamageRecord.create("rest_visual", "rest_visual", roundi(time * 1000000.0), 1, GameplayTypes.Affinity.SU)
			damage.actual_damage = 1
			presentation._queue_actor_damage(damage)
		presentation._update_actor_snapshot({"time_us": roundi(time * 1000000.0), "life_held": false, "death_held": time >= 0.4 and time < 4.8})
		await _save(canvas, "rest-frames/%04d.png" % frame)
	presentation.free()
	canvas.queue_free()

func _twins(width: int) -> void:
	var canvas := _canvas(Vector2i(width, width * 9 / 16))
	var presentation = load("res://src/presentation/adapters/graybox_stage_presentation.gd").new()
	var factor := float(width) / 1920.0
	var life := _actor(canvas, Vector2(520, 505) * factor, "idle", 0.0, 0.48 * factor)
	var death := _actor(canvas, Vector2(1400, 575) * factor, "idle", 0.0, 0.48 * factor)
	death.rotation = PI
	presentation._life_actor = life
	presentation._death_actor = death
	presentation._preview_time_driven = true
	presentation._reset_preview_actors()
	presentation._update_actor_snapshot({"time_us": 0, "life_held": true, "death_held": true})
	presentation._queue_actor_death(0.5)
	for age: float in [0.12, 0.65, 1.2, 1.399, 1.4, 1.6, 1.9, 2.05]:
		presentation._update_actor_snapshot({"time_us": roundi((0.5 + age) * 1000000.0), "life_held": false, "death_held": false})
		await _save(canvas, "twins-%d-%04d.png" % [width, roundi(age * 1000)])
	presentation.free()
	canvas.queue_free()

func _stage_samples() -> void:
	var canvas := _canvas(Vector2i(1920, 1080))
	# 正式背景和角色位于负 CanvasLayer，不能用采样底色盖住它们。
	canvas.get_child(0).queue_free()
	var scene = load("res://scenes/stage/stage_root.tscn").instantiate()
	scene.auto_start_initial_stage = false
	scene.initial_stage = null
	canvas.add_child(scene)
	var stage := (load("res://content/stages/s08/stage_definition.tres") as StageDefinition).duplicate(true)
	stage.resolve_dependencies_sync()
	stage.debug_nonlethal = false
	scene.stage_session.external_preview = true
	scene.stage_session.set_process(false)
	scene.presentation.set_preview_time_driven()
	scene.load_stage(stage, false)
	scene.set_debug_visible(false)
	scene.stage_session.reset_preview()
	scene.stage_session.advance_preview(0)
	await _save(canvas, "stage-idle.png")
	var inputs: Array[SemanticInputSample] = [SemanticInputSample.create(100000, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED)]
	scene.stage_session.inject_preview_inputs(inputs)
	scene.stage_session.advance_preview(160000)
	scene.gameplay_coordinator.simulation._apply_damage(DamageRecord.create("capture_hit", "capture_hit", 180000, 20, GameplayTypes.Affinity.ZHU))
	scene.stage_session.advance_preview(240000)
	await _save(canvas, "stage-hurt.png")
	scene.gameplay_coordinator.simulation._apply_damage(DamageRecord.create("capture_death", "capture_death", 300000, 200, GameplayTypes.Affinity.XUAN))
	scene.stage_session.advance_preview(1500000)
	await _save(canvas, "stage-death.png")
	scene.stage_session.advance_preview(1920000)
	await _save(canvas, "stage-ashes.png")
	canvas.queue_free()
