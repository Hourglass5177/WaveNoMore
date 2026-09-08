extends SceneTree
## 试玩生命周期不得修改文档或让时间线丢失原有对象。
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func run() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start = false
	workspace.recovery_path = "user://chart_studio/tests/trial_document/recovery.json"
	root.add_child(workspace)
	var source := "res://tests/editor/fixtures/tuning/song.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--song="): source = arg.trim_prefix("--song=")
	workspace._open_path(source)
	for i in 10: await process_frame
	var original := ChartJsonCodec.encode_chart(workspace.document.chart())
	var count := ChartEditEvents.all(workspace.document.chart()).size()
	print("BEFORE ", count, " indexed=", workspace.timeline._indexed_notes.size())
	workspace.timeline.view_start = 0.0
	var visible: int = workspace.timeline.visible_notes(0, 10000).size()
	workspace.playtest.executable = ProjectSettings.globalize_path("res://builds/chart-studio/game/minghe.exe")
	workspace.playtest.temp_root = "user://chart_studio/tests/trial_document/trials"
	workspace._playtest()
	workspace._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(ChartJsonCodec.encode_chart(workspace.document.chart()) == original, "开始试玩和失焦保留文档")
	var deadline := Time.get_ticks_msec() + 30000
	while workspace.playtest._last_stage != "ready" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(workspace.playtest._last_stage == "ready", "真实配套游戏完成试玩加载")
	# 试玩期间继续修改注解；返回时即使最后通知无需重编谱面，也应刷新当前对象。
	var note: NoteEvent = workspace.document.chart().note_events[0]
	var copy := note.duplicate(true) as NoteEvent
	copy.boss = not copy.boss
	workspace.document.execute("试玩期间编辑", [note], [copy], {}, {}, &"annotation")
	original = ChartJsonCodec.encode_chart(workspace.document.chart())
	var revision: int = workspace.document.revision
	var cursors: Dictionary = workspace.document._cursors.duplicate(true)
	# 真实手柄 GUI 事件必须被隔离，不能只模拟损坏缓存后再检查重建。
	var first_beat: Button = workspace._alignment_bar.get_node("Actions/SetFirstBeat")
	first_beat.grab_focus()
	workspace.audio.seek(60.0)
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new(); event.button_index = JOY_BUTTON_A; event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	check(ChartJsonCodec.encode_chart(workspace.document.chart()) == original, "真实试玩进程运行时，手柄不能误触后台首拍按钮")
	if workspace.playtest.pid > 0: OS.kill(workspace.playtest.pid)
	while workspace.playtest.pid > 0: await process_frame
	workspace._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	for i in 10: await process_frame
	check(ChartJsonCodec.encode_chart(workspace.document.chart()) == original, "结束试玩保留文档")
	check(workspace.document.dirty and workspace.document.revision == revision and workspace.document._cursors == cursors, "返回不覆盖试玩期间的修改、不增加撤销记录")
	check(workspace.timeline._indexed_notes.size() == count and workspace.timeline.visible_notes(0, 10000).size() == visible, "试玩返回保留时间线索引及可见音符")
	print("AFTER ", ChartEditEvents.all(workspace.document.chart()).size(), " indexed=", workspace.timeline._indexed_notes.size(), " visible=", workspace.timeline.visible_notes(0, 10000).size())
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/trial-document.png")
	workspace.queue_free()
	await process_frame
	print("TRIAL DOCUMENT TESTS: ", failures)
	quit(1 if failures else 0)
