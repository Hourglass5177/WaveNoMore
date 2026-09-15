extends SceneTree
## 固定人工 UV 只用于正式背景上的美术审看；预测算法由领域测试覆盖。
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1920,1080)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var stage_root = load("res://scenes/stage/stage_root.tscn").instantiate()
	stage_root.auto_start_initial_stage = false
	stage_root.initial_stage = null
	canvas.add_child(stage_root)
	stage_root.stage_session.external_preview = true
	stage_root.stage_session.set_process(false)
	stage_root.song_clock.set_process(false)
	stage_root.set_debug_visible(false)
	var presentation = stage_root.presentation
	presentation.handheld_camera_enabled = false
	presentation.set_preview_time_driven()
	var stage := (load("res://content/stages/tutorial2/stage_definition.tres") as StageDefinition).duplicate(true)
	stage.resolve_dependencies_sync()
	if not stage_root.load_stage(stage,false): quit(1); return
	stage_root.stage_session.reset_preview()
	stage_root.stage_session.advance_preview(0)
	var field: TuningInterferenceVisual = presentation._tuning_interference_visual
	var overlay: SuManifestationOverlay = field._su_overlay
	overlay.prepare_targets({"event_id":"art_review", "time_us":3000000,"visible_from_us":300000,
		"points":[Vector2(.31,.29),Vector2(.72,.28),Vector2(.28,.72),Vector2(.69,.71)]})
	field.visible = true
	for item in [[.5,"stage-closed"],[2.4,"stage-opening"],[2.65,"stage-open"]]:
		overlay.set_visual_time(item[0])
		await process_frame
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png("res://builds/ghost-review/"+item[1]+".png")
	canvas.queue_free()
	await process_frame
	print("GHOST ART REVIEW: complete")
	quit()
