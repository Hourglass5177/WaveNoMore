extends SceneTree

## 关卡运行时的综合接口测试。
## 覆盖时钟、输入、调度、表现接线和完整 StageRoot，是覆盖面最广的关卡运行时测试；
## 它不能代替真人手感与最终画面的验收。

## 生成测试节拍音轨的脚本；没有 `class_name`，因此必须显式预载。
const GRAYBOX_CLICK_TRACK_FACTORY: GDScript = preload("res://src/presentation/audio/graybox_click_track_factory.gd")
## Replay 录制器脚本；测试会直接实例化并检查输入序列与元数据。
const REPLAY_RECORDER_SCRIPT: GDScript = preload("res://src/runtime/replay/replay_recorder.gd")
## 演出调度器脚本；用于确认 StageShow cue 按歌曲时间触发。
const STAGE_SHOW_DIRECTOR_SCRIPT: GDScript = preload("res://src/runtime/director/stage_show_director.gd")

## 累计失败文本；单项失败不会中断后续运行时合同测试。
var _failures: PackedStringArray = []
## 已执行断言总数，用于确认测试确实走到了预期分支。
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# 前半部分测试独立部件，最后再实例化整张 StageRoot 做端到端检查。
	_test_song_clock_mapping()
	_test_graybox_click_track()
	_test_chart_scheduler_contract()
	_test_rapid_hud_contract()
	_test_mouse_tuning_projection()
	_test_gamepad_tuning_projection()
	_test_keyboard_bell_bindings()
	_test_coordinator_rearm_bridge()
	_test_tuning_auto_finish_runtime_cutoff()
	_test_physical_judgment_gate()
	_test_stage_show_director()
	_test_presentation_timing_cues()
	await _test_stage_root_contract()
	if _failures.is_empty():
		print("STAGE RUNTIME TESTS: %d checks passed." % _checks)
		quit(0)
		return
	printerr("STAGE RUNTIME TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
	for failure: String in _failures:
		printerr("  - " + failure)
	quit(1)


func _test_song_clock_mapping() -> void:
	var clock := SongClock.new()
	root.add_child(clock)
	clock.set_calibration(0.07, 0.025, 0.1)
	clock.configure(null, 2.0)
	_expect_near(clock.audio_calibration_sec, 0.07, 0.000001, "configure preserves preloaded audio calibration")
	_expect_near(clock.input_compensation_sec, 0.025, 0.000001, "configure preserves preloaded input calibration")
	_expect_near(clock.visual_lead_sec, 0.1, 0.000001, "configure preserves preloaded visual calibration")
	clock.audio_calibration_sec = 0.0
	clock.start(0.0, 1_000_000)
	_expect_near(clock.song_time_at_usec(1_500_000), -1.5, 0.000001, "SongClock subtracts first-beat offset")
	var calibrated_sample: ClockSample = clock.sample(1_600_000)
	_expect_near(calibrated_sample.visual_time_sec, -1.3, 0.000001, "positive visual lead maps presentation later without changing judgment")
	_expect_near(clock.song_time_at_usec(1_550_000), -1.45, 0.000001, "historical input capture is not clamped to latest frame")
	_expect_near(clock.judge_time_at_usec(1_550_000), -1.475, 0.000001, "positive input compensation maps input to earlier song time once")
	clock.pause(2_000_000)
	_expect_near(clock.song_time_at_usec(2_700_000), -1.0, 0.000001, "paused SongClock is frozen")
	clock.resume(3_000_000)
	_expect_near(clock.song_time_at_usec(3_500_000), -0.5, 0.000001, "resume excludes paused wall time")
	clock.stop(3_500_000)
	clock.audio_calibration_sec = 0.1
	clock.start(0.0, 4_000_000)
	_expect_near(clock.song_time_at_usec(4_000_000), -2.1, 0.000001, "positive audio calibration delays the system-clock origin")
	clock.stop(4_000_000)

	var player := AudioStreamPlayer.new()
	root.add_child(player)
	player.stream = GRAYBOX_CLICK_TRACK_FACTORY.create(0.5, 120.0, 0.0, 4)
	clock.configure(player, 0.0)
	clock.audio_calibration_sec = 0.0
	clock.start()
	var uncalibrated_audio: float = clock.sample().audio_time_raw_sec
	clock.audio_calibration_sec = 0.1
	var delayed_audio: float = clock.sample().audio_time_raw_sec
	_expect_near(delayed_audio - uncalibrated_audio, -0.1, 0.01, "positive audio calibration shifts observed audio time earlier by the same sign convention")
	clock.stop()
	player.stream = null
	player.queue_free()
	clock.queue_free()


func _test_graybox_click_track() -> void:
	var stream: AudioStreamWAV = GRAYBOX_CLICK_TRACK_FACTORY.create(1.0, 120.0, 0.25, 4)
	_expect(stream != null, "graybox click track is generated")
	_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS, "graybox click track uses PCM16")
	_expect(stream.mix_rate == GRAYBOX_CLICK_TRACK_FACTORY.SAMPLE_RATE, "graybox click track has deterministic sample rate")
	_expect_near(stream.get_length(), 1.0, 0.001, "graybox click track matches fallback duration")
	var first_nonzero_byte: int = -1
	for index: int in range(stream.data.size()):
		if stream.data[index] != 0:
			first_nonzero_byte = index
			break
	var first_sound_sec: float = float(first_nonzero_byte / 2) / float(stream.mix_rate)
	_expect(first_nonzero_byte >= 0, "graybox click track is audible")
	_expect(first_sound_sec >= 0.249 and first_sound_sec <= 0.252, "first click follows first-beat offset")
	var late_offset_stream: AudioStreamWAV = GRAYBOX_CLICK_TRACK_FACTORY.create(0.5, 120.0, 2.0, 4)
	_expect(_stream_has_signal(late_offset_stream), "fallback BGM remains audible when first beat lies beyond its graybox duration")


func _test_chart_scheduler_contract() -> void:
	var rules := DomainFixtureFactory.rules()
	var compile_result: Dictionary = ChartCompiler.compile(DomainFixtureFactory.all_mechanics_chart(), rules, 0)
	_expect(bool(compile_result.get("ok", false)), "scheduler fixture compiles")
	if not bool(compile_result.get("ok", false)):
		return
	var scheduler := ChartScheduler.new()
	root.add_child(scheduler)
	var spawned: Array[Dictionary] = []
	scheduler.visual_spawn_requested.connect(func(kind: StringName, data: Dictionary) -> void:
		spawned.append({"kind": kind, "data": data})
	)
	scheduler.configure(compile_result["compiled"], 0.1)
	scheduler.advance(0.41, 0.41)
	_expect(not spawned.is_empty(), "scheduler spawns canonical start_us events in lookahead")
	if not spawned.is_empty():
		_expect_equal(spawned[0]["data"].get("event_id"), "tap_zhu", "scheduler keeps stable event ID")
	scheduler.advance(5.0, 5.0)
	var tuning_spawn_count: int = 0
	var tuning_ids: Array[String] = []
	for entry: Dictionary in spawned:
		if entry["kind"] != ChartScheduler.KIND_TUNING:
			continue
		tuning_spawn_count += 1
		tuning_ids.append(str((entry["data"] as Dictionary).get("event_id", "")))
	tuning_ids.sort()
	_expect_equal(spawned.size(), 7, "scheduler presents Tap/chord/Hold/two independent sliders/Rapid without judging")
	_expect_equal(tuning_spawn_count, 2, "scheduler creates one visual event for each side of a dual tuning group")
	_expect_equal(tuning_ids, ["tuning_01_death", "tuning_01_life"], "scheduler preserves both independent slider IDs")
	scheduler.queue_free()


func _test_rapid_hud_contract() -> void:
	var visual := GrayboxFieldVisual.new()
	visual.field_kind = 1
	root.add_child(visual)
	visual.prepare({
		"event_id": "rapid_hud_test",
		"duration_ticks": 480,
		"duration_us": 1_000_000,
		"required_strikes": 10,
		"must_alternate": true,
	})
	var idle: Dictionary = visual.visual_state_snapshot()
	_expect(bool(idle["rapid_hud_only"]), "rapid center visual declares that it is functional HUD only")
	_expect_equal(int(idle["rapid_static_wave_count"]), 0, "rapid preview cannot fabricate static wave shells")
	_expect_equal(int(idle["rapid_valid_strikes"]), 0, "rapid preview starts with no implied player strikes")
	visual.set_rapid_ratio(0.6)
	var progressed: Dictionary = visual.visual_state_snapshot()
	_expect_equal(int(progressed["rapid_valid_strikes"]), 6, "rapid HUD converts authoritative ratio into a readable strike count")
	visual.queue_free()


func _test_mouse_tuning_projection() -> void:
	var router := InputRouter.new()
	root.add_child(router)
	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	var blocked_motion := InputEventMouseMotion.new()
	blocked_motion.relative = Vector2(20.0, 0.0)
	_expect(not bool(router.call("_handle_tune_event", blocked_motion)), "mouse tuning is ignored outside an authored tuning region")
	router.call("_handle_bell_event", _mouse_button_event(MOUSE_BUTTON_LEFT, true))
	_expect(router.death_held and not router.life_held, "left mouse can hold the death bell by itself")
	router.set_tuning_capture_active(true)
	var one_pixel_motion := InputEventMouseMotion.new()
	one_pixel_motion.relative = Vector2(1.0, 80.0)
	_expect(bool(router.call("_handle_tune_event", one_pixel_motion)), "tuning capture consumes a one-pixel mouse motion")
	_expect_equal(samples[-1].kind, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, "mouse emits relative displacement instead of an absolute shared cursor")
	_expect_near(samples[-1].tune_vector.x, 0.0, 0.00001, "left mouse cannot move the life channel")
	_expect_near(samples[-1].tune_vector.y, router.pointer_displacement_per_pixel, 0.0001, "mouse tuning responds on the first pixel without an analog deadzone")
	router.call("_handle_bell_event", _mouse_button_event(MOUSE_BUTTON_RIGHT, true))
	router.call("_handle_tune_event", blocked_motion)
	_expect_near(samples[-1].tune_vector.x, samples[-1].tune_vector.y, 0.00001, "dual mouse hold applies one test delta to both independent channels")
	router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	router.queue_free()


func _test_gamepad_tuning_projection() -> void:
	var router := InputRouter.new()
	root.add_child(router)
	var samples: Array[SemanticInputSample] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void: samples.append(sample))
	router.set_tuning_capture_active(true)
	router.set_tuning_gesture_windows([
		{"event_id": "life_window", "affinity": GameplayTypes.Affinity.ZHU, "start_value": 0.333333, "end_value": 0.666667},
		{"event_id": "death_window", "affinity": GameplayTypes.Affinity.XUAN, "start_value": 0.333333, "end_value": 0.0},
	])
	var l1 := _joy_button_event(JOY_BUTTON_LEFT_SHOULDER, true)
	l1.device = 0
	router.call("_handle_bell_event", l1)
	var r1 := _joy_button_event(JOY_BUTTON_RIGHT_SHOULDER, true)
	r1.device = 0
	router.call("_handle_bell_event", r1)
	var windows: Dictionary = router.tuning_gesture_window_snapshot()
	var life_window: Dictionary = windows["life"]
	var death_window: Dictionary = windows["death"]
	var life_upper_left := Vector2.from_angle(float(life_window["start_angle_rad"]))
	var life_upper_right := Vector2.from_angle(float(life_window["end_angle_rad"]))
	var death_lower_right := Vector2.from_angle(float(death_window["start_angle_rad"]))
	var death_lower_left := Vector2.from_angle(float(death_window["end_angle_rad"]))
	router.call("_process_rotary_sticks", 0, life_upper_left, 0, death_lower_right)
	var anchored_count: int = samples.size()
	router.call("_process_rotary_sticks", 0, life_upper_right, 0, death_lower_left)
	_expect_equal(samples.size(), anchored_count + 1, "two complete stick vectors produce one combined rotary sample")
	_expect(samples[-1].tune_vector.x > 0.0 and samples[-1].tune_vector.y < 0.0, "clockwise upper-left/right and lower-right/left gestures follow the mirrored frequency axes")
	_expect_near(samples[-1].tune_vector.x, -samples[-1].tune_vector.y, 0.00001, "equal simultaneous rotations keep full mirrored magnitudes")
	var held_count: int = samples.size()
	router.call("_process_rotary_sticks", 0, life_upper_right, 0, death_lower_left)
	_expect_equal(samples.size(), held_count, "holding a pushed stick still produces no displacement")
	router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	router.queue_free()


func _test_keyboard_bell_bindings() -> void:
	var router := InputRouter.new()
	root.add_child(router)
	var semantic_kinds: Array[int] = []
	router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void:
		semantic_kinds.append(sample.kind)
	)
	var f_press := _key_event(KEY_F, true)
	var f_release := _key_event(KEY_F, false)
	var j_press := _key_event(KEY_J, true)
	var j_release := _key_event(KEY_J, false)
	_expect(f_press.is_action_pressed(InputRouter.ACTION_DEATH), "F is mapped to the spatially left death bell action")
	_expect(j_press.is_action_pressed(InputRouter.ACTION_LIFE), "J is mapped to the spatially right life bell action")
	_expect(_key_event(KEY_LEFT, true).is_action_pressed(InputRouter.ACTION_DEATH), "left-arrow fallback maps to the death bell")
	_expect(_key_event(KEY_RIGHT, true).is_action_pressed(InputRouter.ACTION_LIFE), "right-arrow fallback maps to the life bell")
	_expect(_mouse_button_event(MOUSE_BUTTON_LEFT, true).is_action_pressed(InputRouter.ACTION_DEATH), "left mouse maps to the lower-left death stream")
	_expect(_mouse_button_event(MOUSE_BUTTON_RIGHT, true).is_action_pressed(InputRouter.ACTION_LIFE), "right mouse maps to the upper-right life stream")
	_expect(_joy_button_event(JOY_BUTTON_LEFT_SHOULDER, true).is_action_pressed(InputRouter.ACTION_DEATH), "left shoulder maps to the death bell")
	_expect(_joy_button_event(JOY_BUTTON_RIGHT_SHOULDER, true).is_action_pressed(InputRouter.ACTION_LIFE), "right shoulder maps to the life bell")
	_expect(_joy_button_event(JOY_BUTTON_A, true).is_action_pressed(&"ui_accept"), "gamepad A maps to menu confirm")
	_expect(_joy_button_event(JOY_BUTTON_B, true).is_action_pressed(&"ui_cancel"), "gamepad B maps to menu cancel")
	_expect(_joy_button_event(JOY_BUTTON_START, true).is_action_pressed(InputRouter.ACTION_PAUSE), "gamepad Start maps to pause")
	router.call("_handle_bell_event", f_press)
	router.call("_handle_bell_event", j_press)
	_expect(router.life_held and router.death_held, "F then J establishes a dual hold")
	router.call("_handle_bell_event", f_release)
	_expect(router.life_held and not router.death_held, "releasing F clears only the death bell")
	router.call("_handle_bell_event", j_release)
	_expect_equal(
		semantic_kinds,
		[
			GameplayTypes.SemanticInputKind.DEATH_PRESSED,
			GameplayTypes.SemanticInputKind.LIFE_PRESSED,
			GameplayTypes.SemanticInputKind.DEATH_RELEASED,
			GameplayTypes.SemanticInputKind.LIFE_RELEASED,
		],
		"spatially reversed F/J press and release preserve semantic order"
	)
	router.reset_for_run()
	semantic_kinds.clear()
	router.call("_handle_bell_event", j_press)
	router.call("_handle_bell_event", f_press)
	_expect(router.life_held and router.death_held, "J then F also establishes a dual hold")
	_expect_equal(
		semantic_kinds,
		[GameplayTypes.SemanticInputKind.LIFE_PRESSED, GameplayTypes.SemanticInputKind.DEATH_PRESSED],
		"J then F follows right-life then left-death deterministically"
	)
	router.call("_handle_bell_event", f_release)
	router.call("_handle_bell_event", j_release)
	router.queue_free()


## 构造不经操作系统的键盘事件，让 InputRouter 的按下/松开映射可重复测试。
func _key_event(key: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	return event


## 构造鼠标按键事件，验证 PC 临时操作与键盘/手柄共用同一语义输入。
func _mouse_button_event(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


## 构造手柄按钮事件，不依赖测试机器实际连接控制器。
func _joy_button_event(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


## 构造语义动作事件，配合 `Input.action_press()` 测试摇杆归一化而不依赖真实手柄。
func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _test_coordinator_rearm_bridge() -> void:
	var rules := DomainFixtureFactory.rules()
	var compiled: CompiledChart = ChartCompiler.compile(DomainFixtureFactory.all_mechanics_chart(), rules, 0)["compiled"]
	var coordinator := GameplayCoordinator.new()
	root.add_child(coordinator)
	_expect(coordinator.configure(compiled, rules), "GameplayCoordinator configures shared simulation")
	var capture_states: Array[bool] = []
	coordinator.tuning_capture_changed.connect(func(active: bool, _value: Vector2) -> void: capture_states.append(active))
	var tuning_start_us: int = int(compiled.tuning_fields[0]["start_us"])
	coordinator.advance_to(tuning_start_us, true)
	_expect(bool(coordinator.snapshot().get("tuning_field_active", false)), "authored field opens tuning capture without requiring a dual press")
	_expect(not capture_states.is_empty() and capture_states[-1], "coordinator capture follows tuning_field_active")
	coordinator.accept_input(SemanticInputSample.create(tuning_start_us, 0, GameplayTypes.SemanticInputKind.LIFE_PRESSED))
	coordinator.accept_input(SemanticInputSample.create(tuning_start_us, 1, GameplayTypes.SemanticInputKind.DEATH_PRESSED))
	_expect(bool(coordinator.snapshot().get("tuning_field_active", false)), "holding both bells does not replace the authored field gate")
	coordinator.begin_pause_rearm()
	_expect(not capture_states.is_empty() and not capture_states[-1], "pause rearm releases mouse tuning capture")
	coordinator.apply_resume_rearm({"life_held": true, "death_held": true})
	_expect(not capture_states.is_empty() and capture_states[-1], "resume rearm restores field capture without requiring new bell presses")
	var tuning_end_us: int = int(compiled.tuning_fields[0]["end_us"])
	coordinator.advance_to(tuning_end_us, true)
	_expect(not bool(coordinator.snapshot().get("tuning_field_active", true)), "capture closes at the authored final endpoint")
	_expect(not capture_states.is_empty() and not capture_states[-1], "coordinator broadcasts capture release after endpoint judgment")
	coordinator.queue_free()


func _test_tuning_auto_finish_runtime_cutoff() -> void:
	var rules := DomainFixtureFactory.rules()
	var chart := DomainFixtureFactory.tuning_only_chart()
	chart.end_tick = 960
	var compile_result: Dictionary = ChartCompiler.compile(chart, rules, 0)
	_expect(bool(compile_result.get("ok", false)), "end-aligned tuning fixture compiles")
	if not bool(compile_result.get("ok", false)):
		return
	var song := SongDefinition.new()
	song.first_beat_offset_sec = 0.0
	song.fallback_duration_sec = 1.0
	var stage := StageDefinition.new()
	stage.song = song
	var session := StageSession.new()
	var clock := SongClock.new()
	clock.input_compensation_sec = 0.025
	session.stage_definition = stage
	session.compiled_chart = compile_result["compiled"]
	session.rule_set = rules
	session.song_clock = clock
	_expect_near(
		float(session.call("_calculate_end_song_time_sec")),
		1.0,
		0.000001,
		"StageSession ends tuning at its authored endpoint without an extra late window"
	)
	clock.free()
	session.free()


func _test_physical_judgment_gate() -> void:
	var session := StageSession.new()
	var scheduler := ChartScheduler.new()
	root.add_child(scheduler)
	root.add_child(session)
	session.chart_scheduler = scheduler
	var presented: Array[JudgmentRecord] = []
	var timing_confirmed: Array[Dictionary] = []
	var visually_judged: Array[Dictionary] = []
	session.judgment_presented.connect(func(record: JudgmentRecord) -> void: presented.append(record))
	scheduler.visual_timing_confirmed.connect(func(event_id: String, grade: int) -> void:
		timing_confirmed.append({"event_id": event_id, "grade": grade})
	)
	scheduler.visual_judged.connect(func(event_id: String, grade: int) -> void:
		visually_judged.append({"event_id": event_id, "grade": grade})
	)

	var paired_tuning := JudgmentRecord.new()
	paired_tuning.unit_id = "paired_tuning_group"
	paired_tuning.unit_kind = &"tuning"
	paired_tuning.grade = GameplayTypes.JudgmentGrade.GOOD
	paired_tuning.metadata = {
		"sides": {
			"life": {"event_id": "life_slider"},
			"death": {"event_id": "death_slider"},
		}
	}
	session.call("_on_judgment_recorded", paired_tuning)
	_expect_equal(
		visually_judged.map(func(item: Dictionary) -> String: return str(item["event_id"])),
		["life_slider", "death_slider"],
		"paired tuning result reaches both independently registered slider visuals"
	)
	# 后续断言专门检查普通音符的延迟演出，先移除上面的调频演出记录。
	presented.clear()

	var hit := JudgmentRecord.new()
	hit.unit_id = "wave_gated_hit"
	hit.unit_kind = &"tap"
	hit.grade = GameplayTypes.JudgmentGrade.PERFECT
	scheduler.call("_spawn", ChartScheduler.KIND_NOTE, {"id": hit.unit_id, "unit_kind": &"tap"}, 0)
	session.call("_on_judgment_recorded", hit)
	_expect_equal(timing_confirmed.size(), 1, "ordinary timing acceptance confirms the target immediately")
	_expect_equal(presented.size(), 0, "ordinary timing acceptance does not present a hit before wave contact")
	session.call("_on_wave_contacted", {"note_id": hit.unit_id, "contact_us": 1000})
	_expect_equal(presented.size(), 1, "ordinary hit feedback is presented exactly when the physical wave contacts")

	var miss := JudgmentRecord.new()
	miss.unit_id = "wave_gated_miss"
	miss.unit_kind = &"tap"
	miss.grade = GameplayTypes.JudgmentGrade.MISS
	scheduler.call("_spawn", ChartScheduler.KIND_NOTE, {"id": miss.unit_id, "unit_kind": &"tap"}, 1)
	session.call("_on_judgment_recorded", miss)
	_expect_equal(timing_confirmed.size(), 2, "ordinary Miss is signalled immediately while its threat keeps travelling")
	_expect_equal(presented.size(), 1, "ordinary Miss feedback waits while the unopposed note keeps travelling")
	session.call("_on_note_arrived", {"note_id": miss.unit_id, "arrival_us": 2000})
	_expect_equal(presented.size(), 2, "ordinary Miss feedback is presented when the note reaches its bell")

	var contacted_hold_miss := JudgmentRecord.new()
	contacted_hold_miss.unit_id = "contacted_hold_tail_miss"
	contacted_hold_miss.unit_kind = &"hold"
	contacted_hold_miss.grade = GameplayTypes.JudgmentGrade.MISS
	scheduler.call("_spawn", ChartScheduler.KIND_NOTE, {"id": contacted_hold_miss.unit_id, "unit_kind": &"hold"}, 2)
	session.call("_on_wave_contacted", {"note_id": contacted_hold_miss.unit_id, "contact_us": 3000})
	_expect_equal(presented.size(), 2, "Hold head contact alone waits for the final tail grade")
	session.call("_on_judgment_recorded", contacted_hold_miss)
	_expect_equal(presented.size(), 3, "Hold head success plus tail Miss presents on its existing physical contact path")

	var short_hold_miss := JudgmentRecord.new()
	short_hold_miss.unit_id = "short_hold_tail_miss"
	short_hold_miss.unit_kind = &"hold"
	short_hold_miss.grade = GameplayTypes.JudgmentGrade.MISS
	scheduler.call("_spawn", ChartScheduler.KIND_NOTE, {"id": short_hold_miss.unit_id, "unit_kind": &"hold"}, 3)
	session.call("_on_judgment_recorded", short_hold_miss)
	_expect_equal(presented.size(), 3, "a very short Hold can finalize before its scheduled wave contact")
	session.call("_on_wave_contacted", {"note_id": short_hold_miss.unit_id, "contact_us": 4000})
	_expect_equal(presented.size(), 4, "a later Hold contact releases an already deferred tail Miss")
	scheduler.mark_timing_confirmed("not_an_active_note", GameplayTypes.JudgmentGrade.PERFECT)
	_expect_equal(timing_confirmed.size(), 4, "timing confirmation ignores stale or unknown presentation ids")

	session.queue_free()
	scheduler.queue_free()


func _test_stage_show_director() -> void:
	var chart := DomainFixtureFactory.base_chart("director", 2400)
	var map := TempoMap.from_chart(chart)
	var show := StageShow.new()
	show.show_id = "director_test"
	show.cues = [
		_make_cue("cue_a", 480, 0, 5, &"tutorial_a"),
		_make_cue("cue_b", 960, 480, 3, &"rift_b"),
		_make_cue("cue_c", 1920, 0, 1, &"world_c"),
	]
	var director: Node = STAGE_SHOW_DIRECTOR_SCRIPT.new()
	root.add_child(director)
	var triggered: Array[String] = []
	var started: Array[String] = []
	var ended: Array[String] = []
	director.connect("cue_triggered", func(cue: Dictionary) -> void: triggered.append(String(cue["event_id"])))
	director.connect("cue_started", func(cue: Dictionary) -> void: started.append(String(cue["event_id"])))
	director.connect("cue_ended", func(cue: Dictionary) -> void: ended.append(String(cue["event_id"])))
	director.call("configure", show, map)
	director.call("advance_to_us", map.tick_to_us(2100))
	_expect_equal(triggered, ["cue_a", "cue_b", "cue_c"], "director does not miss cues crossed in one large frame")
	_expect_equal(started, ["cue_b"], "duration cue starts once across a large frame")
	_expect_equal(ended, ["cue_b"], "duration cue ends once across a large frame")
	director.call("advance_to_us", map.tick_to_us(2300))
	_expect_equal(triggered.size(), 3, "director does not repeat cues on later frames")
	director.call("reset")
	director.call("advance_to_us", map.tick_to_us(2100))
	_expect_equal(triggered.size(), 6, "director reset makes retry cues replay deterministically")
	director.call("seek_us", map.tick_to_us(1200))
	var active: Array = director.call("get_active_cues")
	_expect_equal(active.size(), 1, "director seek reconstructs an in-progress duration cue")
	if not active.is_empty():
		_expect_equal(active[0]["event_id"], "cue_b", "seek reconstruction keeps stable cue ID")
	director.queue_free()


func _test_presentation_timing_cues() -> void:
	var backdrop := GrayboxBackdrop.new()
	var boundary: PackedVector2Array = backdrop.call("_boundary_points")
	_expect_equal(boundary.size(), 33, "flat divider keeps enough samples for art replacement")
	for point: Vector2 in boundary:
		_expect_near(point.y, 540.0, 0.00001, "default life/death divider is exactly horizontal")
	backdrop.free()

	var ring_scene := load("res://scenes/presentation/notes/default_timing_ring.tscn") as PackedScene
	var ring := ring_scene.instantiate() as TimingRingVisual
	root.add_child(ring)
	ring.prepare({"event_id": "ring_test", "affinity": GameplayTypes.Affinity.ZHU, "tail_requires_release": true})
	ring.set_timing(2.25, 2.25)
	_expect_near(float(ring.get("_progress")), 0.0, 0.00001, "timing ring starts empty at lookahead spawn")
	ring.set_timing(1.125, 2.25)
	_expect_near(float(ring.get("_progress")), 0.5, 0.00001, "timing ring is half closed halfway to hit")
	ring.set_timing(0.0, 2.25)
	_expect_near(float(ring.get("_progress")), 1.0, 0.00001, "timing ring closes exactly at hit time")
	ring.set_timing(2.25, 2.25)
	_expect_near(float(ring.get("_progress")), 0.0, 0.00001, "timing ring recomputes correctly after backward seek")
	ring.set_sustain_progress(0.4)
	_expect_near(float(ring.get("_progress")), 0.4, 0.00001, "Hold release ring follows absolute sustain progress")
	_expect(bool(ring.get("_sustain_mode")), "Hold release ring is distinguishable from its head cue")
	ring.free()

	var tuning_scene := load("res://scenes/presentation/fields/graybox_tuning_field.tscn") as PackedScene
	var life_slider := tuning_scene.instantiate() as GrayboxFieldVisual
	root.add_child(life_slider)
	life_slider.prepare({
		"event_id": "tuning_visual_life",
		"group_id": "tuning_visual_pair",
		"affinity": GameplayTypes.Affinity.ZHU,
		"tick": 480,
		"traversal_ticks": 960,
		"traversal_count": 1,
		"duration_ticks": 960,
		"duration_us": 1_000_000,
		"start_value": 0.20,
		"end_value": 0.70,
	})
	life_slider.set_region_progress(0.5)
	# 缩圈属于未来滑条的独立起手提示：轨道可以退后，但提示本身必须始终清楚。
	life_slider.set_preview_presentation(1, 1, 0.70)
	life_slider.set_approach_timing(2.25, 2.25)
	var cue_early: Dictionary = life_slider.visual_state_snapshot()
	life_slider.set_approach_timing(1.125, 2.25)
	var cue_middle: Dictionary = life_slider.visual_state_snapshot()
	life_slider.set_approach_timing(0.225, 2.25)
	var cue_late: Dictionary = life_slider.visual_state_snapshot()
	_expect(bool(cue_early["start_cue_visible"]), "future slider exposes its start cue during preview")
	_expect(
		float(cue_early["start_cue_radius_px"]) > float(cue_middle["start_cue_radius_px"])
		and float(cue_middle["start_cue_radius_px"]) > float(cue_late["start_cue_radius_px"]),
		"start cue closes monotonically as the hit time approaches"
	)
	_expect(
		float(cue_early["start_cue_radius_px"]) - float(cue_late["start_cue_radius_px"]) >= 60.0,
		"start cue travels far enough to remain obvious on a 104px rail"
	)
	_expect(float(cue_early["start_cue_progress_stroke_px"]) >= 8.0, "start cue keeps a readable high-contrast stroke")
	life_slider.set_approach_timing(1.125, 2.25)
	life_slider.set_gameplay_snapshot({
		"tuning_field_active": true,
		"life_held": true,
		"death_held": false,
		"active_tuning_sliders": [{
			"event_id": "tuning_visual_life",
			"player_progress": 0.52,
			"guide_progress": 0.55,
			"guide_band_min": 0.43,
			"guide_band_max": 0.67,
			"held": true,
			"required_rotation_sign": 1,
			"endpoint_target_progress": 1.0,
			"endpoint_inside": false,
			"endpoint_captured": false,
			"endpoint_window_active": true,
			"endpoint_grade": GameplayTypes.JudgmentGrade.MISS,
			"endpoint_best_error_us": 0,
		}],
	})
	var life_state: Dictionary = life_slider.visual_state_snapshot()
	_expect(not bool(life_state["start_cue_visible"]), "start cue disappears once the slider becomes interactive")
	var expected_chord_px: float = 3.0 * 160.0
	var expected_center_distance_px: float = TuningArcGeometry.equivalent_center_distance_px(1920.0)
	var expected_sweep_rad: float = TuningArcGeometry.equivalent_sweep_from_chord_rad(
		expected_chord_px,
		expected_center_distance_px
	)
	var expected_radius_px: float = TuningArcGeometry.equivalent_radius_from_chord_px(
		expected_chord_px,
		expected_sweep_rad
	)
	var expected_arc_length_px: float = expected_radius_px * expected_sweep_rad
	_expect_near(float(life_slider.tuning_rail_width), 104.0, 0.001, "tuning uses the wide osu-style rail")
	_expect_near(float(life_slider.tuning_outline_width), 8.0, 0.001, "tuning keeps one restrained outer outline")
	_expect_near(float(life_state["slider_chord_px"]), expected_chord_px, 0.001, "Hz span fixes the visible endpoint distance")
	_expect_near(float(life_state["slider_length_px"]), expected_arc_length_px, 0.01, "the equivalent circle derives the real rail length from its chord")
	_expect_near(float(life_state["curve_length_px"]), expected_arc_length_px, 0.08, "the rendered rail follows the shared equivalent circle")
	_expect_equal(int(life_state["curve_sample_count"]), 49, "equivalent-circle curve uses one stable sample budget")
	_expect_near(float(life_state["arc_span_rad"]), expected_sweep_rad, 0.0001, "the visible rail and stick gesture share one expanded central angle")
	_expect_near(float(life_state["rail_radius"]), expected_radius_px, 0.1, "arc radius reconstructs the authored chord")
	_expect_near(float(life_state["equivalent_center_distance_px"]), expected_center_distance_px, 0.1, "the rail uses the shared equivalent-circle centre distance")
	_expect_near(float(life_state["guide_min_progress"]), 0.43, 0.00001, "visual guide range reads the authoritative lower edge")
	_expect_near(float(life_state["guide_max_progress"]), 0.67, 0.00001, "visual guide range reads the authoritative upper edge")
	_expect_near(float(life_state["player_progress"]), 0.52, 0.00001, "player fill reads this slider's independent accumulated displacement")
	_expect_near(float(life_state["fill_progress"]), 0.52, 0.00001, "the filled portion ends exactly at player progress")
	_expect(int(life_state["guide_dot_count"]) > 1, "time guidance grows as a sparse dotted trail instead of a solid band")
	_expect_equal(int(life_state["required_rotation_sign"]), 1, "visual consumes the domain-provided clockwise cue")
	var life_cue_start: Vector2 = life_state["rotation_cue_start_direction"]
	var life_cue_end: Vector2 = life_state["rotation_cue_end_direction"]
	_expect(life_cue_start.x < 0.0 and life_cue_start.y < 0.0, "Life clockwise cue starts at the upper-left stick direction")
	_expect(life_cue_end.x > 0.0 and life_cue_end.y < 0.0, "Life clockwise cue ends at the upper-right stick direction")
	_expect_near(float(life_state["rotation_cue_sweep_rad"]), expected_sweep_rad, 0.0001, "rotation cue sweep equals the expanded finite gesture")
	_expect(not life_state.has("coverage"), "slider presentation no longer carries obsolete continuous coverage")
	_expect(bool(life_state["endpoint_window_active"]), "slider presentation exposes the current endpoint timing window")
	_expect(bool(life_state["inside_guide"]) and bool(life_state["tuning_active"]), "held cursor inside the visible band receives immediate alignment feedback")
	_expect_equal(int(life_state["target_count"]), 0, "coarse slider contains no hidden Su checkpoints or along-track ticks")
	_expect_near(float(life_state["approach_progress"]), 0.5, 0.00001, "slider head cue closes from absolute time-to-start")
	var active_cursor_point: Vector2 = life_state["current_cursor_point"]
	var cursor_before_time_advance: Vector2 = active_cursor_point
	life_slider.set_region_progress(0.8)
	var cursor_after_time_advance: Vector2 = life_slider.visual_state_snapshot()["current_cursor_point"]
	_expect_near(cursor_before_time_advance.distance_to(cursor_after_time_advance), 0.0, 0.00001, "song time moves only the guide; it never drags the player's fill")
	life_slider.set_slider_state({"player_progress": 0.24, "required_rotation_sign": -1})
	var rolled_back_state: Dictionary = life_slider.visual_state_snapshot()
	_expect_near(float(rolled_back_state["fill_progress"]), 0.24, 0.00001, "reverse rotation removes fill immediately instead of leaving a travelled trail")
	_expect_equal(int(rolled_back_state["required_rotation_sign"]), -1, "rotation cue flips without the presentation guessing direction")

	var death_slider := tuning_scene.instantiate() as GrayboxFieldVisual
	root.add_child(death_slider)
	death_slider.prepare({
		"event_id": "tuning_visual_death",
		"group_id": "tuning_visual_pair",
		"affinity": GameplayTypes.Affinity.XUAN,
		"tick": 480,
		"traversal_ticks": 480,
		"traversal_count": 2,
		"duration_ticks": 960,
		"duration_us": 1_000_000,
		"start_value": 0.20,
		"end_value": 0.70,
	})
	death_slider.set_region_progress(0.5)
	death_slider.set_gameplay_snapshot({
		"tuning_field_active": true,
		"life_held": true,
		"death_held": false,
		"active_tuning_sliders": [{
			"event_id": "tuning_visual_death",
			"player_progress": 0.18,
			"guide_progress": 1.0,
			"guide_band_min": 0.88,
			"guide_band_max": 1.0,
			"held": false,
			"required_rotation_sign": -1,
		}],
	})
	var death_state: Dictionary = death_slider.visual_state_snapshot()
	var life_center: Vector2 = ((life_state["slider_start_point"] as Vector2) + (life_state["slider_end_point"] as Vector2)) * 0.5
	var death_center: Vector2 = ((death_state["slider_start_point"] as Vector2) + (death_state["slider_end_point"] as Vector2)) * 0.5
	_expect(life_center.distance_to(-death_center) <= 0.001, "life and death rails occupy center-symmetric operation-side slots")
	_expect(life_center.x > 0.0 and life_center.y < 0.0, "right-stick Life rail appears in the upper-right operation area")
	_expect(death_center.x < 0.0 and death_center.y > 0.0, "left-stick Death rail appears in the lower-left operation area")
	var outer_radius: float = life_slider.tuning_rail_width * 0.5 + life_slider.tuning_outline_width
	var life_min_x: float = INF
	var life_max_x: float = -INF
	var death_min_x: float = INF
	var death_max_x: float = -INF
	for point: Vector2 in life_state["curve_points"]:
		life_min_x = minf(life_min_x, point.x)
		life_max_x = maxf(life_max_x, point.x)
	for point: Vector2 in death_state["curve_points"]:
		death_min_x = minf(death_min_x, point.x)
		death_max_x = maxf(death_max_x, point.x)
	_expect_near(life_min_x - outer_radius, 32.0, 0.1, "Life rail outline begins exactly beyond the central gutter")
	_expect_near(death_max_x + outer_radius, -32.0, 0.1, "Death rail outline ends exactly before the central gutter")
	var safe_edge_x: float = life_slider.canvas_size.x * 0.5 - life_slider.slider_edge_margin_px
	_expect(life_max_x + outer_radius <= safe_edge_x + 0.1, "Life rail keeps the 72px screen-edge margin")
	_expect(death_min_x - outer_radius >= -safe_edge_x - 0.1, "Death rail keeps the 72px screen-edge margin")
	_expect(not bool(death_state["tuning_active"]), "one side may be inactive while the opposite slider remains held and aligned")
	_expect_near(float(death_state["player_progress"]), 0.18, 0.00001, "death cursor keeps its own state instead of copying the life cursor")
	_expect_equal(int(death_state["traversal_count"]), 2, "round-trip slider retains one explicit reversal without adding intermediate targets")
	_expect_near(float(death_slider.call("_turnaround_pulse")), 1.0, 0.00001, "round-trip endpoint emits one restrained turnaround pulse")
	var death_rising_start: Vector2 = death_state["rotation_cue_start_direction"]
	var death_rising_end: Vector2 = death_state["rotation_cue_end_direction"]
	_expect(death_rising_start.x < 0.0 and death_rising_start.y > 0.0, "Death counter-clockwise cue starts at the lower-left stick direction")
	_expect(death_rising_end.x > 0.0 and death_rising_end.y > 0.0, "Death counter-clockwise cue ends at the lower-right stick direction")
	death_slider.set_slider_state({"required_rotation_sign": 1})
	var death_falling_state: Dictionary = death_slider.visual_state_snapshot()
	var death_falling_start: Vector2 = death_falling_state["rotation_cue_start_direction"]
	var death_falling_end: Vector2 = death_falling_state["rotation_cue_end_direction"]
	_expect(death_falling_start.x > 0.0 and death_falling_start.y > 0.0, "Death clockwise cue starts at the lower-right stick direction")
	_expect(death_falling_end.x < 0.0 and death_falling_end.y > 0.0, "Death clockwise cue ends at the lower-left stick direction")
	var life_curve: PackedVector2Array = life_state["curve_points"]
	var death_curve: PackedVector2Array = death_state["curve_points"]
	var curves_are_center_symmetric: bool = life_curve.size() == death_curve.size()
	for index: int in range(life_curve.size()):
		if life_curve[index].distance_to(-death_curve[death_curve.size() - 1 - index]) > 0.001:
			curves_are_center_symmetric = false
			break
	_expect(curves_are_center_symmetric, "life and death curves are center-symmetric while both frequency axes still run left-to-right")

	var full_span_slider := tuning_scene.instantiate() as GrayboxFieldVisual
	root.add_child(full_span_slider)
	full_span_slider.prepare({
		"event_id": "tuning_visual_full_span",
		"affinity": GameplayTypes.Affinity.ZHU,
		"traversal_ticks": 960,
		"traversal_count": 1,
		"duration_ticks": 960,
		"duration_us": 1_000_000,
		"start_value": 0.0,
		"end_value": 1.0,
	})
	_expect(
		float(full_span_slider.visual_state_snapshot()["slider_length_px"]) > float(life_state["slider_length_px"]),
		"larger frequency span produces a longer rail even when traversal time is unchanged"
	)

	var custom_rules := DomainFixtureFactory.rules()
	custom_rules.tuning_min_frequency_hz = 2.0
	custom_rules.tuning_base_frequency_hz = 5.0
	custom_rules.tuning_max_frequency_hz = 8.0
	custom_rules.tuning_pixels_per_hz = 123.0
	var exact_scale_slider := tuning_scene.instantiate() as GrayboxFieldVisual
	root.add_child(exact_scale_slider)
	exact_scale_slider.prepare({
		"event_id": "tuning_visual_exact_scale",
		"field_id": "preposition_field",
		"affinity": GameplayTypes.Affinity.ZHU,
		"traversal_ticks": 480,
		"traversal_count": 1,
		"duration_ticks": 480,
		"duration_us": 500_000,
		"start_value": 0.49,
		"end_value": 0.51,
	})
	exact_scale_slider.configure_from_rules(custom_rules)
	_expect_near(
		float(exact_scale_slider.visual_state_snapshot()["slider_chord_px"]),
		absf(0.51 - 0.49) * (8.0 - 2.0) * 123.0,
		0.0001,
		"even a tiny slider keeps the exact shared pixels-per-Hz chord before angular clamping"
	)

	# 滑条提前出现时还没有 active slider state；此时仍要显示本钟真实全局频率，
	# 包括位于轨道范围之外的位置，不能夹到 0 冒充已经站在起点。
	var preposition_life := tuning_scene.instantiate() as GrayboxFieldVisual
	root.add_child(preposition_life)
	preposition_life.prepare({
		"event_id": "preposition_life",
		"field_id": "preposition_field",
		"affinity": GameplayTypes.Affinity.ZHU,
		"traversal_ticks": 480,
		"start_value": 0.30,
		"end_value": 0.70,
	})
	preposition_life.set_gameplay_snapshot({
		"tuning_field_active": true,
		"active_tuning_field_id": "preposition_field",
		"life_tuning_value": 0.10,
		"death_tuning_value": 0.90,
		"active_tuning_sliders": [],
	})
	_expect_near(float(preposition_life.visual_state_snapshot()["player_progress"]), -0.50, 0.00001, "pre-spawned life rail shows a true cursor position before its start")
	var preposition_death := tuning_scene.instantiate() as GrayboxFieldVisual
	root.add_child(preposition_death)
	preposition_death.prepare({
		"event_id": "preposition_death",
		"field_id": "preposition_field",
		"affinity": GameplayTypes.Affinity.XUAN,
		"traversal_ticks": 480,
		"start_value": 0.30,
		"end_value": 0.70,
	})
	preposition_death.set_gameplay_snapshot({
		"tuning_field_active": true,
		"active_tuning_field_id": "preposition_field",
		"life_tuning_value": 0.10,
		"death_tuning_value": 0.90,
		"active_tuning_sliders": [],
	})
	_expect_near(float(preposition_death.visual_state_snapshot()["player_progress"]), 1.50, 0.00001, "pre-spawned death rail reads its own out-of-range global frequency")
	preposition_death.free()
	preposition_life.free()
	exact_scale_slider.free()
	full_span_slider.free()
	death_slider.free()
	life_slider.free()

	var hold_scene := load("res://scenes/presentation/notes/graybox_hold_visual.tscn") as PackedScene
	var hold := hold_scene.instantiate() as GrayboxHoldVisual
	root.add_child(hold)
	hold.prepare({"event_id": "hold_visual_test", "affinity": GameplayTypes.Affinity.ZHU, "start_us": 0, "end_us": 2_000_000})
	hold.set_approach_progress(0.05)
	var head_state: Dictionary = hold.visual_state_snapshot()
	_expect(float(head_state["head_alpha"]) > 0.0 and float(head_state["body_reveal"]) > 0.0, "Hold enters with its head and body visible")
	hold.set_approach_progress(0.50)
	var body_state: Dictionary = hold.visual_state_snapshot()
	_expect(float(body_state["body_reveal"]) > 0.0, "Hold body remains visible during approach")
	hold.set_approach_progress(0.90)
	hold.set_body_target(hold.body_length)
	hold.advance_body(1.0 / 60.0)
	var hold_spine := PackedVector2Array()
	var hold_widths := PackedFloat32Array()
	hold._build_spine(hold_spine, hold_widths)
	_expect(hold_widths[0] > hold_widths[-2] and is_zero_approx(hold_widths[-1]), "Hold body narrows to a single tip")
	hold.set_approach_progress(1.0)
	hold.set_hold_progress(0.0)
	var full_length: float = float(hold.visual_state_snapshot()["visible_length"])
	hold.set_hold_progress(0.5)
	_expect_near(float(hold.visual_state_snapshot()["visible_length"]), full_length * 0.5, 0.001, "active Hold body shortens with held progress")
	hold.free()


func _test_stage_root_contract() -> void:
	var packed := load("res://scenes/stage/stage_root.tscn") as PackedScene
	_expect(packed != null, "StageRoot scene loads")
	if packed == null:
		return
	var stage_root := packed.instantiate() as StageRoot
	root.add_child(stage_root)
	await process_frame
	_expect(stage_root != null and stage_root.stage_session != null, "StageRoot composition resolves")
	_expect(stage_root.audio_feedback.life_strike != null and stage_root.audio_feedback.miss_sfx != null, "graybox has procedural strike and judgment feedback")
	_expect(
		stage_root.audio_feedback.life_carrier_loop != null
		and stage_root.audio_feedback.death_carrier_loop != null,
		"graybox has independent sustained carrier tones for both bells"
	)

	# 先检查决定画面构图的空间约定：共用中心、弧线路径与生死中心对称。
	var life_actor := stage_root.get_node("Presentation/GrayboxStagePresentation/ActorLayer/LifeActorSlot") as Node2D
	var death_actor := stage_root.get_node("Presentation/GrayboxStagePresentation/ActorLayer/DeathActorSlot") as Node2D
	_expect(life_actor.position + death_actor.position == Vector2(1920.0, 1080.0), "actors are center-symmetric")
	_expect_near(absf(death_actor.rotation), PI, 0.00001, "death actor is inverted toward life actor")
	var host := stage_root.get_node("Presentation/GrayboxStagePresentation/GameplayLayer/NoteVisualHost") as NoteVisualHost
	_expect(host.life_spawn.x > 1920.0, "life notes spawn beyond the upper-right edge")
	_expect(host.death_spawn.x < 0.0, "death notes spawn beyond the lower-left edge")
	_expect(host.life_spawn.y < 540.0, "life notes enter from the upper-right")
	_expect(host.death_spawn.y > 540.0, "death notes enter from the lower-left")
	_expect(host.life_target == Vector2(960.0, 540.0), "life notes resolve their timing at the exact canvas center")
	_expect(host.death_target == host.life_target, "life and death share one spatial judgment point")
	_expect(host.life_spawn + host.death_spawn == Vector2(1920.0, 1080.0), "note spawn anchors are center-symmetric")
	var life_note_data: Dictionary = {"event_id": "path_life", "affinity": GameplayTypes.Affinity.ZHU}
	var death_note_data: Dictionary = {"event_id": "path_death", "affinity": GameplayTypes.Affinity.XUAN}
	var life_start: Vector2 = host.call("_sample_approach_path", life_note_data, 0.0)
	var life_quarter: Vector2 = host.call("_sample_approach_path", life_note_data, 0.25)
	var life_half: Vector2 = host.call("_sample_approach_path", life_note_data, 0.5)
	var life_hit: Vector2 = host.call("_sample_approach_path", life_note_data, 1.0)
	var death_start: Vector2 = host.call("_sample_approach_path", death_note_data, 0.0)
	var death_quarter: Vector2 = host.call("_sample_approach_path", death_note_data, 0.25)
	var death_half: Vector2 = host.call("_sample_approach_path", death_note_data, 0.5)
	var death_hit: Vector2 = host.call("_sample_approach_path", death_note_data, 1.0)
	_expect(life_start.distance_to(host.life_spawn) <= 0.01 and life_hit.distance_to(host.life_target) <= 0.01, "life note travels from upper-right spawn to central judgment point (start=%s hit=%s)" % [life_start, life_hit])
	_expect(death_start == host.death_spawn and death_hit == host.death_target, "death note travels from lower-left spawn to central judgment point")
	_expect(life_quarter.distance_to(life_start.lerp(life_hit, 0.25)) > 40.0, "life route is visibly curved rather than a disguised straight lane")
	_expect(death_quarter.distance_to(death_start.lerp(death_hit, 0.25)) > 40.0, "death route is visibly curved rather than a disguised straight lane")
	for ratio: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var life_sample: Vector2 = host.call("_sample_approach_path", life_note_data, ratio)
		var death_sample: Vector2 = host.call("_sample_approach_path", death_note_data, ratio)
		_expect(life_sample.distance_to(Vector2(1920.0, 1080.0) - death_sample) <= 0.01, "both curved routes remain exactly center-symmetric at %.2f" % ratio)
	_expect(life_start.x > life_half.x and life_half.x > life_hit.x, "life note moves right to left")
	_expect(death_start.x < death_half.x and death_half.x < death_hit.x, "death note moves left to right")
	var life_after_cue: Vector2 = host.call("_sample_approach_path", life_note_data, 1.1)
	var death_after_cue: Vector2 = host.call("_sample_approach_path", death_note_data, 1.1)
	_expect(life_after_cue.x < host.life_target.x, "unresolved life note keeps travelling toward the life bell after its cue")
	_expect(death_after_cue.x > host.death_target.x, "unresolved death note keeps travelling toward the death bell after its cue")
	_expect(life_after_cue.y < host.life_target.y, "life note turns upward toward its bell only after crossing the timing gate")
	_expect(death_after_cue.y > host.death_target.y, "death note turns downward toward its bell only after crossing the timing gate")
	var approach_speed_px_sec: float = float(host.call("_approach_distance_px", life_note_data)) / host.approach_duration_sec
	var wave_speed_px_sec: float = 2400.0
	var contact_delay_sec: float = host.life_target.distance_to(host.life_wave_origin) / (wave_speed_px_sec + approach_speed_px_sec)
	var physical_meeting: Vector2 = host.call(
		"_sample_approach_path", life_note_data,
		1.0 + contact_delay_sec / host.approach_duration_sec
	)
	var expected_meeting: Vector2 = host.life_target.move_toward(host.life_wave_origin, approach_speed_px_sec * contact_delay_sec)
	_expect(physical_meeting.distance_to(expected_meeting) <= 0.001, "visible life note reaches the analytic wave meeting point")
	_expect_near(host.life_wave_origin.distance_to(physical_meeting), wave_speed_px_sec * contact_delay_sec, 0.001, "visible wave radius and note path agree at contact")
	var life_tangent: Vector2 = host.call("_sample_approach_tangent", life_note_data, 0.5)
	var death_tangent: Vector2 = host.call("_sample_approach_tangent", death_note_data, 0.5)
	_expect(life_tangent.length() > 0.999 and death_tangent.length() > 0.999, "curved Hold tangents remain normalized and non-zero")
	_expect((life_tangent + death_tangent).length() <= 0.0001, "life and death Hold tangents remain center-symmetric")
	var life_spawn_tangent: Vector2 = host.call("_sample_approach_tangent", life_note_data, 0.0)
	var death_spawn_tangent: Vector2 = host.call("_sample_approach_tangent", death_note_data, 0.0)
	_expect((life_spawn_tangent + death_spawn_tangent).length() <= 0.0001, "opposing paths begin with mirrored facing")
	var life_post_tangent: Vector2 = host.call("_sample_approach_tangent", life_note_data, 1.0)
	var death_post_tangent: Vector2 = host.call("_sample_approach_tangent", death_note_data, 1.0)
	_expect(life_post_tangent.distance_to((host.life_wave_origin - host.life_target).normalized()) <= 0.00001, "life Hold turns toward its bell at the judgment endpoint")
	_expect(death_post_tangent.distance_to((host.death_wave_origin - host.death_target).normalized()) <= 0.00001, "death Hold turns toward its bell at the judgment endpoint")
	var twin_gate := stage_root.get_node("Presentation/GrayboxStagePresentation/GameplayCueLayer/TwinGateCueVisual") as TwinGateCueVisual
	_expect(twin_gate != null, "stage owns one fixed double-aspect central gaze anchor")
	_expect_equal(twin_gate.get_parent().z_index, 10, "central gate stays above note art while timing rings remain uppermost")
	_expect(twin_gate.life_gate == Vector2(960.0, 540.0) and twin_gate.death_gate == twin_gate.life_gate, "both semantic gate anchors occupy the same exact center")
	_expect_equal(str(twin_gate.debug_snapshot()["life_input_label"]), "R1 / 右键 / J", "shared gate labels the right control as life")
	_expect_equal(str(twin_gate.debug_snapshot()["death_input_label"]), "L1 / 左键 / F", "shared gate labels the left control as death")
	twin_gate.set_tuning_active(true)
	_expect_near(twin_gate.modulate.a, 0.22, 0.00001, "tuning dims central gates so the two peripheral rails own the active gaze")
	twin_gate.set_tuning_active(false)
	_expect_near(twin_gate.modulate.a, 1.0, 0.00001, "central gates restore after tuning ends")
	# Hold 使用中心持续环，调频使用上下两个独立粗滑条，疾振使用紧凑计数 HUD。
	var hold_anchor_data: Dictionary = {
		"event_id": "hold_anchor_life",
		"unit_kind": &"hold",
		"affinity": GameplayTypes.Affinity.ZHU,
		"start_us": 0,
		"end_us": 2_000_000,
	}
	host.call("_on_visual_spawn_requested", ChartScheduler.KIND_NOTE, hold_anchor_data)
	host.set_gameplay_snapshot({"active_hold_ids": ["hold_anchor_life"], "held_hold_ids": ["hold_anchor_life"]})
	host.set_visual_time(0.5)
	var hold_anchor_entry: Dictionary = host.get("_active")["hold_anchor_life"]
	var hold_anchor_ring: Node2D = hold_anchor_entry["timing_ring"] as Node2D
	_expect(hold_anchor_ring.position == host.life_target, "active Hold sustain ring remains fixed on the shared central gate")
	_expect((hold_anchor_entry["node"] as Node2D).position != host.life_target, "Hold spirit continues physically toward the bell beneath its fixed sustain ring")
	host.clear()
	var tuning_life_data: Dictionary = {
		"event_id": "tuning_host_life",
		"unit_kind": &"tuning",
		"group_id": "tuning_host_pair",
		"affinity": GameplayTypes.Affinity.ZHU,
		"tick": 0,
		"traversal_ticks": 960,
		"traversal_count": 2,
		"duration_ticks": 1920,
		"start_us": 0,
		"end_us": 2_000_000,
		"duration_us": 2_000_000,
		"start_value": 0.25,
		"end_value": 0.75,
	}
	var tuning_death_data: Dictionary = tuning_life_data.duplicate(true)
	tuning_death_data["event_id"] = "tuning_host_death"
	tuning_death_data["affinity"] = GameplayTypes.Affinity.XUAN
	host.call("_on_visual_spawn_requested", ChartScheduler.KIND_TUNING, tuning_life_data)
	host.call("_on_visual_spawn_requested", ChartScheduler.KIND_TUNING, tuning_death_data)
	host.set_gameplay_snapshot({
		"tuning_field_active": true,
		"life_held": true,
		"death_held": false,
		"active_tuning_sliders": [
			{
				"event_id": "tuning_host_life",
				"interaction_open": true,
				"player_progress": 0.62,
				"guide_progress": 0.60,
				"guide_band_min": 0.48,
				"guide_band_max": 0.72,
				"held": true,
			},
			{
				"event_id": "tuning_host_death",
				"interaction_open": true,
				"player_progress": 0.14,
				"guide_progress": 0.40,
				"guide_band_min": 0.28,
				"guide_band_max": 0.52,
				"held": false,
			},
		],
	})
	host.set_visual_time(0.75)
	var tuning_life_entry: Dictionary = host.get("_active")["tuning_host_life"]
	var tuning_death_entry: Dictionary = host.get("_active")["tuning_host_death"]
	var tuning_life_visual := tuning_life_entry["node"] as GrayboxFieldVisual
	var tuning_death_visual := tuning_death_entry["node"] as GrayboxFieldVisual
	var tuning_life_state: Dictionary = tuning_life_visual.visual_state_snapshot()
	var tuning_death_state: Dictionary = tuning_death_visual.visual_state_snapshot()
	_expect(tuning_life_entry["timing_ring"] == null and tuning_death_entry["timing_ring"] == null, "each tuning rail owns its start cue and never stacks a central timing ring")
	_expect(tuning_life_visual.position == host.approach_origin and tuning_death_visual.position == host.approach_origin, "rail nodes share one coordinate origin while their contents remain peripheral")
	_expect_near(float(tuning_life_state["player_progress"]), 0.62, 0.00001, "NoteVisualHost routes life state only to the life rail")
	_expect_near(float(tuning_death_state["player_progress"]), 0.14, 0.00001, "NoteVisualHost routes death state only to the death rail")
	_expect(bool(tuning_life_state["tuning_active"]) and not bool(tuning_death_state["tuning_active"]), "each side preserves its own held state")
	var tuning_life_center: Vector2 = ((tuning_life_state["slider_start_point"] as Vector2) + (tuning_life_state["slider_end_point"] as Vector2)) * 0.5
	var tuning_death_center: Vector2 = ((tuning_death_state["slider_start_point"] as Vector2) + (tuning_death_state["slider_end_point"] as Vector2)) * 0.5
	_expect(tuning_life_center.distance_to(-tuning_death_center) <= 0.001, "NoteVisualHost keeps the two rails in center-symmetric slots")

	# 同侧未来滑条进入预读窗后立即生成，各自保留绝对缩圈和固定美术锚点。
	var tuning_life_late: Dictionary = tuning_life_data.duplicate(true)
	tuning_life_late["event_id"] = "tuning_host_life_late"
	tuning_life_late["group_id"] = "tuning_host_late"
	tuning_life_late["start_us"] = 3_000_000
	tuning_life_late["end_us"] = 3_300_000
	tuning_life_late["visual_offset_px"] = Vector2(0.0, 150.0)
	var tuning_life_next: Dictionary = tuning_life_late.duplicate(true)
	tuning_life_next["event_id"] = "tuning_host_life_next"
	tuning_life_next["group_id"] = "tuning_host_next"
	tuning_life_next["start_us"] = 2_500_000
	tuning_life_next["end_us"] = 2_800_000
	tuning_life_next["visual_offset_px"] = Vector2(0.0, -150.0)
	host.call("_on_visual_spawn_requested", ChartScheduler.KIND_TUNING, tuning_life_late)
	host.call("_on_visual_spawn_requested", ChartScheduler.KIND_TUNING, tuning_life_next)
	host.call("_on_visual_spawn_requested", ChartScheduler.KIND_TUNING, tuning_life_next)
	host.set_visual_time(0.75)
	var tuning_active_visuals: Dictionary = host.get("_active")
	_expect_equal(tuning_active_visuals.size(), 4, "current rail and two same-side future rails coexist while duplicate IDs are ignored")
	_expect(tuning_active_visuals.has("tuning_host_life_next") and tuning_active_visuals.has("tuning_host_life_late"), "every preview event owns an independent visual immediately")
	var next_visual := tuning_active_visuals["tuning_host_life_next"]["node"] as GrayboxFieldVisual
	var late_visual := tuning_active_visuals["tuning_host_life_late"]["node"] as GrayboxFieldVisual
	var next_state: Dictionary = next_visual.visual_state_snapshot()
	var late_state: Dictionary = late_visual.visual_state_snapshot()
	_expect_equal(int(tuning_life_visual.visual_state_snapshot()["preview_order_number"]), 1, "current tuning group receives the first visible order number")
	_expect_equal(int(tuning_death_visual.visual_state_snapshot()["preview_order_number"]), 1, "paired life and death rails share one order number")
	_expect_equal(int(next_state["preview_order_number"]), 2, "nearest future group receives the next order number")
	_expect_equal(int(late_state["preview_order_number"]), 3, "farther future group remains readable as the third step")
	_expect_near(next_visual.modulate.a, 1.0, 0.00001, "managed tuning visual keeps node alpha intact so its cue is not dimmed twice")
	_expect_near(late_visual.modulate.a, 1.0, 0.00001, "farther tuning cue also owns its alpha internally")
	_expect(
		float(tuning_life_visual.visual_state_snapshot()["preview_alpha"]) > float(next_state["preview_alpha"])
		and float(next_state["preview_alpha"]) > float(late_state["preview_alpha"]),
		"current, nearest future and farther future rails retain a strict visual hierarchy"
	)
	_expect(next_visual.z_index > late_visual.z_index and tuning_life_visual.z_index > next_visual.z_index, "current and future rails have stable foreground ordering")
	_expect(not bool(next_state["interaction_open"]) and float(next_state["fill_progress"]) == 0.0 and int(next_state["guide_dot_count"]) == 0, "future preview shows no player fill or active guide dots")
	_expect(bool(next_state["start_cue_visible"]) and bool(late_state["start_cue_visible"]), "every independent future slider keeps its own visible start cue")
	_expect((next_state["visual_offset_px"] as Vector2) == Vector2(0.0, -150.0), "authored preview offset reaches the visual unchanged")
	_expect((next_state["slider_start_point"] as Vector2).distance_to(late_state["slider_start_point"] as Vector2) > 200.0, "authored offsets keep simultaneous same-side previews spatially distinct")
	_expect(float(next_state["approach_progress"]) > float(late_state["approach_progress"]), "each independent preview keeps its own absolute shrink-ring progress")

	host.call("_on_visual_despawn_requested", ChartScheduler.KIND_TUNING, "tuning_host_life")
	_expect(host.get("_active").has("tuning_host_life_next") and host.get("_active").has("tuning_host_life_late"), "releasing the current rail does not recreate or disturb existing previews")
	host.call("_on_visual_despawn_requested", ChartScheduler.KIND_TUNING, "tuning_host_life_next")
	_expect(host.get("_active").has("tuning_host_life_late"), "each preview can be released independently by event ID")
	_expect_near(float(late_visual.visual_state_snapshot()["preview_alpha"]), 0.70, 0.00001, "farther preview is promoted internally when the nearer event leaves")
	_expect_equal(int(late_visual.visual_state_snapshot()["preview_order_number"]), 2, "visible order numbers close their gap after a preview leaves")
	host.clear()
	_expect(host.get("_active").is_empty() and host.get("_known_tuning_ids").is_empty(), "clear removes all preview instances and duplicate guards")
	var rapid_hud_data := {
		"id": "rapid_hud_anchor",
		"event_id": "rapid_hud_anchor",
		"unit_kind": &"rapid",
		"tick": 0,
		"duration_ticks": 960,
		"start_us": 0,
		"end_us": 1_000_000,
		"duration_us": 1_000_000,
		"required_strikes": 10,
		"must_alternate": true,
	}
	host.call("_on_visual_spawn_requested", ChartScheduler.KIND_RAPID, rapid_hud_data)
	var rapid_hud_entry: Dictionary = host.get("_active")["rapid_hud_anchor"]
	_expect(rapid_hud_entry["timing_ring"] == null, "rapid owns one compact count/time HUD instead of stacking a generic timing ring")
	_expect_equal(int((rapid_hud_entry["node"] as GrayboxFieldVisual).visual_state_snapshot()["rapid_static_wave_count"]), 0, "rapid HUD contains no pre-authored wave shells")
	host.clear()
	# 中央白色合印只属于谱面明确标记的双押；普通快速交替不能冒充双押。
	var chord_life_record := JudgmentRecord.new()
	chord_life_record.unit_id = "gate_chord_life"
	chord_life_record.affinity = GameplayTypes.Affinity.ZHU
	chord_life_record.group_id = "gate_chord"
	chord_life_record.grade = GameplayTypes.JudgmentGrade.PERFECT
	var chord_death_record := JudgmentRecord.new()
	chord_death_record.unit_id = "gate_chord_death"
	chord_death_record.affinity = GameplayTypes.Affinity.XUAN
	chord_death_record.group_id = "gate_chord"
	chord_death_record.grade = GameplayTypes.JudgmentGrade.PERFECT
	twin_gate.call("_on_judgment_presented", chord_life_record)
	twin_gate.call("_on_judgment_presented", chord_death_record)
	_expect_equal(int(twin_gate.debug_snapshot()["fusion_count"]), 1, "an authored opposite-affinity chord creates one bone-white central fusion seal")
	twin_gate.clear()
	chord_life_record.group_id = ""
	chord_death_record.group_id = ""
	twin_gate.call("_on_judgment_presented", chord_life_record)
	twin_gate.call("_on_judgment_presented", chord_death_record)
	_expect_equal(int(twin_gate.debug_snapshot()["fusion_count"]), 0, "quick ungrouped alternation never masquerades as a chord fusion seal")
	twin_gate.clear()
	# 普通敲击、持续调频与疾振使用三套波场，但都由同一次关卡会话驱动。
	var backdrop := stage_root.get_node("Presentation/GrayboxStagePresentation/Backdrop") as GrayboxBackdrop
	_expect(backdrop.draw_placeholder_boundary, "graybox boundary placeholder is enabled without formal art")
	_expect(backdrop.draw_placeholder_life_actor and backdrop.draw_placeholder_death_actor, "graybox actor placeholders are enabled without formal art")
	var wave_field := stage_root.get_node("Presentation/GrayboxStagePresentation/WaveLayer/WaveFieldVisual") as WaveFieldVisual
	_expect(wave_field != null, "stage owns a dedicated physical wave field below the notes")
	var tuning_wave_field := stage_root.get_node("Presentation/GrayboxStagePresentation/WaveLayer/TuningInterferenceVisual") as TuningInterferenceVisual
	_expect(tuning_wave_field != null, "stage owns a separate sustained tuning interference field")
	var rapid_wave_field := stage_root.get_node("Presentation/GrayboxStagePresentation/WaveLayer/RapidInterferenceVisual") as RapidInterferenceVisual
	_expect(rapid_wave_field != null, "stage owns a discrete input-driven rapid interference field")
	var rapid_idle: Dictionary = rapid_wave_field.debug_snapshot()
	_expect(not bool(rapid_idle["dynamic_pattern_active"]), "rapid field is visually empty before the player strikes")
	_expect_equal(int(rapid_idle["white_overlap_pair_count"]), 0, "rapid field cannot pre-author white interference")
	var settings_service := root.get_node_or_null("SettingsService")
	_expect(settings_service != null, "settings service is available to the stage presentation")
	if settings_service != null:
		var persisted_visual_intensity: float = float(settings_service.get("tuning_wave_intensity"))
		_expect_near(
			float(tuning_wave_field.debug_snapshot()["visual_intensity"]),
			persisted_visual_intensity,
			0.00001,
			"stage presentation applies the persisted interference visual intensity"
		)
	_test_authoritative_tuning_wavefront_history(tuning_wave_field)
	var life_wave := {
		"wave_id": "test_life_wave", "affinity": GameplayTypes.Affinity.ZHU,
		"valid": true, "launch_us": 0, "origin": Vector2(350.0, 280.0),
		"speed_px_sec": 480.0, "half_width_px": 25.0,
	}
	var death_wave := {
		"wave_id": "test_death_wave", "affinity": GameplayTypes.Affinity.XUAN,
		"valid": true, "launch_us": 0, "origin": Vector2(1570.0, 800.0),
		"speed_px_sec": 480.0, "half_width_px": 25.0,
	}
	stage_root.stage_session.wave_launched.emit(life_wave)
	wave_field.set_visual_time(1.0)
	var one_wave_snapshot: Dictionary = wave_field.debug_snapshot()
	_expect_equal(int(one_wave_snapshot["active_wave_count"]), 1, "session wave launch reaches the visual field")
	_expect_near(float(one_wave_snapshot["waves"][0]["radius_px"]), 480.0, 0.001, "wave radius comes from absolute timeline time")
	_expect_equal(int(one_wave_snapshot["overlap_point_count"]), 0, "one valid wave cannot create false white interference")
	stage_root.stage_session.wave_launched.emit(death_wave)
	wave_field.set_visual_time(1.4)
	_expect(int(wave_field.debug_snapshot()["overlap_point_count"]) > 0, "real life/death annulus overlap creates bone-white interference points")
	wave_field.clear()
	var gray_wave: Dictionary = death_wave.duplicate(true)
	gray_wave["wave_id"] = "test_gray_wave"
	gray_wave["valid"] = false
	stage_root.stage_session.wave_launched.emit(life_wave)
	stage_root.stage_session.wave_launched.emit(gray_wave)
	wave_field.set_visual_time(1.4)
	var gray_overlap_snapshot: Dictionary = wave_field.debug_snapshot()
	_expect_equal(int(gray_overlap_snapshot["overlap_point_count"]), 0, "gray unqualified wave never masquerades as life/death white overlap")
	wave_field.set_visual_time(10.0)
	_expect_equal(wave_field.active_wave_count(), 0, "wave retires only after its full ring has left every canvas corner")
	wave_field.clear()

	# 疾振图案必须读取玩法产生的实体波记录。仅有进度数值、来自其他机制的波，
	# 或无效的同侧敲击，都不能凭空生成疾振相纹。
	rapid_wave_field.clear()
	var ignored_note_wave: Dictionary = life_wave.duplicate(true)
	ignored_note_wave["wave_id"] = "rapid_test_ignored_note"
	ignored_note_wave["owner"] = GameplayTypes.InputOwner.NOTE
	stage_root.stage_session.wave_launched.emit(ignored_note_wave)
	_expect_equal(int(rapid_wave_field.debug_snapshot()["accepted_wave_count"]), 0, "ordinary note waves never fabricate rapid wave packets")
	var rejected_rapid_wave: Dictionary = death_wave.duplicate(true)
	rejected_rapid_wave["wave_id"] = "rapid_test_rejected"
	rejected_rapid_wave["owner"] = GameplayTypes.InputOwner.RAPID
	rejected_rapid_wave["valid"] = false
	stage_root.stage_session.wave_launched.emit(rejected_rapid_wave)
	var rejected_rapid_snapshot: Dictionary = rapid_wave_field.debug_snapshot()
	_expect_equal(int(rejected_rapid_snapshot["accepted_wave_count"]), 0, "invalid rapid strike cannot enter the coloured interference field")
	_expect_equal(int(rejected_rapid_snapshot["rejected_wave_count"]), 1, "invalid rapid strike remains observable")

	var rapid_life_wave: Dictionary = life_wave.duplicate(true)
	rapid_life_wave["wave_id"] = "rapid_test_life"
	rapid_life_wave["owner"] = GameplayTypes.InputOwner.RAPID
	var rapid_death_wave: Dictionary = death_wave.duplicate(true)
	rapid_death_wave["wave_id"] = "rapid_test_death"
	rapid_death_wave["owner"] = GameplayTypes.InputOwner.RAPID
	stage_root.stage_session.wave_launched.emit(rapid_life_wave)
	rapid_wave_field.set_visual_time(1.0)
	var rapid_single_source: Dictionary = rapid_wave_field.debug_snapshot()
	_expect_equal(int(rapid_single_source["life_wavefront_count"]), 1, "one valid life rapid strike creates exactly one causal packet")
	_expect_equal(int(rapid_single_source["death_wavefront_count"]), 0, "one source cannot invent the opposite rapid packet")
	_expect_equal(int(rapid_single_source["white_overlap_pair_count"]), 0, "one rapid source cannot create white interference")
	_expect_near(float(rapid_single_source["life_wavefronts"][0]["radius_px"]), 480.0, 0.001, "rapid packet radius follows immutable launch time and wave speed")
	stage_root.stage_session.wave_launched.emit(rapid_life_wave)
	_expect_equal(int(rapid_wave_field.debug_snapshot()["accepted_wave_count"]), 1, "duplicate rapid wave IDs are ignored")
	stage_root.stage_session.wave_launched.emit(rapid_death_wave)
	rapid_wave_field.set_visual_time(1.4)
	var rapid_interwoven: Dictionary = rapid_wave_field.debug_snapshot()
	_expect_equal(int(rapid_interwoven["accepted_wave_count"]), 2, "opposite valid rapid strikes produce one packet per real input")
	_expect(int(rapid_interwoven["white_overlap_pair_count"]) > 0, "bone-white rapid pattern requires physical red/black packet intersection")
	var delegated_snapshot: Dictionary = wave_field.debug_snapshot()
	_expect(int(delegated_snapshot["rapid_shader_owned_count"]) >= 2, "valid rapid waves have one dedicated shader rendering owner")
	rapid_wave_field.clear()
	wave_field.clear()
	var rapid_reset: Dictionary = rapid_wave_field.debug_snapshot()
	_expect(not bool(rapid_reset["dynamic_pattern_active"]), "clearing the stage removes all rapid wave history")
	var rapid_generation_one := ClockSample.new()
	rapid_generation_one.generation = 41
	rapid_generation_one.visual_time_sec = 0.0
	rapid_wave_field.set_clock_sample(rapid_generation_one)
	stage_root.stage_session.wave_launched.emit(rapid_life_wave)
	_expect_equal(int(rapid_wave_field.debug_snapshot()["accepted_wave_count"]), 1, "rapid wave is accepted in the current clock generation")
	var rapid_generation_two := ClockSample.new()
	rapid_generation_two.generation = 42
	rapid_generation_two.visual_time_sec = 0.5
	rapid_wave_field.set_clock_sample(rapid_generation_two)
	_expect_equal(int(rapid_wave_field.debug_snapshot()["accepted_wave_count"]), 0, "clock generation change clears rapid wave history")
	stage_root.stage_session.wave_launched.emit(rapid_life_wave)
	_expect_equal(int(rapid_wave_field.debug_snapshot()["accepted_wave_count"]), 1, "the same deterministic wave ID may replay after a seek generation")
	rapid_wave_field.clear()
	wave_field.clear()
	for overflow_index: int in range(RapidInterferenceVisual.MAX_SHADER_WAVEFRONTS + 1):
		var overflow_wave: Dictionary = rapid_life_wave.duplicate(true)
		overflow_wave["wave_id"] = "rapid_overflow_%02d" % overflow_index
		overflow_wave["launch_us"] = overflow_index * 1_000
		stage_root.stage_session.wave_launched.emit(overflow_wave)
	var rapid_overflow: Dictionary = rapid_wave_field.debug_snapshot()
	var wave_overflow: Dictionary = wave_field.debug_snapshot()
	_expect_equal(int(rapid_overflow["life_wavefront_count"]), RapidInterferenceVisual.MAX_SHADER_WAVEFRONTS, "rapid shader keeps its bounded newest packet set")
	_expect_equal(int(rapid_overflow["dropped_wave_count"]), 1, "rapid shader reports a packet that exceeded its detailed capacity")
	_expect_equal(int(wave_overflow["rapid_shader_owned_count"]), RapidInterferenceVisual.MAX_SHADER_WAVEFRONTS, "wave render ownership mirrors the shader capacity")
	_expect_equal(int(wave_overflow["rapid_cpu_fallback_count"]), 1, "overflow rapid packet falls back to a physical CPU ring instead of disappearing")
	var uploads_before_time_only: int = int(rapid_overflow["array_upload_count"])
	rapid_wave_field.set_visual_time(0.01)
	_expect_equal(int(rapid_wave_field.debug_snapshot()["array_upload_count"]), uploads_before_time_only, "time-only frames update one scalar without re-uploading packet arrays")
	rapid_wave_field.clear()
	wave_field.clear()

	# 有正式资源时必须优先使用正式资源，Graybox 只负责缺省兜底。
	var formal_stream := AudioStreamWAV.new()
	formal_stream.format = AudioStreamWAV.FORMAT_16_BITS
	formal_stream.mix_rate = 22_050
	formal_stream.data = PackedByteArray([0, 0, 0, 0])
	var formal_stage := _make_stage("runtime_formal", formal_stream)
	formal_stage.rule_set.approach_duration_sec = 1.37
	formal_stage.rule_set.tuning_min_frequency_hz = 2.0
	formal_stage.rule_set.tuning_max_frequency_hz = 7.0
	formal_stage.rule_set.tuning_pixels_per_hz = 100.0
	formal_stage.rule_set.tuning_hz_per_revolution = 2.5
	formal_stage.visual_theme.boundary_scene = _packed_placeholder("FormalBoundary")
	formal_stage.visual_theme.life_actor_scene = _packed_placeholder("FormalLifeActor")
	formal_stage.visual_theme.death_actor_scene = _packed_placeholder("FormalDeathActor")
	_expect(stage_root.load_stage(formal_stage, false), "formal-audio stage prepares")
	_expect_near(host.approach_duration_sec, 1.37, 0.00001, "visual timing guide shares the stage rule-set lookahead")
	_expect_near(stage_root.input_router.pointer_displacement_per_pixel, 1.0 / 500.0, 0.000001, "prepared stage injects rule-derived pointer tuning scale")
	_expect_near(stage_root.input_router.rotary_displacement_per_radian, 2.5 / (TAU * 5.0), 0.000001, "prepared stage injects the rule-derived rotary tuning scale")
	_expect(stage_root.song_player.stream == formal_stream, "formal song audio is never replaced")
	_expect(not stage_root.stage_session.uses_generated_graybox_audio, "formal stage is not marked graybox audio")
	_expect(not backdrop.draw_placeholder_boundary, "formal boundary scene suppresses duplicate graybox boundary")
	_expect(not backdrop.draw_placeholder_life_actor and not backdrop.draw_placeholder_death_actor, "formal actor scenes suppress duplicate graybox actors")
	_expect(stage_root.seek_tick(480), "prepared StageRoot accepts deferred editor seek before playback")
	_expect_equal(stage_root.stage_session.state, GameplayTypes.StageState.READY, "seek keeps a prepared session READY")
	_expect_equal(stage_root.song_clock.state, SongClock.State.STOPPED, "prepared seek does not start BGM implicitly")

	# 无正式 BGM 时再验证程序音轨、暂停、回放和重试这一整条开发闭环。
	var graybox_stage := _make_stage("runtime_graybox", null)
	var replay_path: String = "user://minghe/replays/tests/runtime_%d.json" % Time.get_ticks_usec()
	stage_root.replay_recorder.set("output_path", replay_path)
	stage_root.set_loadout_hash("integration_loadout".sha256_text())
	_expect(stage_root.load_stage(graybox_stage, false), "null-audio graybox stage prepares")
	_expect(stage_root.song_player.stream is AudioStreamWAV, "null audio receives audible fallback BGM")
	_expect(stage_root.stage_session.uses_generated_graybox_audio, "generated BGM is reported in debug state")
	var generated_playback: AudioStreamPlayback = stage_root.song_player.stream.instantiate_playback()
	_expect(generated_playback != null, "generated fallback BGM creates a playable stream")
	generated_playback = null
	_expect(stage_root.stage_session.start(), "prepared stage starts")
	stage_root.stage_show_director.call("advance_to_us", 0)
	var tutorial_panel := stage_root.get_node("Presentation/GrayboxStagePresentation/ShowCueHost/TutorialPanel") as Control
	var tutorial_label := stage_root.get_node("Presentation/GrayboxStagePresentation/ShowCueHost/TutorialPanel/Label") as Label
	_expect(tutorial_panel.visible, "graybox tutorial cue produces visible text proxy")
	_expect_equal(tutorial_label.text, "运行时教程提示", "tutorial proxy reads generic cue parameters")
	_expect(stage_root.seek_tick(1440), "StageRoot exposes stable tick seek for editor preview")
	_expect_near(stage_root.song_clock.song_time_sec, 1.5, 0.001, "seek maps tick through shared TempoMap")
	_expect(not stage_root.gameplay_coordinator.is_failed(), "cropped preview chart does not fail immediately after middle seek")

	var semantic_kinds: Array[int] = []
	stage_root.input_router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void:
		semantic_kinds.append(sample.kind)
	)
	stage_root.stage_session.resume_countdown_sec = 0.0
	var state_before_pause: int = stage_root.stage_session.state
	_expect(stage_root.stage_session.request_pause(&"integration_manual"), "manual pause succeeds")
	_expect(stage_root.stage_session.state == GameplayTypes.StageState.PAUSED, "manual pause enters PAUSED")
	_expect(semantic_kinds.is_empty(), "manual pause does not inject focus cancellation")
	_expect(stage_root.stage_session.request_resume(), "zero-countdown resume succeeds")
	_expect_equal(stage_root.stage_session.state, state_before_pause, "resume returns to previous gameplay state")

	var before_focus_count: int = semantic_kinds.size()
	stage_root.input_router.cancel_all(InputRouter.CancelReason.FOCUS_LOST)
	_expect_equal(semantic_kinds.size(), before_focus_count + 1, "focus loss injects one semantic cancellation")
	_expect_equal(semantic_kinds[-1], GameplayTypes.SemanticInputKind.FOCUS_CANCELLED, "focus loss uses FOCUS_CANCELLED kind")
	_expect(stage_root.stage_session.state == GameplayTypes.StageState.PAUSED, "focus loss pauses after cancellation is judged")
	stage_root.stage_session.request_resume()

	var finished_results: Array[Dictionary] = []
	stage_root.stage_finished.connect(func(result: Dictionary) -> void: finished_results.append(result))
	stage_root.stage_session.abort()
	_expect_equal(finished_results.size(), 1, "StageRoot forwards result as stage_finished")
	_expect(not bool(finished_results[0].get("success", true)), "aborted stage result is unsuccessful")
	var recorded: ReplayData = stage_root.get_last_replay()
	_expect(recorded != null, "live run produces last_replay")
	if recorded != null:
		_expect_equal(recorded.inputs.size(), 1, "only live focus cancellation is recorded; pause rearm input is excluded")
		_expect_equal(recorded.inputs[0].kind, GameplayTypes.SemanticInputKind.FOCUS_CANCELLED, "recorded semantic input preserves kind")
		_expect_equal(recorded.inputs[0].sequence, 0, "first run input sequence starts at zero")
		_expect_equal(recorded.chart_hash, stage_root.stage_session.compiled_chart.content_hash, "replay carries chart hash")
		_expect_equal(recorded.rules_hash, ChartCompiler.rules_hash(graybox_stage.rule_set), "replay carries rules hash")
		_expect_equal(recorded.loadout_hash, "integration_loadout".sha256_text(), "replay carries loadout hash")
		_expect(recorded.build_id.length() == 64, "replay carries build hash")
	var loaded: Dictionary = REPLAY_RECORDER_SCRIPT.load_from_path(replay_path)
	_expect(bool(loaded.get("ok", false)), "persisted replay JSON round-trips")
	if bool(loaded.get("ok", false)) and recorded != null:
		var loaded_replay: ReplayData = loaded["replay"]
		_expect_equal(loaded_replay.canonical_input_hash(), recorded.canonical_input_hash(), "roundtrip preserves canonical input hash")
		_expect(not String(loaded["run_log"].get("result_digest", "")).is_empty(), "run log stores result digest")

	var first_completed_run_id: int = stage_root.stage_session.run_id
	_expect(stage_root.retry(), "retry starts a fresh run")
	_expect_equal(stage_root.stage_session.run_id, first_completed_run_id + 1, "retry increments run ID exactly once")
	stage_root.input_router.cancel_all(InputRouter.CancelReason.FOCUS_LOST)
	stage_root.stage_session.request_resume()
	stage_root.stage_session.abort()
	_expect_equal(finished_results.size(), 2, "second live run reaches result")
	var replacement: ReplayData = stage_root.get_last_replay()
	_expect(replacement != null and replacement.inputs[0].sequence == 0, "new run resets semantic input sequence")
	var replacement_load: Dictionary = REPLAY_RECORDER_SCRIPT.load_from_path(replay_path)
	_expect(bool(replacement_load.get("ok", false)), "atomic replay replacement remains readable")

	_expect(stage_root.retry(), "third run starts for replay injection")
	var replay: ReplayData = ReplayRunner.build_perfect_replay(
		stage_root.stage_session.compiled_chart,
		graybox_stage.rule_set,
		graybox_stage.song
	)
	var wrong_chart: ReplayData = ReplayData.from_dictionary(replay.to_dictionary())
	wrong_chart.chart_hash = "wrong-chart"
	_expect(stage_root.replay_input_driver.load_replay(wrong_chart), "runtime driver can stage a Replay before playback validation")
	_expect(not stage_root.replay_input_driver.start(), "runtime replay refuses a mismatched chart identity")
	var wrong_rules: ReplayData = ReplayData.from_dictionary(replay.to_dictionary())
	wrong_rules.rules_hash = "wrong-rules"
	_expect(stage_root.replay_input_driver.load_replay(wrong_rules), "runtime driver can stage a Replay with deferred rules validation")
	_expect(not stage_root.replay_input_driver.start(), "runtime replay refuses a mismatched rules identity")
	var wrong_identity: ReplayData = ReplayData.from_dictionary(replay.to_dictionary())
	wrong_identity.song_timing_hash = "wrong-song-timing"
	_expect(stage_root.replay_input_driver.load_replay(wrong_identity), "runtime driver may load Replay before checking the active stage")
	_expect(not stage_root.replay_input_driver.start(), "runtime replay refuses a mismatched song timing identity")
	_expect(stage_root.replay_input_driver.load_replay(replay), "ReplayData loads into runtime injection driver")
	_expect(stage_root.replay_input_driver.start(), "runtime replay injection starts")
	stage_root.replay_input_driver.advance_to(3_000_000)
	_expect(int(stage_root.replay_input_driver.get("_cursor")) > 0, "replay cursor advances before a preview seek")
	_expect(stage_root.seek_tick(0), "running replay can seek through StageRoot")
	_expect_equal(int(stage_root.replay_input_driver.get("_cursor")), 0, "seek rewinds replay injection cursor with simulation")
	stage_root.replay_input_driver.stop()
	stage_root.stage_session.abort()
	_expect_equal(finished_results.size(), 3, "replay playback run reaches result")
	_expect(stage_root.get_last_replay() == replacement, "replay playback is not re-recorded as a live run")
	_expect(not paused, "stage cleanup restores SceneTree pause state")
	stage_root.teardown()
	_expect(stage_root.song_player.stream == null, "StageRoot teardown releases the generated audio stream")
	# 留出若干帧和短暂延时，让音频线程处理停止命令，再结束 headless 进程。
	await process_frame
	await process_frame
	await create_timer(0.08, true).timeout
	stage_root.queue_free()
	await process_frame
	if FileAccess.file_exists(replay_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(replay_path))


func _test_authoritative_tuning_wavefront_history(field: TuningInterferenceVisual) -> void:
	# 载波首先是领域事实。表现层只消费波前，不再按画面帧率自行猜测发射时刻。
	var rules := DomainFixtureFactory.rules()
	rules.tuning_base_frequency_hz = 4.0
	var causal_engine := CarrierWaveEngine.new()
	causal_engine.configure(rules)
	causal_engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	causal_engine.advance_to(250_000)
	var history_before_change: Array[Dictionary] = causal_engine.history_copy()
	var fronts_before_change: Array[Dictionary] = causal_engine.visible_wavefronts(250_000)
	_expect_equal(history_before_change.size(), 2, "a held 4 Hz life bell emits immediately and again after one period")
	_expect_equal(int(history_before_change[0]["launch_us"]), 0, "carrier history stores the exact first emission time")
	_expect_equal(int(history_before_change[1]["launch_us"]), 250_000, "carrier cadence uses authoritative microseconds")

	causal_engine.set_frequency(GameplayTypes.Affinity.ZHU, 2.0, 250_000)
	var history_at_change: Array[Dictionary] = causal_engine.history_copy()
	var fronts_at_change: Array[Dictionary] = causal_engine.visible_wavefronts(250_000)
	_expect_equal(history_at_change, history_before_change, "changing source frequency cannot rewrite emitted carrier records")
	_expect_equal(fronts_at_change, fronts_before_change, "changing source frequency cannot move an existing wavefront")
	causal_engine.advance_to(750_000)
	var history_after_change: Array[Dictionary] = causal_engine.history_copy()
	_expect_equal(history_after_change.size(), 3, "lower future cadence leaves a larger physical gap")
	_expect_equal(int(history_after_change[2]["launch_us"]), 750_000, "new frequency affects only the next emission time")
	_expect_near(float(history_after_change[2]["frequency_hz"]), 2.0, 0.00001, "newly emitted front records the changed source frequency")
	var propagated: Array[Dictionary] = causal_engine.visible_wavefronts(350_000)
	_expect_near(
		float(propagated[0]["radius_px"]) - float(fronts_before_change[0]["radius_px"]),
		240.0,
		0.001,
		"old front advances only by fixed wave speed times elapsed time"
	)

	field.clear()
	field.configure_from_rules(rules)
	field.set_visual_intensity(1.0)
	_expect_near(field.band_half_width_px, 30.0, 0.00001, "carrier rings use the wider readable visual band")
	_expect_near(field.overlap_threshold, 0.055, 0.00001, "bone-white overlap opens at the strengthened threshold")
	_expect_near(field.glow_strength, 1.20, 0.00001, "bone-white overlap uses the strengthened glow")
	var carrier_clock := ClockSample.new()
	carrier_clock.generation = 10
	carrier_clock.visual_time_sec = 0.25
	field.set_clock_sample(carrier_clock)
	field.set_gameplay_snapshot({
		"time_us": 250_000,
		"tuning_field_active": false,
		"life_held": true,
		"death_held": false,
		"life_frequency_hz": 4.0,
		"death_frequency_hz": 4.0,
		"carrier_wavefronts": fronts_before_change,
		"su_manifestations": [],
	})
	var single_source: Dictionary = field.debug_snapshot()
	_expect(bool(single_source["field_enabled"]) and field.visible, "one held bell remains visible even when no tuning slider exists")
	_expect_equal(int(single_source["life_wavefront_count"]), 2, "visual receives every authoritative life front")
	_expect_equal(int(single_source["death_wavefront_count"]), 0, "single-bell carrier never invents the opposite source")
	_expect(not bool(single_source["tuning_field_active"]), "ordinary held carrier is independent from the tuning permission field")

	# 两口钟的等半径圆波具有真实交点；Shader 同时取得两组波前后才可能叠出骨白相纹。
	var overlap_engine := CarrierWaveEngine.new()
	overlap_engine.configure(rules)
	overlap_engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	overlap_engine.set_held(GameplayTypes.Affinity.XUAN, true, 0)
	overlap_engine.advance_to(750_000)
	var overlap_fronts: Array[Dictionary] = overlap_engine.visible_wavefronts(750_000)
	var constructive_points: Array[Vector2] = overlap_engine.find_constructive_intersections(
		750_000,
		Rect2(Vector2.ZERO, Vector2.ONE),
		2,
		0.0
	)
	_expect(not constructive_points.is_empty(), "dual authoritative circle waves create real constructive-interference points")
	carrier_clock.visual_time_sec = 0.75
	field.set_clock_sample(carrier_clock)
	field.set_gameplay_snapshot({
		"time_us": 750_000,
		"tuning_field_active": true,
		"active_tuning_field_id": "field_pair",
		"life_held": true,
		"death_held": true,
		"life_tuning_value": 0.70,
		"death_tuning_value": 0.25,
		"life_frequency_hz": 5.37,
		"death_frequency_hz": 3.075,
		"carrier_wavefronts": overlap_fronts,
		"active_tuning_sliders": [
			{
				"affinity": GameplayTypes.Affinity.ZHU,
				"held": true,
				"player_progress": 0.50,
				"guide_band_min": 0.40,
				"guide_band_max": 0.60,
			},
			{
				"affinity": GameplayTypes.Affinity.XUAN,
				"held": true,
				"player_progress": 0.15,
				"guide_band_min": 0.40,
				"guide_band_max": 0.60,
			},
		],
		"su_manifestations": [],
	})
	var dual_source: Dictionary = field.debug_snapshot()
	_expect(int(dual_source["life_wavefront_count"]) > 0 and int(dual_source["death_wavefront_count"]) > 0, "dual hold uploads both coloured carrier trains for bone-white overlap")
	_expect(absf(float(dual_source["life_frequency_hz"]) - float(dual_source["death_frequency_hz"])) > 0.1, "two bells retain independent frequencies inside one field")
	_expect(bool(dual_source["life_guide_aligned"]), "a held life cursor inside its visible guide band strengthens only the life carrier")
	_expect(not bool(dual_source["death_guide_aligned"]), "a held death cursor outside its guide band receives no false carrier emphasis")
	field.call("_process", 0.03)
	var half_aligned: Dictionary = field.debug_snapshot()
	_expect_near(float(half_aligned["life_alignment_strength"]), 0.5, 0.001, "carrier alignment fades in instead of switching the full-screen shader instantly")
	_expect_near(float(half_aligned["death_alignment_strength"]), 0.0, 0.001, "unaligned death carrier receives no false fade-in")
	field.call("_process", 0.03)
	_expect_near(float(field.debug_snapshot()["life_alignment_strength"]), 1.0, 0.001, "carrier alignment reaches full emphasis after sixty milliseconds")
	_expect(not field.resolve_su_candidate_points(Rect2(Vector2.ZERO, Vector2.ONE), 1, 0.0).is_empty(), "visual white-knot candidates come from the same authoritative circle intersections")
	_expect(
		not bool(field.call("_side_is_guide_aligned", {
			"active_tuning_sliders": [{
				"affinity": GameplayTypes.Affinity.ZHU,
				"held": true,
				"player_progress": -0.10,
				"guide_band_min": 0.0,
				"guide_band_max": 0.12,
			}],
		}, GameplayTypes.Affinity.ZHU)),
		"progress beyond a slider endpoint cannot be clamped back into visual alignment"
	)

	# 相纹强度只能改变着色强弱；所有权威波前仍要完整上传，避免双钟持续按住时成段断流。
	var physical_before_intensity: Array = dual_source["life_wavefronts"]
	var physical_count_before_intensity: int = int(dual_source["life_wavefront_count"])
	var displayed_before_intensity: int = int(dual_source["life_display_wavefront_count"])
	field.set_visual_intensity(0.35)
	var dimmed_display: Dictionary = field.debug_snapshot()
	_expect_equal(int(dimmed_display["life_wavefront_count"]), physical_count_before_intensity, "visual intensity does not delete physical carrier fronts")
	_expect_equal(dimmed_display["life_wavefronts"], physical_before_intensity, "visual intensity does not alter launch times or radii")
	_expect_equal(int(dimmed_display["life_display_wavefront_count"]), displayed_before_intensity, "visual intensity keeps every authoritative ring visible")
	_expect_near(float(dimmed_display["visual_intensity"]), 0.35, 0.00001, "visual intensity remains an appearance-only setting")
	var interference_material := field.material as ShaderMaterial
	_expect_near(
		float(interference_material.get_shader_parameter(&"field_strength")),
		field.field_strength * 0.35,
		0.00001,
		"visual intensity is applied once to the final carrier field strength"
	)
	_expect_near(
		float(interference_material.get_shader_parameter(&"glow_strength")),
		field.glow_strength,
		0.00001,
		"overlap glow is not attenuated by visual intensity a second time"
	)

	# 素音位置由领域结果直接进入覆盖层；表现层不再预放固定靶点。
	var su_points: Array[Vector2] = [constructive_points[0]]
	field.set_gameplay_snapshot({
		"time_us": 750_000,
		"tuning_field_active": true,
		"life_held": true,
		"death_held": true,
		"carrier_wavefronts": overlap_fronts,
		"su_manifestations": [{
			"event_id": "su_domain_result",
			"time_us": 750_000,
			"points": su_points,
			"success": true,
			"visual_variant": &"test",
		}],
	})
	var su_overlay_state: Dictionary = field.debug_snapshot()["su_overlay"]
	_expect_equal(int(su_overlay_state.get("active_count", 0)), 1, "domain Su manifestation appears once at its computed white-knot position")

	# 同一 visual_time 代表暂停：重复快照不能补波；generation 改变代表 Seek，必须清空旧历史。
	var frozen_fronts: Array = field.debug_snapshot()["life_wavefronts"]
	field.set_visual_time(0.75)
	_expect_equal(field.debug_snapshot()["life_wavefronts"], frozen_fronts, "paused visual time cannot fabricate carrier emissions")
	var sought_clock := ClockSample.new()
	sought_clock.generation = 11
	sought_clock.visual_time_sec = 2.0
	field.set_clock_sample(sought_clock)
	var after_seek: Dictionary = field.debug_snapshot()
	_expect_equal(int(after_seek["life_wavefront_count"]), 0, "seek generation clears authoritative life-wave history")
	_expect_equal(int(after_seek["death_wavefront_count"]), 0, "seek generation clears authoritative death-wave history")
	_expect(not field.visible, "seek immediately removes stale full-screen interference and Su overlays")
	field.set_visual_intensity(1.0)
	field.clear()


func _make_stage(stage_id: String, stream: AudioStream) -> StageDefinition:
	var stage := StageDefinition.new()
	stage.stage_id = stage_id
	stage.display_name = stage_id
	stage.song = SongDefinition.new()
	stage.song.song_id = stage_id + "_song"
	stage.song.audio_stream = stream
	stage.song.fallback_duration_sec = 3.0
	stage.song.first_beat_offset_sec = 0.0
	stage.chart = DomainFixtureFactory.one_tap_chart()
	stage.chart.chart_id = stage_id + "_chart"
	stage.chart.note_events[0].tick = 1920
	stage.chart.end_tick = 2400
	stage.rule_set = DomainFixtureFactory.rules()
	stage.visual_theme = StageVisualTheme.new()
	stage.stage_show = StageShow.new()
	stage.stage_show.show_id = stage_id + "_show"
	var tutorial := _make_cue("show_tutorial", 0, 0, 5, &"tutorial_generic")
	tutorial.parameters = {"text": "运行时教程提示", "display_sec": 0.2}
	var vfx := _make_cue("show_vfx", 0, 480, 3, &"rift_generic")
	vfx.target_slot = &"boundary"
	vfx.parameters = {"intensity": 0.8}
	stage.stage_show.cues = [tutorial, vfx]
	return stage


func _make_cue(
	event_id: String,
	tick: int,
	duration_ticks: int,
	track: int,
	cue_id: StringName
) -> ShowCue:
	var cue := ShowCue.new()
	cue.event_id = event_id
	cue.tick = tick
	cue.duration_ticks = duration_ticks
	cue.track = track
	cue.cue_id = cue_id
	return cue


func _packed_placeholder(node_name: String) -> PackedScene:
	var root_node := Node2D.new()
	root_node.name = node_name
	var packed := PackedScene.new()
	packed.pack(root_node)
	root_node.free()
	return packed


func _stream_has_signal(stream: AudioStreamWAV) -> bool:
	for value: int in stream.data:
		if value != 0:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual=%f expected=%f)" % [message, actual, expected])
