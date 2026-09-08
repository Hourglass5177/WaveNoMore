extends SceneTree
## 在隔离副本验证恢复、ZIP、工程内加载，并保存可复查的真实渲染截图。
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1
func settle() -> void:
	for i in 8: await process_frame
func run() -> void:
	var document := StudioDocument.new()
	check(StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", document).is_empty(), "打开 v2 示例")
	check(StudioProjectIO.save_project(document, "user://chart_studio/tests/tuning_delivery/project").is_empty(), "另存为完整项目副本")
	check(StudioProjectIO.export_zip(document, "user://chart_studio/tests/tuning_delivery/tuning.zip").is_empty(), "同一份 v2 数据导出 ZIP")
	var loaded := ChartProjectLoader.load_stage("user://chart_studio/tests/tuning_delivery/tuning.zip")
	check(loaded.stage != null, "游戏共享入口读取 v2 ZIP")
	var w = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	w.offer_recovery_on_start = false; w.recovery_path = "user://chart_studio/tests/tuning_delivery/recovery.json"
	root.add_child(w); await settle()
	w._open_path(document.directory.path_join("song.json")); await settle()
	while w.preview.rebuilding: await process_frame
	w.document.add_difficulty("second", true); await settle()
	w._write_recovery()
	var recovery: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(w.recovery_path))
	print("RECOVERY KEYS ", recovery.keys())
	check(JSON.stringify(recovery).contains("ghost_events") and JSON.stringify(recovery).contains("tuning_paths"), "恢复稿保存新轨及多难度")
	w.document.new_project(); w._restore_recovery(recovery); await settle()
	check(w.document.current == 1 and w.document.chart().tuning_paths.size() == 2 and w.document.chart().ghost_events.size() == 2, "真实恢复入口还原当前难度和五轨内容")
	# 图像来自 Godot 实际窗口渲染，不是重新绘制的界面示意。
	w.document.current = 0; w.document.mark_changed(); await settle()
	w.timeline.selected = PackedStringArray(["life_tuning"]); w._inspect()
	w.timeline.view_start = -0.8; w.timeline.pixels_per_second = 120
	w._ui_scale = 1.0; root.size = Vector2i(1920, 1080); w._apply_ui_scale(); await settle()
	w.get_node("Layout/Split").split_offset = 500
	w._seek(4.8); await settle()
	while w.preview.rebuilding: await process_frame
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://builds/tuning-review")
		for window_size in [Vector2i(1280,720), Vector2i(1440,900), Vector2i(1920,1080)]:
			root.size = window_size; w._apply_ui_scale(); await settle()
			w.get_node("Layout/Split").split_offset = roundi(window_size.y * 0.41)
			w.get_node("Layout/Split/Top/Main").split_offset = window_size.x - 850
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://builds/tuning-review/workspace-%d.png" % window_size.x)
	await w.preview.seek_preview(6_200_000)
	var first_results: Dictionary = w.preview.ghost_results.duplicate(true)
	print("GHOST EXAMPLE RESULTS ", first_results)
	check(first_results.ghost_45.actual == 2, "正式预览生成指定的两个 Ghost，不继承隐藏中央禁区")
	check(first_results.ghost_60.actual == 2 and first_results.ghost_60.generation_issue == "insufficient_constructive_intersections", "示例第二批确实只有两个交点，明确报告不足")
	await w.preview.seek_preview(3_000_000)
	await w.preview.seek_preview(6_200_000)
	check(w.preview.ghost_results == first_results, "往返定位恢复两批 Ghost 数量")
	# 仅在内存副本将第一批改为三个，证明同一正式预览可以显示三个目标。
	var original: GhostEvent = w.document.find_note("ghost_45")
	var three: GhostEvent = original.duplicate(true); three.count = 3
	w.document.execute("三个 Ghost 预览检查", [original], [three])
	w._refresh_pending = false; w._rebuild_preview(); await settle()
	while w.preview.rebuilding: await process_frame
	await w.preview.seek_preview(4_600_000)
	check(w.preview.ghost_results.ghost_45.actual == 3, "正式预览生成指定的三个 Ghost")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/tuning-review/ghost-three.png")
	w.queue_free(); await settle()
	print("TUNING DELIVERY TESTS: ", failures); quit(1 if failures else 0)
