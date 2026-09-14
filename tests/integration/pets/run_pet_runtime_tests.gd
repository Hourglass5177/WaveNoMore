extends "res://tests/integration/pets/run_pet_tests.gd"
## 正式接入回归：事件侧别、有效起手、死亡优先以及会话重演。
const A = GameplayTypes.Affinity

func _run() -> void:
	_test_cues()
	await _test_runtime()
	await _test_equipment_flow()
	print("PET RUNTIME: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_cues() -> void:
	for advanced in [false, true]:
		for side in [A.ZHU, A.XUAN]:
			var c := chart()
			c.note_events[0].affinity = side
			var s := sim(c, pet("yi_huo_she").effect(advanced))
			var down: int = K.LIFE_A_PRESSED if side == A.ZHU else K.DEATH_A_PRESSED
			var up: int = K.LIFE_A_RELEASED if side == A.ZHU else K.DEATH_A_RELEASED
			press(s, 1000000, down)
			check(s.drain_pet_triggers() == [{"timestamp_us": 1000000, "affinity": side}], "两形态 Hold 起手精确记录所属侧")
			press(s, 1100000, up); press(s, 1120000, down)
			var rearm := s.begin_pause_rearm()
			if side == A.ZHU: rearm.life_a_held = true
			else: rearm.death_a_held = true
			s.apply_resume_rearm(rearm)
			s.force_finish()
			check(s.drain_pet_triggers().is_empty(), "续按、重臂和尾部提档均不重复触发")
			var missed := sim(c, pet("yi_huo_she").effect(advanced))
			missed.force_finish()
			check(missed.drain_pet_triggers().is_empty(), "漏接没有苹果蛇技能")
			var tap_chart := c.duplicate(true) as SongChart
			tap_chart.note_events[0].kind = GameplayTypes.NoteKind.TAP
			tap_chart.note_events[0].duration_ticks = 0
			var bat := sim(tap_chart, pet("nu_tu_fu").effect(advanced))
			press(bat, 1000000, down)
			check(bat.drain_pet_triggers() == [{"timestamp_us": 1000000, "affinity": side}], "实际加分事件保留阵营")
			var good := sim(tap_chart, pet("nu_tu_fu").effect(advanced))
			press(good, 1070000, down)
			check(good.drain_pet_triggers().is_empty(), "非 Perfect 没有蝠漆漆技能")
		for side in [A.ZHU, A.XUAN, A.SU]:
			var sheep := sim(chart(), pet("gui_jin_yang").effect(advanced))
			# 从统一伤害入口覆盖机制提供的双侧来源与去重。
			sheep._apply_damage(DamageRecord.create("a", "pair", 100, 20, side))
			sheep._apply_damage(DamageRecord.create("b", "pair", 100, 20, side))
			check(sheep.drain_pet_triggers() == [{"timestamp_us": 100, "affinity": side}], "实际减伤按伤害组去重并保留来源")
			sheep._apply_damage(DamageRecord.create("zero", "zero", 200, 0, side))
			sheep._apply_damage(DamageRecord.create("round", "round", 300, 1, side))
			check(sheep.drain_pet_triggers().is_empty(), "零伤害与取整后没有减伤均不触发")
			sheep.health_engine.soul_fire = 1
			sheep._apply_damage(DamageRecord.create("fatal", "fatal", 400, 20, side))
			check(sheep.damages.back().fatal and sheep.drain_pet_triggers().is_empty(), "致命减伤不播放技能")
			sheep.reset()
			check(sheep.drain_pet_triggers().is_empty(), "重试清空待发表现事件")
	# 消费表现事件不能改变判定、技能收益或 Replay 摘要。
	for id in ["nu_tu_fu", "yi_huo_she", "gui_jin_yang"]:
		var one := sim(chart(), pet(id).effect(true))
		var two := sim(chart(), pet(id).effect(true))
		for s in [one, two]:
			press(s, 1000000)
			if s == one: s.drain_pet_triggers()
			s.force_finish()
		check(ReplayRunner.result_digest(one.judgments, one.strays, one.result_summary()) == ReplayRunner.result_digest(two.judgments, two.strays, two.result_summary()), "消费随从事件不改变 Replay 摘要 " + id)

func make_stage(id: String, parent: Node):
	var definition: StageDefinition = root.get_node("ContentCatalog").get_stage("s08").duplicate(true)
	for slot in definition.dependency_paths():
		definition.assign_dependency(slot, load(definition.dependency_paths()[slot]))
	definition.chart = chart(true, 6)
	var other: NoteEvent = definition.chart.note_events[0].duplicate(true)
	other.event_id = "other"; other.affinity = A.XUAN
	definition.chart.note_events.append(other)
	definition.rule_set = GameplayRuleSet.new()
	definition.debug_nonlethal = false
	var scene = load("res://scenes/stage/stage_root.tscn").instantiate()
	scene.initial_stage = null; scene.auto_start_initial_stage = false
	parent.add_child(scene)
	scene.stage_session.external_preview = true
	scene.stage_session.pause_on_focus_loss = false
	scene.stage_session.set_process(false); scene.song_clock.set_process(false)
	scene.presentation.set_preview_time_driven()
	scene.audio_feedback.preview_muted = true
	scene.audio_feedback.preview_strikes_muted = true
	scene.set_debug_visible(false)
	scene.set_pet(pet(id))
	check(scene.load_stage(definition, false), "正式 StageRoot 装配 " + id)
	return scene

func _bone_pose(view: Node) -> Array:
	var result := []
	for bone in view.skeleton.get_skeleton().get_bones(): result.append(bone.get_global_transform())
	return result

func _same_pose(one: Array, two: Array) -> bool:
	for i in one.size():
		if one[i].origin.distance_to(two[i].origin) > .001 or one[i].x.distance_to(two[i].x) > .001: return false
	return true

func _test_runtime() -> void:
	for id in ["nu_tu_fu", "yi_huo_she", "gui_jin_yang"]:
		var scene = make_stage(id, root)
		var life = scene._pet_views[0]
		var dead = scene._pet_views[1]
		check(life.global_position.distance_to(Vector2(134, 305)) < .01 and (life.global_position + dead.global_position).distance_to(Vector2(1920,1080)) < .01, "120px 随从锚点中心对称")
		check(absf(angle_difference(life.global_rotation, dead.global_rotation)) > 3.14, "死界继承180度旋转")
		check(life._surface != dead._surface and dead._surface.get_shader_parameter("world_gray") == 1.0 and dead._surface.get_shader_parameter("world_brightness") == .65 and life._surface.get_shader_parameter("world_gray") == 0.0, "骨骼滤镜独立实例")
		check(dead.ashes.material.get_shader_parameter("world_gray") == 1.0, "灰烬使用死界滤镜")
		if dead.trigger_lights != null:
			check(dead.trigger_lights.surfaces.all(func(m): return m.get_shader_parameter("world_gray")==1.0 and m.get_shader_parameter("world_brightness")==.65), "胸波与三眼统一死界滤镜")
		if dead.breath != null:
			check(dead.breath.flames.all(func(f): return f.material.get_shader_parameter("world_gray") == 1.0), "三口喷火使用死界滤镜")
		life.sample(-.5)
		var preroll := _bone_pose(life)
		life.sample(-.4)
		check(not _same_pose(preroll, _bone_pose(life)), "倒计时期间常态继续推进")
		life.trigger(-.2); life.sample(-.15)
		check(is_equal_approx(life.skeleton.get_animation_state().get_track(0).get_track_time(), .05), "负时间有效起手保留精确年龄")
		life.die(-.1); life.sample(-.04)
		check(is_equal_approx(life.death_started, -.1), "负时间事件不与未死亡状态混淆")
		life.clear_events()
		# 协调层同一批中跨时刻发送，表现按时间和来源分发。
		scene._queue_pet_trigger(500000, A.ZHU)
		scene._queue_pet_trigger(540000, A.ZHU)
		scene.stage_session.publish_preview_state(580000)
		check(life.events.size() == 1 and dead.events.is_empty(), "单侧与密集技能不串播、不排队")
		var frozen := _bone_pose(life)
		for i in 10: scene.stage_session.publish_preview_state(580000)
		check(_same_pose(frozen, _bone_pose(life)), "暂停期间骨骼及混合冻结")
		scene._queue_pet_trigger(2200000, A.SU)
		scene.stage_session.publish_preview_state(2450000)
		check(life.events.size() == 2 and dead.events.size() == 1, "双侧事件各播一次")
		var fatal := DamageRecord.create("fatal", "fatal", 2600000, 20, A.ZHU)
		fatal.fatal = true
		scene._queue_pet_trigger(2600000, A.SU)
		scene._queue_pet_death(fatal)
		scene.stage_session.publish_preview_state(2670000)
		check(life.events.back().kind == "death" and dead.events.back().kind == "death" and life.events.size() == 3, "同刻死亡取代技能，双侧同时死亡")
		var mixed := _bone_pose(life)
		# 非整除帧率穿过短混合段；定位不依赖帧间隔的拆分方式。
		for fps in [30, 60, 144]:
			life.clear_events()
			life.trigger(.5); life.trigger(2.2); life.die(2.6)
			for frame in int(2.67 * fps): life.sample(float(frame) / fps)
			life.sample(2.67)
			check(_same_pose(mixed, _bone_pose(life)), "不同帧率与定位一致 %dHz" % fps)
		scene.stage_session.reset_preview()
		check(life.events.is_empty() and dead.events.is_empty(), "会话重置清空双方历史")
		# 一批定位跨越技能与死亡边界，恢复与逐帧相同的嵌套混合。
		scene._queue_pet_trigger(500000, A.ZHU)
		scene._queue_pet_trigger(2200000, A.SU)
		scene._queue_pet_death(fatal)
		scene.stage_session.publish_preview_state(2670000)
		check(_same_pose(mixed, _bone_pose(life)), "定位重演与连续播放的混合姿态一致")
		scene.stage_session.publish_preview_state(4350000)
		check(life.ashes.visible and dead.ashes.visible and not life.skeleton.visible, "双方在死亡1.75秒进入灰烬")
		scene.stage_session.publish_preview_state(4650000)
		check(not life.ashes.visible and not dead.ashes.visible and not life.skeleton.visible, "死亡2.05秒完全隐藏")
		scene.stage_session.reset_preview()
		# 正式输入 → 协调层 → StageRoot → 骨骼，不依赖工具的触发接口。
		if id == "yi_huo_she":
			scene.gameplay_coordinator.accept_input(SemanticInputSample.create(1000000, 0, K.LIFE_A_PRESSED))
			scene.stage_session.advance_preview(1450000)
			check(life.events.size() == 1 and dead.events.is_empty() and life.breath.flames.all(func(f): return f.visible), "真实 Hold 起手只让生界喷火")
			scene.stage_session.reset_preview()
			scene.gameplay_coordinator.defer_preview_snapshot = true
			scene.gameplay_coordinator.accept_input(SemanticInputSample.create(1000000, 0, K.LIFE_A_PRESSED))
			scene.stage_session.advance_preview(1450000)
			scene.gameplay_coordinator.defer_preview_snapshot = false
			scene.stage_session.publish_preview_state(1450000)
			check(life.breath.flames.all(func(f): return f.visible), "批次重演保留起手与喷火时间")
		scene.queue_free()
		await process_frame

func _test_equipment_flow() -> void:
	var save = root.get_node("SaveService")
	save.configure_storage_paths("user://pet_run_flow.json", "user://pet_run_flow.tmp", "user://pet_run_flow.bak")
	save.data = save.default_data()
	var definition := StageDefinition.new()
	definition.stage_id = "pet_run_flow"
	definition.chart = chart(); definition.rule_set = GameplayRuleSet.new()
	definition.song = SongDefinition.new(); definition.song.fallback_duration_sec = 8
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	root.add_child(app)
	for id in ["nu_tu_fu", "yi_huo_she", "gui_jin_yang"]:
		for advanced in [false, true]:
			save.data.pets[id] = {"owned": true, "advanced": advanced}
			check(save.equip_pet(id), "菜单选择可装备 " + id)
			save.load_or_create()
			app._show_stage_select()
			app._show_stage(definition)
			var loaded = app._current_screen
			check(loaded.active_pet.pet_id == id and loaded.pet_advanced == advanced and loaded._pet_views.size() == 2, "保存重开后进入关卡使用选中形态")
			loaded.song_clock.stop()
			# 局外存档改变也不能影响本次重试的快照。
			save.equip_pet("")
			app._show_stage(definition)
			loaded = app._current_screen
			check(loaded.active_pet.pet_id == id and loaded.pet_advanced == advanced, "重试沿用本局装备及形态")
			loaded.song_clock.stop()
			app._show_stage_select()
			app._show_stage(definition)
			check(app._current_screen.active_pet == null and app._current_screen._pet_views.is_empty(), "关外卸下后进关不显示随从")
			app._current_screen.song_clock.stop()
			await process_frame
	app.queue_free()
	await process_frame
