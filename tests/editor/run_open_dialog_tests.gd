extends SceneTree
## 通过文件列表的真实鼠标输入检查选中文件与打开，不绕过对话框直接调用加载。
var failures := 0
func _init() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1
func frames() -> void:
	for i in 12: await process_frame
func _run() -> void:
	var w = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	w.offer_recovery_on_start = false; w.recovery_path = "user://chart_studio/tests/open/recovery.json"
	root.add_child(w); await frames()
	w._open(); await frames()
	var dialog: FileDialog
	for child in w.get_children():
		if child is FileDialog: dialog = child
	if "--legacy-filter" in OS.get_cmdline_user_args(): dialog.filters = PackedStringArray(["song.json ; 歌曲项目"])
	dialog.current_dir = ProjectSettings.globalize_path("res://tests/editor/fixtures/training")
	await frames()
	var list: ItemList
	var index := -1
	for node in dialog.find_children("*", "ItemList", true, false):
		for i in node.item_count:
			if node.get_item_text(i) == "song.json": list = node; index = i
	check(index >= 0, "项目文件在列表可见")
	if index >= 0:
		var pos := list.get_global_rect().position + list.get_item_rect(index).get_center()
		for double in [false, true]:
			var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.position = pos; e.global_position = pos; e.pressed = true; e.double_click = double
			if DisplayServer.get_name() == "headless":
				if double: list.item_activated.emit(index)
				else: list.select(index); list.item_selected.emit(index)
			else: dialog.push_input(e, true)
			e = InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.position = pos; e.global_position = pos; e.pressed = false
			if DisplayServer.get_name() != "headless" and is_instance_valid(dialog): dialog.push_input(e, true)
			await process_frame
			if not double: check(dialog.get_line_edit().text == "song.json", "单击项目后文件名框显示 song.json")
	await frames()
	check(w.document.directory.replace("\\", "/").ends_with("tests/editor/fixtures/training"), "双击 song.json 装入项目")
	check(w.document.chart().note_events.size() > 0, "装入非空谱面的音符")
	w.queue_free(); await process_frame
	print("OPEN DIALOG TESTS: ", failures); quit(1 if failures else 0)
