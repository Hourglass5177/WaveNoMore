extends SceneTree
## 故障回归使用独立恢复目录；不读取或覆盖谱师的恢复稿。
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func settle(workspace: Node) -> void:
	for frame in 12: await process_frame
	while workspace.preview.rebuilding: await process_frame

func _run() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	workspace.recovery_path = "user://chart_studio/tests/stability/recovery.json"
	workspace.offer_recovery_on_start = false
	root.add_child(workspace)
	workspace._open_path("res://tests/editor/fixtures/training/song.json")
	await settle(workspace)
	while workspace.audio._wave_thread != null: await process_frame
	check(workspace.timeline.peaks.size() > 0 and workspace.timeline.view_start == -2, "打开项目同时恢复音乐、波形和负时间视野")
	workspace.document.add_difficulty("copy", true)
	await settle(workspace)
	workspace._seek(4.2)
	await settle(workspace)
	workspace._write_recovery()
	workspace._write_recovery()
	var recovery: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(workspace.recovery_path))
	check(recovery.workspace.current == 1 and recovery.charts[1].notes.size() == 8 and FileAccess.file_exists(workspace.recovery_path + ".bak"), "恢复稿记录难度、音符和上一份备份")
	workspace.document.new_project(); workspace._activate_project({})
	check(workspace.timeline.peaks.is_empty() and workspace.document.chart().note_events.is_empty(), "新建清空旧波形和旧音符")
	workspace._restore_recovery(recovery)
	await settle(workspace)
	while workspace.audio._wave_thread != null: await process_frame
	check(workspace.document.current == 1 and workspace.document.chart().note_events.size() == 8 and workspace.timeline.peaks.size() > 0 and is_equal_approx(workspace.audio.position, 4.2), "非空多难度恢复稿恢复波形、位置与正确难度")
	workspace.audio.build_waveform("res://tests/editor/fixtures/training/audio/decode_test.ogg")
	workspace.audio.build_waveform("res://tests/editor/fixtures/training/audio/song.wav")
	workspace.audio.build_waveform("res://tests/editor/fixtures/training/audio/song.wav")
	while workspace.audio._wave_thread != null: await process_frame
	check(workspace.audio._wave_running == workspace.audio._wave_request, "换歌和同路径重复请求只接收最新波形")

	var root_id: int = workspace.preview.stage_root.get_instance_id()
	var loads: int = workspace.preview.load_count
	var seeks: int = workspace.preview.rebuild_count
	workspace.audio.set_playing(true)
	var color_start := Time.get_ticks_usec()
	for i in 12:
		var picker: ColorPickerButton = workspace._colors.life
		picker.get_popup().popup()
		for j in 8: picker.color_changed.emit(Color(float(j) / 8, 0.2, 0.3))
		picker.get_popup().hide()
		workspace.document.undo()
		await process_frame
	var color_ms := (Time.get_ticks_usec() - color_start) / 1000.0
	check(workspace.preview.stage_root.get_instance_id() == root_id and workspace.preview.load_count == loads and workspace.preview.rebuild_count == seeks and workspace.audio.playing, "反复调色、关闭弹窗与撤销不销毁关卡或打断音乐")
	var trace: Array = []
	var events: Array = []
	workspace.preview.stage_root.gameplay_coordinator.wave_contacted.connect(func(contact: Dictionary) -> void: events.append({"kind": "contact", "data": contact}))
	var prior: Array = []
	var last_time := Time.get_ticks_usec()
	for frame in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		var host: Node = workspace.preview.stage_root.presentation.get("_note_visual_host")
		var active: Array = host.get("_active").keys()
		for id in active:
			if not prior.has(id): events.append({"kind": "spawn", "id": id, "time": workspace.audio.position})
		for id in prior:
			if not active.has(id): events.append({"kind": "release", "id": id, "time": workspace.audio.position})
		trace.append({"audio": workspace.audio.position, "frame_ms": (now - last_time) / 1000.0, "rebuilds": workspace.preview.rebuild_count})
		prior = active; last_time = now
	check(workspace.preview.rebuild_count == seeks, "连续普通播放没有无意重演")
	workspace.audio.set_playing(false)
	workspace.preview.advance(workspace.audio.position - 0.005, false)
	check(workspace.preview.rebuild_count == seeks, "普通时间采样回退不触发重演")

	var map: TempoMap = workspace.timeline._map
	for rate in [0.5, 0.75, 1.0, 1.25, 1.5]:
		var recorder := StudioRecorder.new(); recorder.begin(map, 120)
		recorder.press(0, 3.5, 1000000); recorder.release(0, 3.5 + 0.15 * rate, 1150000)
		recorder.press(1, 3.5, 2000000); recorder.release(1, 3.5 + 0.4 * rate, 2400000)
		check(recorder.notes[0].kind == GameplayTypes.NoteKind.TAP and recorder.notes[1].kind == GameplayTypes.NoteKind.HOLD and recorder.notes[1].duration_ticks % 120 == 0, "真实按住阈值与跨 BPM 吸附，倍率 %s" % rate)
	var edge := StudioRecorder.new(); edge.begin(map, 480)
	edge.press(0, 4.0, 0); edge.cut_loop(4.1, 200000)
	check(edge.notes[0].tick + edge.notes[0].duration_ticks <= floori(map.us_to_tick(4100000)), "循环末端不足一格也不跨越回绕")
	var recorder := StudioRecorder.new(); recorder.begin(map, 0)
	recorder.press(0, 3.9, 0); recorder.press(0, 4.0, 50000); recorder.press(1, 3.9, 0)
	recorder.cut_loop(4.1, 200000)
	check(recorder.notes.size() == 2 and recorder.held.is_empty(), "双键循环截断且忽略重复按下")
	recorder.press(0, 4.0, 300000)
	check(recorder.held.is_empty(), "循环截断后须先松开才能再次录入")
	recorder.release(0, 4.0, 300000); recorder.press(0, 4.0, 400000)
	var finished := recorder.finish(4.5, 900000, true)
	check(finished.size() == 2, "失焦取消未完成按键、保留已完成音符")

	workspace._seek(0)
	await settle(workspace)
	workspace._record_button.button_pressed = true
	workspace.audio.set_playing(true)
	workspace.timeline.grab_focus()
	var press := InputEventKey.new(); press.keycode = KEY_F; press.pressed = true
	Input.parse_input_event(press)
	await create_timer(0.05).timeout
	press = InputEventKey.new(); press.keycode = KEY_F; press.pressed = false; Input.parse_input_event(press)
	await process_frame
	var count: int = workspace.document.chart().note_events.size()
	check(workspace.recorder.notes.size() == 1 and workspace.document.chart().note_events.size() == count, "播放中开启录制才接收 F，未结束不重编正式谱面")
	workspace.audio.set_playing(false)
	check(workspace.document.chart().note_events.size() == count + 1, "暂停结算录制")
	workspace.document.undo()
	check(workspace.document.chart().note_events.size() == count, "整段录制一次撤销")
	await settle(workspace)
	check(workspace.timeline.format_time(-1.5) == "−00:01.500", "负时间刻度有明确负号")
	workspace._ui_scale = 0; root.size = Vector2i(1280, 720); await process_frame; workspace._apply_ui_scale()
	var small_scale := root.content_scale_factor
	root.size = Vector2i(1920, 1080); await process_frame; workspace._apply_ui_scale()
	check(root.content_scale_factor > small_scale, "放大窗口同步放大界面")
	workspace._fit_timeline(false)
	check(workspace.timeline.view_start == -2, "显示整曲包含音乐零点之前")
	workspace.timeline.pixels_per_second = 100; workspace.timeline.view_start = -2
	workspace.audio.loop_start = 1; workspace.audio.loop_end = 3
	await process_frame
	var mouse := InputEventMouseButton.new(); mouse.position = Vector2(300, 10)
	workspace.timeline._begin(mouse)
	var motion := InputEventMouseMotion.new(); motion.position = Vector2(350, 10)
	workspace.timeline._motion(motion)
	check(is_equal_approx(workspace.audio.loop_start, 1.5), "拖动循环起点把手更新范围")
	workspace.timeline.cancel_gesture()
	check(is_equal_approx(workspace.audio.loop_start, 1), "Esc 撤销循环范围手势")
	mouse.position = Vector2(400, 35); workspace.timeline._begin(mouse)
	motion.position = Vector2(450, 35); workspace.timeline._motion(motion)
	mouse.position = motion.position; workspace.timeline._finish(mouse)
	check(is_equal_approx(workspace.audio.position, 2.5), "标尺拖动松手精确定位")
	await settle(workspace)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/stability/workspace.png")
	StudioProjectIO.write_json("res://builds/stability/playback-trace.json", {"frames": trace, "events": events, "palette_total_ms": color_ms, "palette_commits": 12, "loads": workspace.preview.load_count, "audio_backward_samples": workspace.audio.backward_samples})
	workspace.queue_free(); await process_frame
	print("STABILITY TESTS: ", failures)
	quit(1 if failures else 0)
