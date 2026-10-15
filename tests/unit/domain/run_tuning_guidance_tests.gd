extends SceneTree
## 用真实输入转换验证推荐摇杆；Ghost 的中途余量与尾点 Pass 共用同一尺度。
const FIXTURE := preload("res://tests/unit/domain/test_tuning_arc_assist.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func engine_for(compiled: CompiledChart, rules: GameplayRuleSet) -> TuningEngine:
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	engine.set_dual_holding_notes(true, 0)
	engine.advance_to(0, true, true, true)
	return engine

func place(engine: TuningEngine, slider: Dictionary, progress: float, time_us: int) -> void:
	# 边界测试直接布置领域位置，避免 Q15 输入量化把“精确 80%”移到边界外。
	# 后面的引导闭环和 Ghost 另通过正式速度输入与时间积分，不用这里的布置入口。
	var target := lerpf(float(slider.start_value), float(slider.end_value), progress)
	engine._set_stick_side_value(int(slider.affinity), target, time_us)

func input_vector(raw: Vector2, side: int, time_us: int, rules: GameplayRuleSet) -> Vector2:
	var event := PhysicalInputEvent.new()
	event.kind = GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED if side == 0 else GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED
	event.axis_value = raw
	event.timestamp_us = time_us
	return InputSemanticConverter.to_tuning_control(event, rules.tuning_stick_deadzone).control_vector

func run() -> void:
	var rules := GameplayRuleSet.new()
	var fixture := FIXTURE.new()
	for side in 2:
		for leg in 2:
			for target: float in [0.10, 0.20, 0.50, 0.90]:
				for lag: float in [0.03, 0.10, 0.1001, 0.1999, 0.20, 0.2001, -0.05]:
					var compiled: CompiledChart = fixture._compile_single_slider(1.2, 2, rules)
					var slider: Dictionary = compiled.tuning_sliders[0]
					slider.affinity = side
					var engine := engine_for(compiled, rules)
					var time := leg * 1000000 + roundi(target * 1000000)
					engine.advance_to(time, true, true, true)
					var traveled := maxf(0.0, target - lag)
					place(engine, slider, traveled if leg == 0 else 1.0 - traveled, time)
					var grade := engine.ghost_grade(PackedStringArray([slider.event_id]), time)
					var expected := expected_lag_grade(minf(lag, target))
					check(grade == expected, "中途 Ghost 侧%d 程%d 目标%.2f 落后%.4f 等级%d/%d" % [side, leg, target, lag, grade, expected])
					check(engine.ghost_grade(PackedStringArray([slider.event_id]), time) == grade, "重复查询不改变 Ghost 成绩")
	# 节点同刻不能被下一程重置覆盖；Pass 达标也能击碎，边界外仍漏击。
	for amount: float in [0.97, 0.90, 0.899, 0.8001, 0.80, 0.7999]:
		var compiled: CompiledChart = fixture._compile_single_slider(1.2, 2, rules)
		var slider: Dictionary = compiled.tuning_sliders[0]
		var engine := engine_for(compiled, rules)
		place(engine, slider, amount, 0)
		engine.advance_to(1000000, true, true, true)
		check(engine.ghost_grade(PackedStringArray([slider.event_id]), 1000000) == expected_lag_grade(1.0 - amount), "折返点读取已结算成绩 %.3f" % amount)
		place(engine, slider, 1.0 - amount, 1000000)
		engine.advance_to(2000000, true, true, true)
		check(engine.ghost_grade(PackedStringArray([slider.event_id]), 2000000) == expected_lag_grade(1.0 - amount), "尾点 Good 与 Pass %.3f" % amount)
	var paired: CompiledChart = fixture._compile_paired_sliders(1.2, rules)
	var pair := engine_for(paired, rules)
	pair.advance_to(500000, true, true, true)
	place(pair, paired.tuning_sliders[0], 0.4, 500000)
	place(pair, paired.tuning_sliders[1], 0.4, 500000)
	var ids := PackedStringArray(["life_slider", "death_slider"])
	check(pair.ghost_grade(ids, 500000) == 1, "双侧 Good 共同击碎")
	place(pair, paired.tuning_sliders[1], 0.3, 500000)
	check(pair.ghost_grade(ids, 500000) == 2, "一侧达到Pass，双方仍共同击碎")
	place(pair, paired.tuning_sliders[1], 0.2999, 500000)
	check(pair.ghost_grade(ids, 500000) == 3, "一侧落后超标即漏击")
	place(pair, paired.tuning_sliders[1], 0.5, 500000)
	pair.advance_to(500001, true, false, true)
	check(pair.ghost_grade(ids, 500001) == 3, "松开所属钟仍漏击")
	# 提示只读：玩家提前完成不改变提示，提示继续走到谱面终点。
	var compiled: CompiledChart = fixture._compile_single_slider(1.2, 2, rules)
	var engine := engine_for(compiled, rules)
	var start: Vector2 = engine.active_slider_snapshots()[0].recommended_stick_vector
	engine.advance_to(300000, true, true, true)
	var behind: Vector2 = engine.active_slider_snapshots()[0].recommended_stick_vector
	check(is_equal_approx(start.length(), 1.0) and is_equal_approx(behind.length(), 1.0), "起手与落后均满推，按谱面目标提示角度")
	place(engine, compiled.tuning_sliders[0], 0.8, 300000)
	check(is_equal_approx(Vector2(engine.active_slider_snapshots()[0].recommended_stick_vector).length(), 1.0), "提前但未完成本程仍满推贴边")
	place(engine, compiled.tuning_sliders[0], 1.0, 300000)
	check(engine.active_slider_snapshots()[0].recommended_stick_vector == behind, "提前完成不让提示回中或跳到终点")
	var before := engine.active_slider_snapshots()
	engine.begin_pause_rearm()
	engine.advance_to(900000, true, true, true)
	# 暂停宿主冻结歌曲时钟；这里验证只读快照不改变进度，且取消不延续控制。
	check(engine.active_slider_snapshots()[0].raw_player_progress == before[0].raw_player_progress, "暂停不推进身体位置")
	engine.reset(compiled, rules)
	engine.advance_to(-500000)
	var preview_a := engine.active_slider_snapshots()
	engine.advance_to(-100000)
	check(preview_a[0].recommended_stick_vector == engine.active_slider_snapshots()[0].recommended_stick_vector, "预告不循环演示")
	# 各帧步使用同一组 240 Hz 原版切线输入，重放输出必须一致。
	for side in 2:
		for rotation: float in [-40.0, 35.0]:
			compiled = fixture._compile_single_slider(1.2, 2, rules)
			compiled.tuning_sliders[0].affinity = side
			compiled.tuning_sliders[0].arc_rotation_deg = rotation
			var samples := build_guided_inputs(compiled, rules, side)
			var reference: Array = []
			for frame_step: int in [8333, 16667, 33333, 51739]:
				var result := replay_controls(compiled, rules, side, samples, frame_step)
				check(result[0] == 0, "原版切线输入可完成双程 Perfect 侧%d 旋转%s 帧%d" % [side, rotation, frame_step])
				if reference.is_empty(): reference = result
				else: check(result[0] == reference[0] and absf(result[1] - reference[1]) < 0.00001, "同输入帧率独立")
	# 长短行程和程内变速，用真实控制闭环检查两侧自定义旋转圆弧。
	for ticks: int in [240, 3840]:
		for side in 2:
			var chart := DomainFixtureFactory.base_chart("variable_guidance", ticks * 2 + 960)
			var tempo := TempoEvent.new(); tempo.tick = ticks / 2; tempo.bpm = 180.0
			chart.tempo_events.append(tempo)
			var field := TuningFieldRegion.new(); field.event_id = "field"; field.duration_ticks = ticks * 2 + 960
			var slider := TuningSliderEvent.new(); slider.event_id = "slider"; slider.field_id = "field"
			slider.affinity = side; slider.traversal_ticks = ticks; slider.traversal_count = 2
			slider.start_value = 0.25; slider.end_value = 0.7
			chart.tuning_fields = [field]; chart.tuning_sliders = [slider]
			compiled = ChartCompiler.compile(chart, rules).compiled
			compiled.tuning_sliders[0].visual_radius_px = 80.0 if ticks == 240 else 720.0
			compiled.tuning_sliders[0].arc_rotation_deg = -55.0 if side == 0 else 65.0
			var samples := build_guided_inputs(compiled, rules, side)
			for frame_step: int in [8333, 16667, 33333, 51739]:
				check(replay_controls(compiled, rules, side, samples, frame_step)[0] == 0, "长短程变 BPM 与自定义圆弧闭环 %d/%d/%d" % [ticks, side, frame_step])
	var planning := PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	check(planning.errors.is_empty(), "实际策划表无读取错误")
	var configured := PlanningParameters.rules_copy(rules, planning)
	check(is_equal_approx(configured.tuning_good_completion, 0.9), "实际策划表保留 Good 90%")
	check(is_equal_approx(configured.tuning_progress_speed_multiplier, 1.02), "实际策划表应用原版速度的1.02倍")
	test_velocity_ghost(fixture, rules)
	# 击碎底线跟随策划Pass阈值，不能把20%写死在Ghost里。
	var adjusted := rules.duplicate() as GameplayRuleSet
	adjusted.tuning_pass_completion = 0.85
	var adjusted_chart: CompiledChart = fixture._compile_single_slider(1.2, 1, adjusted)
	var adjusted_engine := engine_for(adjusted_chart, adjusted)
	adjusted_engine.advance_to(500000, true, true, true)
	place(adjusted_engine, adjusted_chart.tuning_sliders[0], 0.35, 500000)
	check(adjusted_engine.ghost_grade(PackedStringArray([adjusted_chart.tuning_sliders[0].event_id]), 500000) == 2, "自定义Pass85%包含15%落后边界")
	place(adjusted_engine, adjusted_chart.tuning_sliders[0], 0.32, 500000)
	check(adjusted_engine.ghost_grade(PackedStringArray([adjusted_chart.tuning_sliders[0].event_id]), 500000) == 3, "自定义Pass85%拒绝18%落后")
	print("TUNING GUIDANCE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func build_guided_inputs(compiled: CompiledChart, rules: GameplayRuleSet, side: int) -> Array:
	var engine := engine_for(compiled, rules)
	var samples: Array = []
	for time in range(0, int(compiled.tuning_sliders[0].end_us), 4166):
		engine.advance_to(time, true, true, true)
		var state := engine.active_slider_snapshots()[0]
		var raw := original_control_direction(engine, state)
		var vector := input_vector(raw, side, time, rules)
		engine.set_stick_control(side, vector, time)
		samples.append([time, vector])
	return samples

func replay_controls(compiled: CompiledChart, rules: GameplayRuleSet, side: int, samples: Array, step: int) -> Array:
	var engine := engine_for(compiled, rules)
	var time := 0
	var cursor := 0
	var end_us := int(compiled.tuning_sliders[0].end_us)
	while time < end_us:
		time = mini(time + step, end_us)
		while cursor < samples.size() and int(samples[cursor][0]) <= time:
			engine.advance_to(samples[cursor][0], false, true, true)
			engine.set_stick_control(side, samples[cursor][1], samples[cursor][0])
			engine.advance_to(samples[cursor][0], true, true, true)
			cursor += 1
		engine.advance_to(time, true, true, true)
	var records := engine.drain_judgments()
	return [records[0].grade, engine._value_for_affinity(side)]


func test_velocity_ghost(fixture: RefCounted, rules: GameplayRuleSet) -> void:
	# 与前面的纯阈值测试分开：以下位置只能通过实际速度输入随时间累积得到。
	for side in 2:
		for leg in 2:
			for lag: float in [0.02, 0.08, 0.099, 0.101, 0.15, 0.199, 0.201]:
				var compiled: CompiledChart = fixture._compile_single_slider(1.2, 2, rules)
				compiled.tuning_sliders[0].affinity = side
				var engine := engine_for(compiled, rules)
				var start_us := leg * 1000000
				engine.advance_to(start_us, true, true, true)
				drive_velocity(engine, rules, start_us, start_us + 400000, [0.4 - lag])
				var state: Dictionary = engine.active_slider_snapshots()[0]
				var traveled: float = 1.0 - float(state.raw_player_progress) if leg == 1 else float(state.raw_player_progress)
				check(absf(traveled - (0.4 - lag)) < 0.00002, "真实速度累积得到预期位置")
				var ids := PackedStringArray([state.event_id])
				var grade := engine.ghost_grade(ids, start_us + 400000)
				check(grade == expected_lag_grade(lag), "速度版Ghost按整程20%余量判断，两侧往返一致")
				engine.set_stick_control(side, Vector2.ZERO, start_us + 400000)
				engine.advance_to(start_us + 450000, true, true, true)
				check(engine.ghost_grade(ids, start_us + 450000) == expected_lag_grade(lag + 0.05), "停杆后实际进度冻结，Ghost落后量随谱面增大")
				engine.advance_to(start_us + 450001, true, side != 0, side != 1)
				check(engine.ghost_grade(ids, start_us + 450001) == 3, "速度版Ghost仍要求所属钟按住")
	for amount: float in [0.32, 0.28, 0.19]:
		var paired: CompiledChart = fixture._compile_paired_sliders(1.2, rules)
		var engine := engine_for(paired, rules)
		drive_velocity(engine, rules, 0, 400000, [0.32, amount])
		var ids := PackedStringArray(["life_slider", "death_slider"])
		check(engine.ghost_grade(ids, 400000) == expected_lag_grade(0.4 - amount), "双侧速度不同，Ghost以落后较多一侧判定")
		engine.set_dual_holding_notes(false, 400000)
		check(engine.ghost_grade(ids, 400000) == 3, "失去双Hold资格不能凭残留进度击碎Ghost")
	for side in 2:
		for leg in 2:
			for amount: float in [0.901, 0.899, 0.801, 0.799]:
				var compiled: CompiledChart = fixture._compile_single_slider(1.2, 2, rules)
				compiled.tuning_sliders[0].affinity = side
				var engine := engine_for(compiled, rules)
				var start_us := leg * 1000000
				engine.advance_to(start_us, true, true, true)
				drive_velocity(engine, rules, start_us, start_us + 800000, [amount])
				engine.set_stick_control(side, Vector2.ZERO, start_us + 800000)
				engine.advance_to(start_us + 1000000, true, true, true)
				var grade := engine.ghost_grade(PackedStringArray([compiled.tuning_sliders[0].event_id]), start_us + 1000000)
				check(grade == expected_lag_grade(1.0 - amount), "速度累积节点与尾点的Good/Pass边界：侧%d程%d完成%.3f实际%d" % [side,leg,amount,grade])


func drive_velocity(engine: TuningEngine, rules: GameplayRuleSet, start_us: int, end_us: int, amounts: Array) -> void:
	# 测试谱每程1秒；推量由目标距离/原速度/输入持续时间换算。
	var at := start_us
	while at < end_us:
		var states := engine.active_slider_snapshots()
		for i in states.size():
			var state: Dictionary = states[i]
			var direction := original_control_direction(engine, state)
			var amplitude: float = float(amounts[i]) * 0.5 / (float(end_us - start_us) / 1000000.0 * rules.tuning_progress_speed_multiplier)
			var raw := direction * (rules.tuning_stick_deadzone + (1.0 - rules.tuning_stick_deadzone) * amplitude)
			engine.set_stick_control(state.affinity, input_vector(raw, state.affinity, at, rules), at)
		at = mini(end_us, at + 4166)
		engine.advance_to(at, true, true, true)


func original_control_direction(engine: TuningEngine, state: Dictionary) -> Vector2:
	# 只给测试构造原版操作输入，不能将显示引导反馈进领域推进。
	var data: Dictionary = engine._slider_states[engine._slider_by_id[state.event_id]]
	var reverse := int(data.traversal_index) % 2 == 1
	var p: float = 1.0 - state.raw_player_progress if reverse else state.raw_player_progress
	return TuningArcGeometry.slider_tangent(p, state.affinity, state.start_value,
		state.end_value, data.sweep_rad, data.rotation_rad) * (-1.0 if reverse else 1.0)


func expected_lag_grade(lag: float) -> int:
	# 默认四档独立预期；精确20%落后仍是Pass，超过边界才Miss。
	if lag <= 0.0300001: return 0
	if lag <= 0.1000001: return 1
	if lag <= 0.2000001: return 2
	return 3
