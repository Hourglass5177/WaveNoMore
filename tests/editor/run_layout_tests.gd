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
	check(w.timeline._vscroll.visible, "紧凑时间线显示轨道滚动条")
	for track in 5:
		w.timeline.track_scroll = w.timeline.track_y(track) + w.timeline.track_scroll - w.timeline.RULER
		w.timeline._update_track_scroll()
		var y: float = w.timeline.track_y(track)
		check(y + w.timeline.track_height(track) > w.timeline.RULER and y < w.timeline.size.y, "压缩后可滚动访问轨道 %d" % track)
	w._apply_workspace({"track_folded": [false,false,false,false,false]})
	check(w.timeline.folded.all(func(value): return value), "旧版工作区首次改用可编辑紧凑轨道")
	w.timeline.folded[2] = false
	var track_state: Dictionary = w._capture_workspace()
	w.timeline.folded.fill(true); w._apply_workspace(track_state)
	check(not w.timeline.folded[2] and w.timeline.folded[0], "新版工作区保存并恢复单轨展开选择")
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
