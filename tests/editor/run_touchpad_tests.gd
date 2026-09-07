extends SceneTree
## 通过 Viewport 的真实 Control 分发入口注入触摸板/鼠标事件；不冒充真机驱动测试。
var failures := 0
var timeline: StudioTimeline
var observations := {"browse": 0, "seek": 0, "view": 0, "events": 0}

func _init() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

# 输入事件的 factor 为单精度；比较容差远小于一个逻辑像素，不要求十进制精确表示。
func near(first: float, second: float) -> bool: return absf(first - second) < 0.000001

func settle() -> void:
	await process_frame
	await process_frame

func dispatch(event: InputEvent) -> void:
	root.push_input(event, true)

func wheel(button: MouseButton, factor: float, ctrl := false, at := Vector2(240, 180)) -> void:
	var event := InputEventMouseButton.new()
	event.position = timeline.get_global_transform() * at
	event.global_position = event.position
	event.button_index = button; event.factor = factor; event.pressed = true; event.ctrl_pressed = ctrl
	dispatch(event)

func pan(delta: Vector2, at := Vector2(240, 180)) -> void:
	var event := InputEventPanGesture.new()
	event.position = timeline.get_global_transform() * at; event.delta = delta
	dispatch(event)

func click(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = timeline.get_global_transform() * at
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	dispatch(event)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var doc := StudioDocument.new(); doc.new_project()
	var note := NoteEvent.new(); note.event_id = "hold"; note.tick = 960; note.duration_ticks = 480
	note.kind = GameplayTypes.NoteKind.HOLD
	doc.execute("测试音符", [], [note])
	timeline = StudioTimeline.new(); timeline.position = Vector2(16, 24); timeline.size = Vector2(800, 280)
	root.add_child(timeline); timeline.bind(doc)
	timeline.manual_browse.connect(func() -> void: observations.browse += 1)
	timeline.seek_requested.connect(func(_seconds: float) -> void: observations.seek += 1)
	timeline.view_changed.connect(func() -> void: observations.view += 1)
	timeline.gui_input.connect(func(_event: InputEvent) -> void: observations.events += 1)
	timeline.selected = PackedStringArray(["hold"]); timeline.playhead = 3.25
	await settle()
	var before := ChartJsonCodec.encode_chart(doc.chart())
	var revision := doc.revision
	timeline.view_start = 20; timeline.pixels_per_second = 160
	var count: int = observations.browse
	var views: int = observations.view
	wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.125); wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.125)
	check(near(timeline.view_start, 20), "同帧滚轮先合并，不逐事件重绘")
	await settle()
	check(near(timeline.view_start, 20.15625) and observations.browse == count + 1 and observations.view == views + 1, "高精度横向滚动保留 factor，合并为一次视图修改")
	wheel(MOUSE_BUTTON_WHEEL_LEFT, 0.25); await settle()
	check(near(timeline.view_start, 20), "左右滚轮方向对称")
	wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.5); await settle()
	check(near(timeline.view_start, 20.3125), "普通上下滚轮保留横移习惯及 factor")
	wheel(MOUSE_BUTTON_WHEEL_UP, 0.5); await settle()
	check(near(timeline.view_start, 20), "普通上滚轮反向恢复")
	for horizontal_first in [false, true]:
		if horizontal_first:
			wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.2); wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.9)
		else:
			wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.9); wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.2)
		await settle()
		check(near(timeline.view_start, 20.125), "斜滑以横向为准，与事件顺序无关：%s" % horizontal_first)
		timeline.view_start = 20
	wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.2); wheel(MOUSE_BUTTON_WHEEL_LEFT, 0.2); wheel(MOUSE_BUTTON_WHEEL_DOWN, 1)
	await settle()
	check(near(timeline.view_start, 20), "同帧横向抵消后不意外采用纵向分量")
	pan(Vector2(0.25, 0.75)); await settle()
	check(near(timeline.view_start, 20.05), "PanGesture 横轴每单位 32 逻辑像素，忽略斜滑纵轴")
	pan(Vector2(-0.25, 0)); await settle()
	pan(Vector2(0, -0.5)); await settle()
	check(near(timeline.view_start, 19.9), "PanGesture 纵向分量在没有横向时仍可浏览")
	timeline.view_start = 20
	var anchor := timeline.view_start + 240.0 / timeline.pixels_per_second
	wheel(MOUSE_BUTTON_WHEEL_UP, 0.2, true); wheel(MOUSE_BUTTON_WHEEL_UP, 0.3, true)
	await settle()
	check(near(timeline.pixels_per_second, 160 * pow(1.2, 0.5)) and near(timeline.view_start + 240.0 / timeline.pixels_per_second, anchor), "Ctrl 高精度滚轮按累计 factor 缩放，保持鼠标下的时间")
	wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.5, true); await settle()
	check(near(timeline.pixels_per_second, 160) and near(timeline.view_start, 20), "相反 Ctrl 滚动精确还原视口")
	wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.1, true); wheel(MOUSE_BUTTON_WHEEL_UP, 1, true)
	await settle()
	check(near(timeline.pixels_per_second, 160) and near(timeline.view_start, 20.0625), "Ctrl 斜向滑动仅横移，不夹带纵向缩放")
	timeline.view_start = 10000; timeline.pixels_per_second = 3000
	wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.0001); await settle()
	check(near(timeline.view_start, 10000 + 0.01 / 3000), "远端视口的细小滚动不会被相对近似比较吞掉")
	for scale_factor in [1.0, 1.25, 1.5]:
		timeline.scale = Vector2.ONE * scale_factor; timeline.view_start = 20; timeline.pixels_per_second = 160
		wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.5); await settle()
		check(near(timeline.view_start, 20.3125), "缩放 %s 下实际 Control 分发保持逻辑滚动尺度" % scale_factor)
	timeline.scale = Vector2.ONE; timeline.view_start = 0
	# 逐一覆盖各编辑状态的浏览隔离；随后再通过真实按下检查滚动与绘制的先后顺序。
	for gesture in ["draw", "move", "head", "tail", "box", "align_marker", "align_wave", "rhythm", "seek", "loop_start", "loop_end", "pan"]:
		timeline._mode = gesture
		count = observations.browse
		wheel(MOUSE_BUTTON_WHEEL_RIGHT, 2); wheel(MOUSE_BUTTON_WHEEL_UP, 1, true); pan(Vector2(1, 1))
		# 手势内部边缘自动滚动不属于本测试。
		timeline._current = Vector2(400, 180)
		await settle()
		check(near(timeline.view_start, 0) and near(timeline.pixels_per_second, 160) and observations.browse == count, "进行 %s 手势时忽略触摸板和滚轮" % gesture)
	timeline._mode = ""
	wheel(MOUSE_BUTTON_WHEEL_RIGHT, 0.25)
	click(Vector2(400, 180), true)
	check(timeline._mode == "draw" and near(timeline.view_start, 0.15625) and timeline._anchor_tick == timeline.tick_at(400), "同帧先滚动后按下绘制，起手基准采用最终视图")
	timeline.cancel_gesture()
	check(observations.events > 20, "事件确实经过 Viewport 到 Control 的输入分发")
	check(doc.revision == revision and ChartJsonCodec.encode_chart(doc.chart()) == before and timeline.selected == PackedStringArray(["hold"]) and timeline.playhead == 3.25 and observations.seek == 0, "全部浏览操作不改谱、不改选区、不定位播放头、不产生撤销历史")
	timeline.queue_free(); await process_frame
	print("TOUCHPAD TESTS: ", failures)
	quit(1 if failures else 0)
