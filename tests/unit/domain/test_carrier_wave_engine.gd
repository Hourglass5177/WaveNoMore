extends SceneTree

## 持续载波的纯逻辑回归：证明“单钟可成波、双钟独立、改频不改旧波”。

var _checks: int = 0
var _failures: PackedStringArray = []

const TEST_BASE_FREQUENCY_HZ: float = 3.0
const TEST_LOW_FREQUENCY_HZ: float = 1.0
const TEST_HIGH_FREQUENCY_HZ: float = 7.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_single_bell_emits_without_tuning_target()
	_test_frequency_change_only_affects_future_emissions()
	_test_repeated_frequency_changes_preserve_phase()
	_test_two_sources_are_independent()
	_test_dual_hold_remains_continuous_for_ten_seconds()
	_test_frame_partition_is_deterministic()
	_test_exclusive_advance_respects_boundary()
	_test_pause_resume_does_not_supplement_wave()
	_test_intersection_selection_is_deterministic()
	_test_authored_su_manifestations_are_deterministic()
	if _failures.is_empty():
		print("CARRIER WAVE TESTS: %d checks passed." % _checks)
		quit(0)
		return
	for failure: String in _failures:
		printerr("  FAIL " + failure)
	quit(1)


func _test_single_bell_emits_without_tuning_target() -> void:
	var engine := _engine()
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	engine.advance_to(1_000_000)
	var history: Array[Dictionary] = engine.history_copy()
	_expect(history.size() >= 4, "单独按住生钟一秒也会持续成波")
	for wave: Dictionary in history:
		_expect_equal(int(wave["affinity"]), GameplayTypes.Affinity.ZHU, "单钟波不会伪造另一侧波源")


func _test_frequency_change_only_affects_future_emissions() -> void:
	var engine := _engine()
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	engine.advance_to(300_000)
	var old_wave: Dictionary = engine.history_copy()[0]
	engine.set_frequency(GameplayTypes.Affinity.ZHU, TEST_HIGH_FREQUENCY_HZ, 300_000)
	engine.advance_to(800_000)
	var fronts: Array[Dictionary] = engine.visible_wavefronts(800_000)
	var matched: Dictionary = {}
	for front: Dictionary in fronts:
		if str(front["wave_id"]) == str(old_wave["wave_id"]):
			matched = front
			break
	_expect(not matched.is_empty(), "改频后先前波前仍然存在")
	_expect_near(float(matched.get("radius_px", 0.0)), 1920.0, 0.01, "旧波仍按固定波速传播")
	_expect_near(float(matched.get("frequency_hz", 0.0)), TEST_BASE_FREQUENCY_HZ, 0.001, "旧波保留发射时的频率元数据")


func _test_repeated_frequency_changes_preserve_phase() -> void:
	var engine := _engine()
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	var base_period: int = roundi(1_000_000.0 / TEST_BASE_FREQUENCY_HZ)
	var high_period: int = roundi(1_000_000.0 / TEST_HIGH_FREQUENCY_HZ)
	var low_period: int = roundi(1_000_000.0 / TEST_LOW_FREQUENCY_HZ)
	engine.set_frequency(GameplayTypes.Affinity.ZHU, TEST_HIGH_FREQUENCY_HZ, 100_000)
	var after_first_change: int = 100_000 + roundi(
		float(base_period - 100_000) / float(base_period) * float(high_period)
	)
	engine.set_frequency(GameplayTypes.Affinity.ZHU, TEST_LOW_FREQUENCY_HZ, 150_000)
	var expected_next: int = 150_000 + roundi(
		float(after_first_change - 150_000) / float(high_period) * float(low_period)
	)
	engine.advance_to(expected_next, false)
	_expect_equal(engine.emission_count(), 1, "连续两次改频后不会提前发出下一圈")
	engine.advance_to(expected_next, true)
	_expect_equal(engine.emission_count(), 2, "连续两次改频会沿用上一次换算后的剩余相位")


func _test_two_sources_are_independent() -> void:
	var engine := _engine()
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	engine.set_held(GameplayTypes.Affinity.XUAN, true, 0)
	engine.set_frequency(GameplayTypes.Affinity.ZHU, TEST_HIGH_FREQUENCY_HZ, 100_000)
	engine.set_frequency(GameplayTypes.Affinity.XUAN, TEST_LOW_FREQUENCY_HZ, 100_000)
	engine.advance_to(1_000_000)
	_expect_near(engine.frequency_hz(GameplayTypes.Affinity.ZHU), TEST_HIGH_FREQUENCY_HZ, 0.001, "生钟频率独立保存")
	_expect_near(engine.frequency_hz(GameplayTypes.Affinity.XUAN), TEST_LOW_FREQUENCY_HZ, 0.001, "死钟频率独立保存")
	var life_count: int = 0
	var death_count: int = 0
	for wave: Dictionary in engine.history_copy():
		if int(wave["affinity"]) == GameplayTypes.Affinity.ZHU:
			life_count += 1
		else:
			death_count += 1
	_expect(life_count > death_count, "高频一侧在同段时间内产生更多波前")


func _test_dual_hold_remains_continuous_for_ten_seconds() -> void:
	var engine := _engine()
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	engine.set_held(GameplayTypes.Affinity.XUAN, true, 0)
	engine.advance_to(10_000_000)
	var period_us: int = roundi(1_000_000.0 / TEST_BASE_FREQUENCY_HZ)
	for affinity: int in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		var launch_times := PackedInt64Array()
		for wave: Dictionary in engine.history_copy():
			if int(wave["affinity"]) == affinity:
				launch_times.append(int(wave["launch_us"]))
		_expect(launch_times.size() >= 30, "双钟持续按住十秒时两侧都保持稳定发波")
		for index: int in range(1, launch_times.size()):
			_expect_equal(launch_times[index] - launch_times[index - 1], period_us, "十秒载波序列中不存在非物理断流")


func _test_frame_partition_is_deterministic() -> void:
	var one_step := _engine()
	var many_steps := _engine()
	for engine: CarrierWaveEngine in [one_step, many_steps]:
		engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
		engine.set_held(GameplayTypes.Affinity.XUAN, true, 0)
	one_step.advance_to(1_200_000)
	for time_us: int in [16_667, 50_000, 166_667, 333_333, 700_000, 1_200_000]:
		many_steps.advance_to(time_us)
	_expect_equal(_launch_times(one_step), _launch_times(many_steps), "不同帧步得到完全相同的载波发射序列")


func _test_exclusive_advance_respects_boundary() -> void:
	var engine := _engine()
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	var base_period: int = roundi(1_000_000.0 / TEST_BASE_FREQUENCY_HZ)
	engine.advance_to(base_period, false)
	_expect_equal(engine.emission_count(), 1, "排他推进不会提前生成恰好落在边界上的波")
	engine.advance_to(base_period, true)
	_expect_equal(engine.emission_count(), 2, "同一边界随后包含推进时会生成该圈")

	var retuned := _engine()
	retuned.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	retuned.set_frequency(GameplayTypes.Affinity.ZHU, TEST_HIGH_FREQUENCY_HZ, base_period)
	_expect_equal(retuned.emission_count(), 1, "边界改频会先改状态，不会抢先补发旧频率波")
	retuned.advance_to(base_period, true)
	_expect_equal(retuned.emission_count(), 2, "边界改频后仍会在原相位发出该圈")
	_expect_near(
		float(retuned.history_copy()[-1]["frequency_hz"]),
		TEST_HIGH_FREQUENCY_HZ,
		0.001,
		"同刻发射使用已经生效的新频率"
	)

	var released := _engine()
	released.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	released.set_held(GameplayTypes.Affinity.ZHU, false, base_period)
	released.advance_to(base_period, true)
	_expect_equal(released.emission_count(), 1, "同刻松钟会取消尚未发出的边界载波")


func _test_pause_resume_does_not_supplement_wave() -> void:
	var engine := _engine()
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	engine.advance_to(100_000)
	var count_before_pause: int = engine.emission_count()
	engine.begin_pause(100_000)
	engine.resume_after_pause(true, false, 100_000)
	_expect_equal(engine.emission_count(), count_before_pause, "暂停恢复不会在恢复点凭空补发载波")
	var base_period: int = roundi(1_000_000.0 / TEST_BASE_FREQUENCY_HZ)
	engine.advance_to(base_period - 1)
	_expect_equal(engine.emission_count(), count_before_pause, "恢复后会保留暂停前尚未走完的发波周期")
	engine.advance_to(base_period)
	_expect_equal(engine.emission_count(), count_before_pause + 1, "剩余周期走完后才正常发出下一圈")


func _test_intersection_selection_is_deterministic() -> void:
	var engine := _engine()
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	engine.set_held(GameplayTypes.Affinity.XUAN, true, 0)
	engine.advance_to(1_000_000)
	var region := Rect2(Vector2(0.05, 0.05), Vector2(0.9, 0.9))
	var first: Array[Vector2] = engine.find_constructive_intersections(1_000_000, region, 3)
	var second: Array[Vector2] = engine.find_constructive_intersections(1_000_000, region, 3)
	_expect_equal(first, second, "同一波列和区域始终选出相同素音坐标")


func _test_authored_su_manifestations_are_deterministic() -> void:
	# 正式测试关不能只在理论上支持素音：Perfect Replay 必须真的织出合法交点，
	# 而且换帧步后凝现位置不能漂移。
	var rules := load("res://content/rules/default_gameplay_rules.tres") as GameplayRuleSet
	for stage_id: String in ["s04", "s05"]:
		var chart := load("res://content/stages/%s/song_chart.tres" % stage_id) as SongChart
		var compile_result: Dictionary = ChartCompiler.compile(chart, rules)
		_expect(bool(compile_result.get("ok", false)), "%s 调频测试谱可编译" % stage_id)
		if not bool(compile_result.get("ok", false)):
			continue
		var compiled: CompiledChart = compile_result["compiled"]
		var replay := ReplayRunner.build_perfect_replay(compiled, rules)
		var run_30: Dictionary = ReplayRunner.run(compiled, rules, replay, 33_333)
		var run_irregular: Dictionary = ReplayRunner.run_with_frame_steps(
			compiled,
			rules,
			replay,
			PackedInt64Array([3_001, 41_003, 7_779, 20_003])
		)
		var first: Array = (run_30["simulation"] as GameplaySimulation).snapshot()["su_manifestations"]
		var second: Array = (run_irregular["simulation"] as GameplaySimulation).snapshot()["su_manifestations"]
		_expect_equal(first, second, "%s 的素音交点不随帧步改变" % stage_id)
		_expect_equal(first.size(), compiled.su_manifestations.size(), "%s 的每条素音事件都被解析" % stage_id)
		for manifestation: Dictionary in first:
			var event_id: String = str(manifestation.get("event_id", ""))
			_expect(bool(manifestation.get("success", false)), "%s/%s 的 Perfect Replay 能凝成素音：%s" % [stage_id, event_id, var_to_str(manifestation)])
			_expect(not Array(manifestation.get("points", [])).is_empty(), "%s/%s 的素音坐标来自真实加强纹：%s" % [stage_id, event_id, var_to_str(manifestation)])


func _engine() -> CarrierWaveEngine:
	var engine := CarrierWaveEngine.new()
	engine.configure(GameplayRuleSet.new())
	return engine


func _launch_times(engine: CarrierWaveEngine) -> PackedInt64Array:
	var result := PackedInt64Array()
	for wave: Dictionary in engine.history_copy():
		result.append(int(wave["launch_us"]))
	return result


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s（actual=%s expected=%s）" % [message, actual, expected])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s（actual=%.6f expected=%.6f）" % [message, actual, expected])
