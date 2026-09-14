extends "res://tests/integration/stage/run_lingjun_state_tests.gd"
## 地景时间表、步态与跨动作定位；使用实际 Spine 骨骼比较。

func _run() -> void:
	presentation = load("res://src/presentation/adapters/graybox_stage_presentation.gd").new()
	for side in 2:
		var actor := load("res://scenes/presentation/actors/lingjun_actor.tscn").instantiate() as SpineSprite
		root.add_child(actor)
		actors.append(actor)
	presentation._life_actor = actors[0]
	presentation._death_actor = actors[1]
	presentation._preview_time_driven = true
	var stage := StageDefinition.new()
	stage.visual_theme = StageVisualTheme.new()
	presentation.stage_definition = stage
	var sequence := StageEnvironmentSequence.new()
	sequence.end_us = 8000000
	for side in 2:
		var key := stage.visual_theme.life_movement_layer_key if side == 0 else stage.visual_theme.death_movement_layer_key
		var motions: Array = []
		for entry in [[0, 0], [1000000, -10], [4000000, 0], [5000000, -10], [7000000, 0]]:
			motions.append({"at": entry[0], "velocity": Vector2(entry[1], 0), "depth": 1, "position": Vector2.ZERO, "camera_offset": Vector2.ZERO})
		sequence.lanes.append({"id": key, "direction": Vector2.LEFT, "motions": motions, "sources": [{"record": {"present": true}, "born_us": 0, "outgoing": {}}]})
	var schedule := ActorLocomotion.new()
	schedule.configure(sequence, stage.visual_theme)
	check(schedule.changes.size() == 4, "四个准确地景启停边界")
	check(schedule.moving_at(0.9) == [false, false] and schedule.moving_at(1.0) == [true, true], "背景启动才迈步")
	_reset_walk(schedule)
	_step(0.0)
	check(_name() == "idle", "静止地景保持静息")
	_step(1.3)
	check(_name() == "walk", "移动后进入步态")
	var first := _pose(actors[0])
	_step(2.9)
	check(_same(first, _pose(actors[0])), "1.6 秒循环姿态一致")
	check(_same(_pose(actors[0]), _pose(actors[1])), "双侧相位一致")
	var frozen := _pose(actors[0])
	for i in 10: _step(2.9)
	check(_same(frozen, _pose(actors[0])), "同时间暂停保持步态")
	_damage(2.9, SIDE.ZHU)
	_step(2.96)
	check(_name() == "walk" and _hurt(actors[0]) and not _hurt(actors[1]), "行走受击保留步态且双方独立")
	_step(3.4)
	check(_same(_pose(actors[0]), _pose(actors[1])), "受击结束接回同相位步态")
	_step(4.3)
	check(_name() == "idle", "背景停止后收步")
	_step(5.3)
	check(_name() == "walk", "背景恢复后重新行走")
	_step(5.4, true)
	_step(5.5, false)
	_step(6.2)
	check(_name() == "walk", "完整攻击收招后回行走")
	for target: float in [1.05, 1.3, 4.05, 4.3, 5.05, 5.3, 7.05, 7.3]:
		_reset_walk(schedule)
		_step(0.0)
		_step(target)
		var direct := _pose(actors[0])
		_reset_walk(schedule)
		_step(0.0)
		for i in range(1, floori(target * 120.0)): _step(float(i) / 120.0)
		_step(target)
		check(_same(direct, _pose(actors[0])), "启停混合的直接定位与连续播放一致 %.2f" % target)
	var unrelated := StageEnvironmentSequence.new()
	unrelated.lanes = sequence.lanes.duplicate(true)
	unrelated.lanes[0].id = "particles"
	schedule.configure(unrelated, stage.visual_theme)
	check(schedule.moving_at(2.0) == [false, true], "粒子层不能替代缺失地景参考")
	unrelated.camera_velocity = Vector2(-10, 0)
	schedule.configure(unrelated, stage.visual_theme)
	check(schedule.moving_at(2.0) == [false, false], "持续镜头速度抵消地景时静息")
	schedule.configure(sequence, stage.visual_theme, 0.5)
	check(schedule.moving_at(0.49) == [false, false] and schedule.moving_at(0.5) == [true, true], "音频偏移映射到启步边界")
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var measured_actor := actors[0]
	measured_actor.get_animation_state().clear_tracks()
	measured_actor.get_skeleton().set_to_setup_pose()
	var walk = measured_actor.get_animation_state().set_animation("walk", true, 0)
	for frame in 97:
		walk.set_track_time(float(frame) / 60.0)
		measured_actor.update_skeleton(0.0)
		var foot = measured_actor.get_skeleton().find_bone("y").get_applied_pose()
		var p := Vector2(foot.get_world_x(), foot.get_world_y()) * 0.405
		low = low.min(p)
		high = high.max(p)
	check(high.x - low.x >= 20.0 and high.x - low.x <= 28.0, "实际脚部行程 20～28 px")
	check(high.y - low.y >= 3.0 and high.y - low.y <= 4.0, "实际抬脚 3～4 px")
	schedule.configure(sequence, stage.visual_theme)
	_reset_walk(schedule)
	_step(1.3)
	_damage(1.4, SIDE.ZHU, 20, true)
	_step(1.48)
	var direct_death := _pose(actors[0])
	_reset_walk(schedule)
	_step(1.3)
	_damage(1.4, SIDE.ZHU, 20, true)
	for i in range(131, 149): _step(float(i) / 100.0)
	check(_same(direct_death, _pose(actors[0])), "移动转死亡的实际混合姿态定位一致")
	check(_name() == "death", "死亡接管步态")
	for lane: Dictionary in unrelated.lanes:
		for motion: Dictionary in lane.motions: motion.velocity = Vector2.ZERO
	unrelated.end_us = 2000000
	unrelated.camera = func(at_us: int) -> Vector2:
		var t := float(at_us) / 1000000.0
		return Vector2(t * t * 0.5, 0.0)
	schedule.configure(unrelated, stage.visual_theme)
	check(schedule.moving_at(0.49) == [false, false] and schedule.moving_at(0.51) == [false, true], "编排镜头曲线跨过速度阈值才启步")
	check(schedule.changes.size() == 1 and absf(schedule.changes[0].time - 0.5) < 0.002, "曲线阈值边界由绝对采样恢复")
	presentation.free()
	for actor in actors: actor.free()
	print("Lingjun walk: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _name() -> String:
	return actors[0].get_animation_state().get_track(0).get_animation().get_name()

func _reset_walk(schedule: ActorLocomotion) -> void:
	presentation._reset_preview_actors()
	presentation._locomotion = schedule
