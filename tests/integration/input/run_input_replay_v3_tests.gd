extends SceneTree

## 双钟旋钮调频的设备映射与 Replay v3 合同测试。
## 这里只验证“物理输入 → 语义样本”，不测试滑条判定或画面。

var _failures: PackedStringArray = []
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_semantic_sample_dual_channels()
	_test_replay_v3_roundtrip_and_legacy_rejection()
	_test_perfect_replay_uses_relative_slider_displacement()
	_test_perfect_replay_keeps_adjacent_slider_hold()
	_test_input_map_contract()
	_test_rule_driven_tuning_parameters()
	_test_rotary_tracker_contract()
	_test_mouse_displacement_routing()
	_test_pause_menu_mouse_passthrough()
	_test_gamepad_rotary_routing()
	_test_virtual_clutch_directions_and_sweeps()
	_test_virtual_clutch_reengagement_and_event_boundaries()
	_test_multitouch_routing()
	if _failures.is_empty():
		print("INPUT / REPLAY V3 TESTS: %d checks passed." % _checks)
		quit(0)
		return
	printerr("INPUT / REPLAY V3 TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
	for failure: String in _failures:
		printerr("  - " + failure)
	quit(1)


func _test_semantic_sample_dual_channels() -> void:
	var both_full := SemanticInputSample.create(
		100,
		2,
		GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
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
	_expect(encoded.has("life_q15") and encoded.has("death_q15"), "v3 sample uses named life/death channels")
	_expect(not encoded.has("tune_x_q15") and not encoded.has("tune_y_q15"), "v3 sample never writes ambiguous legacy keys")
	var restored := SemanticInputSample.from_dictionary(encoded)
	_expect_equal(restored.tune_vector, independently_clamped.tune_vector, "v3 sample survives Q15 roundtrip")


func _test_replay_v3_roundtrip_and_legacy_rejection() -> void:
	var replay := ReplayData.new()
	replay.replay_id = "input-v3"
	replay.inputs = [
		SemanticInputSample.create(200, 1, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, Vector2(0.25, 0.0)),
		SemanticInputSample.create(200, 0, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, Vector2(0.0, -0.25)),
	]
	var restored := ReplayData.from_dictionary(replay.to_dictionary())
	_expect_equal(restored.schema_version, 3, "new ReplayData records schema v3")
	_expect_equal(restored.sorted_inputs()[0].sequence, 0, "Replay v3 keeps stable timestamp/sequence ordering")
	_expect_equal(restored.canonical_input_hash(), replay.canonical_input_hash(), "Replay v3 canonical hash survives serialization")

	var driver := ReplayInputDriver.new()
	root.add_child(driver)
	_expect(driver.load_replay(restored), "runtime driver accepts Replay v3")
	var rate_replay := ReplayData.new()
	rate_replay.schema_version = 2
	_expect(not driver.load_replay(rate_replay), "runtime driver explicitly rejects rate-based Replay v2")
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
	compiled.chart_id = "slider-replay-v3"
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
		"start_value": 0.333333,
		"end_value": 0.633333,
	}]
	var replay := ReplayRunner.build_perfect_replay(compiled, GameplayRuleSet.new())
	var displacement_sum := Vector2.ZERO
	for sample: SemanticInputSample in replay.inputs:
		if sample.kind == GameplayTypes.SemanticInputKind.TUNING_DISPLACED:
			displacement_sum += sample.tune_vector
	_expect_near(displacement_sum.x, 0.3, 0.001, "perfect Replay follows a life slider by accumulated relative displacement")
	_expect_near(displacement_sum.y, 0.0, 0.000001, "life slider Replay never moves the death channel")
	_expect(replay.inputs.all(func(sample: SemanticInputSample) -> bool:
		return not sample.is_tuning() or sample.kind == GameplayTypes.SemanticInputKind.TUNING_DISPLACED
	), "perfect Replay contains displacement tuning only")


func _test_perfect_replay_keeps_adjacent_slider_hold() -> void:
	var compiled := CompiledChart.new()
	compiled.tempo_map = TempoMap.new()
	compiled.tempo_map.configure(480, 0, [])
	compiled.chart_id = "adjacent-slider-replay-v3"
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
	_expect_equal(release_time_us, 1_001_000, "a slider without Su releases immediately after its authored endpoint")


func _test_input_map_contract() -> void:
	_expect(_joy_button(JOY_BUTTON_LEFT_SHOULDER, true).is_action_pressed(InputRouter.ACTION_DEATH), "L1 holds the death bell")
	_expect(_joy_button(JOY_BUTTON_RIGHT_SHOULDER, true).is_action_pressed(InputRouter.ACTION_LIFE), "R1 holds the life bell")
	_expect(_joy_button(JOY_BUTTON_LEFT_STICK, true).is_action_pressed(InputRouter.ACTION_DEATH), "L3 is an alternate left/death bell key")
	_expect(_joy_button(JOY_BUTTON_RIGHT_STICK, true).is_action_pressed(InputRouter.ACTION_LIFE), "R3 is an alternate right/life bell key")
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
	rules.tuning_hz_per_revolution = 3.0
	router.configure_from_rules(rules)

	_expect_near(router.pointer_displacement_per_pixel, 1.0 / 720.0, 0.000001, "pointer scale is derived from the authored frequency-axis length")
	_expect_near(router.rotary_displacement_per_radian, 3.0 / (TAU * 6.0), 0.000001, "one full revolution changes exactly the authored Hz amount")

	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	router.set_tuning_capture_active(true)
	router.call("_handle_bell_event", _mouse_button(MOUSE_BUTTON_LEFT, true))
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(72.0, 0.0)
	router.call("_handle_tune_event", move)
	_expect_near(samples[-1].tune_vector.y, 0.1, 0.0001, "72 px over a 720 px axis produces exactly one tenth normalized displacement")

	router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	router.queue_free()


func _test_rotary_tracker_contract() -> void:
	var tracker := RotaryStickTracker.new()
	_expect_near(tracker.engage_radius, 0.55, 0.000001, "the stick must be deliberately pushed before its rotary clutch engages")
	_expect_near(tracker.release_radius, 0.35, 0.000001, "the clutch releases near centre without dropping during a normal circular gesture")
	_expect_near(tracker.update(Vector2.RIGHT * 0.54), 0.0, 0.000001, "a push below the outer threshold does not establish an angle anchor")
	_expect(not tracker.is_tracking(), "the tracker stays disengaged below the outer threshold")
	_expect_near(tracker.update(Vector2.RIGHT * 0.70), 0.0, 0.000001, "crossing the outer threshold establishes an angle anchor")
	_expect_near(tracker.update(Vector2.RIGHT * 0.70), 0.0, 0.000001, "holding one direction produces no rotation")
	_expect_near(tracker.update(Vector2.RIGHT * 0.40), 0.0, 0.000001, "radial movement inside hysteresis produces no rotation")
	_expect(tracker.is_tracking(), "tracker stays engaged inside the 0.35-to-0.55 hysteresis band")
	_expect_near(tracker.update(Vector2.DOWN), PI * 0.5, 0.000001, "screen-space clockwise rotation is positive")
	_expect_near(tracker.update(Vector2.RIGHT), -PI * 0.5, 0.000001, "screen-space counter-clockwise rotation is negative")

	tracker.reset()
	tracker.update(Vector2.from_angle(deg_to_rad(179.0)))
	_expect_near(tracker.update(Vector2.from_angle(deg_to_rad(-178.0))), deg_to_rad(3.0), 0.00001, "crossing the PI seam keeps a small continuous clockwise angle")

	tracker.reset()
	tracker.update(Vector2.RIGHT)
	_expect_near(tracker.update(Vector2.from_angle(deg_to_rad(0.10))), 0.0, 0.000001, "tiny motion is accumulated instead of emitted as jitter")
	_expect_near(tracker.update(Vector2.from_angle(deg_to_rad(0.30))), deg_to_rad(0.30), 0.00001, "a quarter-degree packet makes slow rotation visibly continuous")
	tracker.update(Vector2(0.36, 0.0))
	_expect(tracker.is_tracking(), "a shallow circle stays engaged above the inner release radius")
	tracker.update(Vector2(0.34, 0.0))
	_expect(not tracker.is_tracking(), "returning below 0.35 clears the angle anchor")
	_expect_near(tracker.update(Vector2.DOWN), 0.0, 0.000001, "re-entering the outer radius establishes a fresh anchor")

	tracker.reset()
	tracker.update(Vector2.RIGHT)
	_expect_near(tracker.update(Vector2.from_angle(deg_to_rad(120.0))), deg_to_rad(120.0), 0.00001, "a fast healthy arc is not discarded at a low frame rate")

	tracker.reset()
	tracker.update(Vector2.RIGHT)
	_expect_near(tracker.update(Vector2.from_angle(deg_to_rad(179.0))), 0.0, 0.000001, "a near-opposite ambiguous jump is re-anchored without displacement")
	_expect_near(tracker.update(Vector2.from_angle(deg_to_rad(-171.0))), deg_to_rad(10.0), 0.00001, "normal rotation resumes immediately after an ambiguous jump")

	# 真实玩家画出的通常是椭圆而非理想单位圆；半径波动不应改变净角位移。
	tracker.reset()
	var ellipse_total: float = 0.0
	for degree: int in range(0, 91, 5):
		var radians: float = deg_to_rad(float(degree))
		var radius_scale: float = 0.92 + 0.08 * sin(float(degree) * 0.31)
		ellipse_total += tracker.update(Vector2(cos(radians) * 0.90, sin(radians) * 0.68) * radius_scale)
	_expect_near(ellipse_total, PI * 0.5, deg_to_rad(0.26), "a medium-radius elliptical quarter-turn keeps its full angle")

	# 计分滑条只在第一次起手检查 ±15° 扇区。捕获后可离开屏幕圆弧，
	# 进度仍严格来自真实旋转量。
	var finite_sweep: float = deg_to_rad(60.0)
	var finite_angles: Vector2 = TuningArcGeometry.symmetric_directed_angles(
		GameplayTypes.Affinity.ZHU,
		1,
		finite_sweep
	)
	tracker.configure_finite_arc(GameplayTypes.Affinity.ZHU, 1, finite_sweep, 0.0)
	_expect_near(tracker.update_finite_arc(Vector2.UP), 0.0, 0.000001, "the centre of a scored arc cannot bypass its initial capture window")
	_expect(not tracker.is_tracking(), "a wrong initial angle does not establish tracking")
	var early_start: float = finite_angles.x - deg_to_rad(14.0)
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(early_start)), 0.0, 0.000001, "the early side of the start window captures without shifting progress")
	_expect(tracker.is_tracking(), "the authored start window establishes the finite gesture")
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(finite_angles.x + deg_to_rad(80.0))), 1.0, 0.0001, "after capture the hand may leave the visual arc and still complete by real angle")
	_expect_near(tracker.finite_arc_progress(), 1.0, 0.0001, "the complete gesture reaches full progress")

	# 端点会消费向外的多余位移；反向动作立即生效，不必先偿还看不见的过冲。
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(finite_angles.x + deg_to_rad(100.0))), 0.0, 0.000001, "endpoint overshoot is dropped instead of overflowing progress")
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(finite_angles.x + deg_to_rad(94.0))), -6.0 / 60.0, 0.0001, "reversing after overshoot immediately retreats the fill")

	# 未采到回中帧时，异常大跳只重定锚；下一帧即可继续。
	tracker.configure_finite_arc(GameplayTypes.Affinity.ZHU, 1, finite_sweep, 0.0)
	tracker.update_finite_arc(Vector2.from_angle(finite_angles.x))
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(finite_angles.x + deg_to_rad(120.0))), 0.0, 0.000001, "an implausible finite-arc jump is treated as a centre crossing")
	_expect(tracker.is_tracking(), "an implausible jump re-anchors without destroying the clutch session")
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(finite_angles.x + deg_to_rad(130.0))), 10.0 / 60.0, 0.0001, "normal rotation resumes immediately after a large-jump re-anchor")

	# 首次捕获后，回中可从任意手位重新推出：首帧只接合，下一帧才继续。
	tracker.configure_finite_arc(GameplayTypes.Affinity.ZHU, 1, finite_sweep, 0.40)
	_expect_near(tracker.update_finite_arc(Vector2.RIGHT), 0.0, 0.000001, "nonzero authoritative progress does not bypass a new event's start capture")
	tracker.update_finite_arc(Vector2.from_angle(finite_angles.x))
	tracker.update_finite_arc(Vector2.RIGHT * 0.34)
	_expect(not tracker.is_tracking(), "returning the finite gesture to centre disengages without losing its progress")
	_expect_near(tracker.update_finite_arc(Vector2.RIGHT), 0.0, 0.000001, "re-engaging at an arbitrary hand position only establishes a new anchor")
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(deg_to_rad(5.0))), 5.0 / 60.0, 0.0001, "continued rotation resumes from the retained progress")


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
	router.set_tuning_gesture_windows([{
		"event_id": "preview_death",
		"affinity": GameplayTypes.Affinity.XUAN,
		"start_value": 0.333333,
		"end_value": 0.0,
		"interaction_open": false,
	}])
	var before_preview_move: int = samples.size()
	router.call("_handle_tune_event", move)
	_expect_equal(samples.size(), before_preview_move, "the shrinking preview ring cannot be pre-filled by pointer movement")
	router.set_tuning_gesture_windows([{
		"event_id": "preview_death",
		"affinity": GameplayTypes.Affinity.XUAN,
		"start_value": 0.333333,
		"end_value": 0.0,
		"interaction_open": true,
		"current_traversal_index": 0,
	}])
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


func _test_pause_menu_mouse_passthrough() -> void:
	var original_mouse_mode: Input.MouseMode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var router := InputRouter.new()
	root.add_child(router)
	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	router.set_mode(InputRouter.InputMode.GAMEPLAY)
	router.set_tuning_capture_active(true)
	_expect(bool(router.get("_mouse_captured_by_router")), "active tuning owns mouse capture during gameplay")

	router.set_mode(InputRouter.InputMode.RESUME_REARM)
	_expect(not bool(router.get("_mouse_captured_by_router")), "opening the pause menu releases gameplay mouse ownership")
	_expect_equal(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "opening the pause menu restores a visible mouse cursor")
	var before_click: int = samples.size()
	router.call("_input", _mouse_button(MOUSE_BUTTON_LEFT, true))
	_expect_equal(samples.size(), before_click, "pause-menu click is not consumed as a bell strike before Button receives it")
	_expect(not router.death_held and not router.life_held, "pause-menu click does not alter gameplay hold state")

	router.set_mode(InputRouter.InputMode.GAMEPLAY)
	_expect(bool(router.get("_mouse_captured_by_router")), "resuming inside the tuning field restores gameplay mouse ownership")
	router.set_mode(InputRouter.InputMode.DISABLED)
	_expect_equal(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "leaving gameplay restores the original mouse mode")
	router.queue_free()
	Input.mouse_mode = original_mouse_mode


func _test_gamepad_rotary_routing() -> void:
	var router := InputRouter.new()
	root.add_child(router)
	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	router.set_tuning_capture_active(true)
	router.set_tuning_gesture_windows([
		{
			"event_id": "life_window",
			"affinity": GameplayTypes.Affinity.ZHU,
			"start_value": 0.333333,
			"end_value": 0.666667,
		},
		{
			"event_id": "death_window",
			"affinity": GameplayTypes.Affinity.XUAN,
			"start_value": 0.333333,
			"end_value": 0.0,
		},
	])

	var l1 := _joy_button(JOY_BUTTON_LEFT_SHOULDER, true)
	l1.device = 0
	router.call("_handle_bell_event", l1)
	var r1 := _joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	r1.device = 0
	router.call("_handle_bell_event", r1)
	var gesture_windows: Dictionary = router.tuning_gesture_window_snapshot()
	var life_window: Dictionary = gesture_windows["life"]
	var death_window: Dictionary = gesture_windows["death"]
	var life_angles: Vector2 = TuningArcGeometry.symmetric_directed_angles(
		GameplayTypes.Affinity.ZHU,
		int(life_window["rotation_sign"]),
		float(life_window["arc_sweep_rad"])
	)
	var death_angles: Vector2 = TuningArcGeometry.symmetric_directed_angles(
		GameplayTypes.Affinity.XUAN,
		int(death_window["rotation_sign"]),
		float(death_window["arc_sweep_rad"])
	)

	# 起点窗只负责首次捕获。相反半屏和圆弧中央都不能跳过起点直接建立手势。
	var before_wrong_hemisphere: int = samples.size()
	router.call("_process_rotary_sticks", 0, Vector2.DOWN, 0, Vector2.UP)
	_expect_equal(samples.size(), before_wrong_hemisphere, "wrong visual hemispheres cannot establish a rotary gesture")
	router.call("_process_rotary_sticks", 0, Vector2.UP, 0, Vector2.DOWN)
	_expect_equal(samples.size(), before_wrong_hemisphere, "the middle of each arc cannot bypass its authored start")

	# 生升频弧从左上到右上，死降频弧从右下到左下；在 Godot 的 Y 向下坐标中
	# 二者都是正角度（视觉顺时针），而频率轴位移应一正一负。
	var life_upper_left := Vector2.from_angle(life_angles.x)
	var life_upper_right := Vector2.from_angle(life_angles.y)
	var death_lower_right := Vector2.from_angle(death_angles.x)
	var death_lower_left := Vector2.from_angle(death_angles.y)
	var before_rotation_count: int = samples.size()
	router.call("_process_rotary_sticks", 0, life_upper_left, 0, death_lower_right)
	_expect_equal(samples.size(), before_rotation_count, "anchoring both sticks emits no tuning displacement")
	router.call("_process_rotary_sticks", 0, life_upper_right, 0, death_lower_left)
	var clockwise: SemanticInputSample = samples[-1]
	_expect_equal(clockwise.kind, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, "gamepad rotation emits displacement semantics")
	_expect(clockwise.tune_vector.x > 0.0 and clockwise.tune_vector.y < 0.0, "upper-left to upper-right and lower-right to lower-left are both clockwise gestures")
	_expect_near(clockwise.tune_vector.x, -clockwise.tune_vector.y, 0.000001, "mirrored equal rotations preserve equal magnitudes on both channels")
	# 往返折返点只改变当前所需旋向；事件 ID、固定弧和摇杆接合都必须保留。
	router.set_tuning_gesture_windows([
		{
			"event_id": "life_window",
			"affinity": GameplayTypes.Affinity.ZHU,
			"start_value": 0.333333,
			"end_value": 0.666667,
			"raw_player_progress": 1.0,
			"required_rotation_sign": -1,
		},
		{
			"event_id": "death_window",
			"affinity": GameplayTypes.Affinity.XUAN,
			"start_value": 0.333333,
			"end_value": 0.0,
			"raw_player_progress": 1.0,
			"required_rotation_sign": -1,
		},
	])

	# 某些驱动会重复上报仍处于按下状态的肩键；重复事件不能清掉已经建立的角度锚点。
	router.call("_handle_bell_event", l1)
	router.call("_handle_bell_event", r1)
	var before_duplicate_rotation: int = samples.size()
	router.call("_process_rotary_sticks", 0, Vector2.UP, 0, Vector2.DOWN)
	_expect_equal(samples.size(), before_duplicate_rotation + 1, "duplicate shoulder presses do not reset active rotary trackers")
	_expect(samples[-1].tune_vector.x < 0.0 and samples[-1].tune_vector.y > 0.0, "mirrored reverse rotation continues immediately after duplicate shoulder events")

	var fixed_count: int = samples.size()
	router.call("_process_rotary_sticks", 0, Vector2.UP, 0, Vector2.DOWN)
	_expect_equal(samples.size(), fixed_count, "holding both sticks still produces no further movement")
	router.call("_process_rotary_sticks", 0, life_upper_right, 0, death_lower_left)
	var counter_clockwise: SemanticInputSample = samples[-1]
	_expect(counter_clockwise.tune_vector.x > 0.0 and counter_clockwise.tune_vector.y < 0.0, "returning toward both arc endpoints restores clockwise progression")

	var r1_up := _joy_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	r1_up.device = 0
	router.call("_handle_bell_event", r1_up)
	# 释放 R1 只停生钟。死钟先沿下弧退回起点，再从右下推向左下，仍应
	# 按同一固定圆弧产生降频，而不是因为另一侧释放而重置。
	router.call("_process_rotary_sticks", -1, Vector2.ZERO, 0, death_lower_right)
	var after_release_count: int = samples.size()
	router.call("_process_rotary_sticks", -1, Vector2.ZERO, 0, death_lower_left)
	_expect_equal(samples.size(), after_release_count + 1, "releasing R1 leaves L1 rotation active")
	_expect(is_zero_approx(samples[-1].tune_vector.x) and samples[-1].tune_vector.y < 0.0, "lower-right to lower-left is the Death slider's clockwise lowering gesture")
	_expect_equal(router.last_tuning_displacement, samples[-1].tune_vector, "router exposes the most recent displacement for diagnostics")

	# 某个手柄断开时，只撤销这个设备。这里用一根触指继续按住生钟，确认断连
	# 不会清空无关来源，也不会向领域层发送会取消全部 Hold 的 FOCUS_CANCELLED。
	router.call("_set_bell_source", true, "touch:99", true)
	var before_disconnect_count: int = samples.size()
	router.call("_on_joy_connection_changed", 0, false)
	_expect(router.life_held, "disconnecting a gamepad preserves an unrelated touch hold")
	_expect(not router.death_held, "disconnecting the sole L1 owner releases only the death bell")
	_expect_equal(samples.size(), before_disconnect_count + 1, "selective disconnect emits only the changed bell release")
	_expect_equal(samples[-1].kind, GameplayTypes.SemanticInputKind.DEATH_RELEASED, "selective disconnect never emits a global focus cancellation")
	router.call("_set_bell_source", true, "touch:99", false)

	# 设备断连需要清空粘住的肩键，却不能把谱面仍然开放的调频场一起关掉。
	# 否则玩家改用键鼠后也要等到下一段才能继续调频。
	router.cancel_all(InputRouter.CancelReason.DEVICE_DISCONNECTED, false, false)
	_expect(bool(router.get("_tuning_capture_requested")), "device disconnect preserves the authored tuning-field gate")
	router.call("_handle_bell_event", _mouse_button(MOUSE_BUTTON_LEFT, true))
	var fallback_move := InputEventMouseMotion.new()
	fallback_move.relative = Vector2(24.0, 0.0)
	var fallback_count: int = samples.size()
	router.call("_handle_tune_event", fallback_move)
	_expect_equal(samples.size(), fallback_count + 1, "mouse can continue the same tuning field after a gamepad disconnect")
	_expect(samples[-1].tune_vector.y > 0.0, "post-disconnect fallback still controls the death channel")
	router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	_expect(not bool(router.get("_tuning_capture_requested")), "session cleanup closes the tuning-field gate")
	_expect(router.last_tuning_displacement.is_zero_approx(), "reset clears the diagnostic displacement")
	router.queue_free()


func _test_virtual_clutch_directions_and_sweeps() -> void:
	# 不同视觉方向和弧长只决定起点与“填满所需角度”。首次捕获后，椭圆、
	# 轴向吸附、半径波动和轻微噪声都不应让中途某个绝对角度变成死区。
	var offsets_deg: Array[float] = [-75.0, -35.0, 0.0, 35.0, 75.0]
	var sweeps_deg: Array[float] = [28.0, 42.0, 75.0, 100.0]
	for offset_index: int in offsets_deg.size():
		for sweep_index: int in sweeps_deg.size():
			var affinity: int = (
				GameplayTypes.Affinity.ZHU
				if (offset_index + sweep_index) % 2 == 0
				else GameplayTypes.Affinity.XUAN
			)
			var rotation_sign: int = 1 if sweep_index % 2 == 0 else -1
			var sweep_rad: float = deg_to_rad(sweeps_deg[sweep_index])
			var offset_rad: float = deg_to_rad(offsets_deg[offset_index])
			var tracker := RotaryStickTracker.new()
			tracker.configure_finite_arc(affinity, rotation_sign, sweep_rad, 0.0, offset_rad)
			var angles: Vector2 = TuningArcGeometry.symmetric_directed_angles(
				affinity,
				rotation_sign,
				sweep_rad,
				offset_rad
			)
			tracker.update_finite_arc(_elliptical_stick_at_angle(angles.x, 1.0))
			for step: int in range(1, 49):
				var t: float = float(step) / 48.0
				var noise_rad: float = 0.0 if step == 48 else deg_to_rad(sin(float(step) * 1.71) * 0.65)
				var angle: float = angles.x + float(rotation_sign) * sweep_rad * t + noise_rad
				var stick: Vector2 = _elliptical_stick_at_angle(
					angle,
					0.94 + 0.06 * sin(float(step) * 0.47)
				)
				# 模拟部分手柄在主轴附近的量化/吸附。最后一个样本保持精确端点，
				# 使测试关注中途是否卡住，而不是设备量化造成的末端小误差。
				if step % 4 == 0 and step < 48:
					stick.x = snappedf(stick.x, 0.025)
					stick.y = snappedf(stick.y, 0.025)
				tracker.update_finite_arc(stick)
				if step % 12 == 0:
					_expect(
						tracker.finite_arc_progress() >= t - 0.08,
						"each quarter of a noisy gesture keeps advancing without an angle wall"
					)
			_expect_near(
				tracker.finite_arc_progress(),
				1.0,
				0.006,
				"%d degree slider at rotation %d completes without midpoint stall" % [
					roundi(sweeps_deg[sweep_index]),
					roundi(offsets_deg[offset_index]),
				]
			)


func _test_virtual_clutch_reengagement_and_event_boundaries() -> void:
	var sweep_rad: float = deg_to_rad(100.0)
	var tracker := RotaryStickTracker.new()
	tracker.configure_finite_arc(GameplayTypes.Affinity.ZHU, 1, sweep_rad)
	var start_angle: float = TuningArcGeometry.symmetric_directed_angles(
		GameplayTypes.Affinity.ZHU,
		1,
		sweep_rad
	).x
	tracker.update_finite_arc(Vector2.from_angle(start_angle))

	# 分别在 25%、50%、75% 回中，并从三个完全不同的手位重新接合。每次首帧
	# 只定锚，随后再转 25°；逻辑进度必须连续走到终点。
	var anchors: Array[float] = [start_angle, deg_to_rad(150.0), deg_to_rad(-10.0), deg_to_rad(80.0)]
	for quarter: int in range(4):
		if quarter > 0:
			tracker.update_finite_arc(Vector2.RIGHT * 0.34)
			_expect(not tracker.is_tracking(), "returning to centre opens the virtual clutch")
			_expect_near(
				tracker.update_finite_arc(Vector2.from_angle(anchors[quarter])),
				0.0,
				0.000001,
				"re-engaging from an arbitrary hand position creates no jump"
			)
		for step: int in range(1, 11):
			var angle: float = anchors[quarter] + deg_to_rad(25.0) * float(step) / 10.0
			tracker.update_finite_arc(Vector2.from_angle(angle))
		_expect_near(
			tracker.finite_arc_progress(),
			float(quarter + 1) * 0.25,
			0.003,
			"re-clutching preserves progress at each quarter"
		)

	# 到端点后的过冲被丢弃；从真实杆位反向一动就马上回退。
	var last_anchor: float = anchors[-1] + deg_to_rad(25.0)
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(last_anchor + deg_to_rad(12.0))), 0.0, 0.000001, "endpoint overrun creates no hidden debt")
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(last_anchor + deg_to_rad(7.0))), -0.05, 0.0001, "reverse motion retreats immediately after endpoint overrun")

	# 同一 event 的往返只翻转逻辑行程，保留当前离合；无需寻找起点或重放捕获。
	tracker.set_leg_index(1)
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(last_anchor - deg_to_rad(3.0))), -0.10, 0.0001, "a roundtrip reverses continuously inside one gesture session")
	_expect(tracker.is_tracking(), "a roundtrip keeps the established physical clutch")

	# 新 event 即使几何相同且已有权威进度，也必须重新经过自己的起点扇区。
	tracker.configure_finite_arc(GameplayTypes.Affinity.ZHU, 1, sweep_rad, 0.50)
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(start_angle + PI)), 0.0, 0.000001, "a new event rejects an arbitrary inherited hand position")
	_expect(not tracker.is_tracking(), "a new event cannot inherit the previous event's capture")
	_expect_near(tracker.update_finite_arc(Vector2.from_angle(start_angle + deg_to_rad(14.5))), 0.0, 0.000001, "the symmetric fifteen-degree start sector accepts its inner edge")
	_expect(tracker.is_tracking(), "the new event establishes its own gesture session")

	# InputRouter 只把当前可交互条交给 Tracker。未来预览既不能提前填充，也
	# 不能因为排在数组前面而抢走当前事件。
	var router := InputRouter.new()
	root.add_child(router)
	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	router.configure_from_rules(GameplayRuleSet.new())
	router.set_tuning_capture_active(true)
	var r1 := _joy_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	r1.device = 0
	router.call("_handle_bell_event", r1)
	router.set_tuning_gesture_windows([{
		"event_id": "future",
		"affinity": GameplayTypes.Affinity.ZHU,
		"start_value": 0.333333,
		"end_value": 0.666667,
		"interaction_open": false,
	}])
	var before_preview: int = samples.size()
	for degree: int in range(-120, -59, 10):
		router.call("_process_rotary_sticks", 0, Vector2.from_angle(deg_to_rad(float(degree))), -1, Vector2.ZERO)
	_expect_equal(samples.size(), before_preview, "a preview event never consumes gamepad rotation")

	router.set_tuning_gesture_windows([
		{
			"event_id": "future",
			"affinity": GameplayTypes.Affinity.ZHU,
			"start_value": 0.333333,
			"end_value": 0.666667,
			"interaction_open": false,
		},
		{
			"event_id": "current",
			"affinity": GameplayTypes.Affinity.ZHU,
			"start_value": 0.333333,
			"end_value": 0.666667,
			"interaction_open": true,
		},
	])
	var window: Dictionary = router.tuning_gesture_window_snapshot()["life"]
	_expect_equal(str(window["event_id"]), "current", "an active event wins even when a future preview appears first")
	var current_angles: Vector2 = TuningArcGeometry.symmetric_directed_angles(
		GameplayTypes.Affinity.ZHU,
		int(window["rotation_sign"]),
		float(window["arc_sweep_rad"])
	)
	router.call("_process_rotary_sticks", 0, Vector2.from_angle(current_angles.x), -1, Vector2.ZERO)
	var before_active_move: int = samples.size()
	router.call("_process_rotary_sticks", 0, Vector2.from_angle(current_angles.x + deg_to_rad(10.0)), -1, Vector2.ZERO)
	_expect_equal(samples.size(), before_active_move + 1, "only the current event receives gamepad displacement")
	router.queue_free()


func _elliptical_stick_at_angle(physical_angle: float, radius_scale: float) -> Vector2:
	# 求一个椭圆参数角，使归一化后的摇杆方向仍精确指向 physical_angle。
	var x_radius: float = 0.92
	var y_radius: float = 0.70
	var parameter_angle: float = atan2(
		x_radius * sin(physical_angle),
		y_radius * cos(physical_angle)
	)
	return Vector2(
		cos(parameter_angle) * x_radius,
		sin(parameter_angle) * y_radius
	) * radius_scale


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
