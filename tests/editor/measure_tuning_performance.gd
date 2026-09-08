extends SceneTree
## 五分钟、一万音符及十条多节点 Tuning；分别记录交互、编译、完整恢复。
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var document := StudioDocument.new(); document.new_project(); document.chart().end_tick = 288000
	var events: Array = []
	for i in 10:
		for side in 2:
			var hold := NoteEvent.new(); hold.event_id = "h%d_%d" % [i, side]; hold.affinity = side
			hold.kind = GameplayTypes.NoteKind.HOLD; hold.tick = i * 2880 + 480; hold.duration_ticks = 1920
			events.append(hold)
	for i in 9980:
		var tap := NoteEvent.new(); tap.event_id = "tap%d" % i; tap.affinity = i % 2
		tap.tick = 28800 + roundi(i * 259100.0 / 9980); events.append(tap)
	document.execute("压力谱", [], events)
	for i in 10:
		var path := ChartEditEvents.new_path(document.chart(), i % 2, i * 2880 + 600, i * 2880 + 2200)
		var middle := TuningPathPoint.new(); middle.event_id = "m%d" % i; middle.offset_ticks = 700; middle.angle_deg = path.points[-1].angle_deg
		path.points[-1].angle_deg = path.points[0].angle_deg; path.points.insert(1, middle)
		document.execute("折返", [], [path])
	var timeline := StudioTimeline.new(); root.add_child(timeline); timeline.size = Vector2(1280, 370); timeline.bind(document)
	var result := {"notes": 10000, "tuning_paths": 10, "duration_seconds": 300, "engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(), "rendering": DisplayServer.get_name()}
	var start := Time.get_ticks_usec()
	for i in 100: timeline.visible_notes(0, 1280)
	result.visible_query_ms = (Time.get_ticks_usec() - start) / 100000.0
	var chosen := document.find_note("tap5000"); var copy = chosen.duplicate(true); copy.tick += 1
	start = Time.get_ticks_usec(); document.execute("移动一音符", [chosen], [copy])
	result.edit_and_index_ms = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec(); document.copy_notes(PackedStringArray(events.slice(0, 200).map(func(e): return e.event_id)))
	result.copy_200_ms = (Time.get_ticks_usec() - start) / 1000.0
	if "--editing-only" in OS.get_cmdline_user_args():
		StudioProjectIO.write_json("res://docs/chart-editor-tuning-edit-performance.json", result)
		print("TUNING EDIT PERF ", JSON.stringify(result)); timeline.queue_free(); await process_frame; quit(); return
	var view := SubViewport.new(); view.size = Vector2i(960,540); root.add_child(view)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	start = Time.get_ticks_usec()
	if not preview.load_preview(ChartProjectLoader.make_stage(document.song, document.chart()), view): push_error("压力谱无法编译"); quit(1); return
	result.compile_ms = (Time.get_ticks_usec() - start) / 1000.0
	print("TUNING PERF COMPILED ", JSON.stringify(result))
	result.seek_ms = {}
	var short_preview := "--short-preview" in OS.get_cmdline_user_args()
	for seconds in ([4] if short_preview else [4,150,299]):
		start = Time.get_ticks_usec(); await preview.seek_preview(seconds * 1000000)
		result.seek_ms[str(seconds)] = (Time.get_ticks_usec() - start) / 1000.0
		print("TUNING SEEK ", seconds, " ", result.seek_ms[str(seconds)])
	start = Time.get_ticks_usec()
	var advance_start := 4.0 if short_preview else 299.0
	for i in 60: preview.advance(advance_start + (i + 1) / 120.0, false)
	result.advance_average_ms = (Time.get_ticks_usec() - start) / 60000.0
	result.advance_start_seconds = advance_start
	StudioProjectIO.write_json("res://docs/chart-editor-tuning-short-preview.json" if short_preview else "res://docs/chart-editor-tuning-performance.json", result)
	print("TUNING PERF ", JSON.stringify(result))
	preview.queue_free(); view.queue_free(); timeline.queue_free(); await process_frame; quit()
