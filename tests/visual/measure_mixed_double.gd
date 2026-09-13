extends SceneTree
## 固定 24 个正式贴图音符，隔离双押白光，不把 Hold 身体运动计入开销。
func _initialize() -> void: run.call_deferred()
func stats(values: Array) -> Dictionary:
	var sorted := values.duplicate(); sorted.sort(); var sum := 0.0
	for value: float in values: sum += value
	return {"mean_ms": sum / values.size(), "p95_ms": sorted[floori((sorted.size() - 1) * 0.95)], "max_ms": sorted[-1]}
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 0
	var viewport := SubViewport.new(); viewport.size = Vector2i(1920, 1080); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var bg := ColorRect.new(); bg.size = Vector2(1920, 1080); bg.color = Color("35404b"); viewport.add_child(bg)
	var theme: StageVisualTheme = load("res://content/stages/s08/stage_visual_theme.tres")
	var notes: Array[GrayboxNoteVisual] = []; var body_rids := []
	for i: int in 24:
		var item: GrayboxNoteVisual
		if i % 2 == 0:
			var hold := GrayboxHoldVisual.new(); hold.head_texture = theme.zhu_hold_head_texture
			hold.body_texture = load("res://assets/image/note/hold_body.png"); item = hold
		else:
			item = GrayboxNoteVisual.new(); item.tap_texture = theme.zhu_tap_texture; item.tap_material = theme.zhu_tap_material.duplicate()
		viewport.add_child(item)
		item.prepare({"event_id": str(i), "unit_kind": &"hold" if i % 2 == 0 else &"tap", "affinity": i % 4 / 2, "start_us": 1000000, "end_us": 4000000})
		item.position = Vector2(220 + (i % 6) * 290, 150 + (i / 6) * 250)
		if item is GrayboxHoldVisual:
			item.set_body_target(150); item.advance_body(0.0); body_rids.append(item._body_mesh.get_rid())
		notes.append(item)
	var count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)); var phases := []
	for phase: int in 4:
		var on := phase % 2 == 1
		for item: GrayboxNoteVisual in notes: item._double_press = on
		var frames := []; var gpu := []; var first := []; var first_light := []; var previous := Time.get_ticks_usec()
		for frame: int in 240:
			var at := 0.30 + fmod(float(frame) / 300.0, 0.5)
			for item: GrayboxNoteVisual in notes: item.set_note_glow_time(at, 1.0 - at)
			await process_frame; await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec(); var elapsed := float(now - previous) / 1000.0; previous = now
			if frame < 4: first.append(elapsed)
			if on and frame >= 31 and frame <= 34: first_light.append(elapsed)
			if frame >= 30:
				frames.append(elapsed); gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		phases.append({"double_press": on, "frame": stats(frames), "gpu": stats(gpu), "first_four_frames_ms": first, "first_light_frames_ms": first_light}); print(JSON.stringify(phases[-1]))
	var after_rids := []
	for item: GrayboxNoteVisual in notes:
		if item is GrayboxHoldVisual: after_rids.append(item._body_mesh.get_rid())
	var output := "res://builds/mixed-double-review/performance.json"
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "resolution": "1920x1080", "notes": 24, "nodes_before": count, "nodes_after": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "body_meshes_unchanged": body_rids == after_rids, "phases": phases}, "  "))
	viewport.free(); quit()
