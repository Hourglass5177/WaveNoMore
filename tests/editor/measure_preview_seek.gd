extends SceneTree
## 相同谱面、输入及目标：与旧恢复路径比较正式结果、活动音符及 Hold 脊线。
var failures := 0
func _initialize() -> void: run.call_deferred()
func capture(preview) -> Dictionary:
	var host = preview.stage_root.presentation._note_visual_host
	var visuals := {}
	for id in host._active:
		var entry: Dictionary = host._active[id]; var node: Node2D = entry.node
		visuals[id] = {"position": node.position, "rotation": node.rotation}
		if node is GrayboxHoldVisual:
			visuals[id].spine = node._path_spine.duplicate()
			visuals[id].state = node.visual_state_snapshot()
	var field: Dictionary = preview.stage_root.presentation._tuning_interference_visual.debug_snapshot()
	var waves := {}
	for key in ["life_wavefronts", "death_wavefronts", "life_guide_aligned", "death_guide_aligned", "su_overlay"]:
		waves[key] = field[key]
	return {"snapshot": preview.stage_root.gameplay_coordinator.snapshot(), "digest": preview.stage_root.gameplay_coordinator.result_digest(), "visuals": visuals, "waves": waves}
func run() -> void:
	var doc := StudioDocument.new()
	StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", doc)
	# 示例后追加密集 Tap，不动用户 test 工程。
	doc.chart().end_tick = 57600
	for i in 1000:
		var note := NoteEvent.new(); note.event_id = "stress%d" % i; note.affinity = i % 2
		note.tick = 11520 + i * 43; doc.chart().note_events.append(note)
	var results := {"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(), "notes": doc.chart().note_events.size(), "reference": {}, "optimized": {}}
	var expected := {}
	for mode in ["reference", "optimized"]:
		var view := SubViewport.new(); view.size = Vector2i(640,360); root.add_child(view)
		var preview = load("res://tests/editor/reference_preview_seek.gd" if mode == "reference" else "res://src/tools/chart_studio/preview_session.gd").new()
		root.add_child(preview)
		if not preview.load_preview(ChartProjectLoader.make_stage(doc.song, doc.chart()), view): quit(1); return
		for target in ([4.2, 6.2, 9.6] if "--quick" in OS.get_cmdline_user_args() else [4.2, 6.2, 9.6, 55.0]):
			var start := Time.get_ticks_usec()
			await preview.seek_preview(roundi(target * 1000000))
			results[mode][str(target)] = (Time.get_ticks_usec() - start) / 1000.0
			var state := capture(preview)
			if mode == "reference": expected[target] = state
			elif state != expected[target]:
				for key in state:
					if state[key] != expected[target][key]: print("DIFFERENCE ", target, " ", key)
				failures += 1
			print("SEEK ", mode, " ", target, " ms=", results[mode][str(target)])
		if mode == "reference": results.reference_publication_ms = preview.publication_us / 1000.0
		preview.queue_free(); view.queue_free(); await process_frame
	results.failures = failures
	StudioProjectIO.write_json("res://builds/preview-seek-quick.json" if "--quick" in OS.get_cmdline_user_args() else "res://builds/preview-seek-measurement.json", results)
	print("SEEK EQUIVALENCE: ", failures); quit(1 if failures else 0)
