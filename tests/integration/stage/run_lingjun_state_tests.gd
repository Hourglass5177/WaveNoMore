extends SceneTree
## 实际骨骼与领域伤害闭环；同时验证大步定位不会补播、漏播或累计叠加姿态。
var checks := 0
var failures := 0
var presentation
var actors: Array[SpineSprite] = []
const SIDE = GameplayTypes.Affinity

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _step(time: float, held := false) -> void:
	presentation._update_actor_snapshot({"time_us": roundi(time * 1000000.0), "life_held": held, "death_held": false})

func _damage(time: float, side: int, amount := 20, fatal := false) -> void:
	var record := DamageRecord.create("test", "test", roundi(time * 1000000.0), amount, side)
	record.actual_damage = amount
	record.fatal = fatal
	presentation._queue_actor_damage(record)

func _pose(actor: SpineSprite) -> Array:
	var result := []
	for bone in actor.get_skeleton().get_bones(): result.append(bone.get_global_transform())
	return result

func _same(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i].origin.distance_to(b[i].origin) > 0.025 or a[i].x.distance_to(b[i].x) > 0.0002: return false
	return true

func _hurt(actor: SpineSprite) -> bool:
	var state := actor.get_animation_state()
	return state.get_num_tracks() > 1 and state.get_track(1) != null

func _run() -> void:
	presentation = load("res://src/presentation/adapters/graybox_stage_presentation.gd").new()
	for side in 2:
		var actor := load("res://scenes/presentation/actors/lingjun_actor.tscn").instantiate() as SpineSprite
		root.add_child(actor)
		actors.append(actor)
	presentation._life_actor = actors[0]
	presentation._death_actor = actors[1]
	presentation._preview_time_driven = true
	presentation._reset_preview_actors()
	_step(0.0)
	var rest := _pose(actors[0])
	_step(1.6)
	var inhaled := _pose(actors[0])
	check(not _same(rest, inhaled), "静息有呼吸动作")
	var chest_motion: float = rest[5].origin.distance_to(inhaled[5].origin)
	check(chest_motion >= 3.0 and chest_motion <= 9.0, "游戏尺寸下胸肩呼吸清晰，同时保持克制：%.2f px" % chest_motion)
	check(rest[2] == inhaled[2] and rest[3] == inhaled[3] and rest[50] == inhaled[50] and rest[54] == inhaled[54], "静息根、骨盆及双脚固定")
	check(_same(inhaled, _pose(actors[1])), "两侧静息同相位")
	_step(4.0)
	check(_same(rest, _pose(actors[0])), "静息四秒首尾同姿")
	_damage(4.0, SIDE.ZHU, 0)
	_step(4.0)
	check(not _hurt(actors[0]), "零实际伤害不播放受击")
	_damage(4.0, SIDE.ZHU)
	_step(4.06)
	check(_hurt(actors[0]) and not _hurt(actors[1]), "单侧伤害只影响受伤侧")
	check(actors[0].get_animation_state().get_track(0).get_animation().get_name() == "idle" and is_equal_approx(actors[0].get_animation_state().get_track(1).get_alpha(), 1.2), "静息中受击保留呼吸基础轨道，并使用完整收身幅度")
	check(not _same(_pose(actors[0]), _pose(actors[1])), "局部叠加改变实际骨骼姿态")
	var hurt_time := actors[0].get_animation_state().get_track(1).get_track_time()
	_damage(4.06, SIDE.ZHU)
	_step(4.06)
	check(is_equal_approx(actors[0].get_animation_state().get_track(1).get_track_time(), hurt_time), "密集伤害不重启或堆叠动作")
	var frozen := _pose(actors[0])
	for i in 20: _step(4.06)
	await process_frame
	check(_same(frozen, _pose(actors[0])), "暂停和连续同时间快照不累加受击姿态")
	_step(4.5)
	check(not _hurt(actors[0]) and _same(_pose(actors[0]), _pose(actors[1])), "受击结束恢复基础姿态")
	_damage(4.5, SIDE.SU)
	_step(4.56)
	check(_hurt(actors[0]) and _hurt(actors[1]) and _same(_pose(actors[0]), _pose(actors[1])), "双侧机制同时受击")
	check(_same(_replay(false, false, 0.78), _replay(true, false, 0.78)), "攻击中受击的大步与小步定位一致")
	check(is_equal_approx(actors[0].get_animation_state().get_track(0).get_track_time(), 1.24), "受击不改变基础攻击相位或速度")
	check(_same(_replay(false, true, 1.02), _replay(true, true, 1.02)), "攻击转死亡的混合姿态定位一致")
	check(_same(_replay(false, true, 1.8), _replay(true, true, 1.8)), "死亡屈膝及修形定位一致")
	_step(2.0, true)
	check(actors[0].get_animation_state().get_track(0).get_animation().get_name() == "death" and not _hurt(actors[0]), "致命伤害清除局部反应并禁止再攻击")
	_step(2.5)
	check(actors[0].get_node("Ashes").visible and actors[0].get_skeleton().get_color().a == 0.0, "跪地停留后用碎片接替完整角色")
	_step(3.1)
	check(not actors[0].get_node("Ashes").visible and actors[0].get_skeleton().get_color().a == 0.0, "灰烬结束后角色完全消逝")
	presentation._reset_preview_actors()
	_step(0.0)
	check(not actors[0].get_meta("_actor_dead", false) and actors[0].get_skeleton().get_color().a == 1.0 and _same(rest, _pose(actors[0])), "重试清除死亡、修形和消逝状态")
	_test_damage_facts()
	_test_support()
	await _test_stage_connection()
	presentation.free()
	for actor in actors: actor.free()
	print("Lingjun states: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _replay(small: bool, fatal: bool, end: float) -> Array:
	presentation._reset_preview_actors()
	_step(0.0, true)
	_damage(0.70, SIDE.ZHU)
	_damage(0.72, SIDE.ZHU)
	if fatal: _damage(0.96, SIDE.ZHU, 20, true)
	if small:
		for i in range(1, roundi(end * 200.0)): _step(float(i) / 200.0, true)
	_step(end, true)
	return _pose(actors[0])

func _test_damage_facts() -> void:
	var rules := GameplayRuleSet.new()
	rules.stray_input_damages = true
	var chart := DomainFixtureFactory.base_chart("actor_damage", 3840)
	var note := NoteEvent.new()
	note.event_id = "incoming"
	note.tick = 960
	note.affinity = SIDE.XUAN
	chart.note_events.append(note)
	var compiled: CompiledChart = ChartCompiler.compile(chart, rules).compiled
	var core := GameplaySimulation.new()
	core.configure(compiled, rules)
	core.advance_to(1500000)
	check(core.damages.is_empty(), "未抵达的漏击不提前触发角色伤害")
	core.advance_to(core.wave_engine.next_arrival_us())
	var records := core.drain_damages()
	check(records.size() == 1 and records[0].affinity == SIDE.XUAN and records[0].actual_damage > 0, "音符抵达携带实际来源阵营")
	check(core.drain_damages().is_empty(), "实际伤害事件只分发一次")
	core.accept_input(SemanticInputSample.create(core.current_time_us + 100000, 1, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	records = core.drain_damages()
	check(records.size() == 1 and records[0].affinity == SIDE.ZHU, "乱按伤害使用输入阵营")
	core._apply_damage(DamageRecord.create("duplicate", "incoming", core.current_time_us, 20, SIDE.XUAN))
	check(core.drain_damages().is_empty(), "伤害组去重不重复发受击事件")
	core.health_engine.soul_fire = 1
	core._apply_damage(DamageRecord.create("fatal", "fatal", core.current_time_us, 20, SIDE.XUAN))
	records = core.drain_damages()
	check(records.size() == 1 and records[0].fatal, "致命伤害由真实魂火状态确定")
	core.configure(compiled, rules, true)
	core.health_engine.soul_fire = 1
	core._apply_damage(DamageRecord.create("nonlethal", "nonlethal", 0, 20, SIDE.ZHU))
	check(not core.drain_damages()[0].fatal, "非致死模式不触发死亡")

func _test_stage_connection() -> void:
	var scene = load("res://scenes/stage/stage_root.tscn").instantiate()
	scene.auto_start_initial_stage = false
	scene.initial_stage = null
	root.add_child(scene)
	var stage := (load("res://content/stages/s08/stage_definition.tres") as StageDefinition).duplicate(true)
	stage.resolve_dependencies_sync()
	stage.debug_nonlethal = false
	check(scene.load_stage(stage, false), "正式角色场景可装配")
	scene.stage_session.external_preview = true
	scene.stage_session.set_process(false)
	scene.stage_session.reset_preview()
	scene.stage_session.advance_preview(0)
	var core: GameplaySimulation = scene.gameplay_coordinator.simulation
	core._apply_damage(DamageRecord.create("stage_hit", "stage_hit", 100000, 20, SIDE.ZHU))
	scene.stage_session.advance_preview(160000)
	check(_hurt(scene.presentation._life_actor) and not _hurt(scene.presentation._death_actor), "协调层伤害通知进入正式表现入口")
	var hash_before := ChartCompiler.rules_hash(stage.rule_set)
	check(scene.stage_session.failure_visual_settle_sec >= 2.05 and hash_before == ChartCompiler.rules_hash(stage.rule_set), "失败等待覆盖灰烬消逝且不改变规则哈希")
	scene.stage_session.reset_preview()
	scene.stage_session.advance_preview(0)
	check(not _hurt(scene.presentation._life_actor), "正式预览重置清除受击")
	core.health_engine.soul_fire = 20
	core._apply_damage(DamageRecord.create("stage_fatal", "stage_fatal", 200000, 20, SIDE.XUAN))
	scene.stage_session.step(scene.song_clock.publish_external_time(0.2))
	check(scene.stage_session.state == GameplayTypes.StageState.FAILING and scene.presentation._life_actor.get_meta("_actor_dead", false) and scene.presentation._death_actor.get_meta("_actor_dead", false), "真实致命伤害进入失败并使双方死亡")
	scene.stage_session.step(scene.song_clock.publish_external_time(2.299))
	check(scene.stage_session.state == GameplayTypes.StageState.FAILING, "消逝收尾前不进入结算")
	scene.stage_session.step(scene.song_clock.publish_external_time(2.301))
	check(scene.stage_session.state == GameplayTypes.StageState.RESULT and not scene.presentation._life_actor.get_node("Ashes").visible, "灰烬结束后进入结算")
	scene.queue_free()
	await process_frame

func _test_support() -> void:
	var actor := actors[0]
	actor.get_animation_state().clear_tracks()
	actor.get_skeleton().set_to_setup_pose()
	var track := actor.get_animation_state().set_animation("death", false, 0)
	var head_stable := true
	var foot_stable := true
	for frame in range(24, 73):
		track.set_track_time(float(frame) / 60.0)
		actor.update_skeleton(0.0)
		var weapon = actor.get_skeleton().find_bone("cl_wuqi").get_applied_pose()
		var head := Vector2(weapon.get_world_x() + 932.0 * weapon.get_a(), weapon.get_world_y() + 932.0 * weapon.get_c())
		head_stable = head_stable and head.distance_to(Vector2(235.0, -12.0)) < 0.2
		var foot = actor.get_skeleton().find_bone("y").get_applied_pose()
		foot_stable = foot_stable and Vector2(foot.get_world_x(), foot.get_world_y()).distance_to(Vector2(74.60625, -32.39672)) < 0.01
	check(head_stable, "接地后的槌头固定，不随屈膝滑动")
	check(foot_stable, "屈膝期间前脚固定承重")
