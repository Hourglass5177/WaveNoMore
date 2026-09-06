extends SceneTree
## 验证状态来自实际播放控制器，并检查容器在不同逻辑尺寸下的布局。
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new(); event.keycode = code; event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	root.add_child(workspace)
	workspace._open_path("res://tests/editor/fixtures/training/song.json")
	for frame in 30: await process_frame
	while workspace.preview.rebuilding: await process_frame
	workspace.timeline.grab_focus()
	await key(KEY_SPACE)
	check(workspace.audio.playing and workspace.get_node("%Play").icon == workspace.PAUSE_ICON, "空格播放同步暂停图标")
	workspace.get_node("%Play").pressed.emit()
	check(not workspace.audio.playing and workspace.get_node("%Play").icon == workspace.PLAY_ICON, "点击暂停同步播放图标")
	workspace.audio.seek(1.0); await key(KEY_I)
	workspace.audio.seek(2.0); workspace.get_node("%Out").pressed.emit()
	await key(KEY_L)
	check(workspace.audio.loop_start == 1.0 and workspace.audio.loop_end == 2.0 and workspace.get_node("%Loop").button_pressed, "循环快捷键与按钮共享范围和选中状态")
	workspace.audio.set_playing(true); workspace.audio.seek(2.01)
	await process_frame
	check(workspace.audio.position < 1.2 and workspace.audio.playing, "循环回到起点仍保持播放状态")
	workspace.audio.loop_enabled = false
	workspace.audio.seek(7.98)
	await create_timer(0.15).timeout
	check(not workspace.audio.playing and workspace.get_node("%Play").icon == workspace.PLAY_ICON, "歌曲自然结束恢复播放图标")
	var rates := [0.5, 0.75, 1.0, 1.25, 1.5]
	for i in rates.size():
		workspace.get_node("%Rate").item_selected.emit(i)
		check(workspace.audio.rate == rates[i] and workspace.get_node("%Rate").selected == i, "倍率选择 %s" % rates[i])
	workspace.audio.set_rate(1.0)
	workspace.get_node("%Snap").select(7); workspace.get_node("%Snap").item_selected.emit(7)
	check(workspace.timeline.snap_ticks == 0, "关闭吸附保留自由输入")
	workspace.get_node("%Snap").select(2); workspace.get_node("%Snap").item_selected.emit(2)
	var original_directory: String = workspace.document.directory
	workspace.document.directory = "user://chart_studio/tests/ui_workspace"
	workspace.audio.loop_enabled = true; workspace.audio.set_rate(1.25)
	workspace.get_node("%Snap").select(6)
	workspace._save_workspace()
	workspace.audio.loop_enabled = false; workspace.audio.set_rate(1.0)
	workspace.get_node("%Snap").select(2)
	workspace._load_workspace()
	check(workspace.get_node("%Loop").button_pressed and workspace.get_node("%Rate").selected == 3 and "三连音" in workspace.get_node("%Snap").tooltip_text, "恢复工作区同步循环、倍率和吸附提示")
	workspace.document.directory = original_directory
	workspace.audio.loop_enabled = false; workspace.audio.set_rate(1.0)
	workspace.get_node("%Snap").select(2); workspace.get_node("%Snap").item_selected.emit(2)

	workspace.timeline.selected = PackedStringArray(["n01", "n05"])
	workspace._inspect()
	var conversions := 0
	for control in workspace.fields.get_children():
		if control is Button and control.text in ["转为长音", "转为单击"]: conversions += 1
	check(conversions == 2, "混合选区给出两个明确转换目标")
	workspace._convert_selected(GameplayTypes.NoteKind.HOLD)
	check(workspace.document.find_note("n01").duration_ticks == 120 and workspace.document.find_note("n05").duration_ticks == 960, "批量转长音保留原长音时长")
	workspace.document.undo()
	check(workspace.document.find_note("n01").kind == GameplayTypes.NoteKind.TAP, "一次撤销恢复混合选区")
	workspace.timeline.selected = PackedStringArray(["n01"]); workspace._inspect()
	var has_duration := false
	for control in workspace.fields.get_children():
		if control is Label and control.text == "长音时长（tick）": has_duration = true
	check(not has_duration, "单击选区不显示无效长音输入")
	workspace.timeline.selected.clear(); workspace._inspect()
	# 加入实际玩法冲突，验证问题面板展开、折叠和对象定位。
	var copy: NoteEvent = workspace.document.find_note("n05").duplicate(true)
	copy.event_id = "ui_conflict"
	copy.duration_ticks = -1
	workspace.document.execute("冲突草稿", [], [copy])
	for frame in 5: await process_frame
	check(workspace.problems.item_count > 0 and workspace.problems.visible, "新问题自动展开")
	workspace.problems.item_selected.emit(0)
	check(is_equal_approx(workspace.audio.position, 3.5), "问题点击定位音符")
	workspace.get_node("Layout/ProblemToggle").button_pressed = false
	check(not workspace.problems.visible, "问题面板可以手动收起")
	workspace.document.undo()
	for frame in 20: await process_frame
	while workspace.preview.rebuilding: await process_frame
	check(workspace.problems.item_count == 0 and not workspace.problems.visible and not "无法预览" in workspace.status.text, "问题消失后收起列表并清除过期提示")
	workspace._seek(4.2)
	while workspace.preview.rebuilding: await process_frame
	workspace.timeline.view_start = 0

	var results: Array = []
	for scenario in [[1280, 720, 1.0], [1440, 900, 1.0], [1920, 1080, 1.0], [1280, 900, 1.25], [1600, 1000, 1.25], [1920, 1080, 1.5]]:
		root.content_scale_factor = scenario[2]
		root.min_size = Vector2i(Vector2(1024, 720) * scenario[2])
		root.size = Vector2i(scenario[0], scenario[1])
		for frame in 8: await process_frame
		var visible := root.get_visible_rect()
		var valid := visible.encloses(workspace.get_node("Layout").get_global_rect())
		var groups: Array[Node] = workspace.transport.get_children()
		for i in groups.size():
			valid = valid and visible.encloses(groups[i].get_global_rect())
			for j in range(i + 1, groups.size()): valid = valid and not groups[i].get_global_rect().intersects(groups[j].get_global_rect())
		valid = valid and workspace.timeline.size.y >= 244
		var name := "%dx%d_%d" % [scenario[0], scenario[1], roundi(scenario[2] * 100)]
		check(valid, "布局不越界且分组不重叠 " + name)
		results.append({"scenario": name, "valid": valid, "logical_size": str(visible.size), "window_size": str(root.size)})
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://builds/ui-review")
			root.get_texture().get_image().save_png("res://builds/ui-review/" + name + ".png")
	StudioProjectIO.write_json("res://builds/ui-review/layout-results.json", {"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(), "system_scale": DisplayServer.screen_get_scale(), "cases": results})
	workspace.queue_free(); await process_frame
	print("UI TESTS: ", failures)
	quit(1 if failures else 0)
