extends SceneTree
## 读取实际谱面，在相同输入与采样时间下比较白光及 Ghost 段；不保存或修改用户工程。
var output := "res://builds/visual-review/note-glow/performance-before.json"
var project_path := "res://builds/chart-studio/test/song.json"

func _initialize() -> void: run.call_deferred()

func stats(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in sorted: total += value
	return {"mean_ms": total / sorted.size(), "p95_ms": sorted[int((sorted.size() - 1) * 0.95)], "max_ms": sorted[-1]}

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--project="): project_path = arg.trim_prefix("--project=")
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var loaded := ChartProjectLoader.load_stage(project_path)
	var viewport := SubViewport.new()
	viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new()
	root.add_child(preview)
	preview.sound_enabled = false
	if not preview.load_preview(loaded.stage, viewport): quit(1); return
	var compiled: CompiledChart = preview.stage_root.stage_session.compiled_chart
	var first: float = float(compiled.su_manifestations[0].time_us) / 1000000.0
	var start: float = maxf(0, first - 2.75)
	await preview.seek_preview(roundi((start + preview.offset_sec) * 1000000.0))
	var costs: Array = []
	var frames: Array = []
	var samples: Array = []
	var events: Array = []
	var prior_light := false
	var prior_ghosts := 0
	var host: NoteVisualHost = preview.stage_root.presentation._note_visual_host
	var previous := Time.get_ticks_usec()
	for i: int in range(1200):
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		previous = now
		var at: float = start + float(i + 1) / 120.0
		preview.advance(at + preview.offset_sec, false)
		var work_ms := float(Time.get_ticks_usec() - now) / 1000.0
		var lit := false
		for entry: Dictionary in host._active.values():
			if entry.node is GrayboxNoteVisual and entry.node.glow_amount > 0.0: lit = true
		var ghosts: int = preview.stage_root.gameplay_coordinator.simulation._su_prepared.size()
		if (lit and not prior_light) or ghosts != prior_ghosts:
			events.append({"time": at, "work_ms": work_ms, "frame_ms": frame_ms, "light": lit, "ghosts": ghosts})
		prior_light = lit
		prior_ghosts = ghosts
		costs.append(work_ms)
		frames.append(frame_ms)
		samples.append([at, work_ms, frame_ms, ghosts, lit])
	var targets: Dictionary = preview.stage_root.gameplay_coordinator.simulation._su_prepared.duplicate(true)
	var result := {"project": project_path, "start": start, "work": stats(costs), "frame": stats(frames), "events": events, "samples": samples, "targets": var_to_str(targets), "gpu": RenderingServer.get_video_adapter_name()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	result.erase("samples"); result.erase("targets")
	print("EFFECT PERFORMANCE ", JSON.stringify(result))
	preview.queue_free(); viewport.queue_free()
	await process_frame
	quit()
