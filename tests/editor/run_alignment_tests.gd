extends SceneTree
## 首拍对齐回归：真实文档、时间线手势、保存及多难度历史。
var failures := 0

func _init() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func _run() -> void:
	_test_document()
	await _test_workspace()
	print("ALIGNMENT TESTS: ", failures)
	quit(1 if failures else 0)

func near(a: float, b: float) -> bool: return absf(a - b) < 0.0000001

func _test_document() -> void:
	var doc := StudioDocument.new()
	check(StudioProjectIO.open_project("res://tests/editor/fixtures/training/song.json", doc).is_empty(), "打开基准乐句")
	doc.chart().chart_offset_ticks = 480
	var before := ChartJsonCodec.encode_chart(doc.chart())
	var note := doc.chart().note_events[0]
	doc.set_first_beat_offset_ms(65123.456)
	check(near(doc.offset_sec(), 65.123456), "长前奏保留微秒精度")
	var after := ChartJsonCodec.encode_chart(doc.chart())
	after.timing.first_beat_offset_ms = before.timing.first_beat_offset_ms
	check(after == before and doc.chart().note_events[0] == note, "首拍命令保留音符对象、BPM、tick 偏移及所有扩展数据")
	check(doc.tempo_map().tick_to_us(1440) == 67123456 and doc.tempo_map().tick_to_us(2400) == 67923456, "非零全谱偏移和变速段沿用正式换算")
	doc.undo(); check(near(doc.offset_sec(), 2.0), "撤销首拍修改")
	doc.undo(true); check(near(doc.offset_sec(), 65.123456), "重做精确恢复")
	var revision := doc.revision
	doc.set_first_beat_offset_ms(65123.456)
	check(doc.revision == revision, "无变化不产生历史")
	doc.add_difficulty("hard", true)
	doc.set_first_beat_offset_ms(-500.125)
	doc.current = 0
	doc.set_first_beat_offset_ms(doc.offset_sec() * 1000.0, true)
	doc.current = 1
	check(near(doc.offset_sec(), 65.123456), "显式同步其他难度")
	doc.undo()
	check(near(doc.offset_sec(), -0.500125), "项目级撤销恢复其他难度原值")
	doc.current = 0
	check(near(doc.offset_sec(), 65.123456), "同步撤销不影响原难度")
	doc.undo(true); doc.current = 1
	check(near(doc.offset_sec(), 65.123456), "切换难度后可重做整次同步")
	var directory := "user://chart_studio/tests/alignment_roundtrip"
	check(StudioProjectIO.save_project(doc, directory).is_empty(), "保存多难度对齐")
	var reopened := StudioDocument.new()
	check(StudioProjectIO.open_project(directory.path_join("song.json"), reopened).is_empty(), "重开对齐项目")
	for i in reopened.charts.size():
		reopened.current = i
		check(near(reopened.offset_sec(), 65.123456), "重开难度 %d 保留高精度偏移" % i)
	# ZIP 仅作为测试数据，验证交付协议，无游戏应用导出。
	var package := directory.path_join("alignment.zip")
	check(StudioProjectIO.export_zip(reopened, package).is_empty(), "导出测试谱面包")
	var zip := ZIPReader.new()
	check(zip.open(package) == OK, "读取测试交付包")
	var raw: Dictionary = JSON.parse_string(zip.read_file("charts/normal.json").get_string_from_utf8())
	check(near(raw.timing.first_beat_offset_ms, 65123.456), "交付包保存首拍字段且不升级格式")
	zip.close()

func mouse(timeline: StudioTimeline, at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = at; event.button_index = button; event.pressed = pressed; event.shift_pressed = shift
	timeline._gui_input(event)

func move(timeline: StudioTimeline, at: Vector2, shift := false) -> void:
	var event := InputEventMouseMotion.new(); event.position = at; event.shift_pressed = shift
	timeline._gui_input(event)

func settle(w: Control) -> void:
	for i in 10: await process_frame
	while w.preview.rebuilding: await process_frame

func _test_workspace() -> void:
	var w = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	w.offer_recovery_on_start = false; w.recovery_path = "user://chart_studio/tests/alignment/recovery.json"
	root.add_child(w)
	w._open_path("res://tests/editor/fixtures/training/song.json")
	await settle(w)
	var t: StudioTimeline = w.timeline
	# 测试手势直接通过真实控件入口；工作区接收信号并决定提交。
	t.set_waveform(PackedVector2Array([Vector2(-1, 1), Vector2(-0.5, 0.5)]), 8)
	t.view_start = 0; t.pixels_per_second = 160
	w._wave_move_button.button_pressed = true
	w.audio.seek(3.0); w.audio.set_playing(true)
	var original_x := t.x_at(960)
	var stage_id: int = w.preview.stage_root.get_instance_id()
	var notes: Array = ChartJsonCodec.encode_chart(w.document.chart()).notes
	mouse(t, Vector2(800, 48), true); move(t, Vector2(880, 48))
	check(not w.audio.playing and near(w.audio.position, 3), "开始对齐暂停音乐并保留源位置")
	check(near(w.document.offset_sec(), 2) and near(t.x_at(960), original_x), "波形右移时固定谱面，候选不写文档")
	check(near(t.view_start, -0.5), "右拖波形半秒，视口补偿方向正确")
	await process_frame
	check(w.preview.stage_root.get_instance_id() == stage_id, "候选拖动不重建正式预览")
	mouse(t, Vector2(880, 48), false)
	check(near(w.document.offset_sec(), 1.5), "松手提交半秒波形对齐")
	await settle(w)
	check(near(w.preview.stage_root.stage_session.stage_definition.song.first_beat_offset_sec, 1.5), "内嵌正式预览读取新首拍")
	w.document.undo(); check(near(w.document.offset_sec(), 2), "完整波形拖动一次撤销")
	# 首拍标记拖动保持波形坐标；中途按 Shift 不跳变。
	w._wave_move_button.button_pressed = false; t.view_start = 0
	var start := Vector2(320, 42)
	mouse(t, start, true); move(t, start + Vector2(32, 0)); move(t, start + Vector2(48, 0), true)
	mouse(t, start + Vector2(48, 0), false, MOUSE_BUTTON_LEFT, true)
	check(near(w.document.offset_sec(), 2.21) and near(t.view_start, 0), "拖首拍时波形固定，Shift 增量精细调整")
	for scale in [12.0, 3000.0]:
		t.pixels_per_second = scale; t.view_start = w.document.offset_sec() - 1
		var at := Vector2(scale, 42)
		var old: float = w.document.offset_sec()
		mouse(t, at, true); move(t, at + Vector2(scale * 0.1, 0)); mouse(t, at + Vector2(scale * 0.1, 0), false)
		check(near(w.document.offset_sec(), old + 0.1), "不同缩放下标记对齐 100 ms：%s" % scale)
	t.pixels_per_second = 160; t.view_start = 0
	w._wave_move_button.button_pressed = true
	var before_cancel: float = w.document.offset_sec()
	var revision: int = w.document.revision
	mouse(t, Vector2(800, 48), true); move(t, Vector2(850, 48))
	w._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(near(w.document.offset_sec(), before_cancel) and near(t.view_start, 0) and not t.is_aligning(), "失焦取消候选并恢复视口")
	mouse(t, Vector2(800, 48), true); move(t, Vector2(850, 48))
	t.grab_focus()
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	Input.parse_input_event(escape); await process_frame
	check(not t.is_aligning() and w.document.revision == revision, "Esc 取消不产生历史")
	w._wave_move_button.button_pressed = false
	mouse(t, Vector2(640, 48), true); mouse(t, Vector2(640, 48), false)
	check(near(w.audio.position, 4) and near(w.document.offset_sec(), before_cancel), "默认拖波形仍定位播放头")
	mouse(t, Vector2(400, 48), true, MOUSE_BUTTON_RIGHT)
	w._wave_context.hide(); w._wave_context.id_pressed.emit(0)
	check(near(w.document.offset_sec(), 2.5) and near(w.audio.position, 4), "波形右键设首拍不改变播放位置")
	w._alignment_bar.get_node("Actions/SetFirstBeat").pressed.emit()
	check(near(w.document.offset_sec(), 4), "当前位置设为首拍按钮")
	w._metronome_enabled = true; w._refresh_cues()
	var strong: Array = w.audio.cues.events.filter(func(e: Dictionary) -> bool: return e.sample == &"strong")
	check(w.get_node("%TickPosition").text == "tick 0" and near(strong[0].seconds, 4), "暂停调整同步游标及节拍器样本事件")
	var fine_controls: Array[Node] = w._offset_edit.get_parent().get_children()
	fine_controls[4].pressed.emit()
	check(near(w.document.offset_sec(), 4.0001), "精细按钮增加 0.1 ms")
	fine_controls[2].pressed.emit()
	check(near(w.document.offset_sec(), 3.9991), "普通按钮减少 1 ms")
	w.document.undo(); w.document.undo()
	check(near(w.document.offset_sec(), 4), "两次数值微调分别撤销")
	w._set_first_beat(-1.25); w._alignment_bar.get_node("Actions/LocateFirstBeat").pressed.emit()
	check(near(w.audio.position, -1.25), "定位负首拍支持前置空白")
	w.document.chart().chart_offset_ticks = 480
	w._set_first_beat(2)
	check("tick 0" in w._alignment_info.text, "非零全谱偏移显示实际谱面零点")
	w.document.chart().chart_offset_ticks = 0
	w.document.mark_changed(&"timing")
	t.selected = PackedStringArray(["n01"]); w._inspect()
	check(w._offset_edit.is_visible_in_tree(), "选中音符仍可编辑首拍")
	w._offset_edit.grab_focus(); w._offset_edit.text = "45001.234567"
	w.document.directory = "user://chart_studio/tests/alignment_ui"
	w.get_node("Layout/Toolbar/Save").pressed.emit()
	await process_frame
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(w.document.directory.path_join("charts/normal.json")))
	check(near(saved.timing.first_beat_offset_ms, 45001.234567), "数值未按 Enter 直接保存仍提交高精度长前奏")
	check(ChartJsonCodec.encode_chart(w.document.chart()).notes == notes, "全部对齐操作保持 Tap / Hold 数据原样")
	w._set_first_beat(45.002345678)
	w._write_recovery()
	var recovery: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(w.recovery_path))
	w._set_first_beat(1); w._restore_recovery(recovery)
	check(near(w.document.offset_sec(), 45.002345678), "自动恢复使用同一首拍数据")
	w.queue_free(); await process_frame
