class_name StudioRhythmPanel
extends Window
## 分析窗口只维护候选；应用和生成分别进入一次文档历史。
var workspace: Control
var job := StudioRhythmJob.new()
var raw := {}
var exclusions: Array = []
var draft: Array[NoteEvent] = []
var _box: VBoxContainer
var _status: Label
var _summary: Label
var _replacement: Label
var _issues: ItemList
var _bpm: SpinBox
var _anchor: SpinBox
var _meter: OptionButton
var _scope: OptionButton
var _density: OptionButton
var _side: OptionButton
var _listen: CheckButton
var _apply: Button
var _commit: Button
var _point_a := 0.0
var _point_b := 0.0
var _points: Label
var _updating := false
var candidate_enabled := false
var _applied := false

func _ready() -> void:
	title = "节奏分析与 Tap 草稿"; size = Vector2i(740, 670); min_size = Vector2i(600, 480)
	visible = false; transient = true; exclusive = false
	close_requested.connect(func() -> void: hide(); _listen.button_pressed = false; _clear_overlay())
	add_child(job); job.updated.connect(func(text: String) -> void: _status.text = text)
	job.completed.connect(_received)
	var scroll := ScrollContainer.new(); add_child(scroll); scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box = VBoxContainer.new(); _box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_box)
	_box.add_theme_constant_override("separation", 10)
	var row := _row()
	_scope = _options(row, ["全曲", "循环选区"])
	_button(row, "分析节奏", func() -> void: _analyze(false))
	_button(row, "重新分析", func() -> void: _analyze(true))
	_button(row, "取消分析", job.cancel)
	_status = _label("分析不会改变谱面。识别结果需要试听确认。")
	row = _row()
	_bpm = _number(row, "BPM", 120, 1, 1000, 0.001)
	_button(row, "÷2", func() -> void: _bpm.value /= 2)
	_button(row, "×2", func() -> void: _bpm.value *= 2)
	_button(row, "原始建议", func() -> void:
		if raw.has("fit"): _bpm.value = raw.fit.bpm)
	_meter = _options(row, ["拍号需确认", "3/4", "4/4"])
	row = _row()
	_anchor = _number(row, "小节起点（秒）", 0, -86400, 86400, 0.0001)
	_button(row, "−1 拍", func() -> void: _anchor.value -= 60 / _bpm.value)
	_button(row, "+1 拍", func() -> void: _anchor.value += 60 / _bpm.value)
	row = _row()
	_button(row, "−1 ms", func() -> void: _anchor.value -= 0.001)
	_button(row, "+1 ms", func() -> void: _anchor.value += 0.001)
	_button(row, "游标设为小节第一拍", func() -> void: _anchor.value = workspace.audio.position)
	_listen = CheckButton.new(); _listen.text = "试听候选节拍"; row.add_child(_listen)
	_listen.tooltip_text = "开启后使用播放栏播放音乐；高音表示小节第一拍。"
	row = _row()
	_button(row, "记录拍点 A", func() -> void: _point_a = workspace.audio.position; _show_points())
	_button(row, "记录拍点 B", func() -> void: _point_b = workspace.audio.position; _show_points())
	var distance := _number(row, "间隔拍数", 16, 1, 4096, 1)
	_button(row, "两拍校准", func() -> void:
		if _point_b <= _point_a: _status.text = "请先记录先后两个拍点"; return
		_updating = true; _bpm.value = 60 * distance.value / (_point_b - _point_a); _anchor.value = _point_a; _updating = false; _candidate_changed())
	_points = _label("A、B 使用主窗口播放头位置；填入两点之间的拍数。")
	_label("蓝色短线是原始拍点，紫色为检测重拍；绿色为修正网格。拖动绿色把手整体对齐；右键绿色候选拍可设为小节第一拍。")
	_summary = _label("")
	_replacement = _label("")
	row = _row()
	_apply = _button(row, "应用到当前难度", _apply_grid)
	_button(row, "取消候选", func() -> void: candidate_enabled = false; _listen.button_pressed = false; _clear_overlay(); _applied = false; _refresh_replacement())
	row = _row()
	_density = _options(row, ["每小节第一拍", "每拍一个"])
	_side = _options(row, ["生钟", "死钟", "生死交替"]); _side.select(2)
	_button(row, "预览 Tap 草稿", _generate)
	_commit = _button(row, "确认生成", _commit_draft); _commit.disabled = true
	_label("草稿范围不超过谱面结束位置；需要覆盖更长音乐时，请先调整右侧的谱面结束位置。")
	row = _row()
	_button(row, "排除循环选区", func() -> void:
		if workspace.audio.loop_end > workspace.audio.loop_start:
			exclusions.append(Vector2(workspace.audio.loop_start, workspace.audio.loop_end)); _invalidate_draft(); _status.text = "已排除 %d 个区域，请重新预览草稿" % exclusions.size())
	_button(row, "清除排除区域", func() -> void: exclusions.clear(); _invalidate_draft(); _status.text = "已清除排除区域")
	_issues = ItemList.new(); _issues.custom_minimum_size.y = 130; _box.add_child(_issues)
	_issues.item_selected.connect(func(i: int) -> void: workspace._seek(float(_issues.get_item_metadata(i))))
	_bpm.value_changed.connect(func(_v: float) -> void: _candidate_changed())
	_anchor.value_changed.connect(func(_v: float) -> void: _candidate_changed())
	_meter.item_selected.connect(func(_i: int) -> void: _candidate_changed())
	for options in [_scope, _density, _side]: options.item_selected.connect(func(_i: int) -> void: _invalidate_draft())
	workspace.document.changed.connect(_document_changed)
	workspace.timeline.rhythm_anchor_changed.connect(func(seconds: float) -> void: _anchor.value = seconds)
	_refresh_replacement()
	visibility_changed.connect(func() -> void:
		if visible and candidate_enabled: _show_overlay())

func _unhandled_key_input(event: InputEvent) -> void:
	var focus := gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		workspace._toggle_play(); set_input_as_handled()

func _show_overlay() -> void:
	var meter: int = [0, 3, 4][_meter.selected]
	workspace.timeline.rhythm_raw = raw
	workspace.timeline.rhythm_grid = {"bpm": _bpm.value, "anchor": _anchor.value, "meter": meter,
		"regions": StudioRhythmTools.diagnose(raw, _bpm.value, _anchor.value, meter).regions}
	workspace.timeline.queue_redraw()

func _row() -> HFlowContainer:
	var row := HFlowContainer.new(); _box.add_child(row); return row

func _button(row: Control, text: String, action: Callable) -> Button:
	var button := Button.new(); button.text = text; row.add_child(button); button.pressed.connect(action); return button

func _label(text: String) -> Label:
	var label := Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _box.add_child(label); return label

func _number(row: Control, text: String, value: float, minimum: float, maximum: float, step: float) -> SpinBox:
	var label := Label.new(); label.text = text; row.add_child(label)
	var spin := SpinBox.new(); spin.min_value = minimum; spin.max_value = maximum; spin.step = step; spin.value = value; spin.custom_minimum_size.x = 115; row.add_child(spin); return spin

func _options(row: Control, labels: Array) -> OptionButton:
	var option := OptionButton.new()
	for text: String in labels: option.add_item(text)
	row.add_child(option); return option

func _show_points() -> void:
	_points.text = "A：%.4f 秒   B：%.4f 秒" % [_point_a, _point_b]

func _span() -> Vector2:
	if _scope.selected == 1: return Vector2(workspace.audio.loop_start, workspace.audio.loop_end)
	return Vector2(0, workspace.timeline.audio_duration)

func _analyze(force: bool) -> void:
	workspace._finish_recording(true); _invalidate_draft()
	var path: String = workspace.document.directory.path_join(str(workspace.document.song.get_meta("json_source", {}).get("audio", "")))
	job.start(path, _span(), force)

func _received(result: Dictionary) -> void:
	raw = result; _updating = true
	_bpm.value = result.fit.bpm; _anchor.value = result.fit.anchor
	_meter.select({0: 0, 3: 1, 4: 2}.get(int(result.fit.meter), 0))
	_updating = false; _candidate_changed()
	if result.has("range"):
		_status.text = "分析完成（%.2f—%.2f 秒）；请试听确认 BPM 和小节位置" % [result.range[0], result.range[1]]

func _candidate_changed() -> void:
	if _updating: return
	candidate_enabled = true; _applied = false; _invalidate_draft()
	var meter: int = [0, 3, 4][_meter.selected]
	var diagnostic := StudioRhythmTools.diagnose(raw, _bpm.value, _anchor.value, meter)
	_summary.text = "拟合中位偏差：%.1f ms；可疑区域：%d%s" % [diagnostic.median_ms, diagnostic.regions.size(), "；请确认拍号" if meter == 0 else ""]
	_issues.clear()
	for issue: Dictionary in diagnostic.regions: _add_issue(issue)
	_show_overlay(); _refresh_replacement()

func _refresh_replacement() -> void:
	var chart: SongChart = workspace.document.chart()
	_replacement.text = "将替换当前难度的 %d 个 BPM 事件和 %d 个拍号事件。已有 %d 个音符保留 tick／Hold 时长，音频时刻随新映射改变；可一步撤销。" % [chart.tempo_events.size(), chart.meter_events.size(), chart.note_events.size()]
	_apply.disabled = not candidate_enabled or _meter.selected == 0

func _apply_grid() -> void:
	if _meter.selected == 0: _status.text = "请确认拍号"; return
	workspace._prepare_alignment()
	StudioRhythmTools.apply_grid(workspace.document, _bpm.value, _anchor.value, [0, 3, 4][_meter.selected])
	_applied = true; _status.text = "已应用对齐，可继续生成 Tap 草稿"

func _generate() -> void:
	if candidate_enabled and not _applied: _status.text = "请先应用候选对齐，或取消候选后使用当前谱面网格"; return
	var result := StudioRhythmTools.generate(workspace.document, _span(), _density.selected == 1, _side.selected, exclusions)
	draft.assign(result.notes); _commit.disabled = draft.is_empty()
	workspace.timeline.rhythm_draft.assign(draft); workspace.timeline.queue_redraw()
	_status.text = "待生成 %d 个 Tap；重复 %d；冲突 %d；主动排除 %d" % [draft.size(), result.duplicates, result.issues.size(), result.excluded]
	for issue: Dictionary in result.issues: _add_issue(issue)

func _add_issue(issue: Dictionary) -> void:
	_issues.add_item("%.3f 秒：%s" % [issue.start, issue.reason]); _issues.set_item_metadata(_issues.item_count - 1, issue.start)

func _commit_draft() -> void:
	if draft.is_empty(): return
	workspace._prepare_alignment()
	workspace.document.execute("生成 Tap 草稿", [], draft.duplicate())
	_invalidate_draft(); _status.text = "Tap 草稿已生成，可整段撤销"

func _invalidate_draft() -> void:
	draft.clear(); _commit.disabled = true; workspace.timeline.rhythm_draft.clear(); workspace.timeline.queue_redraw()

func _clear_overlay() -> void:
	workspace.timeline.rhythm_grid = {}; workspace.timeline.rhythm_raw = {}; _invalidate_draft()

func reset_analysis() -> void:
	job.cancel(); raw = {}; exclusions.clear(); candidate_enabled = false; _applied = false
	_listen.button_pressed = false; _clear_overlay(); _issues.clear(); _refresh_replacement()

func _document_changed() -> void:
	_invalidate_draft(); _refresh_replacement()
	if workspace.document.change_kind in [&"timing", &"project"]: _applied = false

func candidate_beat(seconds: float) -> Vector2i:
	if not visible or not candidate_enabled or not _listen.button_pressed: return Vector2i(-2147483648, 0)
	var beat := floori((seconds - _anchor.value) * _bpm.value / 60.0)
	var meter: int = [0, 3, 4][_meter.selected]
	return Vector2i(beat, 1 if meter > 0 and posmod(beat, meter) == 0 else 0)
