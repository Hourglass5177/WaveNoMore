extends SceneTree

## 固定负载隔离表现开销：32 Tap、4 Hold、16 Ghost 点与连续四枚裂解。

func _initialize() -> void: run.call_deferred()

func stats(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value: float in values: total += value
	return {"mean_ms": total / values.size(), "p95_ms": values[int(values.size() * 0.95)], "max_ms": values[-1]}

func run() -> void:
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var style := GrayboxNoteVisual.EFFECT_STYLE
	var theme := load("res://content/stages/s08/stage_visual_theme.tres") as StageVisualTheme
	var viewport := SubViewport.new(); viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var stage := Node2D.new(); viewport.add_child(stage)
	var notes: Array[GrayboxNoteVisual] = []
	for i: int in 32:
		var tap := GrayboxNoteVisual.new()
		tap.tap_texture = theme.zhu_tap_texture; tap.tap_material = theme.zhu_tap_material.duplicate(false)
		stage.add_child(tap)
		tap.prepare({"event_id": "dense%d" % i, "affinity": i % 2, "double_tap": true})
		tap.position = Vector2(140 + (i % 8) * 230, 110 + (i / 8) * 180)
		tap.set_approach_progress(1.0); notes.append(tap)
	for i: int in 4:
		var hold := GrayboxHoldVisual.new()
		hold.head_texture = theme.zhu_hold_head_texture
		hold.body_texture = load("res://assets/image/note/hold_body.png")
		stage.add_child(hold)
		hold.prepare({"event_id": "hold%d" % i, "affinity": i % 2, "unit_kind": &"hold", "end_us": 5000000})
		hold.position = Vector2(420 + i * 460, 900)
		hold.set_body_target(280); hold.advance_body(0.0); notes.append(hold)
	var ghost := SuManifestationOverlay.new(); stage.add_child(ghost)
	var points := PackedVector2Array()
	for i: int in 16: points.append(Vector2(0.12 + (i % 8) * 0.11, 0.30 + (i / 8) * 0.2))
	ghost.prepare_targets({"event_id": "fixed_ghost", "time_us": 0, "points": points})
	var effects := NoteFragmentHost.new(); stage.add_child(effects)
	var result := []
	for phase: int in 4:
		style.enabled = phase % 2 == 1
		effects.clear()
		for item: GrayboxNoteVisual in notes: item.configure_effect_style(style, item.affinity)
		var frames := []; var work := []; var draw_calls := []; var first_burst := 0.0
		var previous := Time.get_ticks_usec()
		for frame: int in 420:
			await process_frame
			var now := Time.get_ticks_usec()
			var elapsed := float(now - previous) / 1000.0; previous = now
			var at := float(frame) / 120.0
			effects.set_time(at)
			for item: GrayboxNoteVisual in notes:
				if item is GrayboxHoldVisual:
					item.set_tuning_glow(true, at); item.advance_body(1.0 / 120.0)
				else: item.set_note_glow_time(at, 0.5)
			if frame % 20 == 0:
				for i: int in 4: effects.burst("%d/%d" % [frame, i], notes[i * 8].effect_snapshot(), at, Vector2.RIGHT)
			var cost := float(Time.get_ticks_usec() - now) / 1000.0
			if frame == 20: first_burst = cost
			if frame >= 60:
				frames.append(elapsed); work.append(cost)
				draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		result.append({"enabled": style.enabled, "frame": stats(frames), "work": stats(work), "first_burst_work_ms": first_burst, "draw_calls_mean": stats(draw_calls).mean_ms})
		print("DENSITY ", JSON.stringify(result[-1]))
	style.enabled = true
	DirAccess.make_dir_recursive_absolute("res://builds/visual-review/note-effects")
	FileAccess.open("res://builds/visual-review/note-effects/density.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	quit()
