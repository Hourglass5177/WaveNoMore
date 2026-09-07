extends SceneTree
var failures := 0
func _init() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func frames() -> void:
	for i in 12: await process_frame
func _run() -> void:
	var doc := StudioDocument.new(); doc.new_project()
	doc.chart().chart_offset_ticks = 240
	var hold := NoteEvent.new(); hold.event_id = "existing_hold"; hold.tick = 480; hold.duration_ticks = 960; hold.kind = GameplayTypes.NoteKind.HOLD
	doc.execute("准备", [], [hold])
	StudioRhythmTools.apply_grid(doc, 150, 1.25, 3)
	check(doc.tempo_map().tick_to_us(0) == 1250000 and is_equal_approx(doc.offset_sec(), 1.05), "小节起点通过全谱偏移正确换算")
	check(doc.chart().note_events[0].tick == 480 and doc.chart().note_events[0].duration_ticks == 960, "对齐保留已有 Hold 音乐位置")
	doc.undo(); check(doc.tempo_map().bpm_at_tick(0) == 120 and doc.offset_sec() == 0, "对齐一次撤销还原完整时间映射")
	StudioRhythmTools.apply_grid(doc, 120, 1, 4)
	var generated := StudioRhythmTools.generate(doc, Vector2(0, 9), true, 0, [])
	check(not generated.issues.is_empty(), "草稿使用正式 Hold 输入区间跳过冲突")
	doc.execute("草稿", [], generated.notes)
	var repeated := StudioRhythmTools.generate(doc, Vector2(0, 9), true, 0, [])
	check(repeated.notes.is_empty() and repeated.duplicates == generated.notes.size(), "重复生成不堆叠 Tap")
	doc.undo(); check(doc.chart().note_events.size() == 1, "整段草稿一次撤销")
	var meter := MeterEvent.new(); meter.tick = 3840; meter.numerator = 3; meter.denominator = 4; doc.chart().meter_events.append(meter)
	var mixed := StudioRhythmTools.generate(doc, Vector2(0, 9), false, 2, [])
	var ticks: Array = []
	for note: NoteEvent in mixed.notes: ticks.append(note.tick)
	check(ticks.has(3840) and ticks.has(5280) and not ticks.has(5760), "草稿尊重现有变拍号")
	var excluded := StudioRhythmTools.generate(doc, Vector2(0, 9), false, 2, [Vector2(0, 3)])
	check(excluded.excluded > 0, "可显式排除不可靠区域")
	var w = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	w.offer_recovery_on_start = false; w.recovery_path = "user://chart_studio/tests/rhythm/recovery.json"
	root.add_child(w); w._open_path("res://tests/editor/fixtures/training/song.json"); await frames()
	while w.preview.rebuilding: await process_frame
	var revision: int = w.document.revision
	var loads: int = w.preview.load_count
	var raw := {"fit": {"bpm": 120, "anchor": 2, "meter": 4}, "beats": [2.0, 2.5, 3.0, 3.5, 4.0], "downbeats": [2.0, 4.0]}
	w.rhythm.popup_centered(); w.rhythm._received(raw)
	w.rhythm._bpm.value = 240; w.rhythm._bpm.value = 120
	await frames()
	check(w.document.revision == revision and w.preview.load_count == loads, "候选修改不触发正式谱面编译")
	var feedback_start := Time.get_ticks_usec()
	for i in 100: w.rhythm._bpm.value = 120 + i * 0.001
	print("候选修改平均 ms：", (Time.get_ticks_usec() - feedback_start) / 100000.0)
	w.rhythm._bpm.value = 120
	w.rhythm.close_requested.emit(); w.rhythm.popup_centered(); await frames()
	check(not w.timeline.rhythm_grid.is_empty(), "重新打开分析窗口恢复候选标记")
	var key := InputEventKey.new(); key.keycode = KEY_SPACE; key.pressed = true
	w.rhythm.gui_release_focus(); w.rhythm._unhandled_key_input(key)
	check(w.audio.playing, "分析窗口空格共用 Transport 播放")
	w.rhythm._unhandled_key_input(key)
	w.rhythm._listen.button_pressed = true
	check(w.rhythm.candidate_beat(2).y == 1 and w.rhythm.candidate_beat(2.5).y == 0, "候选节拍器区分小节首拍")
	w.rhythm._apply_grid(); await frames()
	while w.preview.rebuilding: await process_frame
	check(w.document.tempo_map().bpm_at_tick(0) == 120 and w.document.tempo_map().tick_to_us(0) == 2000000, "应用候选进入共享时间映射")
	w.rhythm._generate(); var count: int = w.rhythm.draft.size()
	var old_count: int = w.document.chart().note_events.size()
	w.rhythm._commit_draft()
	check(count > 0 and w.document.chart().note_events.size() == old_count + count, "预览并确认草稿进入正式文档")
	var saved := "user://chart_studio/tests/rhythm/roundtrip"
	check(StudioProjectIO.save_project(w.document, saved).is_empty(), "生成后保存 JSON 工程")
	var reopened := StudioDocument.new()
	check(StudioProjectIO.open_project(saved.path_join("song.json"), reopened).is_empty() and reopened.chart().note_events.size() == old_count + count, "重开保留生成音符")
	var loaded := ChartProjectLoader.load_stage(saved.path_join("song.json"))
	check(loaded.stage != null and reopened.tempo_map().tick_to_us(0) == 2000000, "游戏共享入口读取生成后的同一谱面和对齐")
	w.document.undo(); check(w.document.chart().note_events.size() == old_count, "界面草稿一步撤销")
	var target := "user://chart_studio/tests/rhythm/formats.wav"
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	for extension in ["wav", "ogg", "mp3"]:
		var path: String = "res://tests/editor/fixtures/training/audio/" + ("song.wav" if extension == "wav" else "decode_test." + extension)
		var result := StudioRhythmJob._decode(path, Vector2(1, 2), target, [false], 48000, 1)
		var file := FileAccess.open(target, FileAccess.READ)
		check(not result.has("error") and file.get_length() == 96044, "独立解码一秒 PCM 音频：" + extension)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/stability/rhythm-workspace.png")
	w.queue_free(); await process_frame
	print("RHYTHM TESTS: ", failures); quit(1 if failures else 0)
