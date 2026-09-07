extends SceneTree
## 检测点只作比较参照；合成时序证明诊断方向、精度和候选隔离。
var failures := 0

func _init() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frames() -> void:
	for i in 6: await process_frame

func _run() -> void:
	_test_application()
	var beats: Array = []
	var downbeats: Array = []
	for i in 96:
		beats.append(0.88 + i * 0.5)
		if i % 4 == 0: downbeats.append(beats.back())
	var raw := {"beats": beats, "downbeats": downbeats, "range": [0.0, 49.0]}
	var late := StudioRhythmTools.diagnose(raw, 120, 0.91, 4)
	check(absf(late.signed_ms - 30) < 0.00001 and absf(late.segments[0].trend_ms_per_sec) < 0.00001, "整体偏晚显示正数，不冒充漂移")
	var early := StudioRhythmTools.diagnose(raw, 120, 0.85, 4)
	check(absf(early.signed_ms + 30) < 0.00001, "整体偏早显示负数")
	var drift := StudioRhythmTools.diagnose(raw, 119, 0.88, 4)
	check(drift.segments[0].trend_ms_per_sec > 8 and str(drift.regions[0].reason).contains("逐渐偏晚"), "慢 BPM 网格给出有符号漂移趋势")
	var half := StudioRhythmTools.diagnose(raw, 240, 0.88, 4)
	check(half.segments[0].coverage < 0.55 and str(half.regions[0].reason).contains("半速"), "半速检测显示覆盖不足，而非识别准确率")
	var w = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	w.offer_recovery_on_start = false; w.recovery_path = "user://chart_studio/tests/rhythm_fit/recovery.json"
	root.add_child(w); w._open_path("res://tests/editor/fixtures/training/song.json"); await frames()
	while w.preview.rebuilding: await process_frame
	var panel: StudioRhythmPanel = w.rhythm
	var changes := [0]
	panel.audition_changed.connect(func() -> void: changes[0] += 1)
	panel.popup_centered()
	raw.fit = {"bpm": 138.123456789123, "anchor": 0.880123456789, "meter": 4, "anchor_confirmed": true}
	panel._received(raw); await frames()
	var bpm_before := panel._bpm.value
	var anchor_before := panel._anchor.value
	var revision: int = w.document.revision
	check(bpm_before == raw.fit.bpm and anchor_before == raw.fit.anchor, "候选控件不按显示步长截断检测精度")
	panel._bpm.get_line_edit().grab_focus(); await frames()
	panel._anchor.get_line_edit().grab_focus(); await frames()
	panel.gui_release_focus(); await frames()
	check(panel._bpm.value == bpm_before and panel._anchor.value == anchor_before and w.document.revision == revision, "只获得和失去焦点不改 BPM、锚点或谱面")
	panel._listen.button_pressed = true
	check(not panel.audition_grid().is_empty() and changes[0] > 0, "候选试听通过信号公开网格，不另起播放器")
	panel._bpm.value /= 2
	check(panel._anchor.value == anchor_before, "半速修正保持参考小节秒位置")
	panel.close_requested.emit(); check(panel.audition_grid().is_empty(), "关闭分析窗口停止候选试听")
	panel.popup_centered(); await frames()
	raw.fit.anchor_confirmed = false; panel._received(raw)
	check(panel._apply.disabled, "不可靠参考拍必须明确确认后应用")
	panel._anchor_confirmed = true; panel._candidate_changed()
	check(not panel._apply.disabled, "人工确认参考拍恢复应用入口")
	var job := panel.job
	job._cache = "user://chart_studio/tests/rhythm_fit/raw.json"; job._fit_span = []
	raw.fit_version = StudioRhythmJob.FIT_VERSION
	job._store_result(raw)
	var cached: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(job._cache))
	var fitting: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(job._fit_cache_path()))
	check(not cached.has("fit") and cached.beats == beats and fitting.fit_version == StudioRhythmJob.FIT_VERSION, "原始检测和带版本拟合分开保存")
	check(job._use_fit_cache(cached), "派生缓存复用不启动模型")
	job._fit_span = [10.0, 30.0]; job._store_result(raw)
	var selection_cache := job._fit_cache_path()
	job._fit_span = []; var full_cache := job._fit_cache_path()
	job._discard_fit_caches()
	check(FileAccess.file_exists(job._cache) and not FileAccess.file_exists(full_cache) and not FileAccess.file_exists(selection_cache), "重新分析使全曲和选区拟合都失效，保留原始拍点")
	panel.hide(); panel._clear_overlay(); panel._received(raw)
	check(w.timeline.rhythm_grid.is_empty() and panel.audition_grid().is_empty(), "窗口关闭后到达的结果不恢复隐藏候选或试听")
	var start := Time.get_ticks_usec()
	for i in 100: panel._bpm.value = 138 + i * 0.001
	print("RHYTHM FIT candidate 96 beats mean ms: ", (Time.get_ticks_usec() - start) / 100000.0)
	w.queue_free(); await process_frame
	print("RHYTHM FIT TESTS: ", failures); quit(1 if failures else 0)

func _test_application() -> void:
	var doc := StudioDocument.new()
	StudioProjectIO.open_project("res://tests/editor/fixtures/training/song.json", doc)
	doc.chart().chart_offset_ticks = 321
	doc.add_difficulty("other", true)
	var other := ChartJsonCodec.encode_chart(doc.chart())
	doc.current = 0
	var before := ChartJsonCodec.encode_chart(doc.chart())
	var revision := doc.revision
	StudioRhythmTools.apply_grid(doc, 138.123456789123, 0.880123456789, 3)
	var after := ChartJsonCodec.encode_chart(doc.chart())
	check(doc.revision == revision + 1 and after.notes == before.notes, "应用固定 BPM、拍号与首拍只提交一次，保留跨变速 Hold 和组合数据")
	check(absf(doc.tempo_map().tick_to_us(0) / 1000000.0 - 0.880123456789) < 0.000002 and doc.chart().chart_offset_ticks == 321, "非零全谱偏移正确换算为首拍偏移，tick 0 对应参考小节")
	check(after.timing.tempo_events[0].bpm == 138.123456789123 and after.timing.meter_events[0].numerator == 3, "应用保留 BPM 小数精度")
	doc.undo()
	check(ChartJsonCodec.encode_chart(doc.chart()) == before, "一次撤销恢复原时间映射、音符和扩展数据")
	doc.current = 1
	check(ChartJsonCodec.encode_chart(doc.chart()) == other, "应用与撤销不修改其他难度")
