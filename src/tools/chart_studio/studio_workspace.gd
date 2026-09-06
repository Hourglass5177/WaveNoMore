extends Control
## 工作区仅协调文档、控件和预览。文件格式与玩法均由独立模块负责。
var document := StudioDocument.new()
var audio := StudioAudio.new()
var preview := StudioPreviewSession.new()
var _refresh_pending := false
var _updating := false
var _input_starts := {}
var _context := PopupMenu.new()
var _autosave := Timer.new()
var _metronome := AudioStreamPlayer.new()
var _metronome_enabled := false
var _note_sound_enabled := true
var _last_beat := -1000000
var _candidate_timer := Timer.new()
var _property_commits: Array[Callable] = []
@onready var timeline: StudioTimeline = $Layout/Split/TimelineColumn/Timeline
@onready var transport: HBoxContainer = $Layout/Split/TimelineColumn/Transport
@onready var library: VBoxContainer = $Layout/Split/Top/Library
@onready var fields: VBoxContainer = $Layout/Split/Top/Main/Inspector/Fields
@onready var viewport: SubViewport = $Layout/Split/Top/Main/PreviewColumn/Aspect/Preview/Viewport
@onready var status: Label = $Layout/Status
@onready var problems: ItemList = $Layout/Problems

func _ready() -> void:
	get_window().title = "冥河 · 写谱器"
	get_window().content_scale_size = Vector2i(1440, 900)
	get_window().min_size = Vector2i(1280, 720)
	InputEventBuffer.set_mode(InputEventBuffer.InputMode.DISABLED)
	InputEventBuffer.set_process_input(false)
	add_child(audio)
	add_child(preview)
	add_child(_context)
	add_child(_metronome)
	_metronome.stream = preload("res://src/presentation/audio/graybox_click_track_factory.gd").create_transient(1400, 0.035, 0.2)
	for caption in ["节拍器", "音符提示音"]:
		var toggle := CheckButton.new(); toggle.text = caption
		toggle.button_pressed = caption == "音符提示音"
		transport.add_child(toggle)
		toggle.toggled.connect(func(enabled: bool) -> void:
			if caption == "节拍器": _metronome_enabled = enabled
			else: _note_sound_enabled = enabled)
	document.new_project()
	timeline.bind(document)
	document.changed.connect(_on_document_changed)
	timeline.selection_changed.connect(_inspect)
	timeline.seek_requested.connect(_seek)
	timeline.gesture_started.connect(_finish_text_edit)
	add_child(_candidate_timer)
	_candidate_timer.one_shot = true; _candidate_timer.wait_time = 0.12
	_candidate_timer.timeout.connect(func() -> void: _refresh_pending = true)
	timeline.candidate_changed.connect(func() -> void: _candidate_timer.start())
	timeline.context_requested.connect(func(at: Vector2) -> void: _context.position = Vector2i(at); _context.popup())
	for label in ["删除", "复制", "粘贴", "生死互换", "组合双押", "解除组合", "量化头", "量化头尾", "重复乐句"]: _context.add_item(label)
	_context.id_pressed.connect(func(id: int) -> void: _edit_action(id))
	var actions := {"New": _new, "Open": _open, "Save": _save, "SaveAs": _save_as, "Audio": _import_audio, "Export": _export, "Legacy": _legacy, "Undo": func() -> void: document.undo(), "Redo": func() -> void: document.undo(true), "Help": _help}
	for key in actions:
		$Layout/Toolbar.get_node(key).pressed.connect(func() -> void: _finish_text_edit(); actions[key].call())
	transport.get_node("Play").pressed.connect(_toggle_play)
	transport.get_node("Home").pressed.connect(func() -> void: _seek(0))
	transport.get_node("Loop").pressed.connect(func() -> void: audio.loop_enabled = not audio.loop_enabled)
	transport.get_node("In").pressed.connect(func() -> void: audio.loop_start = audio.position)
	transport.get_node("Out").pressed.connect(func() -> void: audio.loop_end = audio.position)
	var rate: OptionButton = transport.get_node("Rate")
	for value in [0.5, 0.75, 1.0, 1.25, 1.5]: rate.add_item("%.2f 倍 · 保音高" % value)
	rate.select(2)
	rate.item_selected.connect(func(i: int) -> void: audio.set_rate([0.5, 0.75, 1.0, 1.25, 1.5][i]))
	var snap: OptionButton = transport.get_node("Snap")
	for label in ["四分", "八分", "十六分", "三十二分", "六十四分", "八分三连", "十六分三连", "自由"]: snap.add_item(label)
	snap.select(2)
	snap.item_selected.connect(func(i: int) -> void:
		var divisors := [1, 2, 4, 8, 16, 3, 6, 0]
		timeline.snap_ticks = document.chart().ppq / divisors[i] if divisors[i] else 0
		timeline.queue_redraw())
	audio.position_changed.connect(_position_changed)
	audio.waveform_ready.connect(func(peaks: PackedVector2Array, duration: float) -> void:
		timeline.set_waveform(peaks, duration))
	audio.error_reported.connect(_message)
	preview.status_changed.connect(func(text: String) -> void: $Layout/Split/Top/Main/PreviewColumn/PreviewLabel.text = text)
	for pair in [["SongTitle", "title"], ["Artist", "artist"]]:
		var edit: LineEdit = library.get_node(pair[0])
		edit.text_submitted.connect(func(text: String) -> void: document.set_song_field(pair[1], text))
		edit.focus_exited.connect(func() -> void:
			if not _updating: document.set_song_field(pair[1], edit.text))
	library.get_node("Difficulty").item_selected.connect(func(i: int) -> void:
		_finish_text_edit(); audio.set_playing(false); document.current = i; timeline.selected.clear(); document.changed.emit())
	library.get_node("AddDifficulty").pressed.connect(func() -> void: document.add_difficulty("difficulty_%d" % (document.charts.size() + 1), true))
	library.get_node("AddSection").pressed.connect(_add_section)
	library.get_node("Sections").item_selected.connect(func(i: int) -> void: _seek(float(document.tempo_map().tick_to_us(document.chart().sections[i].tick)) / 1000000.0))
	problems.item_selected.connect(func(i: int) -> void:
		var tick: int = problems.get_item_metadata(i)
		_seek(float(document.tempo_map().tick_to_us(tick)) / 1000000.0))
	add_child(_autosave)
	_autosave.wait_time = 30
	_autosave.timeout.connect(_write_recovery)
	_autosave.start()
	_on_document_changed()
	get_window().close_requested.connect(_close)
	get_tree().auto_accept_quit = false
	_offer_recovery.call_deferred()

func _process(_delta: float) -> void:
	audio.set_suspended(preview.rebuilding)
	timeline.loop_range = Vector2(audio.loop_start, audio.loop_end)
	timeline.loop_enabled = audio.loop_enabled
	if _refresh_pending and not preview.rebuilding:
		_refresh_pending = false
		_rebuild_preview()
	preview.sound_enabled = _note_sound_enabled
	preview.set_transport(roundi(audio.position * 1000000.0), audio.playing)

func _on_document_changed() -> void:
	_refresh_pending = true
	_candidate_timer.stop()
	if preview.rebuilding: preview.clear_preview()
	if not is_node_ready(): return
	var snap_divisors := [1, 2, 4, 8, 16, 3, 6, 0]
	var divisor: int = snap_divisors[maxi(0, transport.get_node("Snap").selected)]
	timeline.snap_ticks = document.chart().ppq / divisor if divisor else 0
	_updating = true
	library.get_node("SongTitle").text = document.song.title
	library.get_node("Artist").text = document.song.artist
	var list: OptionButton = library.get_node("Difficulty")
	list.clear()
	for chart in document.charts: list.add_item(chart.difficulty_id)
	list.select(document.current)
	var sections: ItemList = library.get_node("Sections")
	sections.clear()
	for section in document.chart().sections: sections.add_item(section.label)
	_updating = false
	_inspect()
	get_window().title = "冥河 · %s%s" % [document.song.title, " *" if document.dirty else ""]

func _rebuild_preview() -> void:
	var draft := document.chart().duplicate(true) as SongChart
	# 候选版本仅用于预览，正式资源和撤销栈仍保持手势前的内容。
	if not timeline.candidates.is_empty():
		var ids := {}
		for note in timeline.candidates: ids[note.event_id] = true
		draft.note_events = draft.note_events.filter(func(n: NoteEvent) -> bool: return not ids.has(n.event_id))
		for note in timeline.candidates: draft.note_events.append(note.duplicate(true))
	var report := ChartValidator.validate(draft, load("res://content/rules/default_gameplay_rules.tres"))
	for unknown: Dictionary in draft.get_meta("unknown_notes", []):
		report.add_error(&"editor.unsupported_note", "暂不支持的音符：%s；原数据仍保留" % unknown.get("id", ""), str(unknown.get("id", "")), &"notes", int(unknown.get("tick", 0)))
	var theme_id := str(ChartJsonCodec.encode_chart(draft).get("presentation", {}).get("theme_id", "default"))
	if not ChartProjectLoader.THEMES.has(theme_id): report.add_error(&"editor.unknown_theme", "找不到主题：" + theme_id)
	problems.clear()
	for issue in report.issues:
		problems.add_item(str(issue.get("message")))
		problems.set_item_metadata(problems.item_count - 1, int(issue.get("tick")))
	if report.has_errors() or not document.chart().get_meta("unknown_notes", []).is_empty():
		audio.set_playing(false)
		preview.clear_preview()
		_message("当前稿件可保存，但有内容不能预览；请检查问题列表。")
		return
	var stage := ChartProjectLoader.make_stage(document.song, draft)
	audio.set_suspended(true)
	if preview.load_preview(stage, viewport):
		await preview.seek_preview(roundi(audio.position * 1000000.0))
		if not preview.rebuilding: audio.set_suspended(false)

func _inspect() -> void:
	for child in fields.get_children(): fields.remove_child(child); child.queue_free()
	_label("音符属性" if not timeline.selected.is_empty() else "谱面与时间")
	if timeline.selected.is_empty():
		var property_tick := _cursor_tick()
		_text_field("难度名称", document.chart().difficulty_id, func(value: String) -> void:
			if value.is_empty() or "/" in value or "\\" in value: _message("难度名称不能为空或包含路径分隔符"); return
			for chart in document.charts:
				if chart != document.chart() and chart.difficulty_id == value: _message("难度名称重复"); return
			var data := ChartJsonCodec.encode_chart(document.chart()); data.difficulty_id = value; data.difficulty_name = value; document.change_metadata(data))
		_text_field("谱师", str(ChartJsonCodec.encode_chart(document.chart()).get("mapper", "")), func(value: String) -> void:
			var data := ChartJsonCodec.encode_chart(document.chart()); data.mapper = value; document.change_metadata(data))
		_number("首拍偏移 ms", document.offset_sec() * 1000, -30000, 30000, func(value: float) -> void:
			var data := ChartJsonCodec.encode_chart(document.chart()); data.timing.first_beat_offset_ms = value; document.change_metadata(data), 0.001)
		_number("BPM（编辑点）", document.tempo_map().bpm_at_tick(property_tick + document.chart().chart_offset_ticks), 1, 1000, func(value: float) -> void: _set_bpm(value, property_tick), 0.001)
		_number("谱面尾点 tick", document.chart().end_tick, 1, 10000000, func(value: float) -> void:
			var data := ChartJsonCodec.encode_chart(document.chart()); data.timing.end_tick = int(value); document.change_metadata(data))
		_number("全谱偏移 tick", document.chart().chart_offset_ticks, -100000, 100000, func(value: float) -> void:
			var data := ChartJsonCodec.encode_chart(document.chart()); data.timing.chart_offset_ticks = int(value); document.change_metadata(data))
		_button("当前位置设 3/4", func() -> void: _set_meter(3, 4, property_tick))
		_button("当前位置设 4/4", func() -> void: _set_meter(4, 4, property_tick))
		var meter_n := 4
		var meter_d := 4
		for meter in document.chart().meter_events:
			if meter.tick <= property_tick: meter_n = meter.numerator; meter_d = meter.denominator
		_number("拍号分子（游标处）", meter_n, 1, 32, func(value: float) -> void: _set_meter(int(value), meter_d, property_tick))
		_number("拍号分母（2 的幂）", meter_d, 1, 64, func(value: float) -> void:
			var denominator := int(value)
			if (denominator & (denominator - 1)) != 0 or (document.chart().ppq * 4) % denominator != 0: _message("分母必须是 PPQ 可精确表示的 2 的幂"); return
			_set_meter(meter_n, denominator, property_tick))
		_number("设备试听补偿 ms", audio.device_compensation_ms, -500, 500, func(value: float) -> void: audio.device_compensation_ms = value)
		_label("关卡主题")
		var theme := OptionButton.new()
		var theme_keys := ChartProjectLoader.THEMES.keys()
		var names := ["默认", "载波实验", "Tap 实验", "Hold 实验", "调频实验背景", "综合实验"]
		for name in names: theme.add_item(name)
		fields.add_child(theme)
		var current_theme := str(ChartJsonCodec.encode_chart(document.chart()).get("presentation", {}).get("theme_id", "default"))
		theme.select(maxi(0, theme_keys.find(current_theme)))
		theme.item_selected.connect(func(i: int) -> void:
			var data := ChartJsonCodec.encode_chart(document.chart()); data.presentation.theme_id = theme_keys[i]; document.change_metadata(data))
		for key in ["life", "death", "su", "ink", "paper"]:
			_label({"life": "生界颜色", "death": "死界颜色", "su": "骨白相纹", "ink": "墨色", "paper": "纸色"}[key])
			var picker := ColorPickerButton.new()
			picker.color = ChartProjectLoader.make_stage(document.song, document.chart()).visual_theme.get(key + "_color")
			fields.add_child(picker)
			picker.popup_closed.connect(func() -> void:
				var data := ChartJsonCodec.encode_chart(document.chart())
				if not data.presentation.has("palette_overrides"): data.presentation.palette_overrides = {}
				data.presentation.palette_overrides[key] = "#" + picker.color.to_html(true)
				document.change_metadata(data))
		for section in document.chart().sections:
			_text_field("段落 · tick %d" % section.tick, section.label, func(value: String) -> void:
				var data := ChartJsonCodec.encode_chart(document.chart())
				for raw: Dictionary in data.sections:
					if raw.id == section.event_id: raw.name = value
				document.change_metadata(data))
	else:
		var notes := _selected_notes()
		if notes.is_empty(): return
		_label("已选 %d 个音符" % notes.size())
		_number("头部 tick（整组选移）", notes[0].tick, -100000, 10000000, func(value: float) -> void: _mutate_selected("移动选区", func(n: NoteEvent) -> void: n.tick += int(value) - notes[0].tick))
		_number("Hold 长度 tick", notes[0].duration_ticks, 0, 1000000, func(value: float) -> void: _mutate_selected("修改长度", func(n: NoteEvent) -> void:
			if n.kind == GameplayTypes.NoteKind.HOLD: n.duration_ticks = maxi(1, int(value))))
		_button("生死互换", func() -> void: _edit_action(3))
		_button("转换 Tap / Hold", func() -> void: _mutate_selected("转换音符", func(n: NoteEvent) -> void:
			n.kind = GameplayTypes.NoteKind.TAP if n.kind == GameplayTypes.NoteKind.HOLD else GameplayTypes.NoteKind.HOLD
			n.duration_ticks = maxi(1, timeline.snap_ticks) if n.kind == GameplayTypes.NoteKind.HOLD else 0))
		_button("组合双押", func() -> void: _edit_action(4))
		_button("解除组合", func() -> void: _edit_action(5))
		_button("删除选中", func() -> void: _edit_action(0))
		_text_field("外观键", str(notes[0].visual_variant), func(value: String) -> void: _mutate_selected("外观设置", func(n: NoteEvent) -> void: n.visual_variant = StringName(value)))

func _text_field(title: String, value: String, callback: Callable) -> void:
	_label(title)
	var edit := LineEdit.new(); edit.text = value; fields.add_child(edit)
	var committed := [value]
	var apply := func() -> void:
		if edit.text != committed[0]: committed[0] = edit.text; callback.call(edit.text)
	edit.text_submitted.connect(func(_text: String) -> void: _queue_property_commit(apply))
	edit.focus_exited.connect(func() -> void: _queue_property_commit(apply))

func _label(text: String) -> void:
	var label := Label.new(); label.text = text; fields.add_child(label)

func _button(text: String, callback: Callable) -> void:
	var button := Button.new(); button.text = text; fields.add_child(button); button.pressed.connect(callback)

func _number(text: String, value: float, minimum: float, maximum: float, callback: Callable, step_value := 1.0) -> void:
	_label(text)
	var spin := SpinBox.new()
	spin.min_value = minimum; spin.max_value = maximum; spin.step = step_value; spin.value = value
	fields.add_child(spin)
	# 提交在文本确认或离焦时进行，输入过程中不重建控件。
	var edit := spin.get_line_edit()
	var committed := [value]
	var commit := func() -> void:
		spin.apply()
		if spin.value != committed[0]: committed[0] = spin.value; callback.call(spin.value)
	edit.text_submitted.connect(func(_text: String) -> void: _queue_property_commit(commit))
	edit.focus_exited.connect(func() -> void: _queue_property_commit(commit))

func _queue_property_commit(commit: Callable) -> void:
	if not _property_commits.has(commit): _property_commits.append(commit)
	_flush_property_edits.call_deferred()

func _flush_property_edits() -> void:
	var pending := _property_commits.duplicate()
	_property_commits.clear()
	for commit in pending: commit.call()

func _finish_text_edit() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: focused.release_focus()
	_flush_property_edits()


func _selected_notes() -> Array[NoteEvent]:
	var notes: Array[NoteEvent] = []
	for id in timeline.selected:
		var note := document.find_note(id)
		if note != null: notes.append(note)
	return notes

func _mutate_selected(label: String, callback: Callable) -> void:
	var before: Array = []; var after: Array = []
	for note in _selected_notes():
		before.append(note.duplicate(true))
		var copy := note.duplicate(true) as NoteEvent
		callback.call(copy); after.append(copy)
	if not before.is_empty(): document.execute(label, before, after)

func _edit_action(id: int) -> void:
	match id:
		0: document.execute("删除音符", _selected_notes(), []); timeline.selected.clear()
		1: document.copy_notes(timeline.selected)
		2: timeline.selected = document.paste(_cursor_tick())
		3: _mutate_selected("生死互换", func(n: NoteEvent) -> void: n.affinity = 1 - n.affinity)
		4:
			var notes := _selected_notes()
			if notes.size() != 2 or notes[0].tick != notes[1].tick or notes[0].affinity == notes[1].affinity:
				_message("双押组合需要两个同 tick、异侧音符"); return
			var group := StudioDocument.new_id("group")
			_mutate_selected("组合双押", func(n: NoteEvent) -> void: n.group_id = group; n.damage_group_id = group)
		5: _mutate_selected("解除组合", func(n: NoteEvent) -> void: n.group_id = ""; n.damage_group_id = "")
		6, 7:
			var step := maxi(1, timeline.snap_ticks)
			_mutate_selected("量化", func(n: NoteEvent) -> void:
				var end := n.tick + n.duration_ticks
				n.tick = roundi(float(n.tick) / step) * step
				if id == 7 and n.duration_ticks > 0: n.duration_ticks = maxi(step, roundi(float(end) / step) * step - n.tick))
		8:
			var notes := _selected_notes()
			if notes.is_empty(): return
			var end := notes[0].tick + maxi(1, timeline.snap_ticks)
			for note in notes: end = maxi(end, note.tick + note.duration_ticks)
			document.copy_notes(timeline.selected)
			timeline.selected = document.paste(end)
	timeline.queue_redraw()
	_inspect()

func _cursor_tick() -> int:
	var tick := document.tempo_map().us_to_tick(roundi(audio.position * 1000000.0))
	return roundi(tick / timeline.snap_ticks) * timeline.snap_ticks if timeline.snap_ticks else roundi(tick)

func _set_bpm(value: float, at_tick: int) -> void:
	var data := ChartJsonCodec.encode_chart(document.chart())
	var tick := at_tick + document.chart().chart_offset_ticks
	data.timing.tempo_events = data.timing.tempo_events.filter(func(e: Dictionary) -> bool: return int(e.tick) != tick)
	data.timing.tempo_events.append({"tick": tick, "bpm": value})
	data.timing.tempo_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	document.change_metadata(data)

func _set_meter(numerator: int, denominator: int, tick: int) -> void:
	var data := ChartJsonCodec.encode_chart(document.chart())
	data.timing.meter_events = data.timing.meter_events.filter(func(e: Dictionary) -> bool: return int(e.tick) != tick)
	data.timing.meter_events.append({"tick": tick, "numerator": numerator, "denominator": denominator})
	data.timing.meter_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	document.change_metadata(data)

func _add_section() -> void:
	var data := ChartJsonCodec.encode_chart(document.chart())
	data.sections.append({"id": StudioDocument.new_id("section"), "tick": _cursor_tick(), "name": "段落 %d" % (document.chart().sections.size() + 1)})
	document.change_metadata(data)

func _seek(seconds: float) -> void:
	_flush_property_edits()
	audio.seek(seconds)
	preview.seek_preview(roundi(seconds * 1000000.0))
	if timeline.selected.is_empty(): _inspect()

func _position_changed(seconds: float) -> void:
	timeline.playhead = seconds; timeline.queue_redraw()
	if audio.playing and (seconds < timeline.view_start or seconds > timeline.view_start + timeline.size.x / timeline.pixels_per_second * 0.85): timeline.view_start = seconds - timeline.size.x / timeline.pixels_per_second * 0.15
	transport.get_node("Position").text = "%02d:%06.3f  |  tick %d" % [int(seconds) / 60, fmod(seconds, 60), _cursor_tick()]
	var beat := floori(document.tempo_map().us_to_tick(roundi(seconds * 1000000)) / document.chart().ppq)
	if audio.playing and _metronome_enabled and beat == _last_beat + 1: _metronome.play()
	_last_beat = beat

func _toggle_play() -> void:
	_finish_text_edit()
	audio.set_playing(not audio.playing)
	if not audio.playing and timeline.selected.is_empty(): _inspect()
	transport.get_node("Play").text = "Ⅱ 暂停" if audio.playing else "▶ 播放"

func _message(text: String) -> void:
	status.text = text

func _file_dialog(mode: FileDialog.FileMode, filters: PackedStringArray, callback: Callable) -> void:
	var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.file_mode = mode; dialog.filters = filters
	add_child(dialog)
	if mode == FileDialog.FILE_MODE_OPEN_DIR: dialog.dir_selected.connect(callback)
	else: dialog.file_selected.connect(callback)
	dialog.file_selected.connect(func(_path: String) -> void: dialog.queue_free())
	dialog.dir_selected.connect(func(_path: String) -> void: dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(900, 600))

func _new() -> void:
	_confirm_discard(func() -> void: audio.set_playing(false); document.new_project(); timeline.selected.clear(); _on_document_changed(); _save_as())

func _open() -> void:
	_confirm_discard(func() -> void: _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["song.json ; 歌曲项目"]), _open_path))

func _open_path(path: String) -> void:
	var error := StudioProjectIO.open_project(path, document)
	if not error.is_empty(): _message(error); return
	timeline.selected.clear()
	audio.set_stream(document.song.audio_stream)
	var data := ChartJsonCodec.encode_song(document.song)
	audio.build_waveform(document.directory.path_join(str(data.get("audio", ""))))
	_on_document_changed()
	_load_workspace()
	_message("已打开：" + path)

func _save() -> void:
	if document.directory.is_empty(): _save_as(); return
	var error := StudioProjectIO.save_project(document)
	_message(error if not error.is_empty() else "已保存 · " + document.directory)
	if error.is_empty(): _save_workspace()
	if error.is_empty(): DirAccess.remove_absolute("user://chart_studio/recovery.json")
	if error.is_empty(): get_window().title = "冥河 · " + document.song.title

func _save_as() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_DIR, PackedStringArray(), func(path: String) -> void:
		var error := StudioProjectIO.save_project(document, path); _message(error if not error.is_empty() else "项目已保存，可以导入音乐")
		if error.is_empty():
			_save_workspace(); DirAccess.remove_absolute("user://chart_studio/recovery.json")
			get_window().title = "冥河 · " + document.song.title)

func _import_audio() -> void:
	if document.directory.is_empty(): _save_then(_import_audio); return
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.wav,*.ogg,*.mp3 ; 音频"]), func(path: String) -> void:
		var error := StudioProjectIO.import_audio(path, document)
		if not error.is_empty(): _message(error); return
		audio.set_stream(document.song.audio_stream); audio.build_waveform(path); _message("音乐已导入，正在建立波形；请检查首拍对齐"))

func _export() -> void:
	var dialog := ConfirmationDialog.new(); dialog.title = "选择交付难度"
	var list := ItemList.new(); list.select_mode = ItemList.SELECT_MULTI; list.custom_minimum_size = Vector2(320, 220)
	for chart in document.charts: list.add_item(chart.difficulty_id)
	list.select(document.current)
	dialog.add_child(list); add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty(): _message("至少选择一个难度"); return
		_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, PackedStringArray(["*.zip ; 可玩谱面包"]), func(path: String) -> void:
			var error := StudioProjectIO.export_zip(document, path, selected)
			_message(error if not error.is_empty() else "导出完成：" + path)))
	dialog.popup_centered()

func _legacy() -> void:
	_confirm_discard(func() -> void:
		_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.tres ; 旧 StageDefinition"]), func(path: String) -> void:
			_file_dialog(FileDialog.FILE_MODE_OPEN_DIR, PackedStringArray(), func(target: String) -> void:
				var error := StudioProjectIO.import_legacy(path, target, document)
				if not error.is_empty(): _message(error); return
				_open_path(target.path_join("song.json"))
				_message("迁移完成；未支持内容和原文件见 legacy/import-report.json"))))

func _save_workspace() -> void:
	StudioProjectIO.write_json(document.directory.path_join("editor/workspace.json"), {"version": 1, "current": document.current, "position": audio.position, "view_start": timeline.view_start, "zoom": timeline.pixels_per_second, "loop_start": audio.loop_start, "loop_end": audio.loop_end, "loop_enabled": audio.loop_enabled, "rate": audio.rate, "snap_index": transport.get_node("Snap").selected})

func _load_workspace() -> void:
	var path := document.directory.path_join("editor/workspace.json")
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return
	document.current = clampi(int(data.get("current", 0)), 0, document.charts.size() - 1)
	timeline.view_start = float(data.get("view_start", 0))
	timeline.pixels_per_second = float(data.get("zoom", 160))
	audio.loop_start = float(data.get("loop_start", 0))
	audio.loop_end = float(data.get("loop_end", 4))
	audio.loop_enabled = bool(data.get("loop_enabled", false))
	var rates := [0.5, 0.75, 1.0, 1.25, 1.5]
	var rate_index := rates.find(float(data.get("rate", 1.0)))
	if rate_index < 0: rate_index = 2
	audio.set_rate(rates[rate_index]); transport.get_node("Rate").select(rate_index)
	transport.get_node("Snap").select(clampi(int(data.get("snap_index", 2)), 0, 7))
	audio.seek(float(data.get("position", 0)))
	document.changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		timeline.cancel_gesture()
		_input_starts.clear()

func _write_recovery() -> void:
	if not document.dirty: return
	var data := {"song": ChartJsonCodec.encode_song(document.song), "charts": [], "source": document.directory}
	for chart in document.charts: data.charts.append(ChartJsonCodec.encode_chart(chart))
	StudioProjectIO.write_json("user://chart_studio/recovery.json", data)

func _offer_recovery() -> void:
	var path := "user://chart_studio/recovery.json"
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "找到上次未保存的恢复稿。恢复后可另存为新项目。"
	dialog.ok_button_text = "恢复稿件"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var decoded := ChartJsonCodec.decode_song(data.song)
		if decoded.song == null: _message("恢复稿版本无法读取"); return
		var charts: Array[SongChart] = []
		for raw: Dictionary in data.charts:
			var item := ChartJsonCodec.decode_chart(raw)
			if item.chart == null: _message("恢复谱面版本无法读取"); return
			charts.append(item.chart)
		document.song = decoded.song; document.charts = charts; document.current = 0
		document.directory = str(data.get("source", "")); document.reset_history()
		document.song.audio_stream = ChartJsonCodec.load_audio(document.directory.path_join(str(data.song.get("audio", ""))))
		audio.set_stream(document.song.audio_stream)
		document.mark_changed(); _message("恢复完成，请保存稿件"))
	dialog.popup_centered()

func _confirm_discard(callback: Callable) -> void:
	if not document.dirty: callback.call(); return
	var dialog := ConfirmationDialog.new(); dialog.dialog_text = "当前项目有未保存修改。放弃修改并继续？"; dialog.ok_button_text = "放弃并继续"
	dialog.add_button("保存并继续", true, "save")
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"save": dialog.hide(); _save_then(callback))
	add_child(dialog); dialog.confirmed.connect(callback); dialog.popup_centered()

func _save_then(callback: Callable) -> void:
	var save_at := func(path: String) -> void:
		var error := StudioProjectIO.save_project(document, path)
		if not error.is_empty(): _message(error); return
		_save_workspace(); DirAccess.remove_absolute("user://chart_studio/recovery.json")
		get_window().title = "冥河 · " + document.song.title
		callback.call()
	if document.directory.is_empty(): _file_dialog(FileDialog.FILE_MODE_OPEN_DIR, PackedStringArray(), save_at)
	else: save_at.call(document.directory)

func _close() -> void:
	_finish_text_edit()
	_confirm_discard(func() -> void:
		if not document.directory.is_empty(): _save_workspace()
		DirAccess.remove_absolute("user://chart_studio/recovery.json")
		get_tree().quit())

func _help() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "写谱器操作"
	dialog.dialog_text = "空白点击：Tap；空白拖动：Hold；Shift 框选／增减选\n中键平移；Ctrl+滚轮缩放；Alt 关闭吸附；Esc 取消\nF/J：暂停时输入生／死音符，按住并用方向键延长\n空格播放暂停；I/O/L 循环；Ctrl+C/V/D 复制粘贴重复\nCtrl+M 生死互换；Q 量化；Shift+Q 量化头尾\nCtrl+S 保存；Ctrl+Z 撤销；Ctrl+Shift+Z 重做\n属性输入后按 Enter 确认。"
	add_child(dialog); dialog.popup_centered()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:
		if event.pressed and event.ctrl_pressed and event.keycode == KEY_S:
			_finish_text_edit(); _save(); accept_event()
		return
	for child in get_children():
		if child is Window and child.visible: return
	var key := event as InputEventKey
	if key.echo: return
	if key.keycode in [KEY_F, KEY_J] and not audio.playing:
		if key.pressed: _input_starts[key.keycode] = _cursor_tick()
		elif _input_starts.has(key.keycode):
			var start: int = _input_starts[key.keycode]; _input_starts.erase(key.keycode)
			var note := NoteEvent.new(); note.event_id = StudioDocument.new_id("note"); note.affinity = 0 if key.keycode == KEY_F else 1
			note.tick = mini(start, _cursor_tick()); note.duration_ticks = absi(start - _cursor_tick())
			note.kind = GameplayTypes.NoteKind.HOLD if note.duration_ticks else GameplayTypes.NoteKind.TAP
			document.execute("键盘输入", [], [note])
		accept_event(); return
	if not key.pressed: return
	if key.ctrl_pressed:
		match key.keycode:
			KEY_S: _save_as() if key.shift_pressed else _save()
			KEY_O: _open()
			KEY_N: _new()
			KEY_Z: document.undo(key.shift_pressed)
			KEY_Y: document.undo(true)
			KEY_C: _edit_action(1)
			KEY_X: _edit_action(1); _edit_action(0)
			KEY_V: _edit_action(2)
			KEY_D: _edit_action(8)
			KEY_M: _edit_action(3)
			KEY_A:
				timeline.selected.clear()
				for note in document.chart().note_events: timeline.selected.append(note.event_id)
				timeline.queue_redraw(); _inspect()
			_: return
	else:
		match key.keycode:
			KEY_SPACE: _toggle_play()
			KEY_ESCAPE: timeline.cancel_gesture(); _input_starts.clear()
			KEY_DELETE, KEY_BACKSPACE: _edit_action(0)
			KEY_Q: _edit_action(7 if key.shift_pressed else 6)
			KEY_I: audio.loop_start = audio.position
			KEY_O: audio.loop_end = audio.position
			KEY_L: audio.loop_enabled = not audio.loop_enabled
			KEY_HOME: _seek(0)
			KEY_END: _seek(float(document.tempo_map().tick_to_us(document.chart().end_tick)) / 1000000.0)
			KEY_LEFT, KEY_RIGHT: _seek(float(document.tempo_map().tick_to_us(_cursor_tick() + maxi(1, timeline.snap_ticks) * (-1 if key.keycode == KEY_LEFT else 1))) / 1000000.0)
			KEY_PAGEUP, KEY_PAGEDOWN:
				var length := document.chart().ppq * 4
				for meter in document.chart().meter_events:
					if meter.tick <= _cursor_tick(): length = document.chart().ppq * 4 * meter.numerator / meter.denominator
				_seek(float(document.tempo_map().tick_to_us(_cursor_tick() + length * (-1 if key.keycode == KEY_PAGEUP else 1))) / 1000000.0)
			_: return
	accept_event()
