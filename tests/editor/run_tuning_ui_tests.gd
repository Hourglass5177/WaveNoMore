extends SceneTree
## 真实 Control 手势、共享 Ghost 联动、当前游戏自动演示和跨版本文件闭环。
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1
func settle() -> void:
	for i in 8: await process_frame
func mouse(t, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.position = position; event.pressed = pressed
	t._gui_input(event)
func drag(t, from: Vector2, to: Vector2) -> void:
	mouse(t, from, true)
	var event := InputEventMouseMotion.new(); event.position = to; t._gui_input(event)
	mouse(t, to, false)
func run() -> void:
	var w = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	w.offer_recovery_on_start = false; w.recovery_path = "user://chart_studio/tests/tuning/recovery.json"
	root.add_child(w); await settle()
	w.document.new_project(); w.document.chart().end_tick = 12000
	w.document.song.audio_stream = ChartJsonCodec.load_audio("res://tests/editor/fixtures/training/audio/song.wav")
	w.audio.set_stream(w.document.song.audio_stream)
	var life := NoteEvent.new(); life.event_id = "life"; life.kind = GameplayTypes.NoteKind.HOLD; life.tick = 1920; life.duration_ticks = 5760
	var death := life.duplicate(true) as NoteEvent; death.event_id = "death"; death.affinity = 1; death.tick = 2880
	w.document.execute("双 Hold", [], [life, death]); await settle()
	var t = w.timeline
	t.view_start = 0; t.pixels_per_second = 100
	t.track_scroll = 0; t._update_track_scroll()
	# 轨道有滚动，不要求紧凑分区同时装下五行。
	t.size = Vector2(1000, 370)
	drag(t, Vector2(t.x_at(3360), t.track_y(2) + t.track_height(2) * 0.5), Vector2(t.x_at(6720), t.track_y(2) + t.track_height(2) * 0.5))
	check(w.document.chart().tuning_paths.size() == 1, "在双 Hold 窗口拖画 Tuning")
	if w.document.chart().tuning_paths.is_empty(): w.queue_free(); await settle(); quit(1); return
	var path: TuningPathEvent = w.document.chart().tuning_paths[0]
	check(path.hold_id == "life" and path.support_hold_id == "death", "自动绑定正确 Hold")
	var overlap := ChartEditEvents.new_path(w.document.chart(), 0, 3600, 6600)
	w._commit_events("非法重叠", [], [overlap])
	check(w.document.chart().tuning_paths.size() == 1, "新建同侧重叠 Tuning 被阻止")
	var second := ChartEditEvents.new_path(w.document.chart(), 1, 3840, 7200); second.event_id = "other"
	w.document.execute("死 Tuning", [], [second]); await settle()
	t.size = Vector2(1000, 370); t.track_scroll = 0
	mouse(t, Vector2(t.x_at(4320), t.track_y(4) + t.track_height(4) * 0.5), true)
	mouse(t, Vector2(t.x_at(4320), t.track_y(4) + t.track_height(4) * 0.5), false)
	check(w.document.chart().ghost_events.size() == 1, "点击 Ghost 轨创建批次")
	if w.document.chart().ghost_events.is_empty(): w.queue_free(); await settle(); quit(1); return
	var ghost: GhostEvent = w.document.chart().ghost_events[0]
	check(ghost.tuning_ids.size() == 2, "Ghost 自动关联双方")
	check(not ChartEditEvents.moving_ids(w.document.chart(), PackedStringArray([path.event_id])).has(ghost.event_id), "单侧移动，共同 Ghost 原位")
	check(ChartEditEvents.moving_ids(w.document.chart(), PackedStringArray([path.event_id, "other"])).has(ghost.event_id), "两侧移动，共同 Ghost 随动")
	w._refresh_pending = false
	var loads: int = w.preview.load_count
	w._toggle_boss(); await settle()
	check(w.document.find_note(ghost.event_id).boss, "Ghost BOSS 来源")
	check(t._indexed_notes.any(func(e): return e.event_id == ghost.event_id and e.boss), "BOSS 时间线缓存同步")
	check(w.preview.load_count == loads, "BOSS 不重建预览")
	w.document.undo(); check(not w.document.find_note(ghost.event_id).boss, "BOSS 一步撤销")
	check(not w.fields.get_node("BossFlag").button_pressed, "BOSS 属性撤销同步")
	# 缩短父 Hold 的三个选择使用同一命令，取消不改谱，删除可一步还原。
	var shortened := life.duplicate(true) as NoteEvent; shortened.duration_ticks = 1600
	w._commit_events("缩短 Hold", [life], [shortened]); await settle()
	var impact: ConfirmationDialog
	for child in w.get_children():
		if child is ConfirmationDialog and child.title == "关联内容受到影响": impact = child
	check(impact != null, "缩短 Hold 列出关联影响")
	if impact != null: impact.canceled.emit(); await settle()
	check(w.document.find_note("life").duration_ticks == life.duration_ticks, "取消缩短不改谱")
	w._commit_events("缩短 Hold", [life], [shortened]); await settle()
	for child in w.get_children():
		if child is ConfirmationDialog and child.title == "关联内容受到影响": impact = child
	impact.custom_action.emit(&"remove"); await settle()
	check(w.document.chart().tuning_paths.is_empty() and w.document.chart().ghost_events.is_empty(), "删除受影响的双侧 Tuning 和共同 Ghost")
	w.document.undo(); await settle()
	check(w.document.chart().tuning_paths.size() == 2 and w.document.chart().ghost_events.size() == 1, "整组影响一步撤销")
	# 在真实路径控件里添加节点，检查未应用候选不进入谱面。
	t.selected = PackedStringArray([path.event_id]); w._inspect()
	w._add_path_point(path.event_id, 5040); await settle()
	var dialog: AcceptDialog
	for child in w.get_children():
		if child is AcceptDialog and child.title == "添加 Tuning 转折点": dialog = child
	check(dialog != null and w.document.find_note(path.event_id).points.size() == 2, "添加节点先显示候选")
	if dialog != null:
		var editor = dialog.get_child(0)
		for child in dialog.get_children():
			if child is VBoxContainer and child.get_script() != null: editor = child
		editor.get_node("Apply").grab_focus(); editor.get_node("Apply").pressed.emit(); await settle()
	check(w.document.find_note(path.event_id).points.size() == 3, "图形控件应用转折点")
	w._refresh_pending = false; w._rebuild_preview(); await settle()
	while w.preview.rebuilding: await process_frame
	check(w.preview.stage_root != null, "新轨装入正式 StageRoot")
	if w.preview.stage_root != null:
		var compiled: CompiledChart = w.preview.stage_root.stage_session.compiled_chart
		var inputs := StudioPreviewInputs.build(compiled, w.preview.stage_root.stage_session.rule_set)
		check(inputs.filter(func(e): return e.is_press()).size() == 2, "Tuning 不生成额外敲钟")
		await w.preview.seek_preview(7400000)
		var snapshot: Dictionary = w.preview.get_preview_state().snapshot
		print("PREVIEW SNAPSHOT ", snapshot.get("score", {}))
		var sim: GameplaySimulation = w.preview.stage_root.gameplay_coordinator.simulation
		check(sim.strays.is_empty(), "自动演示无额外空按")
		await w.preview.seek_preview(10000000)
		for record in sim.judgments:
			check(record.grade != GameplayTypes.JudgmentGrade.MISS, "当前规则理想演示 " + record.unit_id)
		var tail: TuningPathEvent = w.document.find_note(path.event_id).duplicate(true)
		tail.duration_ticks = life.tick + life.duration_ticks - tail.tick
		w._commit_events("Tuning 与 Hold 同尾", [w.document.find_note(path.event_id)], [tail])
		w._refresh_pending = false; w._rebuild_preview(); await settle()
		while w.preview.rebuilding: await process_frame
		await w.preview.seek_preview(9000000)
		check(w.preview.stage_root.gameplay_coordinator.simulation.judgments.all(func(r): return r.grade != GameplayTypes.JudgmentGrade.MISS), "Tuning 与 Hold 同尾，结算后松键")
	# 多类型的序列化必须经过真实 JSON 文本，而非仅测试字典。
	var encoded := ChartJsonCodec.encode_chart(w.document.chart())
	var decoded := ChartJsonCodec.decode_chart(JSON.parse_string(JSON.stringify(encoded)))
	check(decoded.chart != null and decoded.chart.tuning_paths.size() == 2 and decoded.chart.ghost_events.size() == 1, "v2 文本 JSON 往返")
	w.queue_free(); await settle()
	print("TUNING UI TESTS: ", failures); quit(1 if failures else 0)
