extends SceneTree
## 五分钟一万音符，分别测量文档编辑、编译、普通推进和完整恢复。
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var count := 1000 if "--small" in OS.get_cmdline_user_args() else 10000
	var document = load("res://src/tools/chart_studio/studio_document.gd").new()
	document.new_project()
	document.chart().end_tick = 288000
	var notes: Array = []
	for i in count:
		var note := NoteEvent.new()
		note.event_id = "perf_%d" % i
		note.affinity = i % 2
		note.tick = roundi(i * 288000.0 / count)
		notes.append(note)
	var started := Time.get_ticks_usec()
	document.execute("一万音符", [], notes)
	var result := {"notes": count, "duration_seconds": 300, "insert_ms": (Time.get_ticks_usec() - started) / 1000.0, "engine": Engine.get_version_info().string, "cpu": OS.get_processor_name()}
	var view := SubViewport.new(); view.size = Vector2i(960, 540); root.add_child(view)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	started = Time.get_ticks_usec()
	var stage := ChartProjectLoader.make_stage(document.song, document.chart())
	if not preview.load_preview(stage, view):
		push_error("密集谱面未能编译")
		quit(1); return
	result.compile_ms = (Time.get_ticks_usec() - started) / 1000.0
	print("PERF COMPILED ", JSON.stringify(result))
	result.seek_targets_ms = {}
	for seconds in [0, 150, 299]:
		started = Time.get_ticks_usec()
		await preview.seek_preview(roundi(seconds * 1000000.0))
		result.seek_targets_ms[str(seconds)] = (Time.get_ticks_usec() - started) / 1000.0
		print("PERF SEEK ", seconds, " ", result.seek_targets_ms[str(seconds)])
	result.restore_ms = result.seek_targets_ms["299"]
	started = Time.get_ticks_usec()
	preview.advance(299.016, false)
	result.advance_ms = (Time.get_ticks_usec() - started) / 1000.0
	StudioProjectIO.write_json("user://chart_studio/performance.json", result)
	print(JSON.stringify(result))
	preview.queue_free(); view.queue_free()
	await process_frame
	quit()
