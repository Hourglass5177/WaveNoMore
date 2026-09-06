extends SceneTree
## 通过 Godot 输入分发验证快捷键与文字焦点，不直接调用工作区快捷键函数。
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func key(code: Key, pressed: bool, character := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = pressed; event.unicode = character
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	workspace.recovery_path = "user://chart_studio/tests/run_input_tests/recovery.json"
	workspace.offer_recovery_on_start = false
	root.add_child(workspace)
	await process_frame
	workspace.timeline.grab_focus()
	await key(KEY_SPACE, true, 32); await key(KEY_SPACE, false, 32)
	check(workspace.audio.playing, "空格播放")
	await key(KEY_SPACE, true, 32); await key(KEY_SPACE, false, 32)
	check(not workspace.audio.playing, "空格暂停")
	workspace.audio.seek(0)
	await key(KEY_F, true, 102)
	await key(KEY_RIGHT, true); await key(KEY_RIGHT, false)
	await key(KEY_F, false, 102)
	check(workspace.document.chart().note_events.size() == 1 and workspace.document.chart().note_events[0].duration_ticks == 120, "F 按住并步进生成 Hold")
	var title: LineEdit = workspace.library.get_node("SongTitle")
	title.grab_focus(); title.caret_column = title.text.length()
	var previous := title.text
	await key(KEY_SPACE, true, 32); await key(KEY_SPACE, false, 32)
	await key(KEY_J, true, 106); await key(KEY_J, false, 106)
	check(title.text == previous + " j" and not workspace.audio.playing and workspace.document.chart().note_events.size() == 1, "文字焦点保留空格和 F/J 字符输入")
	title.release_focus()
	await process_frame
	var bpm: SpinBox
	for control in workspace.fields.get_children():
		if control is SpinBox and control.max_value == 1000: bpm = control
	bpm.get_line_edit().grab_focus(); bpm.get_line_edit().text = "135.125"
	workspace.document.directory = "user://chart_studio/tests/keyboard_save"
	workspace.get_node("Layout/Toolbar/Save").pressed.emit()
	await process_frame
	var reopened := StudioDocument.new()
	var error := StudioProjectIO.open_project(workspace.document.directory.path_join("song.json"), reopened)
	check(error.is_empty() and reopened.chart().tempo_events[-1].bpm == 135.125, "未按 Enter 直接保存也包含小数 BPM 编辑")
	workspace.document.undo()
	check(workspace.document.chart().tempo_events.size() == 1, "属性提交只产生一次撤销")
	workspace.queue_free()
	await process_frame
	print("INPUT TESTS: ", failures)
	quit(1 if failures else 0)
