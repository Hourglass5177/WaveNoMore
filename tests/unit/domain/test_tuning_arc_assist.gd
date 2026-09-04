extends RefCounted

## 调频有限弧与“提前完成、按原时值结算”的纯逻辑回归测试。
## 输入仍使用 Replay v3 的归一化位移，不依赖渲染帧率或滑条画面。

var _failures: PackedStringArray = []
var _checks: int = 0


func run() -> Dictionary:
	_test_default_scale_and_rotary_clutch()
	_test_equivalent_circle_geometry()
	_test_direct_displacement_and_finite_bounds()
	_test_preview_is_visible_but_noninteractive()
	_test_song_time_never_changes_input_distance()
	_test_early_completion_waits_for_authored_endpoint()
	_test_endpoint_deadline_is_inclusive_without_late_window()
	_test_endpoint_magnet_releases_without_erasing_completion()
	_test_roundtrip_settles_each_leg_at_its_authored_time()
	_test_group_waits_for_both_sides()
	_test_snapshot_exposes_endpoint_state()
	_test_endpoint_scoring_has_no_coverage_state()
	_test_field_closes_at_authored_endpoint()
	var passed: bool = _failures.is_empty()
	if passed:
		print("TUNING ARC TESTS: %d checks passed." % _checks)
	else:
		printerr("TUNING ARC TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
		for failure: String in _failures:
			printerr("  - " + failure)
	return {"ok": passed, "checks": _checks, "failures": Array(_failures)}


func _test_equivalent_circle_geometry() -> void:
	var chord_px: float = TuningArcGeometry.chord_length_px(
		1.0 / 3.0,
		2.0 / 3.0,
		1.0,
		7.0,
		160.0
	)
	_expect_near(chord_px, 320.0, 0.0001, "a 2 Hz span becomes a 320 px chord")

	var center_distance_px: float = TuningArcGeometry.equivalent_center_distance_px(1920.0)
	_expect_near(center_distance_px, 420.0, 0.0001, "the default equivalent centre sits 420 px from the chord")
	var sweep: float = TuningArcGeometry.equivalent_sweep_from_chord_rad(
		chord_px,
		center_distance_px
	)
	var expected_sweep: float = 2.0 * atan(320.0 / 840.0)
	_expect_near(sweep, expected_sweep, 0.000001, "the equivalent sweep follows the fixed-chord circle formula")
	_expect_near(rad_to_deg(sweep), 41.7089, 0.001, "a 320 px chord expands to a comfortable forty-two degree arc")

	var angles: Vector2 = TuningArcGeometry.symmetric_directed_angles(
		GameplayTypes.Affinity.ZHU,
		1,
		sweep
	)
	_expect_near((angles.x + angles.y) * 0.5, -PI * 0.5, 0.000001, "life endpoints stay symmetric around the upper axis")
	_expect_near(angles.y - angles.x, sweep, 0.000001, "endpoint separation equals the expanded sweep")
	var reversed: Vector2 = TuningArcGeometry.symmetric_directed_angles(
		GameplayTypes.Affinity.ZHU,
		-1,
		sweep
	)
	_expect_near(reversed.x, angles.y, 0.000001, "reversing direction swaps the fixed endpoints")
	_expect_near(reversed.y, angles.x, 0.000001, "the return trip uses the same geometric arc")

	var radius_px: float = TuningArcGeometry.equivalent_radius_from_chord_px(chord_px, sweep)
	_expect_near(2.0 * radius_px * sin(sweep * 0.5), chord_px, 0.0001, "radius and sweep reconstruct the original chord")
	var normalized_start: Vector2 = TuningArcGeometry.normalized_chord_arc_point(0.0, sweep)
	var normalized_end: Vector2 = TuningArcGeometry.normalized_chord_arc_point(1.0, sweep)
	_expect_near(normalized_start.distance_to(normalized_end), 1.0, 0.000001, "the normalized visual arc has an exact unit chord")

	var early_angle: float = angles.x - deg_to_rad(14.0)
	var late_angle: float = angles.x + deg_to_rad(14.0)
	_expect(TuningArcGeometry.angle_is_inside_start_window(early_angle, GameplayTypes.Affinity.ZHU, 1, sweep), "the start window accepts a slightly early stick angle")
	_expect(TuningArcGeometry.angle_is_inside_start_window(late_angle, GameplayTypes.Affinity.ZHU, 1, sweep), "the start window accepts the same tolerance inside the arc")
	_expect(not TuningArcGeometry.angle_is_inside_start_window(angles.x - deg_to_rad(16.0), GameplayTypes.Affinity.ZHU, 1, sweep), "the start window rejects angles beyond its early boundary")
	_expect(not TuningArcGeometry.angle_is_inside_start_window(angles.x + deg_to_rad(16.0), GameplayTypes.Affinity.ZHU, 1, sweep), "the start window rejects angles beyond its late boundary")
	_expect(not TuningArcGeometry.stick_can_engage_at_start(Vector2.from_angle(angles.x) * 0.54, GameplayTypes.Affinity.ZHU, 1, sweep, 0.55), "a stick below the engage radius cannot start the gesture")
	_expect(TuningArcGeometry.stick_can_engage_at_start(Vector2.from_angle(angles.x) * 0.80, GameplayTypes.Affinity.ZHU, 1, sweep, 0.55), "a pushed stick at the authored start can engage")

	_expect_near(TuningArcGeometry.progress_from_angle(angles.x, GameplayTypes.Affinity.ZHU, 1, sweep), 0.0, 0.000001, "the fixed start angle maps to zero progress")
	_expect_near(TuningArcGeometry.progress_from_angle(-PI * 0.5, GameplayTypes.Affinity.ZHU, 1, sweep), 0.5, 0.000001, "the centre angle maps to half progress")
	_expect_near(TuningArcGeometry.progress_from_angle(angles.y, GameplayTypes.Affinity.ZHU, 1, sweep), 1.0, 0.000001, "the symmetric endpoint maps to full progress")

	_expect_near(TuningArcGeometry.equivalent_sweep_from_chord_rad(0.0, 420.0), 0.0, 0.000001, "zero frequency span remains a zero arc")
	_expect_near(rad_to_deg(TuningArcGeometry.equivalent_sweep_from_chord_rad(1.0, 420.0)), 28.0, 0.0001, "tiny nonzero arcs use the ergonomic minimum")
	_expect_near(rad_to_deg(TuningArcGeometry.equivalent_sweep_from_chord_rad(100000.0, 420.0)), 100.0, 0.0001, "very long arcs stop at the ergonomic maximum")
	_expect_near(rad_to_deg(TuningArcGeometry.bounded_sweep_rad(PI, 0.0, PI, deg_to_rad(50.0))), 80.0, 0.0001, "the start window always remains inside its upper or lower half-plane")


func _test_default_scale_and_rotary_clutch() -> void:
	var rules := GameplayRuleSet.new()
	_expect_near(rules.tuning_min_frequency_hz, 1.0, 0.000001, "default minimum frequency is 1 Hz")
	_expect_near(rules.tuning_base_frequency_hz, 3.0, 0.000001, "default carrier frequency is 3 Hz")
	_expect_near(rules.tuning_max_frequency_hz, 7.0, 0.000001, "default maximum frequency is 7 Hz")
	_expect_near(rules.tuning_hz_per_revolution, 32.0, 0.000001, "one stick revolution changes frequency by 32 Hz")
	var router := InputRouter.new()
	router.configure_from_rules(rules)
	var frequency_range: float = rules.tuning_max_frequency_hz - rules.tuning_min_frequency_hz
	_expect_near(
		router.rotary_displacement_per_radian * TAU * frequency_range,
		32.0,
		0.000001,
		"input conversion preserves the shared Hz-per-revolution scale"
	)
	router.set_tuning_gesture_windows([
		{
			"event_id": "two_hz_life",
			"affinity": GameplayTypes.Affinity.ZHU,
			"start_value": 1.0 / 3.0,
			"end_value": 2.0 / 3.0,
		},
	])
	var life_window: Dictionary = router.tuning_gesture_window_snapshot()["life"]
	var expected_sweep: float = TuningArcGeometry.equivalent_sweep_rad(
		1.0 / 3.0,
		2.0 / 3.0,
		rules.tuning_min_frequency_hz,
		rules.tuning_max_frequency_hz,
		rules.tuning_pixels_per_hz,
		rules.wave_canvas_size.x
	)
	_expect_near(float(life_window["arc_sweep_rad"]), expected_sweep, 0.000001, "a 2 Hz slider expands to the shared equivalent-circle gesture")
	_expect_near(
		float(life_window["start_angle_rad"]) + float(life_window["end_angle_rad"]),
		TuningArcGeometry.center_angle_rad(GameplayTypes.Affinity.ZHU) * 2.0,
		0.000001,
		"gesture endpoints expand symmetrically around the upper-stick axis"
	)
	_expect_near(
		float(life_window["start_angle_rad"]) - float(life_window["capture_start_angle_rad"]),
		deg_to_rad(15.0),
		0.000001,
		"initial capture accepts a fifteen-degree lead-in before the fixed start"
	)
	_expect_near(
		float(life_window["capture_end_angle_rad"]) - float(life_window["start_angle_rad"]),
		deg_to_rad(15.0),
		0.000001,
		"initial capture is symmetric on the inside of the arc"
	)
	router.free()

	var tracker := RotaryStickTracker.new()
	_expect_near(tracker.engage_radius, 0.55, 0.000001, "rotary clutch engages only after a deliberate push")
	_expect_near(tracker.release_radius, 0.35, 0.000001, "rotary clutch releases after returning close to centre")
	_expect_near(tracker.update(Vector2.RIGHT), 0.0, 0.000001, "first pushed frame only anchors the angle")
	_expect_near(tracker.update(Vector2(0.8, 0.0)), 0.0, 0.000001, "fixed direction and radial pull cause no rotation")
	_expect_near(tracker.update(Vector2(0.34, 0.0)), 0.0, 0.000001, "returning inside the release radius disengages without movement")
	_expect_near(tracker.update(Vector2.DOWN), 0.0, 0.000001, "re-engaging only establishes a new anchor")
	_expect_near(tracker.update(Vector2.LEFT), PI * 0.5, 0.000001, "continued clockwise movement emits a positive quarter-turn")


func _test_direct_displacement_and_finite_bounds() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(2.0, 1, rules)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	var start_us: int = int(slider["start_us"])
	engine.advance_to(start_us, true, true, false)

	# 领域层只接收频率轴位移，不应该知道摇杆转角或视觉弧长。
	var slider_span: float = float(slider["end_value"]) - float(slider["start_value"])
	engine.handle_input(_tune_sample(start_us, slider_span * 0.5), true, false)
	_expect_near(float(engine.active_slider_snapshots()[0]["player_progress"]), 0.5, 0.0002, "half the visible arc fills half the slider")
	engine.handle_input(_tune_sample(start_us, -slider_span * 0.25), true, false)
	_expect_near(float(engine.active_slider_snapshots()[0]["player_progress"]), 0.25, 0.0002, "reverse rotation retreats immediately before completion")
	engine.handle_input(_tune_sample(start_us, slider_span * 0.75), true, false)
	_expect_near(float(engine.active_slider_snapshots()[0]["player_progress"]), 1.0, 0.0001, "the exact finite arc fills the short slider immediately")
	engine.handle_input(_tune_sample(start_us, 1.0), true, false)
	_expect_near(engine.life_tuning_value(), float(slider["end_value"]), 0.0001, "extra forward rotation cannot overflow the endpoint")


func _test_song_time_never_changes_input_distance() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(2.0, 1, rules)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var raw_delta: float = 0.05
	var start_us: int = int(slider["start_us"])
	var halfway_us: int = compiled.tempo_map.tick_to_us(int(slider["tick"]) + int(slider["traversal_ticks"]) / 2)

	for time_us: int in [start_us, halfway_us]:
		var engine := TuningEngine.new()
		engine.configure(compiled, rules)
		engine.advance_to(time_us, true, true, false)
		var before: float = engine.life_tuning_value()
		engine.handle_input(_tune_sample(time_us, raw_delta), true, false)
		_expect_near(engine.life_tuning_value() - before, raw_delta, 0.0001, "guide time cannot amplify, damp, or discard real rotation")


func _test_preview_is_visible_but_noninteractive() -> void:
	var rules := GameplayRuleSet.new()
	var chart := DomainFixtureFactory.base_chart("preview_gate", 3840)
	var field := TuningFieldRegion.new()
	field.event_id = "field"
	field.tick = 0
	field.duration_ticks = 2880
	var slider := TuningSliderEvent.new()
	slider.event_id = "delayed_slider"
	slider.field_id = field.event_id
	slider.affinity = GameplayTypes.Affinity.ZHU
	slider.tick = 960
	slider.traversal_ticks = 960
	slider.start_value = inverse_lerp(
		rules.tuning_min_frequency_hz,
		rules.tuning_max_frequency_hz,
		rules.tuning_base_frequency_hz
	)
	slider.end_value = slider.start_value + 2.0 / (
		rules.tuning_max_frequency_hz - rules.tuning_min_frequency_hz
	)
	chart.tuning_fields = [field]
	chart.tuning_sliders = [slider]
	var compile_result: Dictionary = ChartCompiler.compile(chart, rules)
	_expect(bool(compile_result.get("ok", false)), "preview-gate fixture compiles")
	var compiled: CompiledChart = compile_result.get("compiled") as CompiledChart
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	engine.advance_to(0, true, true, false)
	var preview_states: Array[Dictionary] = engine.active_slider_snapshots()
	_expect_equal(preview_states.size(), 1, "the upcoming slider is exposed during its shrinking-ring preview")
	if not preview_states.is_empty():
		_expect_equal(StringName(preview_states[0]["phase"]), &"preview", "the upcoming slider declares an explicit preview phase")
		_expect(not bool(preview_states[0]["interaction_open"]), "preview phase keeps its input gate closed")
		_expect_near(float(preview_states[0]["player_progress"]), 0.0, 0.000001, "preview fill stays at the authored start")
	var before: float = engine.life_tuning_value()
	engine.handle_input(_tune_sample(0, 0.20), true, false)
	_expect_near(engine.life_tuning_value(), before, 0.000001, "rotation during the shrinking ring cannot pre-fill the slider")
	var slider_start_us: int = int(compiled.tuning_sliders[0]["start_us"])
	engine.advance_to(slider_start_us, true, true, false)
	var active_states: Array[Dictionary] = engine.active_slider_snapshots()
	_expect_equal(StringName(active_states[0]["phase"]), &"active", "the input gate opens at the authored start")
	_expect(bool(active_states[0]["interaction_open"]), "active phase accepts real rotation")


func _test_early_completion_waits_for_authored_endpoint() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(1.2, 1, rules)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var target_us: int = int(slider["end_us"])
	var full_delta: float = float(slider["end_value"]) - float(slider["start_value"])
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	_apply_input(engine, target_us - 700_000, Vector2(full_delta, 0.0), true, false)
	_expect(engine.drain_judgments().is_empty(), "early completion records no score before the dotted guide arrives")
	engine.advance_to(target_us - 1, true, true, false)
	_expect(engine.drain_judgments().is_empty(), "the slider remains unsettled through the frame before its endpoint")
	engine.advance_to(target_us, true, true, false)
	var record: JudgmentRecord = _first_record(engine)
	var endpoint := _find_component(record, &"life_endpoint")
	_expect(record != null and record.grade == GameplayTypes.JudgmentGrade.PERFECT, "an early completion scores when the guide reaches the authored endpoint")
	_expect(endpoint != null, "the result keeps one endpoint component")
	if endpoint != null:
		_expect_equal(endpoint.error_us, -700_000, "metadata keeps the real early completion time for debugging")
		_expect_equal(int(endpoint.metadata["entry_count"]), 1, "the first successful completion is locked once")


func _test_endpoint_deadline_is_inclusive_without_late_window() -> void:
	var rules := GameplayRuleSet.new()
	var exact_record: JudgmentRecord = _run_single_endpoint_at_offset(0)
	_expect(exact_record != null and exact_record.grade == GameplayTypes.JudgmentGrade.PERFECT, "completion exactly when the guide arrives is accepted")
	var late_record: JudgmentRecord = _run_single_endpoint_at_offset(1)
	_expect(late_record != null and late_record.grade == GameplayTypes.JudgmentGrade.MISS, "completion one microsecond after settlement cannot repair the result")


func _test_endpoint_magnet_releases_without_erasing_completion() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(1.2, 1, rules)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var target_us: int = int(slider["end_us"])
	var full_delta: float = float(slider["end_value"]) - float(slider["start_value"])
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	_apply_input(engine, target_us - 700_000, Vector2(full_delta * 0.98, 0.0), true, false)
	var held_snapshot: Dictionary = engine.active_slider_snapshots()[0]
	_expect(bool(held_snapshot["endpoint_captured"]), "entering the final three percent registers early completion")
	_expect(bool(held_snapshot["endpoint_magnetized"]), "the held fill receives a small visual endpoint magnet")
	_expect_near(float(held_snapshot["raw_player_progress"]), 0.98, 0.0002, "magnetism does not rewrite the real frequency position")
	_expect_near(float(held_snapshot["player_progress"]), 1.0, 0.0001, "the final few visual cells settle against the endpoint")

	engine.advance_to(target_us - 600_000, true, false, false)
	var released_snapshot: Dictionary = engine.active_slider_snapshots()[0]
	_expect(not bool(released_snapshot["endpoint_magnetized"]), "releasing the bell immediately disengages the endpoint magnet")
	_expect_near(float(released_snapshot["player_progress"]), 0.98, 0.0002, "released fill falls back to its real position")

	_apply_input(engine, target_us - 500_000, Vector2(-full_delta * 0.25, 0.0), true, false)
	var retreated_snapshot: Dictionary = engine.active_slider_snapshots()[0]
	_expect_near(float(retreated_snapshot["player_progress"]), 0.73, 0.0003, "reverse rotation can pull a completed fill away from the endpoint")
	_expect(bool(retreated_snapshot["endpoint_captured"]), "retreating does not erase the already registered early completion")


func _test_roundtrip_settles_each_leg_at_its_authored_time() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(1.2, 2, rules)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var first_target_us: int = compiled.tempo_map.tick_to_us(int(slider["tick"]) + int(slider["traversal_ticks"]))
	var second_target_us: int = int(slider["end_us"])
	var full_delta: float = float(slider["end_value"]) - float(slider["start_value"])
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	_apply_input(engine, first_target_us - 300_000, Vector2(full_delta, 0.0), true, false)
	engine.advance_to(first_target_us, true, true, false)
	_expect(engine.drain_judgments().is_empty(), "finishing the first trip does not settle the whole roundtrip")
	_apply_input(engine, second_target_us - 300_000, Vector2(-full_delta, 0.0), true, false)
	_expect(engine.drain_judgments().is_empty(), "finishing the return trip early still waits for its guide")
	engine.advance_to(second_target_us, true, true, false)
	var record: JudgmentRecord = _first_record(engine)
	_expect_equal(_count_components(record, &"life_endpoint"), 2, "roundtrip creates one timing component per traversal")
	_expect_equal(record.grade, GameplayTypes.JudgmentGrade.PERFECT, "both completed trips score at the final authored endpoint")


func _test_group_waits_for_both_sides() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_paired_sliders(1.2, rules)
	var life_slider: Dictionary = compiled.tuning_sliders[0]
	var death_slider: Dictionary = compiled.tuning_sliders[1]
	var target_us: int = int(life_slider["end_us"])
	var life_delta: float = float(life_slider["end_value"]) - float(life_slider["start_value"])
	var death_delta: float = float(death_slider["end_value"]) - float(death_slider["start_value"])
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	_apply_input(engine, target_us - 500_000, Vector2(life_delta, 0.0), true, true)
	_expect(engine.drain_judgments().is_empty(), "one early side cannot settle a paired slider")
	_apply_input(engine, target_us, Vector2(0.0, death_delta), true, true)
	var record: JudgmentRecord = _first_record(engine)
	_expect_equal(_count_components(record, &"life_endpoint"), 1, "paired group retains the life endpoint")
	_expect_equal(_count_components(record, &"death_endpoint"), 1, "paired group retains the death endpoint")
	_expect_equal(record.grade, GameplayTypes.JudgmentGrade.PERFECT, "one early and one on-time side complete the paired group")


func _test_snapshot_exposes_endpoint_state() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(1.2, 1, rules)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var target_us: int = int(slider["end_us"])
	var full_delta: float = float(slider["end_value"]) - float(slider["start_value"])
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	_apply_input(engine, target_us - 100_000, Vector2(full_delta, 0.0), true, false)
	var snapshot: Dictionary = engine.active_slider_snapshots()[0]
	_expect(not snapshot.has("coverage"), "snapshot no longer computes obsolete continuous coverage")
	_expect_equal(int(snapshot["current_endpoint_index"]), 0, "snapshot identifies the current traversal endpoint")
	_expect(bool(snapshot["endpoint_inside"]), "snapshot exposes spatial capture state")
	_expect(bool(snapshot["endpoint_captured"]), "snapshot exposes that at least one entry occurred")
	_expect_equal(int(snapshot["endpoint_grade"]), GameplayTypes.JudgmentGrade.PERFECT, "snapshot exposes the best endpoint grade so far")
	_expect_equal(int(snapshot["endpoint_best_error_us"]), -100_000, "snapshot exposes signed endpoint timing error")
	_expect(bool(snapshot["endpoint_window_active"]), "snapshot exposes the active timing window")


func _test_endpoint_scoring_has_no_coverage_state() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(1.2, 1, rules)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var target_us: int = int(slider["end_us"])
	var full_delta: float = float(slider["end_value"]) - float(slider["start_value"])
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	engine.advance_to(target_us, false, false, false)
	_apply_input(engine, target_us, Vector2(full_delta, 0.0), true, false)
	engine.advance_to(target_us, true, true, false)
	var record: JudgmentRecord = _first_record(engine)
	_expect_equal(record.grade, GameplayTypes.JudgmentGrade.PERFECT, "a precise endpoint alone determines the slider grade")
	_expect_equal(_count_components(record, &"life_coverage"), 0, "coverage creates no judgment component")
	_expect(not record.metadata["sides"]["life"].has("coverage"), "coverage is not computed or stored in result metadata")


func _test_field_closes_at_authored_endpoint() -> void:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(1.2, 1, rules, 0)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var target_us: int = int(slider["end_us"])
	var full_delta: float = float(slider["end_value"]) - float(slider["start_value"])
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	engine.advance_to(target_us, true, true, false)
	_expect(not engine.field_active(), "field closes as soon as the authored endpoint is settled")
	_apply_input(engine, target_us + 400_000, Vector2(full_delta, 0.0), true, false)
	var record: JudgmentRecord = _first_record(engine)
	_expect_equal(record.grade, GameplayTypes.JudgmentGrade.MISS, "late rotation cannot repair a settled slider")
	_expect_near(engine.life_frequency_hz(), rules.tuning_base_frequency_hz, 0.0001, "frequency resets at the authored field endpoint")


func _run_single_endpoint_at_offset(offset_us: int) -> JudgmentRecord:
	var rules := GameplayRuleSet.new()
	var compiled: CompiledChart = _compile_single_slider(1.2, 1, rules)
	var slider: Dictionary = compiled.tuning_sliders[0]
	var target_us: int = int(slider["end_us"])
	var observed_us: int = target_us + offset_us
	var full_delta: float = float(slider["end_value"]) - float(slider["start_value"])
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	if observed_us <= target_us:
		_apply_input(engine, observed_us, Vector2(full_delta, 0.0), true, false)
	else:
		engine.advance_to(target_us, true, true, false)
		_apply_input(engine, observed_us, Vector2(full_delta, 0.0), true, false)
	return _first_record(engine)


func _compile_single_slider(
		span_hz: float,
		traversal_count: int,
		rules: GameplayRuleSet,
		field_extra_ticks: int = 960
) -> CompiledChart:
	var traversal_ticks: int = 960
	var chart := DomainFixtureFactory.base_chart("finite_arc_%s_%d" % [str(span_hz), traversal_count], 4800)
	var field := TuningFieldRegion.new()
	field.event_id = "field"
	field.tick = 0
	field.duration_ticks = traversal_ticks * traversal_count + field_extra_ticks
	var slider := TuningSliderEvent.new()
	slider.event_id = "life_slider"
	slider.field_id = field.event_id
	slider.affinity = GameplayTypes.Affinity.ZHU
	slider.tick = 0
	slider.traversal_ticks = traversal_ticks
	slider.traversal_count = traversal_count
	slider.start_value = inverse_lerp(rules.tuning_min_frequency_hz, rules.tuning_max_frequency_hz, rules.tuning_base_frequency_hz)
	slider.end_value = slider.start_value + span_hz / (rules.tuning_max_frequency_hz - rules.tuning_min_frequency_hz)
	chart.tuning_fields = [field]
	chart.tuning_sliders = [slider]
	chart.end_tick = field.duration_ticks
	var result: Dictionary = ChartCompiler.compile(chart, rules)
	_expect(bool(result.get("ok", false)), "finite-arc fixture compiles")
	return result.get("compiled") as CompiledChart


func _compile_paired_sliders(span_hz: float, rules: GameplayRuleSet) -> CompiledChart:
	var chart := DomainFixtureFactory.base_chart("paired_endpoint", 4800)
	var field := TuningFieldRegion.new()
	field.event_id = "field"
	field.tick = 0
	field.duration_ticks = 1920
	var start_value: float = inverse_lerp(rules.tuning_min_frequency_hz, rules.tuning_max_frequency_hz, rules.tuning_base_frequency_hz)
	var normalized_span: float = span_hz / (rules.tuning_max_frequency_hz - rules.tuning_min_frequency_hz)
	var life := TuningSliderEvent.new()
	life.event_id = "life_slider"
	life.field_id = field.event_id
	life.group_id = "paired"
	life.affinity = GameplayTypes.Affinity.ZHU
	life.tick = 0
	life.traversal_ticks = 960
	life.start_value = start_value
	life.end_value = start_value + normalized_span
	var death := TuningSliderEvent.new()
	death.event_id = "death_slider"
	death.field_id = field.event_id
	death.group_id = "paired"
	death.affinity = GameplayTypes.Affinity.XUAN
	death.tick = 0
	death.traversal_ticks = 960
	death.start_value = start_value
	death.end_value = start_value - normalized_span
	chart.tuning_fields = [field]
	chart.tuning_sliders = [life, death]
	chart.end_tick = field.duration_ticks
	var result: Dictionary = ChartCompiler.compile(chart, rules)
	_expect(bool(result.get("ok", false)), "paired endpoint fixture compiles")
	return result.get("compiled") as CompiledChart


func _apply_input(engine: TuningEngine, time_us: int, vector: Vector2, life_held: bool, death_held: bool) -> void:
	engine.advance_to(time_us, false, life_held, death_held)
	engine.handle_input(SemanticInputSample.create(
		time_us,
		0,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
		vector
	), life_held, death_held)
	engine.advance_to(time_us, true, life_held, death_held)


func _tune_sample(time_us: int, life_delta: float) -> SemanticInputSample:
	return SemanticInputSample.create(
		time_us,
		0,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
		Vector2(life_delta, 0.0)
	)


func _first_record(engine: TuningEngine) -> JudgmentRecord:
	var records: Array[JudgmentRecord] = engine.drain_judgments()
	return records[0] if not records.is_empty() else null


func _find_component(record: JudgmentRecord, kind: StringName) -> JudgmentComponentRecord:
	if record == null:
		return null
	for component: JudgmentComponentRecord in record.components:
		if component.kind == kind:
			return component
	return null


func _count_components(record: JudgmentRecord, kind: StringName) -> int:
	if record == null:
		return 0
	var count: int = 0
	for component: JudgmentComponentRecord in record.components:
		if component.kind == kind:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual=%.6f expected=%.6f)" % [message, actual, expected])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])
