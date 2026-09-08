extends SceneTree
## 验证短任务不闪提示、慢任务可见、连续定位与清空，以及真实工作区覆盖范围。
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start = false
	workspace.recovery_path = "user://chart_studio/tests/preview_loading/recovery.json"
	root.add_child(workspace)
	for i in 8: await process_frame
	while workspace.preview.rebuilding: await process_frame
	var overlay = workspace.get_node("Layout/Split/Top/Main/PreviewColumn/Aspect/Preview/Loading")
	overlay.set_loading(true)
	await create_timer(0.08).timeout
	check(not overlay.visible, "短于 200 ms 的定位不显示蒙版")
	overlay.set_loading(false)
	await create_timer(0.15).timeout
	check(not overlay.visible, "快速完成后没有迟到的提示")
	overlay.set_loading(true)
	await create_timer(0.24).timeout
	check(overlay.visible and overlay.color.a > 0.5, "慢定位显示黑色半透明蒙版")
	overlay.set_loading(true)
	check(overlay.visible, "连续请求不重新隐藏已有蒙版")
	for window_size in [Vector2i(1280,720), Vector2i(1440,900), Vector2i(1920,1080)]:
		root.size = window_size
		for i in 4: await process_frame
		check(overlay.get_global_rect().is_equal_approx(overlay.get_parent().get_global_rect()), "蒙版只覆盖预览区 %d" % window_size.x)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/tuning-review/preview-loading.png")
	workspace.preview.clear_preview()
	check(not overlay.visible and not overlay.loading, "清空预览立即撤下提示")
	workspace._open_path("res://tests/editor/fixtures/tuning/song.json")
	for i in 8: await process_frame
	while workspace.preview.rebuilding: await process_frame
	workspace.preview.seek_preview(9600000)
	check(overlay.loading, "真实定位入口接通加载状态")
	while workspace.preview.rebuilding: await process_frame
	check(not overlay.loading and not overlay.visible, "真实定位完成立即隐藏")
	workspace.queue_free(); await process_frame
	print("PREVIEW LOADING TESTS: ", failures); quit(1 if failures else 0)
