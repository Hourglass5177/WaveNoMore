extends RefCounted

## 纯玩法内核的回归测试。
## 不创建正式关卡场景，重点验证时间边界、机制状态和 Replay 的确定性。

## 所有纯逻辑用例共享的失败文本，`run()` 结束后一次性返回。
var _failures: PackedStringArray = []
## 已执行断言总数，用于发现某段领域测试意外没有运行。
var _checks: int = 0


func run() -> Dictionary:
	# 测试顺序从基础时间约定逐步走到完整正式谱，失败会统一汇总。
	_test_tempo_map()
	_test_validation_and_compilation()
	_test_tap_boundaries_and_pass_contract()
	_test_chord_damage_group()
	_test_hold_head_and_sustain_contract()
	_test_hold_gap_event_ordering()
	_test_hold_presentation_state_contract()
	_test_tuning_prehold_and_tail_free()
	_test_tuning_endpoint_components()
	_test_tuning_short_endpoint_windows()
	_test_adjacent_tuning_fields_reset_base()
	_test_adjacent_tuning_sliders_validate()
	_test_rotary_tuning_displacement_contract()
	_test_tuning_single_and_grouped_results()
	_test_tuning_ignores_input_outside_field()
	_test_tuning_frame_partition_determinism()
	_test_rapid_alternation_and_debounce()
	_test_stray_contract()
	_test_debug_nonlethal_health()
	_test_perfect_replay_and_frame_determinism()
	_test_replay_serialization_and_preroll()
	_test_replay_hash_guard()
	_test_focus_cancel()
	_test_pause_rearm()
	_test_authored_s05_perfect_replay()
	var passed: bool = _failures.is_empty()
	if passed:
		print("DOMAIN TESTS: %d checks passed." % _checks)
	else:
		printerr("DOMAIN TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - " + failure)
	return {"ok": passed, "checks": _checks, "failures": Array(_failures)}


func _test_tempo_map() -> void:
	var chart := DomainFixtureFactory.base_chart("tempo", 1920)
	var tempo_change := TempoEvent.new()
	tempo_change.tick = 960
	tempo_change.bpm = 60.0
	chart.tempo_events.append(tempo_change)
	var map := TempoMap.from_chart(chart)
	_expect_equal(map.tick_to_us(0), 0, "tick 0 maps to zero")
	_expect_equal(map.tick_to_us(480), 500_000, "120 BPM quarter note is 500 ms")
	_expect_equal(map.tick_to_us(960), 1_000_000, "tempo boundary is exact")
	_expect_equal(map.tick_to_us(1440), 2_000_000, "60 BPM quarter note is 1000 ms")
	_expect(absf(map.us_to_tick(2_000_000) - 1440.0) < 0.001, "microsecond-to-tick round trip")


func _test_validation_and_compilation() -> void:
	var chart := DomainFixtureFactory.all_mechanics_chart()
	var rules := DomainFixtureFactory.rules()
	var report := ChartValidator.validate(chart, rules)
	_expect(not report.has_errors(), "all-mechanics fixture validates: %s" % JSON.stringify(report.to_array()))
	var first: Dictionary = ChartCompiler.compile(chart, rules)
	var second: Dictionary = ChartCompiler.compile(chart.duplicate(true), rules.duplicate(true))
	_expect(bool(first["ok"]), "all-mechanics fixture compiles")
	_expect(bool(second["ok"]), "deep duplicate compiles")
	if first["ok"] and second["ok"]:
		var compiled: CompiledChart = first["compiled"]
		_expect_equal(compiled.theoretical_unit_count, 6, "Tap/chord/Hold/Tuning/Rapid unit count")
		_expect_equal(compiled.content_hash, second["compiled"].content_hash, "compiled chart hash is stable")

	var invalid: SongChart = chart.duplicate(true)
	invalid.note_events[1].event_id = invalid.note_events[0].event_id
	var invalid_report := ChartValidator.validate(invalid, rules)
	_expect(invalid_report.has_errors(), "duplicate stable IDs are rejected")
	var invalid_wave_rules: GameplayRuleSet = rules.duplicate(true)
	invalid_wave_rules.life_wave_origin = invalid_wave_rules.life_note_cue
	_expect(ChartValidator.validate(chart, invalid_wave_rules).has_errors(), "a zero-distance physical wave contact contract is rejected")


func _test_tap_boundaries_and_pass_contract() -> void:
	var chart := DomainFixtureFactory.one_tap_chart()
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(chart, rules)["compiled"]
	var target_us: int = int(compiled.notes[0]["start_us"])

	var perfect_sim := GameplaySimulation.new()
	perfect_sim.configure(compiled, rules)
	perfect_sim.advance_to(target_us + rules.perfect_window_ms * 1000, false)
	perfect_sim.accept_input(SemanticInputSample.create(target_us + rules.perfect_window_ms * 1000, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	perfect_sim.force_finish()
	_expect_equal(perfect_sim.judgments[0].grade, GameplayTypes.JudgmentGrade.PERFECT, "Perfect boundary is inclusive")

	var pass_sim := GameplaySimulation.new()
	pass_sim.configure(compiled, rules)
	var pass_time: int = target_us + rules.pass_window_ms * 1000
	pass_sim.advance_to(pass_time, false)
	pass_sim.accept_input(SemanticInputSample.create(pass_time, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	pass_sim.force_finish()
	var summary := pass_sim.result_summary()
	_expect_equal(pass_sim.judgments[0].grade, GameplayTypes.JudgmentGrade.PASS, "Pass boundary is inclusive")
	_expect(pass_sim.score_engine.raw_score > 0, "PASS awards non-zero score")
	_expect(summary.full_combo, "PASS preserves FC")
	_expect(not summary.all_perfect, "PASS prevents AP")

	var outside_sim := GameplaySimulation.new()
	outside_sim.configure(compiled, rules)
	var outside_time: int = pass_time + 1
	outside_sim.advance_to(outside_time, false)
	outside_sim.accept_input(SemanticInputSample.create(outside_time, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	outside_sim.force_finish()
	_expect_equal(outside_sim.strays.size(), 1, "one microsecond outside PASS is stray")
	_expect_equal(outside_sim.judgments[0].grade, GameplayTypes.JudgmentGrade.MISS, "outside PASS does not consume note")


func _test_chord_damage_group() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.chord_only_chart(), rules)["compiled"]
	var simulation := GameplaySimulation.new()
	simulation.configure(compiled, rules)
	simulation.force_finish()
	_expect_equal(simulation.judgments.size(), 2, "chord keeps two independent judgments")
	_expect_equal(simulation.health_engine.soul_fire, rules.max_soul_fire - rules.miss_damage, "chord damage group deducts soul fire once")


func _test_hold_head_and_sustain_contract() -> void:
	var rules := DomainFixtureFactory.rules()
	var chart := DomainFixtureFactory.hold_only_chart()
	_expect(not chart.note_events[0].tail_requires_release, "new Hold resources default to no release judgment")
	var compiled: CompiledChart = ChartCompiler.compile(chart, rules)["compiled"]
	var hold: Dictionary = compiled.notes[0]

	# 一直按住即可在尾点自动完成；最终记录只含头部和持续，不再含松键分量。
	var held_through_tail := GameplaySimulation.new()
	held_through_tail.configure(compiled, rules)
	held_through_tail.advance_to(int(hold["start_us"]), false)
	held_through_tail.accept_input(SemanticInputSample.create(int(hold["start_us"]), 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	held_through_tail.advance_to(int(hold["end_us"]), true)
	_expect_equal(held_through_tail.judgments.size(), 1, "Hold auto-completes at its tail without a release input")
	_expect_equal(held_through_tail.judgments[0].grade, GameplayTypes.JudgmentGrade.PERFECT, "holding through the tail preserves Perfect")
	_expect(not _has_component(held_through_tail.judgments[0], &"tail"), "Hold result contains no release-timing component")
	_expect(held_through_tail.result_summary().full_combo and held_through_tail.result_summary().all_perfect, "no-release Hold preserves FC and AP")

	# 尾点之后再松键只负责停止载波，不会改写已经完成的 Hold，也不会成为乱按。
	var late_release_us: int = int(hold["end_us"]) + 500_000
	held_through_tail.accept_input(SemanticInputSample.create(late_release_us, 1, GameplayTypes.SemanticInputKind.LIFE_A_RELEASED))
	_expect_equal(held_through_tail.judgments.size(), 1, "late release cannot create or downgrade a second Hold result")
	_expect_equal(held_through_tail.strays.size(), 0, "late Hold release is not a stray press")

	# 旧谱即使仍序列化 true，也必须使用同一套新运行时语义。
	var legacy_chart := DomainFixtureFactory.hold_only_chart()
	legacy_chart.note_events[0].tail_requires_release = true
	var legacy_compiled: CompiledChart = ChartCompiler.compile(legacy_chart, rules)["compiled"]
	_expect(bool(legacy_compiled.notes[0]["tail_requires_release"]), "legacy release flag remains serialized through compilation")
	var legacy_run := GameplaySimulation.new()
	legacy_run.configure(legacy_compiled, rules)
	legacy_run.advance_to(int(legacy_compiled.notes[0]["start_us"]), false)
	legacy_run.accept_input(SemanticInputSample.create(int(legacy_compiled.notes[0]["start_us"]), 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	legacy_run.advance_to(int(legacy_compiled.notes[0]["end_us"]), true)
	_expect_equal(legacy_run.judgments[0].grade, GameplayTypes.JudgmentGrade.PERFECT, "legacy tail_requires_release=true is ignored by runtime")


func _test_hold_gap_event_ordering() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.hold_only_chart(), rules)["compiled"]
	var hold: Dictionary = compiled.notes[0]
	var start_us: int = int(hold["start_us"])
	var end_us: int = int(hold["end_us"])

	# 松键后的 100ms 宽限如果覆盖尾点，即使下一帧很晚才到，仍应按尾点先发生而成功。
	var tail_wins := GameplaySimulation.new()
	tail_wins.configure(compiled, rules)
	tail_wins.advance_to(start_us, false)
	tail_wins.accept_input(SemanticInputSample.create(start_us, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	var near_tail_release_us: int = end_us - 50_000
	tail_wins.accept_input(SemanticInputSample.create(near_tail_release_us, 1, GameplayTypes.SemanticInputKind.LIFE_A_RELEASED))
	tail_wins.advance_to(end_us + 500_000, true)
	_expect_equal(tail_wins.judgments[0].grade, GameplayTypes.JudgmentGrade.PERFECT, "tail reached inside sustain grace succeeds even across one large frame")
	_expect_equal(tail_wins.judgments[0].finalized_at_us, end_us, "successful large-step Hold finalizes at authored tail time")

	# 宽限内重新按下可续持；保留原有轻微断持降为 PASS 的规则。
	var repressed := GameplaySimulation.new()
	repressed.configure(compiled, rules)
	repressed.advance_to(start_us, false)
	repressed.accept_input(SemanticInputSample.create(start_us, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	var short_gap_us: int = start_us + 100_000
	repressed.accept_input(SemanticInputSample.create(short_gap_us, 1, GameplayTypes.SemanticInputKind.LIFE_A_RELEASED))
	repressed.accept_input(SemanticInputSample.create(short_gap_us + 50_000, 2, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	repressed.advance_to(end_us, true)
	_expect_equal(repressed.judgments[0].grade, GameplayTypes.JudgmentGrade.PASS, "re-press inside sustain grace resumes Hold without a Miss")

	# 宽限比尾点先耗尽时，即使一帧跨过两者，也应按真实超时微秒判持续失败。
	var gap_loses := GameplaySimulation.new()
	gap_loses.configure(compiled, rules)
	gap_loses.advance_to(start_us, false)
	gap_loses.accept_input(SemanticInputSample.create(start_us, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	var early_release_us: int = start_us + 100_000
	gap_loses.accept_input(SemanticInputSample.create(early_release_us, 1, GameplayTypes.SemanticInputKind.LIFE_A_RELEASED))
	gap_loses.advance_to(end_us + 500_000, true)
	var expected_failure_us: int = early_release_us + rules.hold_sustain_grace_ms * 1000 + 1
	_expect_equal(gap_loses.judgments[0].grade, GameplayTypes.JudgmentGrade.MISS, "release beyond sustain grace still misses")
	_expect_equal(gap_loses.judgments[0].finalized_at_us, expected_failure_us, "large-step sustain failure uses the real grace-expiry time")


func _test_hold_presentation_state_contract() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.hold_only_chart(), rules)["compiled"]
	var hold: Dictionary = compiled.notes[0]
	var simulation := GameplaySimulation.new()
	simulation.configure(compiled, rules)
	_expect_equal(simulation.snapshot()["active_hold_ids"], PackedStringArray(), "pending Hold is not presented as successfully active")

	var start_us: int = int(hold["start_us"])
	simulation.advance_to(start_us, false)
	simulation.accept_input(SemanticInputSample.create(start_us, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	var held_snapshot: Dictionary = simulation.snapshot()
	_expect((held_snapshot["active_hold_ids"] as PackedStringArray).has("hold_only"), "accepted Hold head exposes its stable active ID")
	_expect((held_snapshot["held_hold_ids"] as PackedStringArray).has("hold_only"), "pressed Hold exposes that its body may be consumed")

	var release_us: int = start_us + 20_000
	simulation.accept_input(SemanticInputSample.create(release_us, 1, GameplayTypes.SemanticInputKind.LIFE_A_RELEASED))
	var released_snapshot: Dictionary = simulation.snapshot()
	_expect((released_snapshot["active_hold_ids"] as PackedStringArray).has("hold_only"), "early release keeps Hold recoverable during sustain grace")
	_expect(not (released_snapshot["held_hold_ids"] as PackedStringArray).has("hold_only"), "early release freezes visual body consumption")

	simulation.accept_input(SemanticInputSample.create(release_us + 20_000, 2, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	_expect((simulation.snapshot()["held_hold_ids"] as PackedStringArray).has("hold_only"), "re-press inside grace resumes Hold body consumption")


func _test_tuning_prehold_and_tail_free() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.tuning_only_chart(), rules)["compiled"]
	var replay := _build_preheld_tail_free_tuning_replay(compiled, rules)
	var run_result: Dictionary = ReplayRunner.run(compiled, rules, replay, 16_667)
	var record := _find_tuning_record(run_result)

	_expect(bool(run_result.get("ok", false)), "pre-held tuning Replay executes")
	_expect(record != null, "pre-held bells produce one tuning judgment without key-up")
	if record == null:
		return
	_expect_equal(record.grade, GameplayTypes.JudgmentGrade.PERFECT, "bells held before the field join the slider without another head press")
	_expect(not _has_component(record, &"head") and not _has_component(record, &"tail"), "tuning grade uses traversal endpoints, never press or release timing")
	_expect_equal(_count_components(record, &"life_endpoint"), 2, "pre-held life bell grades both traversal endpoints")
	_expect_equal(_count_components(record, &"death_endpoint"), 2, "pre-held death bell grades both traversal endpoints")


func _test_tuning_endpoint_components() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.tuning_only_chart(), rules)["compiled"]
	var run_result: Dictionary = ReplayRunner.run(compiled, rules, ReplayRunner.build_perfect_replay(compiled, rules), 16_667)
	var record := _find_tuning_record(run_result)
	_expect(record != null, "perfect slider Replay produces a tuning record")
	if record == null:
		return

	_expect_equal(_count_components(record, &"life_endpoint"), 2, "life round trip exposes one timing component per traversal")
	_expect_equal(_count_components(record, &"death_endpoint"), 2, "death round trip exposes one timing component per traversal")
	_expect(not record.metadata["sides"]["life"].has("coverage"), "obsolete continuous coverage is absent from life metadata")
	_expect(not record.metadata["sides"]["death"].has("coverage"), "obsolete continuous coverage is absent from death metadata")


func _test_tuning_short_endpoint_windows() -> void:
	var rules := DomainFixtureFactory.rules()
	# 很短且不是旧采样间隔整数倍的滑条，也只按真实谱面尾点结算。
	var uneven_record := _run_unheld_short_tuning(31, rules)
	_expect(uneven_record != null, "non-divisible slider finalizes at its authored endpoint")
	if uneven_record != null:
		_expect_equal(_count_components(uneven_record, &"life_endpoint"), 1, "31-tick life slider has one traversal endpoint")
		_expect_equal(_count_components(uneven_record, &"death_endpoint"), 1, "31-tick death slider has one traversal endpoint")

	# 短于旧采样步长也不会丢失尾点或无法生成成组判定。
	var short_record := _run_unheld_short_tuning(17, rules)
	_expect(short_record != null, "sub-step slider still produces a grouped endpoint judgment")
	if short_record != null:
		_expect_equal(short_record.grade, GameplayTypes.JudgmentGrade.MISS, "unplayed short slider misses normally")


func _run_unheld_short_tuning(duration_ticks: int, rules: GameplayRuleSet) -> JudgmentRecord:
	var chart := DomainFixtureFactory.tuning_only_chart().duplicate(true) as SongChart
	chart.chart_id = "endpoint_sampling_%d" % duration_ticks
	chart.su_manifestations.clear()
	var field: TuningFieldRegion = chart.tuning_fields[0]
	field.duration_ticks = duration_ticks
	for slider: TuningSliderEvent in chart.tuning_sliders:
		slider.traversal_ticks = duration_ticks
		slider.traversal_count = 1
	chart.end_tick = field.tick + duration_ticks
	var compile_result: Dictionary = ChartCompiler.compile(chart, rules)
	_expect(bool(compile_result.get("ok", false)), "%d-tick endpoint fixture compiles" % duration_ticks)
	if not bool(compile_result.get("ok", false)):
		return null
	var compiled := compile_result["compiled"] as CompiledChart
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	engine.advance_to(
		int(compiled.tuning_sliders[0]["end_us"]),
		true,
		false,
		false
	)
	var records: Array[JudgmentRecord] = engine.drain_judgments()
	return records[0] if not records.is_empty() else null


func _test_adjacent_tuning_fields_reset_base() -> void:
	var chart := DomainFixtureFactory.base_chart("adjacent_tuning_fields", 960)
	var first := TuningFieldRegion.new()
	first.event_id = "field_before_boundary"
	first.tick = 0
	first.duration_ticks = 480
	var second := TuningFieldRegion.new()
	second.event_id = "field_after_boundary"
	second.tick = 480
	second.duration_ticks = 480
	chart.tuning_fields = [first, second]
	var rules := DomainFixtureFactory.rules()
	var compile_result: Dictionary = ChartCompiler.compile(chart, rules)
	_expect(bool(compile_result.get("ok", false)), "touching tuning fields remain a legal authored boundary")
	if not bool(compile_result.get("ok", false)):
		return
	var compiled := compile_result["compiled"] as CompiledChart
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	engine.advance_to(0, true, true, true)
	engine.handle_input(SemanticInputSample.create(
		0,
		0,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
		Vector2(0.25, -0.20)
	), true, true)
	_expect(not is_equal_approx(engine.life_tuning_value(), engine.death_tuning_value()), "first field may leave the two bells at different frequencies")

	var boundary_us: int = compiled.tempo_map.tick_to_us(480)
	engine.advance_to(boundary_us, true, true, true)
	var base_value: float = inverse_lerp(
		rules.tuning_min_frequency_hz,
		rules.tuning_max_frequency_hz,
		rules.tuning_base_frequency_hz
	)
	_expect(engine.field_active(), "second field is already active on the shared boundary tick")
	_expect_equal(engine.active_field_id(), "field_after_boundary", "old field exits before the adjacent field enters")
	_expect_near(engine.life_tuning_value(), base_value, 0.000001, "adjacent field resets life frequency to base on its exact first tick")
	_expect_near(engine.death_tuning_value(), base_value, 0.000001, "adjacent field resets death frequency to base on its exact first tick")


func _test_adjacent_tuning_sliders_validate() -> void:
	# 连续滑条链允许上一条尾点与下一条起点处于同一个 tick；两者没有正长度交叠。
	var chart := DomainFixtureFactory.base_chart("adjacent_tuning_sliders", 960)
	var field := TuningFieldRegion.new()
	field.event_id = "adjacent_slider_field"
	field.tick = 0
	field.duration_ticks = 960
	chart.tuning_fields = [field]

	var first := TuningSliderEvent.new()
	first.event_id = "adjacent_slider_first"
	first.field_id = field.event_id
	first.affinity = GameplayTypes.Affinity.ZHU
	first.tick = 0
	first.traversal_ticks = 480
	first.start_value = 0.5
	first.end_value = 0.8

	var second := TuningSliderEvent.new()
	second.event_id = "adjacent_slider_second"
	second.field_id = field.event_id
	second.affinity = GameplayTypes.Affinity.ZHU
	second.tick = 480
	second.traversal_ticks = 480
	second.start_value = 0.8
	second.end_value = 0.4
	chart.tuning_sliders = [first, second]

	var compile_result: Dictionary = ChartCompiler.compile(chart, DomainFixtureFactory.rules())
	_expect(bool(compile_result.get("ok", false)), "touching tuning sliders compile as adjacent half-open intervals")


func _test_rotary_tuning_displacement_contract() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.tuning_only_chart(), rules)["compiled"]
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	var field_start_us: int = int(compiled.tuning_fields[0]["start_us"])
	engine.advance_to(field_start_us, true, true, true)
	var base_value: float = engine.life_tuning_value()

	# 固定推杆不再以 delta 积分；只推进歌曲时间时，两口钟必须保持原频率。
	engine.advance_to(field_start_us + 100_000, true, true, true)
	_expect_near(engine.life_tuning_value(), base_value, 0.000001, "time passing without rotary displacement never moves the life frequency")
	_expect_near(engine.death_tuning_value(), base_value, 0.000001, "time passing without rotary displacement never moves the death frequency")

	engine.handle_input(SemanticInputSample.create(
		field_start_us + 100_000,
		0,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
		Vector2(0.10, -0.04)
	), true, true)
	_expect_near(engine.life_tuning_value(), base_value + 0.10, 0.0001, "clockwise life displacement raises only by the submitted amount")
	_expect_near(engine.death_tuning_value(), base_value - 0.04, 0.0001, "death displacement is applied one-to-one without catch-up gain")
	engine.advance_to(field_start_us + 200_000, true, true, true)
	_expect_near(engine.life_tuning_value(), base_value + 0.10, 0.0001, "submitted displacement is instantaneous rather than a persistent rate")

	var opening_snapshots: Array[Dictionary] = engine.active_slider_snapshots()
	_expect_equal(int(opening_snapshots[0]["required_rotation_sign"]), 1, "ascending life traversal requests clockwise rotation")
	_expect_equal(int(opening_snapshots[1]["required_rotation_sign"]), 1, "descending death traversal follows the lower arc clockwise")
	var reversal_us: int = compiled.tempo_map.tick_to_us(int(compiled.tuning_sliders[0]["tick"]) + int(compiled.tuning_sliders[0]["traversal_ticks"]))
	engine.advance_to(reversal_us, true, true, true)
	var reversal_snapshots: Array[Dictionary] = engine.active_slider_snapshots()
	_expect_equal(int(reversal_snapshots[0]["required_rotation_sign"]), -1, "life round trip reverses its requested rotation at the endpoint")
	_expect_equal(int(reversal_snapshots[1]["required_rotation_sign"]), -1, "death round trip reverses along the same lower arc at the endpoint")


func _test_tuning_single_and_grouped_results() -> void:
	var rules := DomainFixtureFactory.rules()
	var paired: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.tuning_only_chart(), rules)["compiled"]

	# 同组两侧分别记录端点，但只形成一条结算记录。
	var missing_death := ReplayRunner.build_perfect_replay(paired, rules)
	var life_only_inputs: Array[SemanticInputSample] = []
	for sample: SemanticInputSample in missing_death.inputs:
		if sample.kind != GameplayTypes.SemanticInputKind.DEATH_A_PRESSED and sample.kind != GameplayTypes.SemanticInputKind.DEATH_A_RELEASED:
			life_only_inputs.append(sample)
	missing_death.inputs = life_only_inputs
	var paired_result: Dictionary = ReplayRunner.run(paired, rules, missing_death, 16_667)
	var paired_record := _find_tuning_record(paired_result)
	_expect_equal(_count_tuning_records(paired_result), 1, "grouped life/death sliders settle as one record")
	_expect_equal(paired.theoretical_unit_count, 1, "grouped life/death sliders count as one theoretical unit")
	if paired_record != null:
		var life_component := _find_component(paired_record, &"life_endpoint")
		var death_component := _find_component(paired_record, &"death_endpoint")
		_expect(life_component != null and life_component.grade == GameplayTypes.JudgmentGrade.PERFECT, "life side may remain Perfect independently")
		_expect(death_component != null and death_component.grade == GameplayTypes.JudgmentGrade.MISS, "unheld death side records its own Miss")
		_expect_equal(paired_record.grade, GameplayTypes.JudgmentGrade.MISS, "group grade takes the worse side")

	# 单侧滑条仍是一枚合法、可独立结算的调频单位。
	var single_chart: SongChart = DomainFixtureFactory.tuning_only_chart().duplicate(true)
	single_chart.chart_id = "tuning_single_life"
	var life_slider: TuningSliderEvent = single_chart.tuning_sliders[0]
	life_slider.group_id = ""
	single_chart.tuning_sliders.clear()
	single_chart.tuning_sliders.append(life_slider)
	single_chart.su_manifestations.clear()
	var single_compile: Dictionary = ChartCompiler.compile(single_chart, rules)
	_expect(bool(single_compile.get("ok", false)), "single-side tuning chart compiles")
	if not bool(single_compile.get("ok", false)):
		return
	var single: CompiledChart = single_compile["compiled"]
	var single_result: Dictionary = ReplayRunner.run(single, rules, ReplayRunner.build_perfect_replay(single, rules), 16_667)
	var single_record := _find_tuning_record(single_result)
	_expect_equal(_count_tuning_records(single_result), 1, "single-side slider produces exactly one record")
	_expect_equal(single.theoretical_unit_count, 1, "single-side slider contributes one theoretical unit")
	if single_record != null:
		_expect_equal(single_record.grade, GameplayTypes.JudgmentGrade.PERFECT, "single-side perfect tracking is graded normally")
		_expect_equal(single_record.components.size(), 2, "single-side round trip contains its two endpoint components")


func _test_tuning_ignores_input_outside_field() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.tuning_only_chart(), rules)["compiled"]
	var engine := TuningEngine.new()
	engine.configure(compiled, rules)
	var base_values := Vector2(engine.life_tuning_value(), engine.death_tuning_value())
	var before_field_us: int = int(compiled.tuning_fields[0]["start_us"]) - 100_000
	engine.advance_to(before_field_us, true, true, true)
	var displaced: bool = engine.handle_input(SemanticInputSample.create(
		before_field_us,
		0,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
		Vector2(1.0, -1.0)
	), true, true)
	engine.advance_to(int(compiled.tuning_fields[0]["start_us"]) - 1, true, true, true)

	_expect(not displaced, "tuning displacement is not consumed outside a TuningFieldRegion")
	_expect_equal(
		Vector2(engine.life_tuning_value(), engine.death_tuning_value()),
		base_values,
		"ordinary song sections keep both bells at the base frequency"
	)
	var simulation := GameplaySimulation.new()
	simulation.configure(compiled, rules)
	var owner: int = simulation.accept_input(SemanticInputSample.create(
		before_field_us,
		0,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
		Vector2(0.25, 0.0)
	))
	_expect_equal(owner, GameplayTypes.InputOwner.NONE, "rejected out-of-field tuning input does not claim TUNING ownership")
	_expect_equal(simulation.snapshot()["input_owner"], GameplayTypes.InputOwner.NONE, "debug snapshot does not retain a false TUNING owner")


func _test_tuning_frame_partition_determinism() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.tuning_only_chart(), rules)["compiled"]
	var replay := ReplayRunner.build_perfect_replay(compiled, rules)
	var at_30: Dictionary = ReplayRunner.run(compiled, rules, replay, 33_333)
	var at_120: Dictionary = ReplayRunner.run(compiled, rules, replay, 8_333)
	var irregular: Dictionary = ReplayRunner.run_with_frame_steps(compiled, rules, replay, PackedInt64Array([3_000, 41_000, 7_777, 19_999]))

	_expect(bool(at_30.get("ok", false)) and bool(at_120.get("ok", false)) and bool(irregular.get("ok", false)), "tuning Replay executes at regular and irregular frame steps")
	_expect_equal(at_30.get("digest", ""), at_120.get("digest", ""), "tuning result is identical at 30 and 120 FPS")
	_expect_equal(at_30.get("digest", ""), irregular.get("digest", ""), "tuning result is independent of irregular frame partitioning")


func _build_preheld_tail_free_tuning_replay(compiled: CompiledChart, rules: GameplayRuleSet) -> ReplayData:
	var replay := ReplayRunner.build_perfect_replay(compiled, rules)
	var start_us: int = int(compiled.tuning_fields[0]["start_us"])
	var retained: Array[SemanticInputSample] = [
		SemanticInputSample.create(start_us - 100_000, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED),
		SemanticInputSample.create(start_us - 100_000, 1, GameplayTypes.SemanticInputKind.DEATH_A_PRESSED),
	]
	for sample: SemanticInputSample in replay.inputs:
		if sample.kind == GameplayTypes.SemanticInputKind.TUNING_DISPLACED:
			retained.append(sample)
	replay.inputs = retained
	return replay


func _find_tuning_record(run_result: Dictionary) -> JudgmentRecord:
	for raw_record: Variant in run_result.get("judgments", []):
		var record := raw_record as JudgmentRecord
		if record != null and record.unit_kind == &"tuning":
			return record
	return null


func _count_tuning_records(run_result: Dictionary) -> int:
	var count: int = 0
	for raw_record: Variant in run_result.get("judgments", []):
		var record := raw_record as JudgmentRecord
		if record != null and record.unit_kind == &"tuning":
			count += 1
	return count


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


func _has_component(record: JudgmentRecord, kind: StringName) -> bool:
	return _find_component(record, kind) != null


func _test_rapid_alternation_and_debounce() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.rapid_only_chart(), rules)["compiled"]
	var region: Dictionary = compiled.rapid_regions[0]
	var valid := GameplaySimulation.new()
	valid.configure(compiled, rules)
	valid.advance_to(int(region["start_us"]), false)
	valid.accept_input(SemanticInputSample.create(int(region["start_us"]), 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	valid.accept_input(SemanticInputSample.create(int(region["start_us"]) + int(region["debounce_us"]), 1, GameplayTypes.SemanticInputKind.DEATH_A_PRESSED))
	var valid_waves: Array[Dictionary] = valid.drain_wave_launches()
	valid.advance_to(int(region["end_us"]) + 1, true)
	_expect_equal(valid.judgments[0].grade, GameplayTypes.JudgmentGrade.PERFECT, "rapid debounce boundary is inclusive and opposite side counts")
	_expect(valid_waves.size() == 2 and bool(valid_waves[0]["valid"]) and bool(valid_waves[1]["valid"]), "counted rapid strikes emit qualified coloured waves")
	_expect(valid_waves.size() == 2 and int(valid_waves[0]["owner"]) == GameplayTypes.InputOwner.RAPID and int(valid_waves[1]["owner"]) == GameplayTypes.InputOwner.RAPID, "rapid physical waves retain their semantic owner for causal presentation")

	var invalid := GameplaySimulation.new()
	invalid.configure(compiled, rules)
	invalid.advance_to(int(region["start_us"]), false)
	invalid.accept_input(SemanticInputSample.create(int(region["start_us"]), 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	invalid.accept_input(SemanticInputSample.create(int(region["start_us"]) + int(region["debounce_us"]) * 2, 1, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	var invalid_waves: Array[Dictionary] = invalid.drain_wave_launches()
	invalid.advance_to(int(region["end_us"]) + 1, true)
	_expect_equal(invalid.judgments[0].grade, GameplayTypes.JudgmentGrade.MISS, "same-side rapid strike is consumed but not counted")
	_expect_equal(int(invalid.judgments[0].metadata["invalid_strikes"]), 1, "invalid rapid strike is observable")
	_expect(invalid_waves.size() == 2 and bool(invalid_waves[0]["valid"]) and not bool(invalid_waves[1]["valid"]), "rejected same-side rapid mash still emits a physical gray wave")


func _test_stray_contract() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.one_tap_chart(), rules)["compiled"]
	var simulation := GameplaySimulation.new()
	simulation.configure(compiled, rules)
	var before_health: int = simulation.health_engine.soul_fire
	simulation.accept_input(SemanticInputSample.create(10_000, 0, GameplayTypes.SemanticInputKind.DEATH_A_PRESSED))
	var stray_waves: Array[Dictionary] = simulation.drain_wave_launches()
	_expect_equal(simulation.strays.size(), 1, "empty press is recorded")
	_expect_equal(simulation.health_engine.soul_fire, before_health, "empty press does not damage soul fire")
	_expect_equal(simulation.score_engine.combo, 0, "empty press breaks combo when configured")
	_expect(stray_waves.size() == 1 and not bool(stray_waves[0]["valid"]), "empty press has a real but unqualified gray wave")


func _test_perfect_replay_and_frame_determinism() -> void:
	var chart := DomainFixtureFactory.all_mechanics_chart()
	var rules := DomainFixtureFactory.rules()
	var compile_result: Dictionary = ChartCompiler.compile(chart, rules)
	_expect(bool(compile_result["ok"]), "all mechanics compile before Replay")
	if not compile_result["ok"]:
		return
	var compiled: CompiledChart = compile_result["compiled"]
	var replay := ReplayRunner.build_perfect_replay(compiled, rules)
	# 用近似 30、60、120 FPS 和不规则帧的推进步长运行同一 Replay；
	# 判定只看歌曲时间，不能随推进粒度改变。
	var at_30: Dictionary = ReplayRunner.run(compiled, rules, replay, 33_333)
	var at_60: Dictionary = ReplayRunner.run(compiled, rules, replay, 16_667)
	var at_120: Dictionary = ReplayRunner.run(compiled, rules, replay, 8_333)
	var irregular: Dictionary = ReplayRunner.run_with_frame_steps(compiled, rules, replay, PackedInt64Array([7_000, 11_000, 23_000]))
	_expect(bool(at_30["ok"]) and bool(at_60["ok"]) and bool(at_120["ok"]) and bool(irregular["ok"]), "Replay runs at all frame steps")
	if not at_30["ok"]:
		return
	_expect_equal(at_30["digest"], at_60["digest"], "30 and 60 FPS Replay digest match")
	_expect_equal(at_30["digest"], at_120["digest"], "30 and 120 FPS Replay digest match")
	_expect_equal(at_30["digest"], irregular["digest"], "irregular frame Replay digest matches")
	var summary: ResultSummary = at_30["summary"]
	_expect(summary.cleared, "Perfect Replay clears chart")
	_expect(summary.full_combo, "Perfect Replay is FC")
	_expect(summary.all_perfect, "Perfect Replay is AP")
	_expect_equal(summary.judgment_count, compiled.theoretical_unit_count, "Replay judges every gameplay unit")


func _test_replay_hash_guard() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.one_tap_chart(), rules)["compiled"]
	var replay := ReplayRunner.build_perfect_replay(compiled, rules)
	replay.chart_hash = "tampered"
	var run_result: Dictionary = ReplayRunner.run(compiled, rules, replay)
	_expect(not bool(run_result["ok"]), "Replay rejects chart hash mismatch")


func _test_replay_serialization_and_preroll() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.all_mechanics_chart(), rules)["compiled"]
	var replay := ReplayRunner.build_perfect_replay(compiled, rules)
	var before: Dictionary = ReplayRunner.run(compiled, rules, replay, 16_667)
	var restored := ReplayData.from_dictionary(replay.to_dictionary())
	var after: Dictionary = ReplayRunner.run(compiled, rules, restored, 16_667)
	_expect_equal(before["digest"], after["digest"], "Replay save/reload preserves quantized input digest")
	_expect_equal(replay.canonical_input_hash(), restored.canonical_input_hash(), "Replay input hash survives serialization")

	var preroll_chart := DomainFixtureFactory.one_tap_chart()
	preroll_chart.chart_id = "preroll"
	preroll_chart.note_events[0].tick = -240
	var preroll_compile: Dictionary = ChartCompiler.compile(preroll_chart, rules)
	_expect(bool(preroll_compile["ok"]), "negative preroll note compiles with a warning")
	if preroll_compile["ok"]:
		var preroll_replay := ReplayRunner.build_perfect_replay(preroll_compile["compiled"], rules)
		var preroll_run: Dictionary = ReplayRunner.run(preroll_compile["compiled"], rules, preroll_replay, 33_333)
		_expect(preroll_run["summary"].all_perfect, "Replay processes negative preroll input deterministically")


func _test_focus_cancel() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.hold_only_chart(), rules)["compiled"]
	var hold: Dictionary = compiled.notes[0]
	var simulation := GameplaySimulation.new()
	simulation.configure(compiled, rules)
	simulation.advance_to(int(hold["start_us"]), false)
	simulation.accept_input(SemanticInputSample.create(int(hold["start_us"]), 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	simulation.accept_input(SemanticInputSample.create(int(hold["start_us"]) + 10_000, 1, GameplayTypes.SemanticInputKind.FOCUS_CANCELLED))
	_expect_equal(simulation.judgments.size(), 1, "focus cancel finalizes active Hold")
	if not simulation.judgments.is_empty():
		_expect_equal(simulation.judgments[0].grade, GameplayTypes.JudgmentGrade.MISS, "focus cancel produces MISS")


func _test_debug_nonlethal_health() -> void:
	var rules := DomainFixtureFactory.rules()
	rules.max_soul_fire = 20
	rules.miss_damage = 15
	var engine := HealthEngine.new()
	engine.configure(rules, true)
	for index: int in range(3):
		var record := JudgmentRecord.new()
		record.unit_id = "debug_miss_%d" % index
		record.damage_group_id = record.unit_id
		record.grade = GameplayTypes.JudgmentGrade.MISS
		engine.apply_judgment(record)
	_expect_equal(engine.soul_fire, -25, "debug nonlethal health preserves damage below zero")
	_expect(not engine.failed, "debug nonlethal health never enters failed state")

	engine.reset()
	_expect_equal(engine.soul_fire, 20, "debug nonlethal reset restores maximum soul fire")
	_expect(not engine.failed, "debug nonlethal reset remains playable")

	var normal_engine := HealthEngine.new()
	normal_engine.configure(rules)
	for index: int in range(3):
		var record := JudgmentRecord.new()
		record.unit_id = "normal_miss_%d" % index
		record.damage_group_id = record.unit_id
		record.grade = GameplayTypes.JudgmentGrade.MISS
		normal_engine.apply_judgment(record)
	_expect_equal(normal_engine.soul_fire, 0, "normal health still clamps at zero")
	_expect(normal_engine.failed, "normal health still enters failed state")


func _test_pause_rearm() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.hold_only_chart(), rules)["compiled"]
	var hold: Dictionary = compiled.notes[0]
	var simulation := GameplaySimulation.new()
	simulation.configure(compiled, rules)
	simulation.advance_to(int(hold["start_us"]), false)
	simulation.accept_input(SemanticInputSample.create(int(hold["start_us"]), 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	var requirements: Dictionary = simulation.begin_pause_rearm()
	_expect(bool(requirements["life_required"]), "pause reports active life Hold rearm requirement")
	simulation.apply_resume_rearm({"life_held": true, "death_held": false})
	simulation.advance_to(int(hold["end_us"]), false)
	simulation.accept_input(SemanticInputSample.create(int(hold["end_us"]), 1, GameplayTypes.SemanticInputKind.LIFE_A_RELEASED))
	simulation.advance_to(int(hold["end_us"]), true)
	_expect_equal(simulation.judgments[0].grade, GameplayTypes.JudgmentGrade.PERFECT, "pause rearm preserves Hold without a second head judgment")


func _test_authored_s05_perfect_replay() -> void:
	var stage := load("res://content/stages/s05/stage_definition.tres") as StageDefinition
	_expect(stage != null, "authored s05 StageDefinition loads")
	if stage == null:
		return
	_expect(stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "authored s05 lazy composition resolves")
	if not stage.dependencies_resolved():
		return
	var authored_duration_us := maxi(0, int(round((stage.song.fallback_duration_sec - stage.song.first_beat_offset_sec) * 1_000_000.0)))
	var compile_result: Dictionary = ChartCompiler.compile(stage.chart, stage.rule_set, authored_duration_us)
	_expect(bool(compile_result["ok"]), "authored s05 passes shared compiler/validator")
	if not compile_result["ok"]:
		return
	var compiled: CompiledChart = compile_result["compiled"]
	var replay := ReplayRunner.build_perfect_replay(compiled, stage.rule_set)
	var run_result: Dictionary = ReplayRunner.run_with_frame_steps(compiled, stage.rule_set, replay, PackedInt64Array([7_000, 11_000, 23_000]))
	_expect(bool(run_result["ok"]), "authored s05 Perfect Replay executes")
	_expect(run_result["summary"].all_perfect, "authored s05 can obtain AP through real state machines")


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual=%f expected=%f)" % [message, actual, expected])


func _report_has_code(report: ValidationReport, code: StringName) -> bool:
	if report == null:
		return false
	for issue: ValidationIssue in report.issues:
		if issue.code == code:
			return true
	return false
