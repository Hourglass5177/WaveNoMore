extends SceneTree
## 真实工作区装载示例，等待重建并保存渲染结果，供人工检查布局。
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	root.add_child(workspace)
	workspace._open_path("res://tests/editor/fixtures/training/song.json")
	for frame in 30: await process_frame
	workspace._seek(4.2)
	while workspace.preview.rebuilding: await process_frame
	for frame in 10: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := "user://chart_studio/workspace.png"
		root.get_texture().get_image().save_png(path)
		print("SCREENSHOT ", ProjectSettings.globalize_path(path))
	workspace.queue_free()
	await process_frame
	print("WORKSPACE SMOKE COMPLETE")
	quit()
