extends SceneTree

## 通过正式写谱器预览拍摄当前测试谱，不修改用户谱面或音频。
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1920, 1080)
	var path := ProjectSettings.globalize_path("res://../Charts/charts/test/song.json")
	var loaded := ChartProjectLoader.load_stage(path)
	var viewport := SubViewport.new(); viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	preview.sound_enabled = false
	if not preview.load_preview(loaded.stage, viewport): quit(1); return
	var output := "res://builds/visual-review/note-effects"
	DirAccess.make_dir_recursive_absolute(output)
	for time: float in [32.25, 32.76, 38.90]:
		await preview.seek_preview(roundi((time + preview.offset_sec) * 1000000.0))
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output + "/stage-%.2f.png" % time)
		print("CAPTURE ", time)
	preview.queue_free(); viewport.queue_free()
	await process_frame
	quit()
