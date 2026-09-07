extends SceneTree
## 程序注入经真实 _input 与正式 StageSession，测量主线程请求；不是硬件按键/扬声器延迟。

var captured: Dictionary = {}
var failures: Array[String] = []
var processed_frame_usec := 0
var judgments: Dictionary = {}

func _init() -> void: call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("请用正常渲染模式测量；headless 结果不能代表帧调度。")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# 仅测量进程可选择 A/B，不把实验开关写进正式项目或玩家设置。
	var immediate_input := OS.get_cmdline_user_args().has("--immediate-input")
	Input.use_accumulated_input = not immediate_input
	var selected_fps := 60
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fps="): selected_fps = argument.trim_prefix("--fps=").to_int()
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	var harness := GDScript.new()
	harness.source_code = "extends \"res://src/app/app_main.gd\"\nfunc _ready() -> void: pass\n"
	harness.reload(); app.set_script(harness); root.add_child(app)
	var input_buffer := root.get_node("InputEventBuffer")
	input_buffer.physical_input_emitted.connect(_captured)
	var reports: Array[Dictionary] = []
	var onset_report: Dictionary = {}
	for fps in [selected_fps]:
		Engine.max_fps = fps
		# 等旧关卡结束全局输入会话，再挂载下一关，避免 teardown 覆盖新关的输入模式。
		app._clear_screen()
		await process_frame
		app._show_stage(_stage())
		# 正式入口已启用及时输入；A/B 只在这个测试进程内重新指定开关。
		Input.use_accumulated_input = not immediate_input
		var stage_root = app._current_screen
		var feedback = stage_root.audio_feedback
		feedback.diagnostics_enabled = true
		if onset_report.is_empty(): onset_report = _onsets(feedback)
		stage_root.song_clock.sample_published.connect(_sampled)
		stage_root.stage_session.judgment_recorded.connect(_judged)
		await create_timer(0.2).timeout
		var start_usec := Time.get_ticks_usec()
		var start_frames := Engine.get_process_frames()
		var samples: Array[Dictionary] = []
		for index in 12:
			var note_time := 0.5 + index * 0.3
			# 覆盖会话本帧处理之前/之后，避免只测人为选定的最优注入时刻。
			while stage_root.song_clock.judge_time_at_usec(Time.get_ticks_usec()) < note_time:
				await process_frame
			if index % 2: await RenderingServer.frame_post_draw
			captured.clear()
			processed_frame_usec = 0
			var requested_usec := Time.get_ticks_usec()
			_key(true)
			var found: Dictionary = {}
			for frame in 8:
				for request in feedback.diagnostic_requests:
					if request.kind == &"strike" and request.event_time_us == captured.get("timestamp_us", -1): found = request
				if not found.is_empty(): break
				await process_frame
			_key(false)
			if found.is_empty():
				failures.append("%d FPS 第 %d 次输入没有敲钟请求，输入模式 %d，会话状态 %d，捕获 %s" % [fps, index, input_buffer.mode, stage_root.stage_session.state, str(captured)])
				continue
			var judgment: Dictionary = judgments.get("request_%02d" % index, {})
			if judgment.is_empty(): failures.append("%d FPS 第 %d 次没有正式 Tap 判定" % [fps, index])
			samples.append({
				"injection_phase": "after_scene_process" if index % 2 else "before_scene_process",
				"parse_input_usec": requested_usec, "captured_usec": captured.captured_usec,
				"event_time_us": captured.timestamp_us, "frame_sample_usec": processed_frame_usec,
				"judgment": judgment, "sfx_requested_usec": found.requested_usec,
				"parse_to_callback_ms": float(captured.captured_usec - requested_usec) / 1000.0,
				"callback_to_request_ms": float(found.requested_usec - captured.captured_usec) / 1000.0,
				"frame_to_request_ms": float(found.requested_usec - processed_frame_usec) / 1000.0,
			})
		var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
		reports.append({"fps_limit": fps, "effective_fps": (Engine.get_process_frames() - start_frames) / elapsed, "samples": samples, "timing": _summary(samples)})
		judgments.clear()
	input_buffer.physical_input_emitted.disconnect(_captured)
	var report := {
		"scope": "程序注入 Input.parse_input_event → 真实输入回调 → 正式领域 → 敲钟播放器请求；不包含硬件递送与实际音频输出",
		"godot": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"driver": AudioServer.get_driver_name(), "reported_output_latency_ms": AudioServer.get_output_latency() * 1000.0,
		"output_device": AudioServer.output_device, "mix_rate": AudioServer.get_mix_rate(),
		"requested_output_latency_ms": ProjectSettings.get_setting("audio/driver/output_latency"),
		"accumulated_input": Input.use_accumulated_input, "asset_onsets": onset_report,
		"runs": reports, "failures": failures,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/stability"))
	var suffix := "-immediate" if immediate_input else ""
	if selected_fps > 0: suffix += "-%d" % selected_fps
	var file := FileAccess.open("res://builds/stability/gameplay-audio-requests%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	for run in reports: print("GAMEPLAY AUDIO REQUEST ", run.fps_limit, " FPS (actual ", run.effective_fps, "): ", run.timing)
	for failure in failures: printerr(failure)
	app.queue_free(); await process_frame
	await create_timer(0.15).timeout
	print("GAMEPLAY AUDIO REQUEST MEASUREMENT: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _stage() -> StageDefinition:
	var stage := StageDefinition.new()
	stage.stage_id = "audio_request_measurement"
	stage.song = SongDefinition.new()
	stage.song.song_id = stage.stage_id
	stage.song.audio_stream = CalibrationTapSession.create_reference()
	stage.chart = DomainFixtureFactory.base_chart(stage.stage_id, 48000)
	for index in 12:
		stage.chart.note_events.append(DomainFixtureFactory._note("request_%02d" % index, 480 + index * 288, GameplayTypes.Affinity.ZHU))
	stage.rule_set = DomainFixtureFactory.rules()
	stage.debug_nonlethal = true
	return stage

func _onsets(feedback: Node) -> Dictionary:
	var result := {}
	for key in ["life_strike", "death_strike", "perfect_sfx", "good_sfx", "pass_sfx", "miss_sfx"]:
		var stream: AudioStreamWAV = feedback.get(key)
		var frames := stream.data.size() / 2
		var peak := 0
		for frame in frames: peak = maxi(peak, absi(stream.data.decode_s16(frame * 2)))
		var points := {}
		for threshold in [1, roundi(peak * 0.01), roundi(peak * 0.1)]:
			for frame in frames:
				if absi(stream.data.decode_s16(frame * 2)) >= threshold:
					points[str(threshold)] = 1000.0 * frame / stream.mix_rate
					break
		result[key] = {"sample_rate": stream.mix_rate, "peak_pcm16": peak, "threshold_pcm16_to_first_ms": points}
	return result

func _summary(samples: Array[Dictionary]) -> Dictionary:
	var result := {}
	for key in ["parse_to_callback_ms", "callback_to_request_ms", "frame_to_request_ms"]:
		var values: Array[float] = []
		for sample in samples: values.append(sample[key])
		values.sort()
		result[key] = {"median": (values[5] + values[6]) * 0.5 if values.size() == 12 else -1, "max": values[-1] if not values.is_empty() else -1}
	return result

func _sampled(_sample: ClockSample) -> void:
	if not captured.is_empty() and processed_frame_usec == 0: processed_frame_usec = Time.get_ticks_usec()

func _judged(record: JudgmentRecord) -> void:
	judgments[record.unit_id] = {"observed_usec": Time.get_ticks_usec(), "grade": record.grade, "finalized_at_us": record.finalized_at_us}

func _captured(sample: PhysicalInputEvent) -> void:
	if sample.kind != GameplayTypes.PhysicalInputKind.KEY_J_PRESSED: return
	captured = {"timestamp_us": sample.timestamp_us, "captured_usec": Time.get_ticks_usec()}

func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_J; event.physical_keycode = KEY_J; event.pressed = pressed
	Input.parse_input_event(event)
