extends SceneTree
## 校准统计、固定采样参考音、弹窗草稿和正式应用接线；不写入玩家设置。

const SESSION = preload("res://src/app/calibration_tap_session.gd")

var failures: Array[String] = []
var checks := 0

func _init() -> void: call_deferred("_run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	_test_statistics()
	_test_reference()
	_test_input_delivery()
	await _test_modal()
	await _test_feedback()
	await _test_app_settings()
	# 播放器 stop 的短淡出由混音线程回收；等它完成再结束测试进程。
	await create_timer(0.15).timeout
	for failure in failures: printerr(failure)
	print("CALIBRATION TESTS: %d failures, %d checks" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _test_statistics() -> void:
	var session = SESSION.new()
	session.begin(20)
	expect(not session.add_tap(SESSION.LEAD_SECONDS), "准备拍不进入统计")
	for index in 24:
		var error_ms := 230.0 if index == 8 else 50.0 + (index % 3 - 1) * 2.0
		expect(session.add_tap(session.target_seconds(index) + error_ms / 1000.0), "跟拍接收")
		expect(not session.add_tap(session.target_seconds(index) + 0.055), "同拍双键不重复计数")
	var result: Dictionary = session.result()
	expect(result.used == 23 and result.excluded == 1, "离群跟拍不改变建议")
	expect(absf(result.median_error_ms - 30.0) < 0.001, "早晚偏差扣除现有输入补偿")
	expect(result.suggested_input_ms == 50, "建议是在现有补偿基础上加中位误差")
	expect(result.can_apply, "足够有效样本可应用")
	session.begin(50)
	for index in 24: session.add_tap(session.target_seconds(index) + 0.05)
	expect(absf(session.result().median_error_ms) < 0.001, "应用后复测归零")
	session.begin(0)
	for index in 24: session.add_tap(session.target_seconds(index) - 0.025)
	expect(session.result().suggested_input_ms == -25, "早按建议保留负号")
	session.begin(0)
	session.add_tap(session.target_seconds(0))
	expect(not session.result().can_apply, "不足样本不假装测量完成")

func _test_reference() -> void:
	var stream: AudioStreamWAV = SESSION.create_reference()
	expect(stream.get_length() > SESSION.new().finish_seconds(), "参考音覆盖最后一拍的输入余量")
	for beat in 28:
		var expected_frame := roundi((SESSION.LEAD_SECONDS + beat * SESSION.BEAT_SECONDS) * stream.mix_rate)
		expect(stream.data.decode_s16((expected_frame - 1) * 2) == 0, "拍点前保持静音")
		var first := -1
		for frame in range(expected_frame, expected_frame + 32):
			if stream.data.decode_s16(frame * 2) != 0:
				first = frame
				break
		expect(first >= expected_frame and first - expected_frame <= 3, "编钟起音精确写入采样位置")

func _test_modal() -> void:
	var settings := root.get_node("SettingsService")
	var before: Array = [settings.audio_output_offset_ms, settings.input_offset_ms, settings.visual_offset_ms]
	var modal = load("res://scenes/ui/modals/calibration_modal.tscn").instantiate()
	root.add_child(modal)
	for frame in 3: await process_frame
	for button in [modal._start_button, modal._stop_button, modal._apply_button]:
		expect(root.get_visible_rect().encloses(button.get_global_rect()), "校准按钮保持在可见窗口内")
	if OS.get_cmdline_user_args().has("--calibration-capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/stability/calibration.png")
	modal._input_offset.get_line_edit().text = "20"
	var accumulated_before := Input.use_accumulated_input
	modal._start_test()
	expect(not Input.use_accumulated_input, "跟拍与正式游玩均不积累输入")
	expect(modal._session.base_input_ms == 20, "开始测量提交未回车字段")
	expect(modal._audio_offset.editable == false, "采集期间基准不被手动改动")
	modal._reference.stop()
	for index in 24: modal._session.add_tap(modal._session.target_seconds(index) + 0.05)
	modal._finish_test()
	expect(Input.use_accumulated_input == accumulated_before, "跟拍完成恢复原来的输入递送设置")
	var output_before: float = modal._audio_offset.value
	var visual_before: float = modal._visual_offset.value
	modal._apply_suggestion()
	expect(modal._input_offset.value == 50, "建议只填入弹窗的输入字段")
	expect(modal._audio_offset.value == output_before and modal._visual_offset.value == visual_before, "不混写输出和画面偏移")
	expect([settings.audio_output_offset_ms, settings.input_offset_ms, settings.visual_offset_ms] == before, "测量和应用草稿不写玩家设置")
	modal._start_test()
	expect(modal._session.taps.is_empty(), "重测清除旧样本")
	modal._reset_values()
	expect(Input.use_accumulated_input == accumulated_before, "停止跟拍也恢复输入递送设置")
	expect(modal._input_offset.value == 0 and modal._audio_offset.value == 0 and modal._visual_offset.value == 0, "重置三个草稿值")
	expect(not modal._running and not modal._reference.playing, "取消或重置收掉参考音")
	modal.queue_free()
	await process_frame

func _test_input_delivery() -> void:
	var router := root.get_node("InputEventBuffer")
	var before := Input.use_accumulated_input
	var enabled_before: bool = router._input_enabled
	var session_before: bool = router._session_active
	Input.use_accumulated_input = true
	router.begin_session()
	router.set_mode(router.InputMode.GAMEPLAY)
	expect(not Input.use_accumulated_input, "正式游玩关闭引擎积累等待")
	var presses: Array[PhysicalInputEvent] = []
	var receive := func(event: PhysicalInputEvent) -> void:
		if event.kind == GameplayTypes.PhysicalInputKind.KEY_J_PRESSED: presses.append(event)
	router.physical_input_emitted.connect(receive)
	var key := InputEventKey.new()
	key.keycode = KEY_J
	key.physical_keycode = KEY_J
	key.pressed = true
	Input.parse_input_event(key)
	expect(presses.size() == 1, "按键经真实 _input 立即进入正式事件缓冲")
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	router.physical_input_emitted.disconnect(receive)
	router.set_mode(router.InputMode.RESUME_REARM)
	expect(not Input.use_accumulated_input, "恢复准备期间不重新积累")
	router.set_mode(router.InputMode.REPLAY)
	expect(Input.use_accumulated_input, "Replay 不占用真人输入配置")
	router.set_mode(router.InputMode.GAMEPLAY)
	router.end_session()
	expect(Input.use_accumulated_input, "会话结束恢复菜单输入配置")
	router.set_mode(router.InputMode.DISABLED)
	Input.use_accumulated_input = false
	router.set_mode(router.InputMode.GAMEPLAY)
	router.set_mode(router.InputMode.DISABLED)
	expect(not Input.use_accumulated_input, "原来关闭积累时也原样恢复")
	router._input_enabled = enabled_before
	router._session_active = session_before
	Input.use_accumulated_input = before

func _test_feedback() -> void:
	var feedback = load("res://src/presentation/audio/audio_feedback_director.gd").new()
	root.add_child(feedback)
	feedback.diagnostics_enabled = true
	feedback._on_wave_launched({"affinity": GameplayTypes.Affinity.ZHU, "launch_us": 1234})
	expect(feedback._cursor == 1, "正式敲钟默认仍立即请求播放")
	expect(feedback.diagnostic_requests[0].event_time_us == 1234, "诊断保存领域与系统请求两种时刻")
	feedback.preview_strikes_muted = true
	feedback._on_wave_launched({"affinity": GameplayTypes.Affinity.ZHU, "launch_us": 2000})
	expect(feedback._cursor == 1, "精确提示轨可单独抑制重复敲钟")
	var record := JudgmentRecord.new()
	record.grade = GameplayTypes.JudgmentGrade.PERFECT
	feedback._on_judgment_recorded(record)
	expect(feedback._cursor == 2, "抑制敲钟不关闭判定反馈")
	feedback.preview_muted = true
	feedback._on_judgment_recorded(record)
	expect(feedback._cursor == 2, "总静音仍关闭全部历史重演声音")
	feedback.queue_free()
	await process_frame

func _test_app_settings() -> void:
	var settings := root.get_node("SettingsService")
	var before: Array = [settings.audio_output_offset_ms, settings.input_offset_ms, settings.visual_offset_ms]
	settings.audio_output_offset_ms = 35
	settings.input_offset_ms = 21
	settings.visual_offset_ms = 12
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	# Autoload 完成后才装入应用脚本；只跳过页面导航，仍调用正式 _show_stage。
	var harness := GDScript.new()
	harness.source_code = "extends \"res://src/app/app_main.gd\"\nfunc _ready() -> void: pass\n"
	harness.reload()
	app.set_script(harness)
	root.add_child(app)
	var song := SongDefinition.new()
	song.song_id = "calibration_test"
	song.audio_stream = SESSION.create_reference()
	var stage := StageDefinition.new()
	stage.stage_id = "calibration_test"
	stage.song = song
	stage.chart = DomainFixtureFactory.base_chart("calibration_test", 48000)
	stage.rule_set = DomainFixtureFactory.rules()
	app._show_stage(stage)
	var stage_root = app._current_screen
	expect(stage_root != null, "正式应用入口接受测试关卡")
	if stage_root != null:
		expect(is_equal_approx(stage_root.song_clock.audio_calibration_sec, 0.035), "正式入口接入输出校准")
		expect(is_equal_approx(stage_root.song_clock.input_compensation_sec, 0.021), "正式入口接入输入补偿")
		expect(is_equal_approx(stage_root.song_clock.visual_lead_sec, 0.012), "正式入口独立接入画面提前量")
	app.queue_free()
	await process_frame
	settings.audio_output_offset_ms = before[0]
	settings.input_offset_ms = before[1]
	settings.visual_offset_ms = before[2]
