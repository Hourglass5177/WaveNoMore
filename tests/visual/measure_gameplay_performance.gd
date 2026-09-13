extends SceneTree
## 同一谱段和输入、2K 实际渲染；正常播放不截图、不逐帧输出日志。
const OUTPUT := "res://builds/gameplay-performance"
var label := "current"
var mode := "preview"
var seconds := 10.0
var start_override := -1.0
var runs := 3
var capture := false
var show_window := false

func _initialize() -> void: run.call_deferred()

func stats(values: Array) -> Dictionary:
	var sorted := values.duplicate(); sorted.sort()
	var sum := 0.0; var over60 := 0; var over30 := 0
	for value: float in sorted:
		sum += value
		if value > 16.67: over60 += 1
		if value > 33.3: over30 += 1
	return {"mean_ms": sum / sorted.size(), "p95_ms": sorted[int((sorted.size()-1)*0.95)], "p99_ms": sorted[int((sorted.size()-1)*0.99)], "max_ms": sorted[-1], "over_16_67": over60, "over_33_3": over30}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--capture": capture = true
		if arg == "--visible": show_window = true
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--start="): start_override = float(arg.trim_prefix("--start="))
		if arg.begins_with("--runs="): runs = int(arg.trim_prefix("--runs="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 0
	var loaded := ChartProjectLoader.load_stage(ProjectSettings.globalize_path("res://../Charts/charts/test/song.json"))
	loaded.stage.visual_theme = load("res://content/stages/s08/stage_visual_theme.tres")
	loaded.stage.background = load("res://content/backgrounds/s00_grave_background.tres")
	var viewport := SubViewport.new(); viewport.size = Vector2i(2560,1440)
	viewport.size_2d_override = Vector2i(1920,1080); viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	if capture or show_window:
		var display := TextureRect.new(); display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; display.texture = viewport.get_texture(); display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(display)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview); preview.sound_enabled = false
	if not preview.load_preview(loaded.stage, viewport): quit(1); return
	var first: float = float(preview.stage_root.stage_session.compiled_chart.su_manifestations[0].time_us) / 1000000.0
	var start := maxf(0.0, first - 2.75) if start_override < 0 else start_override
	var phases := []
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for phase in runs:
		await preview.seek_preview(roundi((start + preview.offset_sec)*1000000))
		if show_window: root.grab_focus()
		for warm in 30: await process_frame
		var capture_start_frame := Engine.get_process_frames()
		var frames := []; var work := []; var gpu := []; var render_cpu := []; var samples := []
		var section_samples := {}; var last_sections := {}
		var node_counts := []
		var focused_frames := []; var background_frames := []
		var previous := Time.get_ticks_usec()
		GameplayFrameProfile.clear(); GameplayFrameProfile.enabled = true
		for frame in roundi(seconds * 60.0):
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now - previous)/1000.0); previous = now
			if root.has_focus(): focused_frames.append(frames.back())
			else: background_frames.append(frames.back())
			var at := start + float(frame + 1)/60.0
			if mode == "preview": preview.advance(at + preview.offset_sec, false)
			else: advance_session(preview, roundi(at*1000000.0))
			work.append(float(Time.get_ticks_usec() - now)/1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()))
			for key in GameplayFrameProfile.totals:
				if not section_samples.has(key): section_samples[key] = []
				section_samples[key].append(GameplayFrameProfile.totals[key] - float(last_sections.get(key,0.0)))
			last_sections = GameplayFrameProfile.totals.duplicate()
			if frame % 60 == 0: node_counts.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			samples.append([at,frames.back(),work.back(),gpu.back()])
			if capture and frame in [60,180,360]:
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png(OUTPUT.path_join("gameplay-%03d.png" % frame))
		GameplayFrameProfile.enabled = false
		var phase_result := {"frame":stats(frames),"work":stats(work),"gpu":stats(gpu),"render_cpu":stats(render_cpu),"sections_ms":GameplayFrameProfile.totals.duplicate(),"calls":GameplayFrameProfile.calls.duplicate(),"samples":samples}
		phase_result.capture_start_frame = capture_start_frame
		phase_result.first_second = stats(frames.slice(0,mini(60,frames.size())))
		phase_result.section_frames = {}
		for key in section_samples: phase_result.section_frames[key] = stats(section_samples[key])
		phase_result.node_counts = node_counts
		phase_result.focused_frames = stats(focused_frames) if not focused_frames.is_empty() else {}
		phase_result.background_count = background_frames.size()
		phases.append(phase_result)
		var brief := phase_result.duplicate(); brief.erase("samples"); brief.erase("section_frames"); brief.erase("node_counts"); print("GAMEPLAY PERF ", JSON.stringify(brief))
	var result := {"label":label,"mode":mode,"visible":show_window,"capture":capture,"resolution":"2560x1440","start":start,"duration":seconds,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"phases":phases}
	FileAccess.open(OUTPUT.path_join(label+"-"+mode+".json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	preview.free(); viewport.free(); quit()

func advance_session(preview: Node, target: int) -> void:
	# 使用相同带时间戳的输入驱动正式 step；不走预览的 120 Hz 身体重演。
	var session = preview.stage_root.stage_session
	preview.stage_root.gameplay_coordinator.defer_preview_snapshot = true
	while preview._cursor < preview._inputs.size() and preview._inputs[preview._cursor].timestamp_us <= target:
		var at: int = preview._inputs[preview._cursor].timestamp_us
		session.advance_preview(at, false)
		var batch: Array[SemanticInputSample] = []
		while preview._cursor < preview._inputs.size() and preview._inputs[preview._cursor].timestamp_us == at:
			batch.append(preview._inputs[preview._cursor]); preview._cursor += 1
		session.inject_preview_inputs(batch)
		session.advance_preview(at, true)
	var sample := ClockSample.new()
	sample.song_time_sec = float(target)/1000000.0
	sample.judge_time_sec = sample.song_time_sec; sample.visual_time_sec = sample.song_time_sec
	session.step(sample)
