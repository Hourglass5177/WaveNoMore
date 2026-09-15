extends SceneTree

## 设备采集已迁入 InputEventBuffer；独立测试实例必须显式加载脚本。
const INPUT_BUFFER_SCRIPT: GDScript = preload("res://src/runtime/input/input_event_buffer.gd")

## 双钟旋钮调频的设备映射与 Replay v3 合同测试。
## 验证物理缓冲、A/B 转换与 Replay；物理层不再直接发出语义位移。

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

	# StageSession 依赖 Autoload，等 SceneTree 初始化完成后再加载回放桥。
	var driver: Node = load("res://src/runtime/replay/replay_input_driver.gd").new()
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
		if sample.kind == GameplayTypes.SemanticInputKind.LIFE_A_PRESSED:
			press_count += 1
		elif sample.kind == GameplayTypes.SemanticInputKind.LIFE_A_RELEASED:
			release_count += 1
			release_time_us = sample.timestamp_us
	_expect_equal(press_count, 1, "adjacent same-side sliders share one continuous press")
	_expect_equal(release_count, 1, "adjacent same-side sliders release only after the complete chain")
	_expect_equal(release_time_us, 1_001_000, "a slider without Su releases immediately after its authored endpoint")


func _test_input_map_contract() -> void:
	_expect(_joy_button(JOY_BUTTON_LEFT_SHOULDER, true).is_action_pressed(INPUT_BUFFER_SCRIPT.ACTION_DEATH), "L1 holds the death bell")
	_expect(_joy_button(JOY_BUTTON_RIGHT_SHOULDER, true).is_action_pressed(INPUT_BUFFER_SCRIPT.ACTION_LIFE), "R1 holds the life bell")
	_expect(_joy_button(JOY_BUTTON_LEFT_STICK, true).is_action_pressed(INPUT_BUFFER_SCRIPT.ACTION_DEATH), "L3 is an alternate left/death bell key")
	_expect(_joy_button(JOY_BUTTON_RIGHT_STICK, true).is_action_pressed(INPUT_BUFFER_SCRIPT.ACTION_LIFE), "R3 is an alternate right/life bell key")
	_expect(InputMap.has_action(INPUT_BUFFER_SCRIPT.ACTION_DEATH_TUNE_LEFT), "left-stick death-low action exists")
	_expect(InputMap.has_action(INPUT_BUFFER_SCRIPT.ACTION_DEATH_TUNE_RIGHT), "left-stick death-high action exists")
	_expect(InputMap.has_action(INPUT_BUFFER_SCRIPT.ACTION_LIFE_TUNE_LEFT), "right-stick life-low action exists")
	_expect(InputMap.has_action(INPUT_BUFFER_SCRIPT.ACTION_LIFE_TUNE_RIGHT), "right-stick life-high action exists")
	_expect(_joy_button(JOY_BUTTON_A, true).is_action_pressed(&"ui_accept"), "gamepad A remains menu confirm")
	_expect(_joy_button(JOY_BUTTON_B, true).is_action_pressed(&"ui_cancel"), "gamepad B remains menu cancel")
	_expect(_joy_button(JOY_BUTTON_START, true).is_action_pressed(INPUT_BUFFER_SCRIPT.ACTION_PAUSE), "gamepad Start remains pause")


func _test_rule_driven_tuning_parameters() -> void:
	var router: Node = INPUT_BUFFER_SCRIPT.new()
	root.add_child(router)
	var rules := GameplayRuleSet.new()
	rules.tuning_min_frequency_hz = 2.0
	rules.tuning_max_frequency_hz = 8.0
	rules.tuning_pixels_per_hz = 120.0
	rules.tuning_hz_per_revolution = 3.0
	router.configure_from_rules(rules)
	_expect_near(router.pointer_displacement_per_pixel,1.0/720.0,0.000001,"规则频率范围决定指针尺度")
	_expect_near(router.rotary_displacement_per_radian,3.0/(TAU*6.0),0.000001,"规则决定旋钮尺度")
	router.free()


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
	var router: Node = INPUT_BUFFER_SCRIPT.new()
	root.add_child(router)
	var events: Array[PhysicalInputEvent] = []
	router.physical_input_emitted.connect(func(event: PhysicalInputEvent): events.append(event))
	router._handle_bell_event(_mouse_button(MOUSE_BUTTON_LEFT,true))
	_expect(router.death_held and not router.life_held,"左键保持死钟")
	_expect_equal(events[-1].kind,GameplayTypes.PhysicalInputKind.MOUSE_LEFT_PRESSED,"缓冲保留精确物理键")
	var mapped := InputSemanticConverter.to_gameplay(events[-1])
	_expect_equal(mapped.event.kind,InputSemanticConverter.GameplayEvent.DEATH_A_PRESSED,"左键转换为死钟 A 通道")
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(72,20)
	_expect(not router._handle_tune_event(move),"调频场外不接收鼠标位移")
	router.set_tuning_capture_active(true)
	_expect(router._handle_tune_event(move),"场内接收鼠标位移")
	_expect_equal(events[-1].relative,Vector2(72,20),"物理层保留原始位移，留给会话转换")
	router.begin_frame(events[-1].timestamp_us)
	var first: Dictionary = router.query(GameplayTypes.PhysicalInputKind.MOUSE_MOVED)
	_expect(first.event == router.query(GameplayTypes.PhysicalInputKind.MOUSE_MOVED).event,"同帧查询复用最早事件")
	router.end_frame()
	_expect(not router.has_input(GameplayTypes.PhysicalInputKind.MOUSE_MOVED),"帧末消费已查询事件")
	router._handle_bell_event(_mouse_button(MOUSE_BUTTON_LEFT,false))
	_expect(not router.death_held,"松开左键释放死钟")
	router.free()


func _test_pause_menu_mouse_passthrough() -> void:
	var original_mouse_mode: Input.MouseMode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var router: Node = INPUT_BUFFER_SCRIPT.new()
	root.add_child(router)
	var samples: Array[PhysicalInputEvent] = []
	router.physical_input_emitted.connect(func(sample: PhysicalInputEvent) -> void: samples.append(sample))
	router.set_mode(INPUT_BUFFER_SCRIPT.InputMode.GAMEPLAY)
	router.set_tuning_capture_active(true)
	_expect(bool(router.get("_mouse_captured_by_router")), "active tuning owns mouse capture during gameplay")

	router.set_mode(INPUT_BUFFER_SCRIPT.InputMode.RESUME_REARM)
	_expect(not bool(router.get("_mouse_captured_by_router")), "opening the pause menu releases gameplay mouse ownership")
	_expect_equal(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "opening the pause menu restores a visible mouse cursor")
	var before_click: int = samples.size()
	router.call("_input", _mouse_button(MOUSE_BUTTON_LEFT, true))
	_expect_equal(samples.size(), before_click, "pause-menu click is not consumed as a bell strike before Button receives it")
	_expect(not router.death_held and not router.life_held, "pause-menu click does not alter gameplay hold state")

	router.set_mode(INPUT_BUFFER_SCRIPT.InputMode.GAMEPLAY)
	_expect(bool(router.get("_mouse_captured_by_router")), "resuming inside the tuning field restores gameplay mouse ownership")
	router.set_mode(INPUT_BUFFER_SCRIPT.InputMode.DISABLED)
	_expect_equal(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "leaving gameplay restores the original mouse mode")
	router.queue_free()
	Input.mouse_mode = original_mouse_mode


func _test_gamepad_rotary_routing() -> void:
	var router: Node = INPUT_BUFFER_SCRIPT.new()
	root.add_child(router)
	var events: Array[PhysicalInputEvent] = []
	router.physical_input_emitted.connect(func(event: PhysicalInputEvent): events.append(event))
	for pair in [[JOY_BUTTON_LEFT_SHOULDER,InputSemanticConverter.GameplayEvent.DEATH_A_PRESSED],
		[JOY_BUTTON_LEFT_STICK,InputSemanticConverter.GameplayEvent.DEATH_B_PRESSED],
		[JOY_BUTTON_RIGHT_SHOULDER,InputSemanticConverter.GameplayEvent.LIFE_A_PRESSED],
		[JOY_BUTTON_RIGHT_STICK,InputSemanticConverter.GameplayEvent.LIFE_B_PRESSED]]:
		router._handle_bell_event(_joy_button(pair[0],true))
		_expect_equal(InputSemanticConverter.to_gameplay(events[-1]).event.kind,pair[1],"手柄肩键/摇杆按键区分 A/B")
		router._handle_bell_event(_joy_button(pair[0],false))
	var left: PhysicalInputEvent = router._emit_joystick_event(GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED,2,Vector2(0.8,0.6))
	var right: PhysicalInputEvent = router._emit_joystick_event(GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED,3,Vector2(-0.6,0.8))
	_expect_equal(left.device_id,2,"左摇杆保留设备 ID")
	_expect_equal(right.axis_value,Vector2(-0.6,0.8),"右摇杆保留完整 X/Y 向量")
	_expect_equal(InputSemanticConverter.to_tuning_control(left).stick_side,InputSemanticConverter.StickSide.LEFT,"左杆映射独立控制侧")
	_expect_equal(InputSemanticConverter.to_tuning_control(right).stick_side,InputSemanticConverter.StickSide.RIGHT,"右杆映射独立控制侧")
	_expect_near(InputSemanticConverter.to_tuning_control(left).control_vector.length(),1.0,0.00001,"满幅二维输入保留完整幅度")
	router.free()


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

	# 物理缓冲只把当前可交互条交给 Tracker。未来预览既不能提前填充，也
	# 不能因为排在数组前面而抢走当前事件。
	var router: Node = INPUT_BUFFER_SCRIPT.new()
	root.add_child(router)
	var samples: Array[PhysicalInputEvent] = []
	router.physical_input_emitted.connect(func(sample: PhysicalInputEvent) -> void: samples.append(sample))
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
	_expect_equal(samples.size(), before_active_move, "历史旋钮追踪不重复发送已经采集的物理事件")
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
	var router: Node = INPUT_BUFFER_SCRIPT.new()
	root.add_child(router)
	var events: Array[PhysicalInputEvent] = []
	router.physical_input_emitted.connect(func(event: PhysicalInputEvent): events.append(event))
	router.set_tuning_capture_active(true)
	var upper := _touch(1,Vector2(200,100),true)
	var lower := _touch(2,Vector2(200,900),true)
	router._handle_touch_event(upper)
	router._handle_touch_event(lower)
	_expect(router.life_held and router.death_held,"两根手指分别保持两侧")
	router._handle_touch_event(_drag(1,Vector2(80,20)))
	_expect_equal(events[-1].touch_id,1,"触屏位移保留手指 ID")
	_expect_equal(events[-1].relative,Vector2(80,20),"触屏位移不提前转成另一套判定输入")
	router._handle_touch_event(_drag(2,Vector2(-60,20)))
	_expect_equal(events[-1].touch_id,2,"另一手指独立采样")
	router._handle_touch_event(_touch(1,upper.position,false))
	_expect(not router.life_held and router.death_held,"抬起上侧手指不释放下侧")
	router._handle_touch_event(_touch(2,lower.position,false))
	_expect(not router.life_held and not router.death_held,"两侧均可释放")
	router.free()


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
