extends SceneTree
## 样本位置、已提交队列边界和实际工作区更新顺序；物理同步另用双路录音测量。
var failures := 0

func _init() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func _run() -> void:
	var track := StudioCueTrack.new(); root.add_child(track)
	var fs := int(AudioServer.get_mix_rate())
	var pulse := PackedVector2Array([Vector2(0.25, 0.25)])
	track.samples[&"pulse"] = pulse
	for rate in [0.5, 0.75, 1.0, 1.25, 1.5]:
		track.set_events([{"seconds": 1.0, "sample": &"pulse"}, {"seconds": 1.0, "sample": &"pulse"}])
		var delay := 0.0 if rate == 1.0 else 512.0 / fs
		track.prepare_segment(0.0, rate, delay)
		var at := roundi((1.0 / rate + delay) * fs)
		var block := track.render_frames(at + 2 - roundi(0.1 * fs))
		var index := at - roundi(0.1 * fs)
		check(block[index].x == 0.5 and block[index - 1] == Vector2.ZERO and block[index + 1] == Vector2.ZERO, "双押样本位置及音乐处理延迟，倍率 %s" % rate)
	var tail := PackedVector2Array(); tail.resize(roundi(0.03 * fs)); tail.fill(Vector2(0.1, 0.1))
	track.samples[&"tail"] = tail
	track.set_events([{"seconds": 0.09, "sample": &"tail"}])
	track.prepare_segment(0, 1, 0); track.stop()
	var block := track.render_frames(roundi(0.05 * fs))
	check(block[0].x > 0 and block[roundi(0.021 * fs)] == Vector2.ZERO, "首块预填后注册播放器不会丢失跨块尾音")
	track.set_events([{"seconds": 0.05, "sample": &"pulse"}])
	track.prepare_segment(0, 1, 0)
	track.set_events([{"seconds": 0.05, "sample": &"pulse"}, {"seconds": 0.12, "sample": &"pulse"}])
	block = track.render_frames(roundi(0.1 * fs))
	var nonzero := 0
	for sample in block:
		if sample != Vector2.ZERO: nonzero += 1
	check(nonzero == 1 and block[roundi(0.02 * fs)].x == 0.25, "播放中编辑只改变未来队列，不重播过去提示")
	block = track.prepare_segment(0.13, 1, 0)
	check(block.count(Vector2.ZERO) == block.size(), "定位不补播历史起手及尾音")
	track.end_seconds = 0.1
	track.prepare_segment(0, 1, 0)
	block = track.render_frames(roundi(0.1 * fs))
	check(block.count(Vector2.ZERO) == block.size(), "循环终点之后的提示不进入预填队列")
	var doc := StudioDocument.new(); doc.new_project()
	var chart_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/editor/fixtures/training/charts/normal.json"))
	doc.charts.assign([ChartJsonCodec.decode_chart(chart_data).chart])
	var notes := StudioCueEvents.build(doc, true, false, {}, 8)
	check(notes.size() == 8 and notes[0].seconds == 2.0 and notes[4].seconds == 3.5, "Tap/Hold 仅起手提示，时间使用正式 TempoMap")
	var meter := doc.chart().meter_events[0]; meter.numerator = 6; meter.denominator = 8
	var beats := StudioCueEvents.build(doc, false, true, {}, 8)
	check(beats[0].sample == &"strong" and beats[1].seconds == 2.25 and beats[6].sample == &"strong", "6/8 分母决定拍长，小节首拍加重")
	var candidate := StudioCueEvents.build(doc, false, false, {"bpm": 120, "anchor": 0.25, "meter": 3}, 3)
	var strong := candidate.filter(func(e: Dictionary) -> bool: return e.sample == &"strong")
	check(strong.size() == 2 and strong[0].seconds == 0.25 and strong[1].seconds == 1.75, "候选节拍沿用同一事件轨，三拍一重拍")
	track.free()
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start = false
	workspace.recovery_path = "user://chart_studio/tests/cues/recovery.json"
	root.add_child(workspace); workspace._open_path("res://tests/editor/fixtures/training/song.json")
	for frame in 30: await process_frame
	while workspace.preview.rebuilding: await process_frame
	workspace.audio.seek(2.0); workspace.audio.set_playing(true)
	var same_frame := true
	for frame in 30:
		await process_frame
		if not workspace.preview.rebuilding:
			var state: Dictionary = workspace.preview.get_preview_state()
			var expected := roundi((workspace.audio.position - workspace.preview.offset_sec) * 1000000)
			if abs(int(state.time_us) - expected) > 1: same_frame = false
	check(same_frame, "工作区预览和 Transport 消费同帧位置")
	check(workspace.preview.stage_root.audio_feedback.preview_strikes_muted, "精确提示与正式预览起手不重复叠声")
	workspace.audio.loop_start = 5; workspace.audio.loop_end = 4; workspace.audio.loop_enabled = true
	workspace.audio.seek(2)
	check(workspace.audio.cues.end_seconds == workspace.document.song.audio_stream.get_length(), "起止倒置的无效循环不截断后续提示")
	workspace.audio.loop_enabled = false
	var old_anchor: int = workspace.audio._anchor
	var added := NoteEvent.new(); added.event_id = &"cue_test_added"; added.tick = 3000
	workspace.document.execute("新提示", [], [added])
	for frame in 5: await process_frame
	check(workspace.audio.playing and workspace.audio._anchor == old_anchor, "播放中编辑不暂停或重启音乐")
	workspace.audio.set_playing(false)
	workspace._inspect()
	var committed := [0]
	workspace._number("精度测试", 138.276204123, 20, 999, func(_value: float) -> void: committed[0] += 1, 0.001)
	var spin: SpinBox = workspace.fields.get_child(-1)
	spin.get_line_edit().focus_exited.emit(); workspace._flush_property_edits()
	check(committed[0] == 0, "小数显示精度不会因焦点退出改写 BPM")
	workspace.audio.seek(-2); workspace.audio.set_playing(true)
	check(workspace.audio.cues._player.playing and not workspace.audio._player.playing, "负时间预滚先播放提示轨，音乐尚未起播")
	check(workspace.audio.cues.end_seconds == 0, "负预滚不提前提交零点起手，跨零只敲一次")
	workspace.audio.set_playing(false)
	workspace.audio.set_stream(null); workspace.audio.set_playing(true)
	workspace.audio._anchor = Time.get_ticks_usec() - 20000 - roundi(workspace.audio._start_delay * 1000000)
	var sampled: float = workspace.audio.sample_position()
	check(sampled - workspace.audio.position > 0.019 and sampled - workspace.audio.position < 0.04, "录入当场取样，消除上一帧播放头的量化等待")
	workspace.queue_free(); await process_frame
	await create_timer(0.15).timeout
	print("CUE TESTS: ", failures); quit(failures)
