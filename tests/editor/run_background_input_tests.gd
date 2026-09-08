extends SceneTree
## 通过真实 GUI 输入复现：后台手柄确认误触首拍，波形保留而音符整体移出视野。
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func joy_button(index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index; event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start = false
	workspace.recovery_path = "user://chart_studio/tests/background_input/recovery.json"
	root.add_child(workspace)
	check(Input.ignore_joypad_on_unfocused_application, "原生手柄输入在应用失焦时由引擎拦截，包括弹窗")
	workspace._open_path("res://tests/editor/fixtures/training/song.json")
	for frame in 30: await process_frame
	workspace.timeline.view_start = -1.0
	workspace.audio.seek(60.0)
	var before := ChartJsonCodec.encode_chart(workspace.document.chart())
	var visible: int = workspace.timeline.visible_notes(120, workspace.timeline.size.x).size()
	check(visible > 0, "复现场景有可见音符")
	var target: Button = workspace._alignment_bar.get_node("Actions/SetFirstBeat")
	target.grab_focus()
	# 覆盖从点击试玩到游戏取得焦点，以及返回编辑器但试玩尚未退出的两个窗口。
	var original_fps := Engine.max_fps
	var loads: int = workspace.preview.load_count
	workspace.playtest._set_state(true, "试玩进行中")
	workspace._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(workspace.preview.suspended and Engine.max_fps <= 15, "后台试玩预览休眠，工具降频")
	await joy_button(JOY_BUTTON_A, true)
	await joy_button(JOY_BUTTON_A, false)
	check(ChartJsonCodec.encode_chart(workspace.document.chart()) == before, "后台手柄不能误触首拍或改写谱面")
	check(workspace.timeline.visible_notes(120, workspace.timeline.size.x).size() == visible, "后台输入后音符仍在原位置，波形时间基准不变")
	workspace._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not workspace.preview.suspended and Engine.max_fps == original_fps and workspace.preview.load_count == loads, "切回恢复原帧率，不重新装谱")
	var motion := InputEventJoypadMotion.new(); motion.axis = JOY_AXIS_LEFT_X; motion.axis_value = 1.0
	Input.parse_input_event(motion)
	await process_frame
	check(root.gui_get_focus_owner() == target, "试玩期间切回编辑器，摇杆不操作编辑控件")
	motion = InputEventJoypadMotion.new(); motion.axis = JOY_AXIS_LEFT_X; motion.axis_value = 0.0
	Input.parse_input_event(motion)
	# 仍可用键盘编辑：不能把整个工具停掉来隔离手柄。
	workspace.timeline.grab_focus()
	var count: int = workspace.document.chart().note_events.size()
	for pressed in [true, false]:
		var key := InputEventKey.new(); key.keycode = KEY_F; key.pressed = pressed
		Input.parse_input_event(key)
		await process_frame
	check(workspace.document.chart().note_events.size() == count + 1, "试玩期间切回仍可用 F 输入 Tap")
	workspace.document.undo()
	check(ChartJsonCodec.encode_chart(workspace.document.chart()) == before, "正常编辑可以独立撤销")
	workspace._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	workspace.playtest._set_state(false, "在游戏中试玩")
	check(not workspace.preview.suspended and Engine.max_fps == original_fps, "试玩退出即解除休眠，不依赖焦点事件顺序")
	workspace._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	target.grab_focus()
	var key := InputEventKey.new(); key.keycode = KEY_ENTER; key.pressed = true
	Input.parse_input_event(key)
	key = InputEventKey.new(); key.keycode = KEY_ENTER; key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	check(not is_equal_approx(workspace.document.offset_sec(), float(before.timing.first_beat_offset_ms) / 1000.0), "返回后键盘确认仍能主动修改首拍")
	workspace.document.undo()
	workspace.queue_free()
	await process_frame
	print("BACKGROUND INPUT TESTS: ", failures)
	quit(1 if failures else 0)
