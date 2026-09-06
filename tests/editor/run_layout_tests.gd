extends SceneTree
## 检查高清渲染尺寸、分区限位和隐藏/恢复；恢复稿隔离，避免影响用户工程。
var failures := 0
func _init() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	print("PASS " if ok else "FAIL ", text)
	if not ok: failures += 1
func settle() -> void:
	for i in 12: await process_frame
func _run() -> void:
	var w = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	w.offer_recovery_on_start = false; w.recovery_path = "user://chart_studio/tests/layout/recovery.json"
	root.add_child(w)
	w._open_path("res://tests/editor/fixtures/training/song.json")
	await settle()
	while w.preview.rebuilding: await process_frame
	w._ui_scale = 1.5; root.size = Vector2i(1920, 1080); w._apply_ui_scale()
	await settle()
	var surface: TextureRect = w.viewport.get_parent()
	check(w.viewport.size.x >= 1920 and w.viewport.size.x >= surface.size.x * 1.5, "预览至少 1080p，并覆盖实际显示像素")
	var stage_id: int = w.preview.stage_root.get_instance_id()
	var before: float = surface.size.y
	w.get_node("Layout/Split").split_offset = 100000
	await settle()
	check(w.timeline.size.y <= 166 and surface.size.y >= before, "时间线可收至紧凑高度，把空间交给预览")
	for side in 2:
		var n := NoteEvent.new(); n.affinity = side
		var rect: Rect2 = w.timeline.note_rect(n)
		check(rect.size.y >= 16 and rect.end.y <= w.timeline.size.y, "压缩后轨道 %d 的音符仍可见可点" % side)
	var layout: Dictionary = w._capture_layout()
	w._layout_action(23); await settle()
	check(not w.timeline.visible and not w.get_node("Layout/Split/Top/LibraryScroll").visible and surface.size.y > before, "专注预览隐藏两侧栏及时间线，保留播放栏")
	check(w.viewport.size_2d_override == Vector2i(1920, 1080) and w.preview.stage_root.get_instance_id() == stage_id, "改变布局不重建关卡，也不改变游戏坐标")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://builds/layout-review")
		root.get_texture().get_image().save_png("res://builds/layout-review/focus.png")
	w._layout_action(23); await settle()
	check(w.timeline.visible and w._capture_layout().library == layout.library, "退出专注预览恢复原布局")
	w._layout_action(20); w._layout_action(21)
	var saved: Dictionary = w._capture_workspace()
	w._layout_action(24); await settle(); w._apply_workspace(saved); await settle()
	check(not w.get_node("Layout/Split/Top/Main/Inspector").visible and not w.get_node("Layout/Split/Top/LibraryScroll").visible, "工作区恢复保留侧栏状态")
	w._layout_action(24); await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/layout-review/workspace.png")
	w.queue_free(); await process_frame
	print("LAYOUT TESTS: ", failures); quit(1 if failures else 0)
