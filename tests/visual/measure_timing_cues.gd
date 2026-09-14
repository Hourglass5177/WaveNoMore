extends SceneTree
## 1080p、48 个持续运动的计时环，交替开关柔光；记录帧耗时与首次显示。
const OUTPUT := "res://builds/timing-cue-review/performance.json"
func _initialize() -> void: run.call_deferred()
func stats(values: Array) -> Dictionary:
	var sorted := values.duplicate(); sorted.sort()
	var sum := 0.0
	for value: float in values: sum += value
	return {"mean_ms": sum / values.size(), "p95_ms": sorted[floori((sorted.size() - 1) * 0.95)], "max_ms": sorted[-1]}
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 0
	var viewport := SubViewport.new(); viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var bg := ColorRect.new(); bg.size = Vector2(1920, 1080); bg.color = Color("35404b"); viewport.add_child(bg)
	var style: TimingCueStyle = load("res://content/presentation/timing_cue_style.tres").duplicate()
	var rings: Array[TimingRingVisual] = []
	for i: int in 48:
		var ring := TimingRingVisual.new(); viewport.add_child(ring); ring.configure_timing_style(style)
		ring.prepare({"event_id": str(i), "affinity": i % 2}); ring.position = Vector2(170 + (i % 8) * 220, 110 + (i / 8) * 170)
		rings.append(ring)
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var phases := []
	for phase: int in 4:
		style.glow_enabled = phase % 2 == 1
		var frames := []; var gpu := []; var first := []
		var previous := Time.get_ticks_usec()
		for frame: int in 330:
			for i: int in rings.size(): rings[i].set_timing(1.0 - fmod(float(frame) / 240.0 + float(i) / 48.0, 1.0), 1.0)
			await process_frame; await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec(); var elapsed := float(now - previous) / 1000.0; previous = now
			if frame < 4: first.append(elapsed)
			if frame >= 30:
				frames.append(elapsed); gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		phases.append({"glow": style.glow_enabled, "frame": stats(frames), "gpu": stats(gpu), "first_four_frames_ms": first})
		print(JSON.stringify(phases[-1]))
	var result := {"gpu": RenderingServer.get_video_adapter_name(), "resolution": "1920x1080", "rings": rings.size(), "nodes_before": nodes_before, "nodes_after": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "phases": phases}
	DirAccess.make_dir_recursive_absolute(OUTPUT.get_base_dir())
	FileAccess.open(OUTPUT, FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	viewport.free(); quit()
