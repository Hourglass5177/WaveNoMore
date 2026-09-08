extends SceneTree
## 紧凑五轨通过真实 Viewport 鼠标分发创建与选取，检查命中框不侵入相邻轨。
var failures := 0
var timeline: StudioTimeline
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func mouse(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = timeline.get_global_transform() * at; event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	root.push_input(event, true)
func draw(track: int, start: float, end: float) -> void:
	var y := timeline.track_y(track) + timeline.track_height(track) * 0.5
	var a := Vector2(start * timeline.pixels_per_second, y)
	var b := Vector2(end * timeline.pixels_per_second, y)
	mouse(a, true)
	if a != b:
		var motion := InputEventMouseMotion.new()
		motion.position = timeline.get_global_transform() * b; motion.global_position = motion.position
		motion.relative = b - a; motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
	mouse(b, false)
func run() -> void:
	root.size = Vector2i(1280,720)
	var doc := StudioDocument.new(); doc.new_project(); doc.chart().end_tick = 12000
	timeline = StudioTimeline.new(); timeline.size = Vector2(1200,320)
	root.add_child(timeline); timeline.bind(doc); timeline.view_start = 0; timeline.pixels_per_second = 120
	await process_frame; await process_frame
	check(timeline.folded.all(func(value): return value) and timeline.track_height(0) == 24, "默认五轨均为 24 像素紧凑行")
	check(timeline.track_y(0) == 72 and timeline.WAVE_BOTTOM - timeline.WAVE_TOP == 24, "标尺与波形压缩到 72 像素，波形带占 24 像素")
	timeline.rhythm_grid = {"bpm": 120.0, "anchor": 0.0, "meter": 4}
	mouse(Vector2(400, 28), true)
	check(timeline._mode == "rhythm", "候选节拍的拖动区域跟随压缩后的辅助尺")
	timeline.cancel_gesture(); mouse(Vector2(400, 28), false)
	mouse(Vector2(400, 48), true)
	check(timeline._mode == "seek", "波形定位区域与候选节拍拖动互不抢占")
	timeline.cancel_gesture(); mouse(Vector2(400, 48), false)
	timeline.rhythm_grid = {}
	draw(0, 1.5, 1.5); draw(1, 1.5, 1.5)
	check(doc.chart().note_events.size() == 2 and doc.chart().note_events[0].affinity != doc.chart().note_events[1].affinity, "紧凑生死轨点击分别放置 Tap")
	var count := doc.chart().note_events.size()
	draw(0, 1.5, 1.5)
	check(doc.chart().note_events.size() == count and timeline.selected.size() == 1, "点击已有紧凑 Tap 只选择，不叠加音符")
	draw(0, 2, 8); draw(1, 3, 9)
	check(doc.chart().note_events.filter(func(e): return e.kind == GameplayTypes.NoteKind.HOLD).size() == 2, "紧凑双轨可直接拖画 Hold")
	draw(2, 3.5, 7); draw(3, 4, 7.5)
	check(doc.chart().tuning_paths.size() == 2, "紧凑双 Hold 窗口可拖画双侧 Tuning")
	draw(4, 4.5, 4.5)
	check(doc.chart().ghost_events.size() == 1 and doc.chart().ghost_events[0].tuning_ids.size() == 2, "紧凑 Ghost 轨点击创建并关联双方")
	for e in ChartEditEvents.all(doc.chart()):
		var rect := timeline.note_rect(e); var track := ChartEditEvents.track(e)
		check(rect.size.y == 18 and rect.position.y >= timeline.track_y(track) and rect.end.y <= timeline.track_y(track) + 24, "紧凑音符绘制范围不越行 " + e.event_id)
		check(timeline._hit(Vector2(rect.get_center().x, timeline.track_y(track) + 24)) != e, "命中容差不抢相邻轨 " + e.event_id)
	var before := ChartJsonCodec.encode_chart(doc.chart())
	mouse(Vector2(30, timeline.track_y(2) + 12), true); mouse(Vector2(30, timeline.track_y(2) + 12), false)
	check(not timeline.folded[2] and timeline.track_height(2) == 48, "标题点击展开单轨")
	check(ChartJsonCodec.encode_chart(doc.chart()) == before, "展开轨道不改谱")
	timeline.queue_free(); await process_frame
	print("COMPACT TRACK TESTS: ", failures); quit(1 if failures else 0)
