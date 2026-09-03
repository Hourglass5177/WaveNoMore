extends SceneTree

## 双钟独立调频的设备映射与 Replay v2 合同测试。
## 这里只验证“物理输入 → 语义样本”，不测试滑条判定或画面。

var _failures: PackedStringArray = []
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_semantic_sample_dual_channels()
	_test_replay_v2_roundtrip_and_v1_rejection()
	_test_perfect_replay_uses_relative_slider_displacement()
	_test_perfect_replay_keeps_adjacent_slider_hold()
	_test_input_map_contract()
	_test_rule_driven_tuning_parameters()
	_test_mouse_displacement_routing()
	_test_gamepad_rate_routing()
	_test_multitouch_routing()
	if _failures.is_empty():
		print("INPUT / REPLAY V2 TESTS: %d checks passed." % _checks)
		quit(0)
		return
	printerr("INPUT / REPLAY V2 TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
	for failure: String in _failures:
		printerr("  - " + failure)
	quit(1)


func _test_semantic_sample_dual_channels() -> void:
	var both_full := SemanticInputSample.create(
		100,
		2,
		GameplayTypes.SemanticInputKind.TUNING_RATE_CHANGED,
		Vector2.ONE
	)
	_expect_near(both_full.tune_vector.x, 1.0, 0.000001, "life channel keeps full simultaneous input")
	_expect_near(both_full.tune_vector.y, 1.0, 0.000001, "death channel is not normalized to 0.707")

	var independently_clamped := SemanticInputSample.create(
		101,
		3,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
		Vector2(-2.0, 2.0)
	)
	_expect_equal(independently_clamped.tune_vector, Vector2(-1.0, 1.0), "each tuning channel clamps independently")
	var encoded: Dictionary = independently_clamped.to_dictionary()
	_expect(encoded.has("life_q15") and encoded.has("death_q15"), "v2 sample uses named life/death channels")
	_expect(not encoded.has("tune_x_q15") and not encoded.has("tune_y_q15"), "v2 sample no longer writes ambiguous v1 keys")
	var restored := SemanticInputSample.from_dictionary(encoded)
	_expect_equal(restored.tune_vector, independently_clamped.tune_vector, "v2 sample survives Q15 roundtrip")


func _test_replay_v2_roundtrip_and_v1_rejection() -> void:
	var replay := ReplayData.new()
	replay.replay_id = "input-v2"
	replay.inputs = [
		SemanticInputSample.create(200, 1, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, Vector2(0.25, 0.0)),
		SemanticInputSample.create(200, 0, GameplayTypes.SemanticInputKind.TUNING_RATE_CHANGED, Vector2(1.0, -1.0)),
	]
	var restored := ReplayData.from_dictionary(replay.to_dictionary())
	_expect_equal(restored.schema_version, 2, "new ReplayData records schema v2")
	_expect_equal(restored.sorted_inputs()[0].sequence, 0, "Replay v2 keeps stable timestamp/sequence ordering")
	_expect_equal(restored.canonical_input_hash(), replay.canonical_input_hash(), "Replay v2 canonical hash survives serialization")

	var driver := ReplayInputDriver.new()
	root.add_child(driver)
	_expect(driver.load_replay(restored), "runtime driver accepts Replay v2")
	var legacy := ReplayData.new()
	legacy.schema_version = 1
	_expect(not driver.load_replay(legacy), "runtime driver explicitly rejects Replay v1")
	var legacy_run: Dictionary = ReplayRunner.run(CompiledChart.new(), GameplayRuleSet.new(), legacy)
	_expect(not bool(legacy_run.get("ok", true)), "domain ReplayRunner explicitly rejects Replay v1")
	driver.queue_free()


func _test_perfect_replay_uses_relative_slider_displacement() -> void:
	var compiled := CompiledChart.new()
	var tempo_events: Array[TempoEvent] = []
	compiled.tempo_map = TempoMap.new()
	compiled.tempo_map.configure(480, 0, tempo_events)
	compiled.chart_id = "slider-replay-v2"
	compiled.tuning_fields = [{"start_us": 0}]
	compiled.tuning_sliders = [{
		"affinity": GameplayTypes.Affinity.ZHU,
		"tick": 0,
		"end_tick": 480,
		"duration_ticks": 480,
		"traversal_ticks": 480,
		"traversal_count": 1,
		"start_us": 0,
		"end_us": 500_000,
		"start_value": 0.5,
		"end_value": 0.8,
	}]
	var replay := ReplayRunner.build_perfect_replay(compiled, GameplayRuleSet.new())
	var displacement_sum := Vector2.ZERO
	var rate_count: int = 0
	for sample: SemanticInputSample in replay.inputs:
		if sample.kind == GameplayTypes.SemanticInputKind.TUNING_DISPLACED:
			displacement_sum += sample.tune_vector
		elif sample.kind == GameplayTypes.SemanticInputKind.TUNING_RATE_CHANGED:
			rate_count += 1
	_expect_near(displacement_sum.x, 0.3, 0.001, "perfect Replay follows a life slider by accumulated relative displacement")
	_expect_near(displacement_sum.y, 0.0, 0.000001, "life slider Replay never moves the death channel")
	_expect_equal(rate_count, 0, "perfect Replay does not confuse absolute guide samples with stick rate")


func _test_perfect_replay_keeps_adjacent_slider_hold() -> void:
	var compiled := CompiledChart.new()
	compiled.tempo_map = TempoMap.new()
	compiled.tempo_map.configure(480, 0, [])
	compiled.chart_id = "adjacent-slider-replay-v2"
	compiled.tuning_fields = [{"start_us": 0}]
	compiled.tuning_sliders = [
		{
			"affinity": GameplayTypes.Affinity.ZHU,
			"tick": 0,
			"end_tick": 480,
			"duration_ticks": 480,
			"traversal_ticks": 480,
			"traversal_count": 1,
			"start_us": 0,
			"end_us": 500_000,
			"start_value": 0.5,
			"end_value": 0.8,
		},
		{
			"affinity": GameplayTypes.Affinity.ZHU,
			"tick": 480,
			"end_tick": 960,
			"duration_ticks": 480,
			"traversal_ticks": 480,
			"traversal_count": 1,
			"start_us": 500_000,
			"end_us": 1_000_000,
			"start_value": 0.8,
			"end_value": 0.4,
		},
	]
	var replay := ReplayRunner.build_perfect_replay(compiled, GameplayRuleSet.new())
	var press_count: int = 0
	var release_count: int = 0
	var release_time_us: int = -1
	for sample: SemanticInputSample in replay.inputs:
		if sample.kind == GameplayTypes.SemanticInputKind.LIFE_PRESSED:
			press_count += 1
		elif sample.kind == GameplayTypes.SemanticInputKind.LIFE_RELEASED:
			release_count += 1
			release_time_us = sample.timestamp_us
	_expect_equal(press_count, 1, "adjacent same-side sliders share one continuous press")
	_expect_equal(release_count, 1, "adjacent same-side sliders release only after the complete chain")
	_expect_equal(release_time_us, 1_001_000, "continuous hold releases after the final slider sample")


func _test_input_map_contract() -> void:
	_expect(_joy_button(JOY_BUTTON_LEFT_SHOULDER, true).is_action_pressed(InputRouter.ACTION_DEATH), "L1 holds the death bell")
	_expect(_joy_button(JOY_BUTTON_RIGHT_SHOULDER, true).is_action_pressed(InputRouter.ACTION_LIFE), "R1 holds the life bell")
	_expect(InputMap.has_action(InputRouter.ACTION_DEATH_TUNE_LEFT), "left-stick death-low action exists")
	_expect(InputMap.has_action(InputRouter.ACTION_DEATH_TUNE_RIGHT), "left-stick death-high action exists")
	_expect(InputMap.has_action(InputRouter.ACTION_LIFE_TUNE_LEFT), "right-stick life-low action exists")
	_expect(InputMap.has_action(InputRouter.ACTION_LIFE_TUNE_RIGHT), "right-stick life-high action exists")
	_expect(_joy_button(JOY_BUTTON_A, true).is_action_pressed(&"ui_accept"), "gamepad A remains menu confirm")
	_expect(_joy_button(JOY_BUTTON_B, true).is_action_pressed(&"ui_cancel"), "gamepad B remains menu cancel")
	_expect(_joy_button(JOY_BUTTON_START, true).is_action_pressed(InputRouter.ACTION_PAUSE), "gamepad Start remains pause")


func _test_rule_driven_tuning_parameters() -> void:
	var router := InputRouter.new()
	root.add_child(router)
	var rules := GameplayRuleSet.new()
	rules.tuning_min_frequency_hz = 2.0
	rules.tuning_max_frequency_hz = 8.0
	rules.tuning_pixels_per_hz = 120.0
	rules.tuning_cursor_speed_px_sec = 540.0
	rules.tuning_stick_deadzone = 0.30
	router.configure_from_rules(rules)

	_expect_near(router.pointer_displacement_per_pixel, 1.0 / 720.0, 0.000001, "pointer scale is derived from the authored frequency-axis length")
	_expect_near(router.tuning_cursor_speed_px_sec, 540.0, 0.000001, "router receives the same cursor speed used by the tuning domain")
	_expect_near(router.tune_deadzone, 0.30, 0.000001, "gamepad deadzone comes from GameplayRuleSet")

	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	router.set_tuning_capture_active(true)
	router.call("_handle_bell_event", _mouse_button(MOUSE_BUTTON_LEFT, true))
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(72.0, 0.0)
	router.call("_handle_tune_event", move)
	_expect_near(samples[-1].tune_vector.y, 0.1, 0.0001, "72 px over a 720 px axis produces exactly one tenth normalized displacement")

	var l1 := _joy_button(JOY_BUTTON_LEFT_SHOULDER, true)
	l1.device = 7
	router.call("_handle_bell_event", l1)
	router.call("_handle_tune_event", _joy_axis(JOY_AXIS_LEFT_X, 0.65, 7))
	_expect_near(samples[-1].tune_vector.y, 0.5, 0.0001, "stick strength is remapped from the rule-driven deadzone")
	router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	router.queue_free()


func _test_mouse_displacement_routing() -> void:
	var router := InputRouter.new()
	root.add_child(router)
	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))

	var left_down := _mouse_button(MOUSE_BUTTON_LEFT, true)
	router.call("_handle_bell_event", left_down)
	_expect(router.death_held and not router.life_held, "left mouse holds death even outside a tuning field")
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(100.0, 50.0)
	_expect(not bool(router.call("_handle_tune_event", move)), "mouse motion cannot tune outside an authored field")

	router.set_tuning_capture_active(true)
	router.call("_handle_tune_event", move)
	var death_move: SemanticInputSample = samples[-1]
	_expect_equal(death_move.kind, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, "mouse drag emits displacement semantics")
	_expect_near(death_move.tune_vector.x, 0.0, 0.000001, "left mouse does not move life tuning")
	_expect_near(death_move.tune_vector.y, 100.0 * router.pointer_displacement_per_pixel, 0.0001, "left mouse moves death tuning immediately")

	router.call("_handle_bell_event", _mouse_button(MOUSE_BUTTON_RIGHT, true))
	router.call("_handle_tune_event", move)
	var dual_move: SemanticInputSample = samples[-1]
	_expect_near(dual_move.tune_vector.x, dual_move.tune_vector.y, 0.000001, "dual mouse hold applies the same temporary delta to both bells")
	router.call("_handle_bell_event", _mouse_button(MOUSE_BUTTON_LEFT, false))
	router.call("_handle_tune_event", move)
	var life_move: SemanticInputSample = samples[-1]
	_expect(life_move.tune_vector.x > 0.0 and is_zero_approx(life_move.tune_vector.y), "releasing left mouse leaves right-mouse life tuning independent")
	router.cancel_all(InputRouter.CancelReason.FOCUS_LOST)
	_expect(not router.life_held and not router.death_held, "focus cancellation clears all mouse-held bells")
	_expect_equal(samples[-1].kind, GameplayTypes.SemanticInputKind.FOCUS_CANCELLED, "focus cancellation is replayable semantic input")
	router.queue_free()


func _test_gamepad_rate_routing() -> void:
	var router := InputRouter.new()
	root.add_child(router)
	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	router.set_tuning_capture_active(true)

	var l1 := _joy_button(JOY_BUTTON_LEFT_SHOULDER, true)
	l1.device = 0
	router.call("_handle_bell_event", l1)
	var left_axis := _joy_axis(JOY_AXIS_LEFT_X, 1.0, 0)
	router.call("_handle_tune_event", left_axis)
	_expect_near(router.tune_vector.x, 0.0, 0.000001, "left stick never changes life rate")
	_expect_near(router.tune_vector.y, 1.0, 0.000001, "L1 plus left stick controls death rate")

	var r1 := _joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	r1.device = 0
	router.call("_handle_bell_event", r1)
	router.call("_handle_tune_event", _joy_axis(JOY_AXIS_RIGHT_X, 1.0, 0))
	_expect_equal(router.tune_vector, Vector2.ONE, "two full sticks remain independent full-rate channels")
	_expect_equal(samples[-1].tune_vector, Vector2.ONE, "emitted rate sample preserves simultaneous full values")

	router.call("_handle_tune_event", _joy_axis(JOY_AXIS_LEFT_X, 0.0, 0))
	_expect_equal(router.tune_vector, Vector2(1.0, 0.0), "centering left stick stops death but preserves life")
	var r1_up := _joy_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	r1_up.device = 0
	router.call("_handle_bell_event", r1_up)
	_expect(router.tune_vector.is_zero_approx(), "releasing R1 stops its persistent life rate")
	router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	router.queue_free()


func _test_multitouch_routing() -> void:
	var router := InputRouter.new()
	root.add_child(router)
	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	router.set_tuning_capture_active(true)

	var upper := _touch(1, Vector2(200.0, 100.0), true)
	var lower := _touch(2, Vector2(200.0, 900.0), true)
	router.call("_handle_touch_event", upper)
	router.call("_handle_touch_event", lower)
	_expect(router.life_held and router.death_held, "two fingers independently hold upper-life and lower-death bells")

	var upper_drag := _drag(1, Vector2(80.0, 20.0))
	router.call("_handle_touch_event", upper_drag)
	_expect(samples[-1].tune_vector.x > 0.0 and is_zero_approx(samples[-1].tune_vector.y), "upper finger moves only life tuning")
	var lower_drag := _drag(2, Vector2(-60.0, 20.0))
	router.call("_handle_touch_event", lower_drag)
	_expect(samples[-1].tune_vector.y < 0.0 and is_zero_approx(samples[-1].tune_vector.x), "lower finger moves only death tuning")

	router.call("_handle_touch_event", _touch(1, upper.position, false))
	_expect(not router.life_held and router.death_held, "lifting upper finger leaves lower bell held")
	router.call("_handle_touch_event", _touch(2, lower.position, false))
	_expect(not router.life_held and not router.death_held, "lifting both fingers releases both bells")
	router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	router.queue_free()


func _mouse_button(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _joy_button(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _joy_axis(axis: JoyAxis, value: float, device: int) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = device
	return event


func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _drag(index: int, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.relative = relative
	return event


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual=%f expected=%f)" % [message, actual, expected])
