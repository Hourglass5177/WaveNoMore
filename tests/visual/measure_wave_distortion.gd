extends SceneTree

## 正式预览路径，真实谱面的 Ghost 段；交替开关时只改变折射。
const OUTPUT := "res://builds/visual-review/wave-distortion-focus"
var capture := false
var fixed := false
func _initialize() -> void: run.call_deferred()
func stats(values: Array) -> Dictionary:
	var sorted := values.duplicate(); sorted.sort()
	var sum := 0.0
	for value: float in sorted: sum += value
	return {"mean_ms": sum / sorted.size(), "p95_ms": sorted[int((sorted.size() - 1) * 0.95)], "max_ms": sorted[-1]}

func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	fixed = "--fixed" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(OUTPUT + "/frames")
	DirAccess.make_dir_recursive_absolute(OUTPUT + "/frames-off")
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var loaded := ChartProjectLoader.load_stage(ProjectSettings.globalize_path("res://../Charts/charts/test/song.json"))
	# 本地测试谱未选场景，临时装配正式背景与音符素材，仅用于可复现的视觉负载。
	loaded.stage.visual_theme = load("res://content/stages/s08/stage_visual_theme.tres")
	loaded.stage.background = load("res://content/backgrounds/s00_grave_background.tres")
	var viewport := SubViewport.new(); viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	preview.sound_enabled = false
	if not preview.load_preview(loaded.stage, viewport): quit(1); return
	var field: TuningInterferenceVisual = preview.stage_root.presentation._tuning_interference_visual
	var warp: WaveDistortionVisual = preview.stage_root.presentation._distortion
	warp.style = warp.style.duplicate()
	var first: float = float(preview.stage_root.stage_session.compiled_chart.su_manifestations[0].time_us) / 1000000.0
	var start := maxf(0.0, first - 2.75)
	if fixed: start = first + 0.3
	var phases := []
	for phase: int in (1 if capture else 4):
		warp.style.enabled = capture or phase % 2 == 1; warp.refresh_style()
		await preview.seek_preview(roundi((start + preview.offset_sec) * 1000000.0))
		if fixed:
			# 固定正式画面并将波前数量推到 16+16 上限，隔离玩法重演的 CPU 波动。
			var fronts := []
			for side: int in 2:
				for i: int in 16: fronts.append({"affinity": side, "radius_px": 70.0 + i * 100.0, "wave_id": "%d:%d" % [side, i]})
			field.set_gameplay_snapshot({"carrier_wavefronts": fronts})
		for frame: int in 30: await process_frame
		var frames := []; var work := []; var gpu := []; var first_front_frames := []; var max_ghosts := 0
		var saw_front := false; var first_frame := -1
		var previous := Time.get_ticks_usec()
		for frame: int in (360 if capture else (360 if fixed else 960)):
			await process_frame
			var now := Time.get_ticks_usec()
			var elapsed := float(now - previous) / 1000.0; previous = now
			var at := start + float(frame + 1) / (60.0 if capture else 120.0)
			if not fixed: preview.advance(at + preview.offset_sec, false)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
			work.append(float(Time.get_ticks_usec() - now) / 1000.0)
			frames.append(elapsed)
			max_ghosts = maxi(max_ghosts, preview.stage_root.gameplay_coordinator.simulation._su_prepared.size())
			if not saw_front and int(field.render_fronts.get("life_wavefront_count", 0)) + int(field.render_fronts.get("death_wavefront_count", 0)) > 0:
				saw_front = true; first_frame = frame
			if first_frame >= 0 and frame >= first_frame and frame <= first_frame + 3: first_front_frames.append(elapsed)
			if capture:
				# 同一已提交姿态切换折射，排除两次独立重演的其他动画差异。
				var previous_mode: int = preview.stage_root.process_mode
				preview.stage_root.process_mode = Node.PROCESS_MODE_DISABLED
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_jpg(OUTPUT + "/frames/%04d.jpg" % frame, 0.97)
				warp.style.enabled = false; warp.refresh_style()
				await process_frame
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_jpg(OUTPUT + "/frames-off/%04d.jpg" % frame, 0.97)
				warp.style.enabled = true; warp.refresh_style()
				preview.stage_root.process_mode = previous_mode
		phases.append({"enabled": warp.style.enabled, "frame": stats(frames), "gpu": stats(gpu), "work": stats(work), "first_front_frames_ms": first_front_frames, "max_prepared_ghosts": max_ghosts})
		print("WAVE PERFORMANCE ", JSON.stringify(phases[-1]))
	if not capture:
		FileAccess.open(OUTPUT + ("/performance-fixed.json" if fixed else "/performance.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "resolution": "1920x1080", "start": start, "phases": phases}, "  "))
	preview.free(); viewport.free()
	quit()
