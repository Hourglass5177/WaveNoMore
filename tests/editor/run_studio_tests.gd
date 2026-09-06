extends SceneTree
## 新版规格回归：共享 JSON、正式模拟、直接定位与逐段播放等价。
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
	else:
		print("PASS ", label)

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/editor/fixtures/training/charts/normal.json"))
	var codec = load("res://src/content/chart_format/chart_json_codec.gd")
	var decoded: Dictionary = codec.decode_chart(data)
	check(decoded.chart != null and decoded.errors.is_empty(), "JSON 示例解码")
	var chart: SongChart = decoded.chart
	var map := TempoMap.from_chart(chart, 2000000)
	check(map.tick_to_us(2400) == 4400000, "跨 BPM Hold 尾点")
	var shifted := chart.duplicate(true) as SongChart; shifted.chart_offset_ticks = 480
	var shifted_map := TempoMap.from_chart(shifted, 2000000)
	check(shifted_map.tick_to_us(1440) == 4000000 and shifted_map.tick_to_us(2400) == 4800000, "全谱偏移跨 BPM 保留有效 tick 语义")
	var encoded: Dictionary = codec.encode_chart(chart)
	check(encoded.notes.size() == 8 and encoded.sections.size() == 3, "JSON 音符段落保留")
	var extended := data.duplicate(true)
	extended["future_metadata"] = {"value": 17}
	extended.notes[0]["future_style"] = [1, 2, 3]
	extended.notes.append({"id": "future_note", "kind": "future", "tick": 6000, "affinity": "zhu", "payload": {"opaque": true}})
	var extended_result: Dictionary = codec.encode_chart(codec.decode_chart(extended).chart)
	check(extended_result.future_metadata.value == 17 and extended_result.notes[0].future_style == [1, 2, 3] and extended_result.notes[-1].payload.opaque, "兼容未知字段与未支持音符无损保存")
	var future_version := data.duplicate(true); future_version.format_version = 99
	check(codec.decode_chart(future_version).chart == null, "重大未知版本拒绝有损覆盖")
	var invalid_time := data.duplicate(true); invalid_time.timing.tempo_events[0].bpm = 0
	check(codec.decode_chart(invalid_time).chart == null, "零 BPM 拒绝建立时间映射")
	var fractional := data.duplicate(true); fractional.notes[0].tick = 0.5
	check(codec.decode_chart(fractional).chart == null, "非整数 tick 不静默截断")
	var unfinished := data.duplicate(true); unfinished.notes[4].duration_ticks = -120
	check(codec.decode_chart(unfinished).chart != null, "玩法冲突草稿仍能解码编辑")
	var doc = load("res://src/tools/chart_studio/studio_document.gd").new()
	doc.new_project()
	doc.charts.assign([chart.duplicate(true)])
	var timeline = load("res://src/tools/chart_studio/studio_timeline.gd").new()
	root.add_child(timeline)
	timeline.size = Vector2(1280, 280)
	timeline.bind(doc)
	# 使用实际控件的鼠标事件入口，而不是直接替它修改音符。
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(timeline.x_at(4800), 140)
	timeline._gui_input(down)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(timeline.x_at(5280), 140)
	timeline._gui_input(motion)
	check(doc.chart().note_events.size() == 8, "拖画候选不修改正式文档")
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	up.position = motion.position
	timeline._gui_input(up)
	check(doc.chart().note_events.size() == 9 and doc.find_note(timeline.selected[0]).duration_ticks == 480, "一次鼠标拖画 Hold")
	doc.undo()
	check(doc.chart().note_events.size() == 8, "一次撤销完整手势")
	doc.undo(true)
	check(doc.chart().note_events.size() == 9, "重做恢复 Hold")
	timeline._gui_input(down)
	timeline._gui_input(motion)
	timeline.cancel_gesture()
	check(doc.chart().note_events.size() == 9, "取消手势无变更")
	timeline.selected = PackedStringArray(["n03", "n04"])
	drag(timeline, Vector2(timeline.x_at(960), 140), Vector2(timeline.x_at(1200), 140))
	check(doc.find_note("n03").tick == 1200 and doc.find_note("n04").tick == 1200 and timeline.selected.size() == 2, "拖动选区成员保留双侧选区")
	doc.undo()
	drag(timeline, Vector2(timeline.x_at(1440), 140), Vector2(timeline.x_at(1560), 140))
	check(doc.find_note("n05").tick == 1560 and doc.find_note("n05").tick + doc.find_note("n05").duration_ticks == 2400, "Hold 头把手固定尾点")
	doc.undo()
	drag(timeline, Vector2(timeline.x_at(2400), 140), Vector2(timeline.x_at(2520), 140))
	check(doc.find_note("n05").tick == 1440 and doc.find_note("n05").duration_ticks == 1080, "Hold 尾把手固定头点")
	doc.undo()
	timeline.selected.clear()
	drag(timeline, Vector2(timeline.x_at(960) - 20, 110), Vector2(timeline.x_at(960) + 20, 242), true)
	check(timeline.selected.has("n03") and timeline.selected.has("n04"), "Shift 空白拖动框选双押")
	doc.copy_notes(PackedStringArray(["n03", "n04"]))
	var copied: PackedStringArray = doc.paste(5760)
	check(copied.size() == 2 and doc.find_note(copied[0]).group_id == doc.find_note(copied[1]).group_id and doc.find_note(copied[0]).group_id != "g01", "复制组合重新生成引用")
	var io = load("res://src/tools/chart_studio/studio_project_io.gd")
	var temp := "user://chart_studio/tests/roundtrip"
	check(io.save_project(doc, temp).is_empty() and io.save_project(doc).is_empty(), "JSON 首次保存和覆盖保存")
	var reopened = load("res://src/tools/chart_studio/studio_document.gd").new()
	check(io.open_project(temp.path_join("song.json"), reopened).is_empty() and reopened.chart().note_events.size() == 11, "工程重开保留编辑结果")
	var loader = load("res://src/content/chart_format/chart_project_loader.gd")
	var package: Dictionary = loader.load_stage("res://tests/editor/fixtures/training/song.json", "normal")
	check(package.stage != null, "游戏公共入口读取同一 JSON 项目")
	var wave: Dictionary = load("res://src/tools/chart_studio/studio_audio.gd").decode_peaks("res://tests/editor/fixtures/training/audio/song.wav")
	check(wave.has("peaks") and wave.peaks.size() > 100 and wave.peaks[0].y > 0, "独立解码实例生成 WAV 波形")
	for extension in ["ogg", "mp3"]:
		var result: Dictionary = load("res://src/tools/chart_studio/studio_audio.gd").decode_peaks("res://tests/editor/fixtures/training/audio/decode_test." + extension)
		check(result.has("peaks") and result.peaks.size() > 100 and result.peaks[1].y > 0, "独立解码 " + extension + " 波形")
	var migrated = load("res://src/tools/chart_studio/studio_document.gd").new()
	var destination := "user://chart_studio/tests/migrated_%d" % Time.get_ticks_usec()
	var migration_error: String = io.import_legacy("res://content/stages/s05/stage_definition.tres", destination, migrated)
	check(migration_error.is_empty(), "旧综合关迁移为独立工程：" + migration_error)
	check(FileAccess.get_file_as_bytes("res://content/stages/s05/stage_definition.tres") == FileAccess.get_file_as_bytes(destination.path_join("legacy/res/content/stages/s05/stage_definition.tres")), "旧入口逐字节归档")
	var copied_doc = load("res://src/tools/chart_studio/studio_document.gd").new()
	io.open_project("res://tests/editor/fixtures/training/song.json", copied_doc)
	check(io.save_project(copied_doc, "user://chart_studio/tests/package").is_empty(), "另存为复制音频与谱面")
	var zip_path := "user://chart_studio/tests/package.zip"
	check(io.export_zip(copied_doc, zip_path).is_empty(), "可玩 ZIP 交付")
	var reader := ZIPReader.new()
	reader.open(zip_path)
	check(reader.file_exists("song.json") and reader.file_exists("audio/song.wav") and not reader.file_exists("editor/workspace.json"), "交付包包含音频而不含本机工作区")
	reader.close()
	check(loader.load_stage(zip_path, "normal").stage != null, "正式游戏直接读取 ZIP 中的同一谱面和音频")
	timeline.queue_free()
	var view := SubViewport.new()
	view.size = Vector2i(1920, 1080)
	root.add_child(view)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new()
	root.add_child(preview)
	var stage := StageDefinition.new()
	stage.stage_id = "editor_training"
	stage.chart = chart
	stage.song = SongDefinition.new()
	stage.song.first_beat_offset_sec = 2.0
	stage.song.fallback_duration_sec = 8.0
	stage.stage_show = StageShow.new()
	stage.visual_theme = load("res://content/stages/s02/stage_visual_theme.tres")
	stage.reward = RewardDefinition.new()
	stage.rule_set = load("res://content/rules/default_gameplay_rules.tres")
	check(preview.load_preview(stage, view), "正式 StageRoot 预览接入")
	await preview.seek_preview(roundi(4.2 * 1000000.0))
	var snap: Dictionary = preview.stage_root.gameplay_coordinator.snapshot()
	check(snap.get("life_held", false), "4.2 秒恢复跨变速 Hold")
	var first: Dictionary = preview.stage_root.gameplay_coordinator.simulation.carrier_engine.snapshot()
	await preview.seek_preview(roundi(2.0 * 1000000.0))
	preview.advance(3.5, false)
	preview.advance(4.2, false)
	var second: Dictionary = preview.stage_root.gameplay_coordinator.simulation.carrier_engine.snapshot()
	check(first == second, "直接定位与连续推进载波状态等价")
	for target in [2.02, 2.3, 3.05, 4.2, 5.3, 6.2]:
		await preview.seek_preview(roundi(target * 1000000.0))
		var direct := visual_state(preview)
		await preview.seek_preview(roundi(0.0 * 1000000.0))
		var at := 0.0
		while at < target:
			at = minf(at + 0.05, target)
			preview.advance(at, false)
		var played := visual_state(preview)
		if direct != played: print("VISUAL DIFF ", target, " direct=", direct, " played=", played)
		check(direct == played, "活动音符与接触反馈定位等价 %.2f" % target)
	var stress := chart.duplicate(true) as SongChart
	stress.note_events.clear(); stress.end_tick = 50000
	for index in 200:
		var note := NoteEvent.new(); note.event_id = "seek_%d" % index; note.tick = index * 240; note.affinity = index % 2
		stress.note_events.append(note)
	stage.chart = stress
	preview.load_preview(stage, view)
	preview.seek_preview(99000000)
	await preview.seek_preview(4200000)
	await process_frame
	await process_frame
	check(preview.get_preview_state().time_us == 2200000 and not preview.rebuilding, "新定位请求替换旧重演，旧结果不覆盖游标")
	preview.queue_free()
	view.queue_free()
	await process_frame
	print("STUDIO TESTS: ", failures)
	quit(1 if failures else 0)

func visual_state(preview: Node) -> Dictionary:
	var host: Node = preview.stage_root.presentation.get("_note_visual_host")
	var result := {}
	for id in host.get("_active"):
		var visual: Node2D = host.get("_active")[id].node
		if visual is GrayboxNoteVisual:
			result[id] = {"contact": visual.wave_contacted, "timing": visual.timing_confirmed, "hold": snappedf(visual.hold_progress, 0.0001), "position": visual.position.snapped(Vector2(0.01, 0.01)), "color": visual.modulate.to_html()}
	return result

func drag(timeline: Control, start: Vector2, end: Vector2, shift := false) -> void:
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = start; down.shift_pressed = shift
	timeline._gui_input(down)
	var move := InputEventMouseMotion.new(); move.position = end; move.shift_pressed = shift
	timeline._gui_input(move)
	var up := down.duplicate() as InputEventMouseButton; up.position = end; up.pressed = false
	timeline._gui_input(up)
