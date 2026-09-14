extends "res://tests/visual/capture_lingjun_states.gd"
## 两个实际视口检查角色缩放和裙摆；仅生成工程内样张。
func _run() -> void:
	for width in [1920, 960]:
		var canvas := _canvas(Vector2i(width, width * 9 / 16))
		# 使用游戏的设计画布伸缩；直接缩小 SubViewport 只会裁切坐标。
		canvas.size_2d_override = Vector2i(1920, 1080)
		canvas.size_2d_override_stretch = true
		canvas.get_child(0).queue_free()
		var scene = load("res://scenes/stage/stage_root.tscn").instantiate()
		scene.auto_start_initial_stage = false
		scene.initial_stage = null
		canvas.add_child(scene)
		var stage := (load("res://content/stages/s08/stage_definition.tres") as StageDefinition).duplicate(true)
		stage.resolve_dependencies_sync()
		scene.stage_session.external_preview = true
		scene.stage_session.pause_on_focus_loss = false
		scene.stage_session.set_process(false)
		scene.load_stage(stage, false)
		scene.set_debug_visible(false)
		scene.presentation.set_preview_time_driven()
		scene.stage_session.reset_preview()
		scene.presentation._update_actor_snapshot({"time_us": 0, "life_held": false, "death_held": false})
		scene.presentation._update_actor_snapshot({"time_us": 1350000, "life_held": false, "death_held": false})
		await _save(canvas, "walk-%d.png" % width)
		canvas.queue_free()
		await process_frame
	quit()
