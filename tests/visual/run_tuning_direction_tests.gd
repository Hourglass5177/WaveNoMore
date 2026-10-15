extends SceneTree
## 分别检查引导姿势和原版速度输入；引导帽面不能成为操作计算的依据。
const FIXTURE = preload("res://tests/unit/domain/test_tuning_arc_assist.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func make_engine(chart: CompiledChart, rules: GameplayRuleSet) -> TuningEngine:
	var engine := TuningEngine.new(); engine.configure(chart, rules)
	engine.set_dual_holding_notes(true, 0); engine.advance_to(0, true, true, true)
	return engine
func control(raw: Vector2, side: int) -> Vector2:
	var event := PhysicalInputEvent.new()
	event.kind = GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED if side == 0 else GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED
	event.axis_value = raw
	return InputSemanticConverter.to_tuning_control(event).control_vector
func progress(engine: TuningEngine) -> float:
	return float(engine.active_slider_snapshots()[0].raw_player_progress)
func run() -> void:
	var rules := GameplayRuleSet.new()
	var fixture := FIXTURE.new()
	var field := GrayboxFieldVisual.new(); root.add_child(field); field.set_process(false)
	test_visible_radial_poses(fixture, rules, field)
	test_display_extra_angle(fixture, rules, field)
	for side in 2:
		for increasing in [true, false]:
			for rotation: float in [-170.0, 0.0, 37.0]:
				var chart: CompiledChart = fixture._compile_single_slider(1.2, 2, rules)
				var slider: Dictionary = chart.tuning_sliders[0]
				slider.affinity = side; slider.arc_rotation_deg = rotation
				if not increasing:
					var previous: float = slider.start_value; slider.start_value = slider.end_value; slider.end_value = previous
				field.prepare(slider)
				# 从实际圆心和端点取方向，独立核对起手杆向。
				var tangent := curve_tangent(field, 0.0)
				var engine := make_engine(chart, rules)
				engine.set_stick_control(side, control(tangent, side), 0)
				check(progress(engine) == 0.0, "刚推杆不发生位置跳变")
				engine.advance_to(50000, true, true, true)
				var first := progress(engine)
				engine.advance_to(100000, true, true, true)
				var full := progress(engine)
				check(first > 0.0 and full > first and full < 0.3, "保持杆向持续累积，短时不瞬间填满")
				engine.set_stick_control(side, Vector2.ZERO, 100000)
				engine.advance_to(150000, true, true, true)
				check(is_equal_approx(progress(engine), full), "回中停速保留进度")
				engine.set_stick_control(side, control(-tangent, side), 150000)
				check(is_equal_approx(progress(engine), full), "反向事件本身不跳位置")
				engine.advance_to(175000, true, true, true)
				check(progress(engine) < full, "反向速度逐步回退")
				engine.begin_pause_rearm()
				var paused := progress(engine)
				engine.advance_to(250000, true, true, true)
				check(is_equal_approx(progress(engine), paused), "暂停不延续旧速度")
				var light := make_engine(chart, rules)
				# 原始幅度0.6经0.2死区后为半速。
				light.set_stick_control(side, control(tangent * 0.6, side), 0)
				light.advance_to(100000, true, true, true)
				check(progress(light) > full * 0.49 and progress(light) < full * 0.52, "半幅有效输入约为半速")
				light.set_dual_holding_notes(false, 100000)
				var released := progress(light)
				light.advance_to(200000, true, true, true)
				check(is_equal_approx(progress(light), released), "双Hold断开停止积分")
				# 原版第二程使用本程进度的反向切线，显示姿势不参与输入。
				var reverse := make_engine(chart, rules)
				reverse.advance_to(1000000, true, true, true)
				var back := -curve_tangent(field, 0.0)
				reverse.set_stick_control(side, control(back, side), 1000000)
				check(is_equal_approx(progress(reverse), 1.0), "折返输入不瞬移")
				reverse.advance_to(1100000, true, true, true)
				check(progress(reverse) < 0.9 and progress(reverse) > 0.7, "往返方向与真实曲线一致")
				# 操作使用原版切线；独立检查显示提示不因玩家提前完成而回中。
				var guided := make_engine(chart, rules)
				for at in range(0, 2000000, 4166):
					guided.advance_to(at, true, true, true)
					var state: Dictionary = guided.active_slider_snapshots()[0]
					field.set_slider_state(state)
					var shown: Vector2 = field.visual_state_snapshot().stick_cue_direction
					var p: float = state.raw_player_progress if at < 1000000 else 1.0 - state.raw_player_progress
					var raw := curve_tangent(field, p) * (1.0 if at < 1000000 else -1.0)
					guided.set_stick_control(side, control(raw, side), at)
					check(is_equal_approx(shown.length(), 1.0), "引导不因填满回中")
				guided.advance_to(2000000, true, true, true)
				check(guided.drain_judgments()[0].grade == GameplayTypes.JudgmentGrade.PERFECT, "原版切线速度输入可完成双程")
	for side in 2:
		for count in [1, 2]:
			var chart: CompiledChart = fixture._compile_single_slider(1.2, count, rules)
			chart.tuning_sliders[0].affinity = side; field.prepare(chart.tuning_sliders[0])
			field.set_region_progress(1.0)
			field.set_gameplay_snapshot({"active_tuning_sliders": []})
			var final_direction: Vector2 = field.visual_state_snapshot().stick_cue_direction
			check(is_equal_approx(final_direction.length(), 1.0), "结束后保持终点满推姿势")
			field.set_gameplay_snapshot({"active_tuning_sliders": []})
			check(Vector2(field.visual_state_snapshot().stick_cue_direction).is_equal_approx(final_direction), "退场空快照不回中")
			field.reset_for_pool()
			check(field._recommended_stick_vector == Vector2.ZERO, "回收清理旧姿势")
	test_physical_frame(rules, field)
	field.free()
	print("TUNING VELOCITY/DIRECTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_physical_frame(rules: GameplayRuleSet, field: GrayboxFieldVisual) -> void:
	# 正式物理事件缓冲→GameplaySimulation，验证真实接线仍传递速度向量。
	var chart := DomainFixtureFactory.base_chart("velocity_input", 4800)
	var region := TuningFieldRegion.new(); region.event_id = "field"; region.duration_ticks = 4800
	chart.tuning_fields = [region]
	for side in 2:
		var hold := NoteEvent.new(); hold.event_id = "hold%d" % side
		hold.kind = GameplayTypes.NoteKind.HOLD; hold.affinity = side; hold.duration_ticks = 4800
		chart.note_events.append(hold)
		var slider := TuningSliderEvent.new(); slider.event_id = "slider%d" % side; slider.field_id = "field"
		slider.affinity = side; slider.start_value = 0.2; slider.end_value = 0.8; slider.traversal_ticks = 1920
		chart.tuning_sliders.append(slider)
	var compiled: CompiledChart = ChartCompiler.compile(chart, rules).compiled
	var simulation := GameplaySimulation.new(); simulation.configure(compiled, rules)
	var buffer: Node = load("res://src/runtime/input/input_event_buffer.gd").new()
	root.add_child(buffer); buffer.set_process(false)
	for kind: int in [GameplayTypes.PhysicalInputKind.KEY_J_PRESSED, GameplayTypes.PhysicalInputKind.KEY_F_PRESSED]:
		buffer.inject_physical_event(PhysicalInputEvent.create(0, kind, kind, GameplayTypes.PhysicalDeviceType.KEYBOARD))
	buffer.begin_frame(0); simulation.process_input_frame(buffer); buffer.end_frame(); simulation.advance_to(0)
	check(simulation.note_engine.has_dual_holding_notes(), "正式双Hold建立速度调频资格")
	for side in 2:
		field.prepare(compiled.tuning_sliders[side])
		var tangent := curve_tangent(field, 0.0)
		var kind := GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED if side == 0 else GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED
		buffer.inject_physical_event(PhysicalInputEvent.create(1000, side, kind, GameplayTypes.PhysicalDeviceType.GAMEPAD, 0, 0, tangent))
	buffer.begin_frame(1000); simulation.process_input_frame(buffer); buffer.end_frame(); simulation.advance_to(1000)
	for state: Dictionary in simulation.tuning_engine.active_slider_snapshots():
		check(absf(float(state.raw_player_progress)) < 0.000001, "物理推杆事件不瞬移")
	simulation.advance_to(201000)
	var before := simulation.tuning_engine.active_slider_snapshots()
	simulation.advance_to(401000)
	var after := simulation.tuning_engine.active_slider_snapshots()
	for side in 2:
		check(float(before[side].raw_player_progress) > 0.1 and float(after[side].raw_player_progress) > float(before[side].raw_player_progress), "正式帧无新输入仍持续累积")
		var kind := GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED if side == 0 else GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED
		buffer.inject_physical_event(PhysicalInputEvent.create(401000, side, kind, GameplayTypes.PhysicalDeviceType.GAMEPAD, 0, 0, Vector2.ZERO))
	buffer.begin_frame(401000); simulation.process_input_frame(buffer); buffer.end_frame(); simulation.advance_to(601000)
	var stopped := simulation.tuning_engine.active_slider_snapshots()
	for side in 2:
		check(is_equal_approx(stopped[side].raw_player_progress, after[side].raw_player_progress), "正式物理回中停速")
	buffer.free()


func test_visible_radial_poses(fixture: RefCounted, rules: GameplayRuleSet, field: GrayboxFieldVisual) -> void:
	# 固定用户明确的起手方向，不能再仅用“照着当前推荐能通关”证明推荐正确。
	var chart: CompiledChart = fixture._compile_single_slider(1.2, 2, rules)
	var engine := make_engine(chart, rules)
	field.prepare(chart.tuning_sliders[0])
	for at: int in [0, 500000, 999000, 1000000, 1500000, 1999000]:
		engine.advance_to(at, true, true, true)
		field.set_slider_state(engine.active_slider_snapshots()[0])
		var direction: Vector2 = field.visual_state_snapshot().stick_cue_direction
		var left := at == 0 or at == 1999000
		var middle := at == 500000 or at == 1500000
		check(direction.y < 0.0 and (absf(direction.x) < 0.001 if middle else (direction.x < -0.1 if left else direction.x > 0.1)), "上弧引导必须左上→正上→右上，再沿同一上弧转回：%d" % at)


func curve_tangent(field: GrayboxFieldVisual, p: float) -> Vector2:
	# 从实际圆弧邻点独立求切线，不调用引导方向函数。
	var lo := maxf(0.0, p - 0.0001)
	var hi := minf(1.0, p + 0.0001)
	return (field._point_on_slider(hi) - field._point_on_slider(lo)).normalized()

func test_display_extra_angle(fixture: RefCounted, rules: GameplayRuleSet, field: GrayboxFieldVisual) -> void:
	# 从真实显示路径取径向作独立参照，验证15°只展开端点，中线保持不变。
	for side in 2:
		for increasing in [true, false]:
			for rotation: float in [-170.0, 0.0, 37.0]:
				var chart: CompiledChart = fixture._compile_single_slider(1.2, 2, rules)
				var slider: Dictionary = chart.tuning_sliders[0]
				slider.affinity = side; slider.arc_rotation_deg = rotation
				if not increasing:
					var old_start: float = slider.start_value
					slider.start_value = slider.end_value; slider.end_value = old_start
				field.prepare(slider)
				var engine := make_engine(chart, rules)
				for at: int in [0, 500000, 1000000]:
					engine.advance_to(at, true, true, true)
					field.set_slider_state(engine.active_slider_snapshots()[0])
					var p := float(at) / 1000000.0
					var radial := (field._point_on_slider(p) - field._slider_center() - field._arc_center_offset()).normalized()
					var shown: Vector2 = field.visual_state_snapshot().stick_cue_direction
					check(absf(absf(radial.angle_to(shown)) - (0.0 if at == 500000 else deg_to_rad(15.0))) < 0.00001,
						"两侧正反及旋转弧端点各外展15°，中线与时刻不变")
