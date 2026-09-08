extends Control
## 工作区仅协调文档、控件和预览。文件格式与玩法均由独立模块负责。
const VERSION := "0.1.2"
var rhythm: StudioRhythmPanel
var playtest := StudioPlaytest.new()
var document := StudioDocument.new()
var audio := StudioAudio.new()
var preview := StudioPreviewSession.new()
var _refresh_pending := false
var _application_focused := true
var _trial_background := false
var _foreground_max_fps := 0
var _updating := false
var _input_starts := {}
var _context := PopupMenu.new()
var _autosave := Timer.new()
var _metronome_enabled := false
var _note_sound_enabled := true
var _game_feedback_enabled := false
var _candidate_timer := Timer.new()
var _property_commits: Array[Callable] = []
var recorder := StudioRecorder.new()
var record_armed := false
var _record_button := Button.new()
var _follow := CheckButton.new()
var _follow_suspended := false
var _scroll := HScrollBar.new()
var _view_menu := MenuButton.new()
var _ui_scale := 0.0
var _layout_before_focus := {}
var _seek_timer := Timer.new()
var _seek_target := 0.0
var _recovery_ready := false
var recovery_path := "user://chart_studio/recovery.json"
var offer_recovery_on_start := true
var _color_edit := {}
var _colors := {}
var _preview_theme_id := ""
var _problem_messages: PackedStringArray = []
var _alignment_bar: VBoxContainer
var _offset_edit: LineEdit
var _offset_display_text := ""
var _alignment_info: Label
var _wave_move_button: Button
var _wave_context := PopupMenu.new()
var _wave_context_seconds := 0.0
const RECORD_ICON = preload("res://assets/chart_studio/record.svg")
const RECORD_STOP_ICON = preload("res://assets/chart_studio/record_stop.svg")
const PLAY_ICON = preload("res://assets/chart_studio/play.svg")
const PAUSE_ICON = preload("res://assets/chart_studio/pause.svg")
@onready var timeline: StudioTimeline = $Layout/Split/TimelineColumn/Timeline
@onready var transport: HFlowContainer = $Layout/Split/TimelineColumn/Transport
@onready var library: VBoxContainer = $Layout/Split/Top/LibraryScroll/Library
@onready var fields: VBoxContainer = $Layout/Split/Top/Main/Inspector/Fields
@onready var viewport: SubViewport = $Layout/Split/Top/Main/PreviewColumn/Aspect/Preview/Viewport
@onready var status: Label = $Layout/Status
@onready var problems: ItemList = $Layout/Problems

func _ready() -> void:
	get_window().title = "冥河 · 写谱器 v" + VERSION
	# 手柄默认会同时送达后台窗口；在输入源处隔离，连原生弹窗也不能误收试玩操作。
	Input.ignore_joypad_on_unfocused_application = true
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_size = Vector2i.ZERO
	get_window().min_size = Vector2i(1024, 720)
	InputEventBuffer.set_mode(InputEventBuffer.InputMode.DISABLED)
	InputEventBuffer.set_process_input(false)
	add_child(audio)
	add_child(preview)
	add_child(playtest)
	playtest.changed.connect(func(busy: bool, caption: String):
		$Layout/Toolbar/Playtest.disabled = busy
		$Layout/Toolbar/Playtest.text = caption
		$Layout/Toolbar/Playtest.tooltip_text = "关闭试玩窗口后可再次启动" if busy else "使用当前难度，包括未保存修改"
		_sync_trial_background())
	playtest.notice.connect(_message)
	playtest.executable_needed.connect(_choose_trial_game)
	add_child(_context)
	for caption in ["节拍器", "音符提示音", "游戏反馈"]:
		var toggle := CheckButton.new(); toggle.text = caption
		toggle.button_pressed = caption == "音符提示音"
		transport.get_node("Sound").add_child(toggle)
		toggle.toggled.connect(func(enabled: bool) -> void:
			if caption == "节拍器": _metronome_enabled = enabled
			elif caption == "音符提示音": _note_sound_enabled = enabled
			else: _game_feedback_enabled = enabled
			_refresh_cues())
		toggle.tooltip_text = "按谱面起手时刻敲钟" if caption == "音符提示音" else ("持续音与判定反馈，起手敲钟由音符提示音控制" if caption == "游戏反馈" else "按当前拍号打拍，小节第一拍加重")
	document.new_project()
	timeline.bind(document)
	document.changed.connect(_on_document_changed)
	timeline.selection_changed.connect(_inspect)
	timeline.commit_requested.connect(_commit_events)
	timeline.notice.connect(func(message: String): _message(message))
	timeline.path_edit_requested.connect(_add_path_point)
	timeline.seek_requested.connect(_scrub)
	timeline.seek_finished.connect(_seek)
	timeline.gesture_started.connect(func() -> void: _finish_recording(true); _finish_text_edit())
	add_child(_candidate_timer)
	_candidate_timer.one_shot = true; _candidate_timer.wait_time = 0.12
	_candidate_timer.timeout.connect(func() -> void:
		if not recorder.active: _refresh_pending = true)
	timeline.candidate_changed.connect(func() -> void: _candidate_timer.start())
	timeline.context_requested.connect(func(at: Vector2) -> void: _sync_event_menu(); _context.position = Vector2i(at); _context.popup())
	_setup_alignment_controls()
	rhythm = StudioRhythmPanel.new(); rhythm.workspace = self; rhythm.theme = theme; add_child(rhythm)
	rhythm.audition_changed.connect(_refresh_cues)
	_alignment_button(_alignment_bar.get_node("Actions"), "分析节奏／生成草稿", "RhythmAnalysis", func() -> void:
		_finish_recording(true); _finish_text_edit(); rhythm.popup_centered())
	for label in ["删除", "复制", "粘贴", "生死互换", "组合双押", "解除组合", "量化起始位置", "量化起止位置", "重复乐句"]: _context.add_item(label)
	_context.set_item_tooltip(6, "将起始位置对齐吸附网格，保留 Hold 时长（Q）")
	_context.set_item_tooltip(7, "分别将起始和结束位置对齐吸附网格（Shift+Q）")
	_context.add_separator()
	_context.add_check_item("BOSS 发出", 9)
	_context.add_item("选择关联内容", 10)
	_context.add_item("按当前位置重新关联", 11)
	_context.add_item("此刻再添加一批 Ghost", 12)
	_context.id_pressed.connect(func(id: int) -> void: _edit_action(id))
	var actions := {"New": _new, "Open": _open, "Save": _save, "SaveAs": _save_as, "Audio": _import_audio, "Export": _export, "Playtest": _playtest, "Legacy": _legacy, "Undo": func() -> void: document.undo(), "Redo": func() -> void: document.undo(true), "Help": _help}
	for key in actions:
		$Layout/Toolbar.get_node(key).pressed.connect(func() -> void: _finish_text_edit(); actions[key].call())
	_setup_controls()
	get_node("%Play").pressed.connect(_toggle_play)
	get_node("%Home").pressed.connect(func() -> void: _seek(0))
	get_node("%Loop").pressed.connect(func() -> void: audio.loop_enabled = not audio.loop_enabled)
	get_node("%In").pressed.connect(func() -> void: audio.loop_start = audio.position)
	get_node("%Out").pressed.connect(func() -> void: audio.loop_end = audio.position)
	var rate: OptionButton = get_node("%Rate")
	for caption in ["0.5倍", "0.75倍", "1.0倍", "1.25倍", "1.5倍"]: rate.add_item("倍速：" + caption)
	rate.select(2)
	rate.item_selected.connect(func(i: int) -> void: audio.set_rate([0.5, 0.75, 1.0, 1.25, 1.5][i]))
	var snap: OptionButton = get_node("%Snap")
	for label in ["1/4", "1/8", "1/16", "1/32", "1/64", "1/8 三连音", "1/16 三连音", "关闭"]: snap.add_item("吸附：" + label)
	snap.select(2)
	_sync_snap_hint()
	snap.item_selected.connect(func(i: int) -> void:
		_finish_recording(true)
		var divisors := [1, 2, 4, 8, 16, 3, 6, 0]
		timeline.snap_ticks = document.chart().ppq / divisors[i] if divisors[i] else 0
		timeline.queue_redraw())
	audio.position_changed.connect(_position_changed)
	audio.waveform_ready.connect(func(peaks: PackedVector2Array, duration: float) -> void:
		timeline.set_waveform(peaks, duration); _update_scroll())
	audio.error_reported.connect(_message)
	preview.status_changed.connect(_preview_status)
	preview.loading_changed.connect($Layout/Split/Top/Main/PreviewColumn/Aspect/Preview/Loading.set_loading)
	preview.ghost_results_changed.connect(func(_results: Dictionary): _sync_ghost_preview_label())
	for pair in [["SongTitle", "title"], ["Artist", "artist"]]:
		var edit: LineEdit = library.get_node(pair[0])
		edit.text_submitted.connect(func(text: String) -> void: document.set_song_field(pair[1], text))
		edit.focus_exited.connect(func() -> void:
			if not _updating: document.set_song_field(pair[1], edit.text))
	library.get_node("Difficulty").item_selected.connect(func(i: int) -> void:
		_finish_text_edit(); audio.set_playing(false); document.current = i; document.change_kind = &"project"; timeline.selected.clear(); document.changed.emit())
	library.get_node("AddDifficulty").pressed.connect(func() -> void: document.add_difficulty("difficulty_%d" % (document.charts.size() + 1), true))
	library.get_node("AddSection").pressed.connect(_add_section)
	library.get_node("Sections").item_selected.connect(func(i: int) -> void: _seek(float(document.tempo_map().tick_to_us(document.chart().sections[i].tick)) / 1000000.0))
	problems.item_selected.connect(func(i: int) -> void:
		var tick: int = problems.get_item_metadata(i)
		var id: String = problems.get_meta("event_%d" % i, "")
		var event := document.find_note(id)
		if event != null:
			timeline.selected = PackedStringArray([id])
			timeline.folded[ChartEditEvents.track(event)] = false
			timeline.track_scroll += timeline.track_y(ChartEditEvents.track(event)) - timeline.RULER
			timeline._update_track_scroll(); timeline.queue_redraw(); _inspect()
			if event is TuningPathEvent:
				var editor := fields.get_node_or_null("PathEditor")
				for node_index in event.points.size():
					if event.tick + event.points[node_index].offset_ticks == tick and editor != null:
						editor.circle.selected = node_index; editor._show_point(); break
		_seek(float(document.tempo_map().tick_to_us(tick)) / 1000000.0))
	add_child(_autosave)
	_autosave.wait_time = 1
	_autosave.one_shot = true
	_autosave.timeout.connect(_write_recovery)
	_setup_stability_controls()
	_on_document_changed()
	audio.state_changed.connect(_sync_transport)
	audio.state_changed.connect(_sync_trial_background)
	_sync_transport()
	get_window().close_requested.connect(_close)
	get_tree().auto_accept_quit = false
	_offer_recovery.call_deferred()

func _process(_delta: float) -> void:
	if recorder.active:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit: _finish_recording(true)
		else:
			timeline.recording_notes = recorder.display_notes(audio.position, Time.get_ticks_usec())
			timeline._redraw_overlay()
	timeline.loop_range = Vector2(audio.loop_start, audio.loop_end)
	timeline.loop_enabled = audio.loop_enabled
	if _trial_background: return
	if _refresh_pending and not preview.rebuilding and not recorder.active and not timeline.is_aligning():
		_refresh_pending = false
		_rebuild_preview()
	preview.sound_enabled = _game_feedback_enabled
	preview.set_transport(roundi(audio.position * 1000000.0), audio.playing)

func _sync_trial_background() -> void:
	var background := playtest.busy and not _application_focused and not audio.playing
	if background == _trial_background: return
	_trial_background = background
	# 仅让正在后台等待试玩的工具降频；任务轮询、自动保存仍运行，前台编辑不受影响。
	if background:
		_foreground_max_fps = Engine.max_fps
		Engine.max_fps = mini(15, _foreground_max_fps) if _foreground_max_fps > 0 else 15
	else: Engine.max_fps = _foreground_max_fps
	preview.set_suspended(background)

func _exit_tree() -> void:
	if _trial_background: Engine.max_fps = _foreground_max_fps

func _setup_stability_controls() -> void:
	var settings := ConfigFile.new()
	settings.load("user://chart_studio/settings.cfg")
	_ui_scale = float(settings.get_value("ui", "scale", 0))
	recorder.threshold_ms = float(settings.get_value("input", "hold_threshold_ms", 150))
	_record_button.icon = RECORD_ICON; _record_button.toggle_mode = true
	_record_button.custom_minimum_size = Vector2(36, 34)
	_record_button.accessibility_name = "实时录入"
	_record_button.tooltip_text = "开启／关闭实时录入（R）"; _record_button.focus_mode = Control.FOCUS_NONE
	transport.get_node("Playback").add_child(_record_button)
	_record_button.toggled.connect(func(enabled: bool) -> void:
		record_armed = enabled
		if not enabled: _finish_recording()
		elif audio.playing: recorder.begin(timeline._map, timeline.snap_ticks)
		_update_record_status())
	_follow.text = "跟随"; _follow.button_pressed = true; _follow.focus_mode = Control.FOCUS_NONE
	_follow.tooltip_text = "播放时跟随播放头；手动浏览暂时停止跟随"
	transport.get_node("Sound").add_child(_follow)
	_follow.toggled.connect(func(_enabled: bool) -> void: _follow_suspended = false)
	timeline.manual_browse.connect(func() -> void: _follow_suspended = true)
	timeline.loop_changed.connect(func(start: float, end: float) -> void: audio.loop_start = start; audio.loop_end = end)
	$Layout/Split/TimelineColumn.add_child(_scroll)
	_scroll.value_changed.connect(func(value: float) -> void: _follow_suspended = true; timeline.view_start = value)
	timeline.view_changed.connect(_update_scroll)
	timeline.resized.connect(_update_scroll)
	_view_menu.text = "视图"; $Layout/Toolbar.add_child(_view_menu)
	var menu := _view_menu.get_popup()
	menu.about_to_popup.connect(func() -> void: _finish_recording(true))
	for label in ["自动缩放", "100%", "125%", "150%"]: menu.add_radio_check_item(label)
	menu.add_separator(); menu.add_item("试玩设置…", 40); menu.add_item("显示整曲", 10); menu.add_item("显示选区", 11)
	menu.id_pressed.connect(func(id: int) -> void:
		if id < 4: _ui_scale = [0.0, 1.0, 1.25, 1.5][id]; _apply_ui_scale(); _save_tool_settings()
		elif id == 40: _choose_trial_game()
		elif id in [33, 34]: timeline.folded.fill(id == 33); timeline._update_track_scroll(); timeline.queue_redraw()
		elif id in [30, 31, 32]: timeline.folded.fill(false); timeline.row_height = [36.0, 48.0, 64.0][id - 30]; timeline._update_track_scroll(); timeline.queue_redraw()
		elif id < 20: _fit_timeline(id == 11)
		else: _layout_action(id))
	menu.add_separator()
	menu.add_check_item("显示歌曲侧栏", 20); menu.add_check_item("显示属性侧栏", 21)
	menu.add_check_item("显示时间线", 22); menu.add_check_item("专注预览", 23)
	menu.add_item("恢复默认布局", 24)
	menu.add_separator(); menu.add_item("折叠全部轨道", 33); menu.add_item("展开全部轨道", 34)
	menu.add_item("轨道行高：紧凑", 30); menu.add_item("轨道行高：标准", 31); menu.add_item("轨道行高：宽松", 32)
	menu.about_to_popup.connect(_sync_layout_menu)
	_sync_layout_menu()
	for split: SplitContainer in [$Layout/Split, $Layout/Split/Top, $Layout/Split/Top/Main]:
		split.add_theme_constant_override("separation", 10)
	get_window().size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()
	add_child(_seek_timer); _seek_timer.one_shot = true; _seek_timer.wait_time = 0.05
	_seek_timer.timeout.connect(func() -> void: audio.seek(_seek_target))
	audio.discontinuity.connect(func(seconds: float, reason: StringName) -> void:
		if reason != &"rate": preview.seek_preview(roundi(seconds * 1000000.0)))
	audio.loop_wrapping.connect(func(end: float) -> void:
		if recorder.active: recorder.cut_loop(end, Time.get_ticks_usec()))
	audio.state_changed.connect(func() -> void:
		if not audio.playing: _finish_recording()
		_update_record_status())

func _update_record_status() -> void:
	# 方块表示可以关闭录制，包括已开启但尚未播放的状态。
	_record_button.icon = RECORD_STOP_ICON if record_armed else RECORD_ICON
	_record_button.tooltip_text = ("关闭实时录入（R）" if audio.playing else "已开启实时录入，播放后按 F／J；关闭（R）") if record_armed else "开启实时录入（R）"
	_record_button.accessibility_name = "关闭实时录入" if record_armed else "开启实时录入"

func _finish_recording(cancel_held := false) -> void:
	if not recorder.active: return
	var notes := recorder.finish(audio.position, Time.get_ticks_usec(), cancel_held)
	timeline.recording_notes.clear(); timeline._redraw_overlay()
	if not notes.is_empty(): document.execute("实时录制", [], notes); _write_recovery()

func _apply_ui_scale() -> void:
	var window := get_window()
	var factor := _ui_scale if _ui_scale > 0 else maxf(maxf(1, DisplayServer.screen_get_scale()), minf(window.size.x / 1280.0, window.size.y / 720.0))
	if not is_equal_approx(window.content_scale_factor, factor): window.content_scale_factor = factor
	$Layout/Split/Top/Main/PreviewColumn/Aspect/Preview.update_resolution.call_deferred()
	var menu := _view_menu.get_popup()
	for i in mini(4, menu.item_count): menu.set_item_checked(i, is_equal_approx(_ui_scale, [0.0, 1.0, 1.25, 1.5][i]))

func _save_tool_settings() -> void:
	var config := ConfigFile.new(); config.load("user://chart_studio/settings.cfg")
	config.set_value("ui", "scale", _ui_scale)
	config.set_value("input", "hold_threshold_ms", recorder.threshold_ms)
	DirAccess.make_dir_recursive_absolute("user://chart_studio")
	config.save("user://chart_studio/settings.cfg")

func _update_scroll() -> void:
	if document.charts.is_empty(): return
	var span := timeline.size.x / timeline.pixels_per_second
	_scroll.min_value = minf(-10, timeline.view_start)
	_scroll.max_value = maxf(maxf(timeline.audio_duration + 5, float(timeline._map.tick_to_us(document.chart().end_tick)) / 1000000.0 + 5), timeline.view_start + span)
	_scroll.page = span
	_scroll.set_value_no_signal(timeline.view_start)

func _fit_timeline(selection_only: bool) -> void:
	var from := -2.0
	var to := maxf(timeline.audio_duration, float(timeline._map.tick_to_us(document.chart().end_tick)) / 1000000.0) + 1
	if selection_only:
		var notes := _selected_notes()
		if notes.is_empty(): _message("请先选择音符"); return
		from = INF; to = -INF
		for note in notes:
			from = minf(from, float(timeline._map.tick_to_us(note.tick)) / 1000000.0 - 0.5)
			to = maxf(to, float(timeline._map.tick_to_us(note.tick + note.duration_ticks)) / 1000000.0 + 0.5)
	timeline.pixels_per_second = timeline.size.x / maxf(1, to - from)
	timeline.view_start = from; _follow_suspended = true

func _document_theme(presentation: Dictionary = {}) -> StageVisualTheme:
	var raw: Dictionary = presentation if not presentation.is_empty() else document.chart().get_meta("json_source", {}).get("presentation", {})
	var theme: StageVisualTheme = load(ChartProjectLoader.THEMES.get(str(raw.get("theme_id", "default")), ChartProjectLoader.THEMES.default)).duplicate(true)
	for key in ["life", "death", "su", "ink", "paper"]:
		if raw.get("palette_overrides", {}).has(key): theme.set(key + "_color", Color(raw.palette_overrides[key]))
	return theme

func _begin_color(key: String) -> void:
	_finish_recording(true)
	_color_edit = {"key": key, "presentation": document.chart().get_meta("json_source", {}).get("presentation", {}).duplicate(true)}

func _preview_color(key: String, color: Color) -> void:
	if _color_edit.is_empty(): _begin_color(key)
	var raw: Dictionary = _color_edit.presentation
	if not raw.has("palette_overrides"): raw.palette_overrides = {}
	raw.palette_overrides[key] = "#" + color.to_html(true)
	preview.apply_palette(_document_theme(raw))

func _finish_color() -> void:
	if _color_edit.is_empty(): return
	var value: Dictionary = _color_edit.presentation
	var key: String = _color_edit.key
	_color_edit = {} # 先结束手势，再关闭弹窗，避免 popup_closed 重入。
	if _colors.has(key) and is_instance_valid(_colors[key]): _colors[key].get_popup().hide()
	document.change_presentation(value)

func _apply_document_palette() -> void:
	var theme_id := str(document.chart().get_meta("json_source", {}).get("presentation", {}).get("theme_id", "default"))
	if theme_id != _preview_theme_id: _refresh_pending = true
	var theme := _document_theme()
	preview.apply_palette(theme)
	for key in _colors:
		if is_instance_valid(_colors[key]): _colors[key].color = theme.get(key + "_color")

func _restore_recovery(data: Dictionary) -> void:
	var decoded := ChartJsonCodec.decode_song(data.song)
	if decoded.song == null: _message("恢复稿版本无法读取"); return
	var charts: Array[SongChart] = []
	for raw: Dictionary in data.charts:
		var item := ChartJsonCodec.decode_chart(raw)
		if item.chart == null: _message("恢复谱面无法读取：" + str(item.errors)); return
		charts.append(item.chart)
	if charts.is_empty(): _message("恢复稿没有难度谱面"); return
	document.song = decoded.song; document.charts = charts
	document.directory = str(data.get("source", "")); document.reset_history()
	document.song.audio_stream = ChartJsonCodec.load_audio(document.directory.path_join(str(data.song.get("audio", ""))))
	_activate_project(data.get("workspace", _workspace_data()))
	document.mark_changed()
	_message("已恢复 %d 个编排对象，请保存谱面" % ChartEditEvents.all(document.chart()).size())

func _setup_controls() -> void:
	var icons := {"%Home": "home", "%Loop": "loop", "Layout/Toolbar/Undo": "undo", "Layout/Toolbar/Redo": "redo"}
	for path in icons:
		var button: Button = get_node(path)
		button.text = ""
		button.icon = load("res://assets/chart_studio/%s.svg" % icons[path])
		button.custom_minimum_size = Vector2(36, 34)
	get_node("%Play").custom_minimum_size = Vector2(36, 34)
	get_node("%Loop").toggle_mode = true
	var hints := {"%Home": "返回音乐开头（Home）", "%Rate": "播放速度", "Layout/Toolbar/New": "新建项目（Ctrl+N）", "Layout/Toolbar/Open": "打开项目（Ctrl+O）", "Layout/Toolbar/Save": "保存（Ctrl+S）", "Layout/Toolbar/SaveAs": "另存为（Ctrl+Shift+S）", "Layout/Toolbar/Undo": "撤销（Ctrl+Z）", "Layout/Toolbar/Redo": "重做（Ctrl+Shift+Z / Ctrl+Y）", "Layout/Toolbar/Legacy": "导入旧谱：选择旧 .tres 关卡入口", "Layout/Toolbar/Export": "选择难度并导出 ZIP 谱面包"}
	for path in hints:
		var control: Control = get_node(path)
		control.tooltip_text = hints[path]
		control.accessibility_name = hints[path]
	# 仅时间数字使用等宽字体，正文继续使用中文字体。
	var numbers := SystemFont.new()
	numbers.font_names = PackedStringArray(["Consolas", "monospace"])
	get_node("%Position").add_theme_font_override("font", numbers)
	get_node("%TickPosition").add_theme_font_override("font", numbers)
	$Layout/ProblemToggle.toggled.connect(func(open: bool) -> void: problems.visible = open)
	get_node("%Snap").item_selected.connect(func(_i: int) -> void: _sync_snap_hint())
	_sync_snap_hint()

func _sync_snap_hint() -> void:
	var descriptions := ["四分音符", "八分音符", "十六分音符", "三十二分音符", "六十四分音符", "八分三连音", "十六分三连音"]
	var index: int = get_node("%Snap").selected
	get_node("%Snap").tooltip_text = "不按节拍吸附" if index == 7 else "按%s吸附；Alt 临时关闭" % descriptions[maxi(0, index)]

func _sync_transport() -> void:
	var play: Button = get_node("%Play")
	play.icon = PAUSE_ICON if audio.playing else PLAY_ICON
	play.tooltip_text = "暂停（空格）" if audio.playing else "播放（空格）"
	play.accessibility_name = "暂停" if audio.playing else "播放"
	var loop: Button = get_node("%Loop")
	loop.set_pressed_no_signal(audio.loop_enabled)
	loop.tooltip_text = "关闭循环播放（L）" if audio.loop_enabled else "开启循环播放（L）"
	loop.accessibility_name = "循环播放"
	get_node("%In").tooltip_text = "将当前位置设为循环起点（I）\n当前起点：" + _time_label(audio.loop_start)
	get_node("%Out").tooltip_text = "将当前位置设为循环终点（O）\n当前终点：" + _time_label(audio.loop_end)
	get_node("%Rate").select([0.5, 0.75, 1.0, 1.25, 1.5].find(audio.rate))

func _preview_status(message: String) -> void:
	var suffix := ""
	if message == "定位中": suffix = "  ·  正在定位…"
	elif "不可预览" in message or message == "无法预览": suffix = "  ·  无法预览"
	$Layout/Split/Top/Main/PreviewColumn/PreviewLabel.text = "关卡预览" + suffix
	$Layout/Split/Top/Main/PreviewColumn/PreviewLabel.tooltip_text = "当前规则预览：多节点 Tuning 暂按分段滑条演示，接合、预告和半径可能变化。\nGhost 已从真实交点随机抽取；候选不足时报告数量，理想调频预测、共同等级和独立计分尚待接入。BOSS 仅保存来源标记。"

func _sync_ghost_preview_label() -> void:
	var label := fields.get_node_or_null("GhostPreview") as Label
	if label == null: return
	var events := _selected_notes().filter(func(e): return e is GhostEvent)
	if events.is_empty(): return
	var result: Dictionary = preview.ghost_results.get(events[0].event_id, {})
	label.text = "当前预览：尚未到达命中时刻" if result.is_empty() else "当前预览：实际生成 %d / 编排 %d" % [result.actual, events[0].count]
	if not result.is_empty() and not str(result.get("generation_issue", "")).is_empty(): label.text += "（交点不足）"
	label.tooltip_text = "从生成区域内有足够间距的真实交点随机抽取；不足时显示实际数量，不重复坐标凑数。理想调频预测与独立计分尚待接入。"

func _time_label(seconds: float) -> String:
	var absolute := absf(seconds)
	return ("−" if seconds < 0 else "") + "%02d:%06.3f" % [int(absolute) / 60, fmod(absolute, 60)]

func _section(title: String) -> void:
	if fields.get_child_count() > 0: fields.add_child(HSeparator.new())
	var label := Label.new(); label.text = title; label.theme_type_variation = &"SectionLabel"
	fields.add_child(label)

func _field_hint(title: String) -> String:
	return {"难度标识": "用于谱面文件名；同一歌曲内不能重复", "首拍偏移（ms）": "音乐开头到第一拍的时间，单位毫秒", "当前位置 BPM": "从当前位置开始应用该速度", "全谱偏移（tick）": "按音乐 tick 整体偏移谱面，保留原有时间语义", "起始位置（tick）": "修改后整体移动选区，保持相对间隔", "Hold 时长（tick）": "修改所选 Hold 的持续长度，Tap 不受影响", "外观标识": "对应音符外观预设的稳定标识", "试听补偿（ms）": "本机画面和录入时间补偿：正值使播放头更晚，不改变音乐与提示的相对位置，也不修改歌曲首拍"}.get(title, title)

func _issue_label(issue: ValidationIssue) -> String:
	# 翻译工具当前支持的领域问题；原始诊断仍保留在悬停详情，不改共享校验规则。
	var messages := {
		"chart.null": "没有可读取的谱面", "schema.unsupported": "谱面版本不受支持",
		"chart.id_empty": "谱面标识不能为空", "chart.difficulty_empty": "难度标识不能为空",
		"chart.ppq_not_frozen": "当前游戏要求每拍 480 tick", "chart.end_invalid": "谱面结束位置必须大于零",
		"chart.after_song_end": "谱面结束位置超出音乐时长", "tempo.empty": "请设置初始 BPM",
		"tempo.null": "BPM 事件缺少数据", "tempo.bpm_invalid": "BPM 必须是大于零的数值",
		"tempo.duplicate_tick": "同一位置只能设置一个 BPM", "tempo.missing_zero": "请在 tick 0 设置初始 BPM",
		"meter.null": "拍号事件缺少数据", "meter.invalid": "拍号无效，请检查每小节拍数和分母",
		"meter.duplicate_tick": "同一位置只能设置一个拍号", "note.null": "音符缺少数据",
		"note.preroll": "该音符位于第一拍之前", "note.kind_invalid": "音符类型不受支持",
		"note.affinity_invalid": "Tap 和 Hold 必须属于生钟或死钟", "note.tap_duration": "Tap 的时长必须为零",
		"note.hold_duration": "Hold 时长必须大于零", "note.after_chart_end": "音符超出谱面结束位置",
		"note.group_size": "双押组合必须恰好包含两个音符", "note.group_mismatch": "双押音符必须起始位置相同，分别属于生钟和死钟",
		"input.window_conflict": "音符操作时间冲突，请调整起始位置或 Hold 时长",
		"event.id_empty": "谱面对象缺少标识", "event.id_duplicate": "谱面对象标识重复",
		"section.outside_chart": "段落位置超出谱面范围"
	}
	var caption: String = messages.get(str(issue.code), issue.message)
	return caption + "（%s，tick %d）" % [issue.event_id, issue.tick] if not issue.event_id.is_empty() else caption

func _convert_selected(kind: int) -> void:
	_mutate_selected("转为 Hold" if kind == GameplayTypes.NoteKind.HOLD else "转为 Tap", func(note) -> void:
		if not note is NoteEvent: return
		if note.kind == kind: return
		note.kind = kind
		note.duration_ticks = maxi(1, timeline.snap_ticks) if kind == GameplayTypes.NoteKind.HOLD else 0)

func _meter_controls(tick: int) -> void:
	_label("当前位置拍号")
	var current_n := 4
	var current_d := 4
	for meter in document.chart().meter_events:
		if meter.tick <= tick: current_n = meter.numerator; current_d = meter.denominator
	var row := HBoxContainer.new(); fields.add_child(row)
	var numerator := SpinBox.new(); numerator.min_value = 1; numerator.max_value = 32; numerator.value = current_n
	numerator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	numerator.tooltip_text = "每小节的拍数；修改从当前位置生效"
	row.add_child(numerator)
	var slash := Label.new(); slash.text = "/"; row.add_child(slash)
	var denominator := OptionButton.new(); denominator.tooltip_text = "以几分音符为一拍"; row.add_child(denominator)
	for value in [1, 2, 4, 8, 16, 32, 64]:
		if document.chart().ppq * 4 % value != 0: continue
		denominator.add_item(str(value), value)
		if value == current_d: denominator.select(denominator.item_count - 1)
	var commit := func() -> void:
		numerator.apply()
		if int(numerator.value) != current_n: _set_meter(int(numerator.value), current_d, tick)
	numerator.get_line_edit().text_submitted.connect(func(_text: String) -> void: _queue_property_commit(commit))
	numerator.get_line_edit().focus_exited.connect(func() -> void: _queue_property_commit(commit))
	denominator.item_selected.connect(func(i: int) -> void: _set_meter(int(numerator.value), denominator.get_item_id(i), tick))
	var presets := HBoxContainer.new(); fields.add_child(presets)
	for pair in [[3, 4], [4, 4]]:
		var button := Button.new(); button.text = "%d/%d" % [pair[0], pair[1]]; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "从当前位置应用 %s 拍号" % button.text
		presets.add_child(button)
		button.pressed.connect(func() -> void: _finish_text_edit(); _set_meter(pair[0], pair[1], tick))

func _update_window_title() -> void:
	# 保存、切换歌曲和撤销均保留工具版本及未保存标记。
	get_window().title = "冥河 · 写谱器 v%s · %s%s" % [VERSION, document.song.title, " *" if document.dirty else ""]

func _on_document_changed() -> void:
	if not is_node_ready(): return
	_update_alignment_controls()
	if _recovery_ready and document.dirty: _autosave.start()
	_update_window_title()
	var kind := document.change_kind
	# 暂停时也刷新游标 tick 和节拍器基准，继续试听时沿用新映射。
	if kind == &"timing" and not audio.playing: _position_changed(audio.position)
	if kind == &"annotation":
		timeline.queue_redraw()
		var boss := fields.get_node_or_null("BossFlag") as CheckButton
		if boss != null:
			boss.set_pressed_no_signal(_selected_notes().filter(func(e): return not e is TuningPathEvent).all(func(e): return ChartEditEvents.is_boss(e)))
		return
	if kind == &"presentation":
		_apply_document_palette(); return
	if kind == &"metadata":
		_updating = true
		library.get_node("SongTitle").text = document.song.title
		library.get_node("Artist").text = document.song.artist
		_updating = false
		if not get_viewport().gui_get_focus_owner() is LineEdit: _inspect.call_deferred()
		return
	if not recorder.active and kind != &"sections": _refresh_cues()
	_refresh_pending = kind != &"sections"
	_candidate_timer.stop()
	if preview.rebuilding and _refresh_pending: preview.clear_preview()
	var snap_divisors := [1, 2, 4, 8, 16, 3, 6, 0]
	var divisor: int = snap_divisors[maxi(0, get_node("%Snap").selected)]
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
	_update_window_title()

func _rebuild_preview() -> void:
	var draft := document.chart().duplicate(true) as SongChart
	# 候选版本仅用于预览，正式资源和撤销栈仍保持手势前的内容。
	if not timeline.candidates.is_empty():
		ChartEditEvents.replace(draft, timeline.candidates, timeline.candidates)
	var rules: GameplayRuleSet = load("res://content/rules/default_gameplay_rules.tres")
	var authoring_issues := ChartPathAdapter.validate(draft, rules)
	var report := ValidationReport.new()
	if authoring_issues.is_empty(): report = ChartValidator.validate(ChartPathAdapter.project(draft, rules), rules)
	else:
		for issue in authoring_issues: report.add_error(issue.code, issue.message, issue.event_id, StringName(issue.track), issue.tick)
	for unknown: Dictionary in draft.get_meta("unknown_notes", []):
		report.add_error(&"editor.unsupported_note", "暂不支持的音符：%s；原数据仍保留" % unknown.get("id", ""), str(unknown.get("id", "")), &"notes", int(unknown.get("tick", 0)))
	var theme_id := str(ChartJsonCodec.encode_chart(draft).get("presentation", {}).get("theme_id", "default"))
	if not ChartProjectLoader.THEMES.has(theme_id): report.add_error(&"editor.unknown_theme", "找不到主题：" + theme_id)
	var previous_messages := _problem_messages
	_problem_messages = PackedStringArray()
	problems.clear()
	for issue in report.issues:
		_problem_messages.append(str(issue.get("message")))
		problems.add_item(_issue_label(issue))
		problems.set_item_tooltip(problems.item_count - 1, str(issue.get("message")))
		problems.set_item_metadata(problems.item_count - 1, int(issue.get("tick")))
		problems.set_meta("event_%d" % (problems.item_count - 1), issue.event_id)
	var toggle: Button = $Layout/ProblemToggle
	toggle.text = "问题（%d）" % problems.item_count
	toggle.visible = problems.item_count > 0
	if problems.item_count == 0: toggle.set_pressed_no_signal(false)
	elif _problem_messages != previous_messages: toggle.set_pressed_no_signal(true)
	problems.custom_minimum_size.y = clampi(problems.item_count * 24 + 8, 32, 64)
	problems.visible = toggle.visible and toggle.button_pressed
	if not previous_messages.is_empty() and _problem_messages.is_empty(): _message("问题已修正")
	if report.has_errors() or not document.chart().get_meta("unknown_notes", []).is_empty():
		preview.clear_preview()
		_preview_status("无法预览")
		_message("谱面暂时无法预览。可以继续编辑和保存，请检查问题列表。")
		return
	_preview_theme_id = theme_id
	var stage := ChartProjectLoader.make_stage(document.song, draft)
	if preview.load_preview(stage, viewport):
		audio.cues.set_sample(&"life", preview.stage_root.audio_feedback.life_strike)
		audio.cues.set_sample(&"death", preview.stage_root.audio_feedback.death_strike)
		await preview.seek_preview(roundi(audio.position * 1000000.0))
		# 重建期间音乐继续走；无声补齐这段时间，不补播历史判定声。
		if not preview.rebuilding: preview.set_transport(roundi(audio.position * 1000000.0), false)

func _refresh_cues() -> void:
	if not audio.is_node_ready() or document.charts.is_empty(): return
	var duration := document.song.audio_stream.get_length() if document.song.audio_stream != null else 0.0
	var candidate := rhythm.audition_grid() if rhythm != null else {}
	audio.cues.set_events(StudioCueEvents.build(document, _note_sound_enabled, _metronome_enabled, candidate, duration))

func _setup_alignment_controls() -> void:
	# 独立于选区属性；选中音符或折叠侧栏时仍可调整音乐。
	_alignment_bar = VBoxContainer.new(); _alignment_bar.name = "AlignmentBar"
	var column := timeline.get_parent()
	column.add_child(_alignment_bar); column.move_child(_alignment_bar, 1)
	var row := HFlowContainer.new(); row.name = "Actions"; _alignment_bar.add_child(row)
	var values := HBoxContainer.new(); row.add_child(values)
	var label := Label.new(); label.text = "音乐对齐 · 首拍（ms）"; values.add_child(label)
	_offset_edit = LineEdit.new(); _offset_edit.name = "Offset"
	_offset_edit.custom_minimum_size.x = 132
	_offset_edit.tooltip_text = "有效 tick 0 在音频中的位置；正值表示更晚。Enter 或离焦提交，不移动音符 tick。"
	values.add_child(_offset_edit)
	_offset_edit.text_submitted.connect(func(_text: String) -> void: _commit_offset_text())
	_offset_edit.focus_exited.connect(func() -> void: _queue_property_commit(_commit_offset_text))
	for amount in [-1.0, -0.1, 0.1, 1.0]:
		var button := Button.new(); button.text = "%+.1f" % amount
		button.tooltip_text = "首拍偏移 %+.1f ms" % amount
		values.add_child(button)
		button.pressed.connect(func() -> void:
			_finish_text_edit(); _set_first_beat(document.offset_sec() + amount / 1000.0))
	_alignment_button(row, "当前位置设为首拍", "SetFirstBeat", func() -> void:
		_finish_text_edit(); _set_first_beat(audio.position))
	_alignment_button(row, "定位首拍", "LocateFirstBeat", _locate_first_beat)
	_wave_move_button = _alignment_button(row, "移动波形", "MoveWaveform", func() -> void: pass)
	_wave_move_button.toggle_mode = true
	_wave_move_button.tooltip_text = "开启后拖波形调整对齐；关闭后拖波形定位播放头。Shift 精细拖动，Esc 取消。"
	_wave_move_button.add_theme_color_override("font_pressed_color", Color("ffcf75"))
	_wave_move_button.toggled.connect(func(enabled: bool) -> void:
		_finish_text_edit(); timeline.cancel_gesture(); timeline.move_waveform = enabled
		_update_alignment_controls())
	_alignment_button(row, "同步至全部难度", "SyncFirstBeat", func() -> void:
		_prepare_alignment(); document.set_first_beat_offset_ms(document.offset_sec() * 1000.0, true))
	_alignment_info = Label.new(); _alignment_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alignment_info.add_theme_color_override("font_color", Color("a6b2c5"))
	_alignment_bar.add_child(_alignment_info)
	add_child(_wave_context)
	_wave_context.add_item("将此处设为首拍")
	_wave_context.id_pressed.connect(func(_id: int) -> void: _set_first_beat(_wave_context_seconds))
	timeline.waveform_context_requested.connect(func(at: Vector2, seconds: float) -> void:
		_finish_text_edit(); _wave_context_seconds = seconds
		_wave_context.position = Vector2i(at); _wave_context.popup())
	timeline.alignment_started.connect(_prepare_alignment)
	timeline.alignment_preview.connect(_show_alignment_value)
	timeline.alignment_committed.connect(func(seconds: float) -> void:
		document.set_first_beat_offset_ms(seconds * 1000.0); _update_alignment_controls())
	timeline.alignment_cancelled.connect(_update_alignment_controls)
	_update_alignment_controls()

func _alignment_button(parent: Control, text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new(); button.name = node_name; button.text = text
	parent.add_child(button); button.pressed.connect(action)
	return button

func _prepare_alignment() -> void:
	_finish_text_edit(); _finish_recording(true); _input_starts.clear()
	_seek_timer.stop(); _candidate_timer.stop()
	audio.set_playing(false)
	_follow_suspended = true

func _set_first_beat(seconds: float) -> void:
	_prepare_alignment()
	document.set_first_beat_offset_ms(seconds * 1000.0)
	_update_alignment_controls()

func _commit_offset_text() -> void:
	var text := _offset_edit.text.strip_edges()
	if text == _offset_display_text: return
	if not text.is_valid_float() or not is_finite(text.to_float()):
		_update_alignment_controls(); _message("首拍偏移请输入有限的毫秒数")
		return
	# 先记住已提交文本，释放焦点时的回调便不会重复提交。
	_offset_display_text = text
	_set_first_beat(text.to_float() / 1000.0)

func _show_alignment_value(seconds: float) -> void:
	_offset_display_text = String.num(seconds * 1000.0, 6)
	_offset_edit.text = _offset_display_text
	_alignment_info.visible = document.chart().chart_offset_ticks != 0
	if document.chart().chart_offset_ticks != 0:
		var zero_seconds := float(document.tempo_map().tick_to_us(0)) / 1000000.0 + seconds - document.offset_sec()
		_alignment_info.text = "谱面 tick 0：%s（全谱偏移 %+d tick）" % [timeline.format_time(zero_seconds), document.chart().chart_offset_ticks]

func _update_alignment_controls() -> void:
	if _offset_edit == null: return
	_show_alignment_value(document.offset_sec())

func _locate_first_beat() -> void:
	_prepare_alignment()
	var seconds := document.offset_sec()
	audio.seek(seconds)
	timeline.view_start = seconds - timeline.size.x / timeline.pixels_per_second * 0.25

func _inspect() -> void:
	if not _color_edit.is_empty(): return
	var scroll: ScrollContainer = fields.get_parent()
	var scroll_at := scroll.scroll_vertical
	_colors.clear()
	for child in fields.get_children(): fields.remove_child(child); child.queue_free()
	_section("位置与时长" if not timeline.selected.is_empty() else "谱面信息")
	if timeline.selected.is_empty():
		var property_tick := _cursor_tick()
		_text_field("难度标识", document.chart().difficulty_id, func(value: String) -> void:
			if value.is_empty() or "/" in value or "\\" in value: _message("难度标识不能为空或包含路径分隔符"); return
			for chart in document.charts:
				if chart != document.chart() and chart.difficulty_id == value: _message("难度标识重复"); return
			var data := ChartJsonCodec.encode_chart(document.chart()); data.difficulty_id = value; data.difficulty_name = value; document.change_metadata(data))
		_text_field("谱师", str(ChartJsonCodec.encode_chart(document.chart()).get("mapper", "")), func(value: String) -> void:
			var data := ChartJsonCodec.encode_chart(document.chart()); data.mapper = value; document.change_metadata(data))
		_section("时间与节拍")
		_number("初始 BPM", document.tempo_map().bpm_at_tick(0), 1, 1000, func(value: float) -> void: _set_bpm(value, -document.chart().chart_offset_ticks), 0.001)
		_number("在当前位置添加变速", document.tempo_map().bpm_at_tick(property_tick + document.chart().chart_offset_ticks), 1, 1000, func(value: float) -> void: _set_bpm(value, property_tick), 0.001)
		_number("谱面结束位置（tick）", document.chart().end_tick, 1, 10000000, func(value: float) -> void:
			var data := ChartJsonCodec.encode_chart(document.chart()); data.timing.end_tick = int(value); document.change_metadata(data))
		_number("全谱偏移（tick）", document.chart().chart_offset_ticks, -100000, 100000, func(value: float) -> void:
			var data := ChartJsonCodec.encode_chart(document.chart()); data.timing.chart_offset_ticks = int(value); document.change_metadata(data))
		_meter_controls(property_tick)
		_section("试听")
		_number("试听补偿（ms）", audio.device_compensation_ms, -500, 500, func(value: float) -> void: audio.device_compensation_ms = value)
		_number("长按判定（ms）", recorder.threshold_ms, 50, 500, func(value: float) -> void: recorder.threshold_ms = value; _save_tool_settings())
		_section("外观")
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
		var palette_theme := _document_theme()
		for key in ["life", "death", "su", "ink", "paper"]:
			_label({"life": "生界颜色", "death": "死界颜色", "su": "骨白相纹", "ink": "墨色", "paper": "纸色"}[key])
			var picker := ColorPickerButton.new(); picker.color = palette_theme.get(key + "_color")
			fields.add_child(picker); _colors[key] = picker
			picker.get_popup().about_to_popup.connect(func() -> void: _begin_color(key))
			picker.color_changed.connect(func(color: Color) -> void: _preview_color(key, color))
			picker.popup_closed.connect(func() -> void: _finish_color())
		if not document.chart().sections.is_empty(): _section("段落")
		for section in document.chart().sections:
			_text_field("段落位置（tick）：%d" % section.tick, section.label, func(value: String) -> void:
				var data := ChartJsonCodec.encode_chart(document.chart())
				for raw: Dictionary in data.sections:
					if raw.id == section.event_id: raw.name = value
				document.change_metadata(data))
	else:
		_inspect_events()

	scroll.set_deferred("scroll_vertical", scroll_at)

func _text_field(title: String, value: String, callback: Callable) -> void:
	_label(title)
	var edit := LineEdit.new(); edit.text = value; edit.tooltip_text = _field_hint(title); fields.add_child(edit)
	var committed := [value]
	var apply := func() -> void:
		if edit.text != committed[0]: committed[0] = edit.text; callback.call(edit.text)
	edit.text_submitted.connect(func(_text: String) -> void: _queue_property_commit(apply))
	edit.focus_exited.connect(func() -> void: _queue_property_commit(apply))

func _inspect_events() -> void:
	var events := _selected_notes()
	if events.is_empty(): return
	_label("已选 %d 个对象" % events.size())
	var anchor: int = events[0].tick
	_number("起始位置（tick）", anchor, -100000, 10000000, func(value: float):
		var before: Array = []; var after: Array = []
		for id in ChartEditEvents.moving_ids(document.chart(), timeline.selected):
			var event := document.find_note(id); before.append(event.duplicate(true))
			var copy = event.duplicate(true); copy.tick += int(value) - anchor
			after.append(copy)
		ChartEditEvents.rebind_moved_ghosts(document.chart(), before, after, timeline.selected)
		_commit_events("移动选区", before, after))
	var holds := events.filter(func(e): return e is NoteEvent and e.kind == GameplayTypes.NoteKind.HOLD)
	if not holds.is_empty():
		_number("Hold 时长（tick）", holds[0].duration_ticks, 1, 1000000, func(value: float):
			_mutate_selected("修改 Hold 时长", func(e):
				if e is NoteEvent and e.kind == GameplayTypes.NoteKind.HOLD: e.duration_ticks = int(value)))
	var ghosts := events.filter(func(e): return e is GhostEvent)
	if not ghosts.is_empty():
		_number("Ghost 数量", ghosts[0].count, 1, 16, func(value: float):
			_mutate_selected("修改 Ghost 数量", func(e):
				if e is GhostEvent: e.count = int(value)))
		_label("计分来源：" + ("生、死共同 Tuning" if ghosts[0].tuning_ids.size() == 2 else "所在侧 Tuning"))
		var actual := Label.new(); actual.name = "GhostPreview"; actual.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fields.add_child(actual); _sync_ghost_preview_label()
		_button("此刻再添加一批 Ghost", func(): _edit_action(12))
	if events.size() == 1 and events[0] is TuningPathEvent:
		var path: TuningPathEvent = events[0]
		_number("结束位置（tick）", path.tick + path.duration_ticks, path.tick + path.points.size() - 1, 10000000, func(value: float):
			var copy := path.duplicate(true) as TuningPathEvent
			var length := int(value) - copy.tick
			for point in copy.points: point.offset_ticks = roundi(float(point.offset_ticks) * length / path.duration_ticks)
			_commit_events("伸缩 Tuning", [path], [copy]))
		var expand := CheckButton.new(); expand.text = "角度路径"; expand.button_pressed = true; fields.add_child(expand)
		var editor := preload("res://scenes/tools/chart_studio/path_editor.tscn").instantiate()
		editor.path = path.duplicate(true); fields.add_child(editor)
		editor.edit_queued.connect(_queue_property_commit)
		expand.toggled.connect(func(value: bool): editor.visible = value)
		editor.submitted.connect(func(copy: TuningPathEvent): timeline.candidates.clear(); _commit_events("编辑 Tuning 节点", [path], [copy]))
		editor.candidate.connect(func(copy):
			timeline.candidates.clear()
			if copy != null: timeline.candidates.append(copy)
			timeline.queue_redraw())
		_button("在播放头添加转折点", func(): _add_path_point(path.event_id, _cursor_tick()))
	if events.any(func(e): return e is NoteEvent or e is GhostEvent):
		var boss := CheckButton.new(); boss.name = "BossFlag"; boss.text = "BOSS 发出"
		boss.button_pressed = events.filter(func(e): return not e is TuningPathEvent).all(func(e): return ChartEditEvents.is_boss(e))
		fields.add_child(boss); boss.toggled.connect(func(_value: bool): _toggle_boss())
	_section("编辑操作")
	_button("选择关联内容", func(): _edit_action(10))
	_button("按当前位置重新关联", func(): _edit_action(11))
	_button("生死互换", func(): _edit_action(3))
	var notes := events.filter(func(e): return e is NoteEvent)
	if not notes.is_empty():
		if notes.any(func(e): return e.kind == GameplayTypes.NoteKind.TAP): _button("转为 Hold", func(): _convert_selected(GameplayTypes.NoteKind.HOLD))
		if not holds.is_empty(): _button("转为 Tap", func(): _convert_selected(GameplayTypes.NoteKind.TAP))
		_button("组合双押", func(): _edit_action(4)); _button("解除组合", func(): _edit_action(5))
		_text_field("外观标识", str(notes[0].visual_variant), func(value: String):
			_mutate_selected("外观设置", func(e):
				if e is NoteEvent: e.visual_variant = StringName(value)))
	_button("删除所选对象", func(): _edit_action(0))

func _add_path_point(id: String, tick: int) -> void:
	var source := document.find_note(id) as TuningPathEvent
	if source == null: return
	var offset := tick - source.tick
	var index := 1
	while index < source.points.size() and source.points[index].offset_ticks < offset: index += 1
	if offset <= 0 or index >= source.points.size() or source.points[index].offset_ticks == offset:
		_message("请在两个节点之间选择一个时间位置"); return
	var draft := source.duplicate(true) as TuningPathEvent
	var a := draft.points[index - 1]; var b := draft.points[index]
	var point := TuningPathPoint.new(); point.event_id = StudioDocument.new_id("point"); point.offset_ticks = offset
	point.angle_deg = a.angle_deg + wrapf(b.angle_deg - a.angle_deg, -180, 180) * float(offset - a.offset_ticks) / (b.offset_ticks - a.offset_ticks)
	draft.points.insert(index, point)
	var dialog := AcceptDialog.new(); dialog.title = "添加 Tuning 转折点"; dialog.ok_button_text = "取消"
	var editor := preload("res://scenes/tools/chart_studio/path_editor.tscn").instantiate()
	editor.path = draft; editor.pending_node = true
	editor.edit_queued.connect(_queue_property_commit)
	dialog.add_child(editor); add_child(dialog); editor.circle.selected = index; editor._show_point()
	editor.submitted.connect(func(copy: TuningPathEvent):
		timeline.candidates.clear(); dialog.hide(); _commit_events("添加转折点", [source], [copy]); dialog.queue_free())
	editor.candidate.connect(func(copy):
		timeline.candidates.clear()
		if copy != null: timeline.candidates.append(copy)
		timeline.queue_redraw())
	var cancel := func(): timeline.candidates.clear(); timeline.queue_redraw(); dialog.queue_free()
	dialog.confirmed.connect(cancel); dialog.canceled.connect(cancel)
	dialog.popup_centered(Vector2i(300, 480))

func _sync_event_menu() -> void:
	var eligible := _selected_notes().filter(func(e): return e is NoteEvent or e is GhostEvent)
	var index := _context.get_item_index(9)
	_context.set_item_disabled(index, eligible.is_empty())
	_context.set_item_checked(index, not eligible.is_empty() and eligible.all(func(e): return ChartEditEvents.is_boss(e)))

func _toggle_boss() -> void:
	var eligible := _selected_notes().filter(func(e): return e is NoteEvent or e is GhostEvent)
	if eligible.is_empty(): return
	var value := not eligible.all(func(e): return ChartEditEvents.is_boss(e))
	var after: Array = []
	for event in eligible:
		var copy = event.duplicate(true); ChartEditEvents.set_boss(copy, value); after.append(copy)
	document.execute("BOSS 来源标记", eligible, after, {}, {}, &"annotation")

func _commit_events(label: String, before: Array, after: Array) -> void:
	if before.size() == after.size():
		var unchanged := true
		for i in before.size(): unchanged = unchanged and ChartEditEvents.same(before[i], after[i])
		if unchanged: return
	# 父对象缩短或移除只在这里提示，三种入口（鼠标、属性、菜单）共用一次命令。
	var rules: GameplayRuleSet = load("res://content/rules/default_gameplay_rules.tres")
	for event in after:
		if event is TuningPathEvent:
			var shape := ChartPathAdapter.frequency_values(event, rules)
			if shape.has("error"): _message(shape.error); timeline.candidates.clear(); timeline.queue_redraw(); return
	var shadow := document.chart().duplicate(false) as SongChart
	ChartEditEvents.replace(shadow, before, after)
	# 既有父对象变化允许保留问题稿；直接新建必须满足窗口及同侧排斥。
	for event in after:
		if document.find_note(event.event_id) != null: continue
		var invalid := ""
		for issue in ChartPathAdapter.validate(shadow, rules):
			if issue.event_id == event.event_id: invalid = issue.message; break
		if event is TuningPathEvent:
			for other in shadow.tuning_paths:
				if other.event_id != event.event_id and other.affinity == event.affinity and maxi(other.tick, event.tick) < mini(other.tick + other.duration_ticks, event.tick + event.duration_ticks): invalid = "同侧 Tuning 不能重叠"
		if not invalid.is_empty():
			_message(invalid); timeline.candidates.clear(); timeline.selected.erase(event.event_id); timeline.queue_redraw(); return
	var shortened := false
	var after_ids := {}
	for event in after: after_ids[event.event_id] = event
	for old in before:
		var newer = after_ids.get(old.event_id)
		if old.duration_ticks > 0 and (newer == null or newer.duration_ticks < old.duration_ticks): shortened = true
	var affected := PackedStringArray()
	if shortened:
		for issue in ChartPathAdapter.validate(shadow, rules):
			if not affected.has(issue.event_id): affected.append(issue.event_id)
		affected = ChartEditEvents.related_ids(shadow, affected)
		# 本来就存在的问题不因为这次操作再次弹窗。
		var existing := PackedStringArray()
		for issue in ChartPathAdapter.validate(document.chart(), rules): existing.append(issue.event_id)
		for id in existing:
			if affected.has(id): affected.remove_at(affected.find(id))
	if affected.is_empty():
		document.execute(label, before, after); return
	var dialog := ConfirmationDialog.new(); dialog.title = "关联内容受到影响"
	var lines := PackedStringArray(["这次操作会影响 %d 个关联对象：" % affected.size()])
	for id in affected:
		var event = ChartEditEvents.find(shadow, id)
		if event != null: lines.append("%s · tick %d" % [ChartEditEvents.title(event), event.tick])
	dialog.dialog_text = "\n".join(lines); dialog.ok_button_text = "保留并标出问题"; dialog.cancel_button_text = "取消"
	dialog.add_button("删除受影响内容", false, "remove")
	add_child(dialog)
	dialog.confirmed.connect(func(): document.execute(label, before, after); dialog.queue_free())
	dialog.custom_action.connect(func(_action: StringName):
		var removed := before.duplicate(); var ids := {}
		for e in removed: ids[e.event_id] = true
		for id in affected:
			var event := document.find_note(id)
			if event != null and not ids.has(id): removed.append(event)
		document.execute(label, removed, after.filter(func(e): return not affected.has(e.event_id))); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(480, 280))

func _label(text: String) -> void:
	var label := Label.new(); label.text = text; fields.add_child(label)

func _button(text: String, callback: Callable) -> void:
	var button := Button.new(); button.text = text; fields.add_child(button); button.pressed.connect(func() -> void: _finish_text_edit(); callback.call())

func _number(text: String, value: float, minimum: float, maximum: float, callback: Callable, step_value := 1.0) -> void:
	_label(text)
	var spin := SpinBox.new()
	spin.min_value = minimum; spin.max_value = maximum; spin.step = step_value; spin.value = value
	spin.tooltip_text = _field_hint(text)
	fields.add_child(spin)
	# 提交在文本确认或离焦时进行，输入过程中不重建控件。
	var edit := spin.get_line_edit()
	var committed := [value]
	var displayed := [edit.text]
	var commit := func() -> void:
		# 控件显示的小数位少于谱面原值时，单纯进出焦点不应量化 BPM。
		if edit.text == displayed[0]: return
		spin.apply()
		displayed[0] = edit.text
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
	_finish_color()
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: focused.release_focus()
	_flush_property_edits()


func _selected_notes() -> Array:
	var notes: Array = []
	for id in timeline.selected:
		var note := document.find_note(id)
		if note != null: notes.append(note)
	return notes

func _mutate_selected(label: String, callback: Callable) -> void:
	var before: Array = []; var after: Array = []
	for note in _selected_notes():
		before.append(note.duplicate(true))
		var copy = note.duplicate(true)
		callback.call(copy); after.append(copy)
	if not before.is_empty(): _commit_events(label, before, after)

func _edit_action(id: int) -> void:
	match id:
		0: _commit_events("删除音符", _selected_notes(), [])
		1: document.copy_notes(timeline.selected)
		2: timeline.selected = document.paste(_cursor_tick())
		3: _mutate_selected("生死互换", func(n) -> void:
			if not n is GhostEvent:
				n.affinity = 1 - n.affinity
				if n is TuningPathEvent: ChartEditEvents.rebind(document.chart(), n))
		4:
			var notes := _selected_notes()
			if notes.size() != 2 or not notes[0] is NoteEvent or not notes[1] is NoteEvent or notes[0].tick != notes[1].tick or notes[0].affinity == notes[1].affinity:
				_message("请选择起始位置相同、分别位于生钟和死钟的两个音符"); return
			var group := StudioDocument.new_id("group")
			_mutate_selected("组合双押", func(n: NoteEvent) -> void: n.group_id = group; n.damage_group_id = group)
		5: _mutate_selected("解除组合", func(n) -> void:
			if n is NoteEvent: n.group_id = ""; n.damage_group_id = "")
		6, 7:
			var step := maxi(1, timeline.snap_ticks)
			_mutate_selected("量化", func(n) -> void:
				var end: int = n.tick + n.duration_ticks
				n.tick = roundi(float(n.tick) / step) * step
				if id == 7 and n.duration_ticks > 0: n.duration_ticks = maxi(step, roundi(float(end) / step) * step - n.tick))
		8:
			var notes := _selected_notes()
			if notes.is_empty(): return
			var end: int = notes[0].tick + maxi(1, timeline.snap_ticks)
			for note in notes: end = maxi(end, note.tick + note.duration_ticks)
			document.copy_notes(timeline.selected)
			timeline.selected = document.paste(end)
		9: _toggle_boss()
		10: timeline.selected = ChartEditEvents.linked_ids(document.chart(), timeline.selected)
		11: _mutate_selected("重新关联", func(n): ChartEditEvents.rebind(document.chart(), n))
		12:
			var batch := GhostEvent.new(); batch.event_id = StudioDocument.new_id("ghost"); batch.tick = _cursor_tick()
			var chosen := _selected_notes()
			if chosen.size() == 1 and chosen[0] is GhostEvent: batch.tick = chosen[0].tick
			if ChartEditEvents.rebind(document.chart(), batch): _commit_events("添加 Ghost 批次", [], [batch])
			else: _message("此刻没有 Tuning，无法添加 Ghost")

	timeline.queue_redraw()
	_inspect()

func _cursor_tick() -> int:
	var tick := timeline._map.us_to_tick(roundi(audio.position * 1000000.0))
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
	_seek_timer.stop(); _finish_recording(true); _flush_property_edits()
	var span := timeline.size.x / timeline.pixels_per_second
	if seconds == 0: timeline.view_start = -2.0
	elif seconds < timeline.view_start or seconds > timeline.view_start + span: timeline.view_start = seconds - span * 0.25
	audio.seek(seconds)
	if timeline.selected.is_empty(): _inspect()

func _scrub(seconds: float) -> void:
	_finish_recording(true); _seek_target = seconds; timeline.playhead = seconds
	if _seek_timer.is_stopped(): _seek_timer.start()

func _position_changed(seconds: float) -> void:
	timeline.playhead = seconds
	if audio.playing and _follow.button_pressed and not _follow_suspended and (seconds < timeline.view_start or seconds > timeline.view_start + timeline.size.x / timeline.pixels_per_second * 0.85): timeline.view_start = seconds - timeline.size.x / timeline.pixels_per_second * 0.15
	get_node("%Position").text = _time_label(seconds)
	get_node("%TickPosition").text = "tick %d" % _cursor_tick()

func _toggle_play() -> void:
	_finish_text_edit()
	if not audio.playing: _follow_suspended = false
	audio.set_playing(not audio.playing)
	if not audio.playing and timeline.selected.is_empty(): _inspect()
	_sync_transport()

func _message(text: String, detail: String = "") -> void:
	status.text = text
	status.tooltip_text = detail if not detail.is_empty() else text

func _file_dialog(mode: FileDialog.FileMode, filters: PackedStringArray, callback: Callable) -> void:
	_finish_recording(true)
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
	_confirm_discard(func() -> void: audio.set_playing(false); document.new_project(); _activate_project({}); _save_as())

func _open() -> void:
	# 精确文件名过滤会让 FileDialog 预选但不填写文件名，导致点击与双击失效。
	_confirm_discard(func() -> void: _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.json ; 歌曲项目（请选择 song.json）"]), _open_path))

func _open_path(path: String) -> void:
	var error := StudioProjectIO.open_project(path, document)
	if not error.is_empty(): _message("打开项目失败：" + error, path); return
	_activate_project(_workspace_data())
	_message("已打开：" + document.song.title, path)

func _save() -> void:
	_finish_recording()
	if document.directory.is_empty(): _save_as(); return
	var error := StudioProjectIO.save_project(document)
	_message(error if not error.is_empty() else "已保存", document.directory)
	if error.is_empty(): _save_workspace()
	if error.is_empty(): DirAccess.remove_absolute(recovery_path)
	if error.is_empty(): _update_window_title()

func _save_as() -> void:
	_finish_recording()
	_file_dialog(FileDialog.FILE_MODE_OPEN_DIR, PackedStringArray(), func(path: String) -> void:
		var error := StudioProjectIO.save_project(document, path); _message(error if not error.is_empty() else "项目已保存，可以导入音乐")
		if error.is_empty():
			_save_workspace(); DirAccess.remove_absolute(recovery_path)
			_update_window_title())

func _import_audio() -> void:
	if rhythm != null: rhythm.reset_analysis()
	if document.directory.is_empty(): _save_then(_import_audio); return
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.wav,*.ogg,*.mp3 ; 音频"]), func(path: String) -> void:
		var error := StudioProjectIO.import_audio(path, document)
		if not error.is_empty(): _message(error); return
		audio.set_stream(document.song.audio_stream); audio.build_waveform(path); _message("音乐已导入，正在生成波形…"))

func _export() -> void:
	_finish_recording(true)
	var dialog := ConfirmationDialog.new(); dialog.title = "导出谱面 · 选择难度（ZIP）"
	dialog.ok_button_text = "选择保存位置"
	dialog.cancel_button_text = "取消"
	var list := ItemList.new(); list.select_mode = ItemList.SELECT_MULTI; list.custom_minimum_size = Vector2(320, 220)
	for chart in document.charts: list.add_item(chart.difficulty_id)
	list.select(document.current)
	dialog.add_child(list); add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var selected := list.get_selected_items()
		if selected.is_empty(): _message("至少选择一个难度"); return
		_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, PackedStringArray(["*.zip ; 可玩谱面包"]), func(path: String) -> void:
			var error := StudioProjectIO.export_zip(document, path, selected)
			_message(error if not error.is_empty() else "谱面已导出", path)))
	dialog.popup_centered()

func _legacy() -> void:
	_confirm_discard(func() -> void:
		_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.tres ; 旧关卡入口（.tres）"]), func(path: String) -> void:
			_file_dialog(FileDialog.FILE_MODE_OPEN_DIR, PackedStringArray(), func(target: String) -> void:
				var error := StudioProjectIO.import_legacy(path, target, document)
				if not error.is_empty(): _message(error); return
				_open_path(target.path_join("song.json"))
				_message("旧谱已导入，未支持的内容已归档。", target.path_join("legacy/import-report.json")))))

func _save_workspace() -> void:
	StudioProjectIO.write_json(document.directory.path_join("editor/workspace.json"), _capture_workspace())

func _capture_workspace() -> Dictionary:
	return {"version": 1, "layout": _capture_layout(), "current": document.current, "position": audio.position, "view_start": timeline.view_start, "zoom": timeline.pixels_per_second, "loop_start": audio.loop_start, "loop_end": audio.loop_end, "loop_enabled": audio.loop_enabled, "rate": audio.rate, "snap_index": get_node("%Snap").selected, "track_layout_version": 2, "track_height": timeline.row_height, "track_folded": timeline.folded.duplicate(), "track_scroll": timeline.track_scroll}

func _workspace_data() -> Dictionary:
	var path := document.directory.path_join("editor/workspace.json")
	if not FileAccess.file_exists(path): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _load_workspace() -> void:
	_apply_workspace(_workspace_data())
	document.change_kind = &"project"; document.changed.emit()

func _apply_workspace(data: Dictionary) -> void:
	if data.has("layout"): _restore_layout(data.layout)
	document.current = clampi(int(data.get("current", 0)), 0, document.charts.size() - 1)
	timeline.row_height = float(data.get("track_height", 48))
	# 旧版折叠代表隐藏音符；首次升级统一进入可编辑紧凑视图，之后保留用户的展开选择。
	timeline.folded.fill(true)
	if int(data.get("track_layout_version", 1)) >= 2 and data.get("track_folded", []).size() == 5: timeline.folded.assign(data.track_folded)
	timeline.track_scroll = float(data.get("track_scroll", 0)); timeline._update_track_scroll()
	timeline.view_start = float(data.get("view_start", -2))
	timeline.pixels_per_second = float(data.get("zoom", 160))
	audio.loop_start = float(data.get("loop_start", 0)); audio.loop_end = float(data.get("loop_end", 4))
	audio.loop_enabled = bool(data.get("loop_enabled", false))
	var rate: float = data.get("rate", 1.0)
	audio.set_rate(rate if rate in [0.5, 0.75, 1.0, 1.25, 1.5] else 1.0)
	get_node("%Snap").select(clampi(int(data.get("snap_index", 2)), 0, 7)); _sync_snap_hint()
	audio.seek(float(data.get("position", 0)))

func _activate_project(state: Dictionary) -> void:
	if rhythm != null: rhythm.reset_analysis()
	_finish_recording(true); _finish_color()
	preview.clear_preview(); audio.set_playing(false)
	timeline.selected.clear(); timeline.candidates.clear()
	timeline.set_waveform(PackedVector2Array(), 0); audio.build_waveform("")
	audio.set_stream(document.song.audio_stream); _apply_workspace(state)
	document.change_kind = &"project"; document.changed.emit()
	var relative := str(ChartJsonCodec.encode_song(document.song).get("audio", ""))
	if not relative.is_empty(): audio.build_waveform(document.directory.path_join(relative))
	_update_scroll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		_application_focused = false
		_finish_recording(true)
		timeline.cancel_gesture()
		_input_starts.clear()
		_sync_trial_background()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready():
		_application_focused = true
		_sync_trial_background()
		# 独立游戏可能切换全屏或最小化工具；重新取得焦点时刷新静态轨道和播放头。
		timeline.queue_redraw()
		timeline._redraw_overlay()

func _write_recovery() -> void:
	if not _recovery_ready or (not document.dirty and not recorder.active): return
	var data := {"song": ChartJsonCodec.encode_song(document.song), "charts": [], "source": document.directory, "saved_at": Time.get_datetime_string_from_system(), "workspace": _capture_workspace()}
	for chart in document.charts: data.charts.append(ChartJsonCodec.encode_chart(chart))
	if recorder.active:
		var temp := SongChart.new(); temp.note_events.assign(recorder.notes)
		data.charts[document.current].notes.append_array(ChartJsonCodec.encode_chart(temp).notes)
	StudioProjectIO.write_json(recovery_path, data)

func _offer_recovery() -> void:
	_recovery_ready = true
	if not offer_recovery_on_start: return
	var path := recovery_path
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return
	var dialog := ConfirmationDialog.new()
	var summary := ""
	for chart: Dictionary in data.charts:
		summary += "\n%s：%d 个 Tap/Hold，%d 条 Tuning，%d 批 Ghost" % [chart.get("difficulty_id", ""), chart.get("notes", []).size(), chart.get("tuning_paths", []).size(), chart.get("ghost_events", []).size()]
	dialog.dialog_text = "恢复 %s\n%s%s\n恢复后可另存为新项目。" % [data.song.get("title", ""), data.get("saved_at", "旧版恢复稿"), summary]
	dialog.ok_button_text = "恢复稿件"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void: _restore_recovery(data))
	dialog.popup_centered()

func _confirm_discard(callback: Callable) -> void:
	_finish_recording(true); _finish_color()
	if not document.dirty: callback.call(); return
	var dialog := ConfirmationDialog.new(); dialog.dialog_text = "当前项目有未保存的修改。请选择保存修改或放弃修改后继续。"; dialog.ok_button_text = "放弃并继续"
	dialog.add_button("保存并继续", true, "save")
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"save": dialog.hide(); _save_then(callback))
	dialog.title = "未保存的修改"; dialog.cancel_button_text = "取消"
	add_child(dialog); dialog.confirmed.connect(callback); dialog.popup_centered()

func _save_then(callback: Callable) -> void:
	var save_at := func(path: String) -> void:
		var error := StudioProjectIO.save_project(document, path)
		if not error.is_empty(): _message(error); return
		_save_workspace(); DirAccess.remove_absolute(recovery_path)
		_update_window_title()
		callback.call()
	if document.directory.is_empty(): _file_dialog(FileDialog.FILE_MODE_OPEN_DIR, PackedStringArray(), save_at)
	else: save_at.call(document.directory)

func _close() -> void:
	_finish_text_edit()
	_confirm_discard(func() -> void:
		if not document.directory.is_empty(): _save_workspace()
		DirAccess.remove_absolute(recovery_path)
		get_tree().quit())

func _help() -> void:
	_finish_recording(true)
	var dialog := AcceptDialog.new()
	dialog.title = "写谱器帮助"
	dialog.ok_button_text = "关闭"
	var help_text := "编辑\n点击空白处：Tap；沿时间拖动：Hold\nShift：框选或增减选择；Esc：取消当前操作\nF／J：暂停时输入生钟／死钟音符，按住并用方向键延长\n滚轮／双指纵滑：上下浏览轨道；双指横滑／中键拖动：左右浏览\nCtrl+上下滚轮：缩放；Alt：临时关闭吸附\nCtrl+C／V／D：复制／粘贴／重复乐句；Ctrl+M：生死互换\nQ：量化起始位置，保留时长；Shift+Q：量化起止位置\n\n播放\n空格：播放／暂停；Home：返回音乐开头\nI：将当前位置设为循环起点；O：设为循环终点\nL：开启／关闭循环播放\n音符提示音：起手敲钟；游戏反馈：持续音和判定声\nR：开启／关闭实时录入，再播放并按 F／J\n短按为 Tap，按住超过 150 ms 为 Hold；跟随吸附\n暂停结束本段录制，整段可一步撤销；阈值可在试听设置调整\n拖动标尺或波形定位；拖动循环把手调整范围\n\n音乐对齐\n首拍偏移：有效 tick 0 的音频毫秒位置，正值表示更晚\n可选当前位置／波形右键设首拍，或拖动金色首拍把手\n开启「移动波形」后拖波形对齐，谱面网格固定；Shift 精细拖动\n调整时暂停试听；Esc 或失焦取消，松手一次提交，可撤销\n默认只改当前难度；「同步至全部难度」可一次撤销\n视图菜单：界面缩放、显示整曲／选区；跟随按钮恢复自动跟随\n\n文件\nCtrl+N／O：新建／打开；Ctrl+S：保存；Ctrl+Shift+S：另存为\nCtrl+Z：撤销；Ctrl+Shift+Z 或 Ctrl+Y：重做\n属性按 Enter 或离开输入框时提交，保存也会提交当前输入。"
	help_text += "\n\n真人试玩\n“在游戏中试玩”使用当前难度的未保存版本，从音乐开头开始，不保存原项目。\n试玩时可继续编辑；关闭游戏窗口后可再次启动，使用新的编辑版本。\n视图 → 试玩设置可选择配套游戏。游戏选关 → 本地谱面可导入 ZIP。"
	help_text += "\n\nTuning / Ghost\n五轨依次为生钟 Tap/Hold、死钟 Tap/Hold、生钟 Tuning、死钟 Tuning、Ghost\nTuning：在绿色双 Hold 重合窗口拖画，拖身体移动，拖端点改范围\n选中后在角度路径中拖圆周把手，Shift 微调；节点时间、角度可精确输入\n双击已选路径可添加转折点；首尾以外的节点可以删除\n右上方向为 0°，顺时针为正；相邻节点沿短弧移动\nGhost：在 Tuning 窗口点击创建，时间表示命中时刻；属性可调整同刻数量\n右键「选择关联内容」可整组操作；父对象缩短、删除会提示受影响内容\n右键「BOSS 发出」标记 Tap/Hold/Ghost 来源，不改变当前游戏行为\n默认紧凑轨道也可放置和编辑音符；点击标题展开或折叠\n滚轮或双指纵滑上下浏览轨道；视图菜单可批量折叠和调整行高\n当前规则将多节点 Tuning 分段预览；Ghost 随机抽取真实交点；理想调频预测和独立计分等待后续接入"
	# 帮助随功能增长可滚动，最小窗口下仍能关闭和阅读全部操作。
	help_text += "\n\n自动节奏识别\n音乐对齐 → 分析节奏／生成草稿，按分析、试听修正、应用、生成依次操作\n蓝色为原始拍点，紫色为检测重拍，绿色为修正网格\n拖动绿色标记整体对齐；右键可设为小节第一拍\n候选节拍器使用同一播放控制；输入框外空格可播放／暂停\n拍号需确认时请选择 3/4 或 4/4；偏差提示不是识别准确率\n应用只改当前难度的时间映射，已有音符保留 tick，可一步撤销\n草稿按正式网格生成；重复或冲突跳过，确认后可整批撤销\n草稿不超过谱面结束位置，生成前检查范围和数量"
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(660, 480)
	dialog.add_child(scroll)
	var text := Label.new(); text.text = help_text
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	dialog.canceled.connect(dialog.queue_free); dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog); dialog.popup_centered(Vector2i(700, 600))

func _input(event: InputEvent) -> void:
	# 专用试玩期间手柄属于游戏；也覆盖启动/退出的焦点交接和已经排队的事件。
	# 谱师切回本窗口仍可用鼠标、键盘继续编辑，不能停掉整个工作区。
	if playtest.busy and (event is InputEventJoypadMotion or event is InputEventJoypadButton):
		accept_event()
		return
	if not event is InputEventKey: return
	if timeline.is_aligning():
		if event.pressed and event.keycode == KEY_ESCAPE: timeline.cancel_gesture()
		# 对齐期间只接收修饰键；不让空格或 F/J 创建新的播放、录入状态。
		if event.keycode != KEY_SHIFT: accept_event()
		return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:
		if event.pressed and event.ctrl_pressed and event.keycode == KEY_S:
			_finish_text_edit(); _save(); accept_event()
		return
	for child in get_children():
		if child is Window and child.visible: return
	var key := event as InputEventKey
	if key.echo: return
	if key.keycode in [KEY_F, KEY_J] and audio.playing:
		if record_armed:
			if not recorder.active: recorder.begin(timeline._map, timeline.snap_ticks)
			var side := 0 if key.keycode == KEY_F else 1
			var at := audio.sample_position()
			if key.pressed: recorder.press(side, at, Time.get_ticks_usec())
			else: recorder.release(side, at, Time.get_ticks_usec()); _autosave.start()
		accept_event(); return
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
				for note in ChartEditEvents.all(document.chart()): timeline.selected.append(note.event_id)
				timeline.queue_redraw(); _inspect()
			_: return
	else:
		match key.keycode:
			KEY_SPACE: _toggle_play()
			KEY_R: _record_button.button_pressed = not _record_button.button_pressed
			KEY_ESCAPE: timeline.cancel_gesture(); _input_starts.clear()
			KEY_DELETE, KEY_BACKSPACE: _edit_action(0)
			KEY_Q: _edit_action(7 if key.shift_pressed else 6)
			KEY_I: audio.loop_start = audio.position
			KEY_O: audio.loop_end = audio.position
			KEY_L: audio.loop_enabled = not audio.loop_enabled
			KEY_HOME: _seek(0)
			KEY_END: _seek(float(timeline._map.tick_to_us(document.chart().end_tick)) / 1000000.0)
			KEY_LEFT, KEY_RIGHT: _seek(float(document.tempo_map().tick_to_us(_cursor_tick() + maxi(1, timeline.snap_ticks) * (-1 if key.keycode == KEY_LEFT else 1))) / 1000000.0)
			KEY_PAGEUP, KEY_PAGEDOWN:
				var length := document.chart().ppq * 4
				for meter in document.chart().meter_events:
					if meter.tick <= _cursor_tick(): length = document.chart().ppq * 4 * meter.numerator / meter.denominator
				_seek(float(document.tempo_map().tick_to_us(_cursor_tick() + length * (-1 if key.keycode == KEY_PAGEUP else 1))) / 1000000.0)
			_: return
	accept_event()


func _capture_layout() -> Dictionary:
	return {"vertical": $Layout/Split.split_offset, "left": $Layout/Split/Top.split_offset,
		"right": $Layout/Split/Top/Main.split_offset, "library": $Layout/Split/Top/LibraryScroll.visible,
		"inspector": $Layout/Split/Top/Main/Inspector.visible, "timeline": timeline.visible}

func _restore_layout(layout: Dictionary) -> void:
	$Layout/Split/Top/LibraryScroll.visible = layout.get("library", true)
	$Layout/Split/Top/Main/Inspector.visible = layout.get("inspector", true)
	timeline.visible = layout.get("timeline", true); _scroll.visible = timeline.visible; _alignment_bar.visible = timeline.visible
	# 容器先完成显示/隐藏，再应用拖动位置，避免使用旧的最小尺寸限位。
	_apply_split_offsets.call_deferred(layout)

func _apply_split_offsets(layout: Dictionary) -> void:
	$Layout/Split.split_offset = int(layout.get("vertical", 360))
	$Layout/Split/Top.split_offset = int(layout.get("left", 190))
	$Layout/Split/Top/Main.split_offset = int(layout.get("right", 0))

func _layout_action(id: int) -> void:
	_finish_text_edit()
	match id:
		20: $Layout/Split/Top/LibraryScroll.visible = not $Layout/Split/Top/LibraryScroll.visible
		21: $Layout/Split/Top/Main/Inspector.visible = not $Layout/Split/Top/Main/Inspector.visible
		22: timeline.visible = not timeline.visible; _scroll.visible = timeline.visible; _alignment_bar.visible = timeline.visible
		23:
			if _layout_before_focus.is_empty():
				_layout_before_focus = _capture_layout()
				_restore_layout({"library": false, "inspector": false, "timeline": false, "vertical": 100000})
			else:
				_restore_layout(_layout_before_focus); _layout_before_focus = {}
		24:
			_layout_before_focus = {}; _restore_layout({})
	_sync_layout_menu()

func _sync_layout_menu() -> void:
	var menu := _view_menu.get_popup()
	var states := [$Layout/Split/Top/LibraryScroll.visible, $Layout/Split/Top/Main/Inspector.visible, timeline.visible, not _layout_before_focus.is_empty()]
	for i in states.size(): menu.set_item_checked(menu.get_item_index(20 + i), states[i])

func _playtest() -> void:
	_finish_text_edit()
	_finish_recording(true)
	timeline.cancel_gesture()
	_input_starts.clear()
	audio.set_playing(false)
	var issues := ChartProjectLoader.check_chart(document.chart())
	if not issues.is_empty():
		_message(ChartProjectLoader.describe_issues(issues))
		var issue: Dictionary = issues[0]
		if issue.has("tick"): _seek(float(document.tempo_map().tick_to_us(int(issue.tick))) / 1000000.0)
		return
	playtest.start(document)

func _choose_trial_game() -> void:
	var dialog := FileDialog.new()
	dialog.title = "试玩设置：选择配套游戏 minghe.exe"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.exe ; Windows 游戏"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String): playtest.choose_executable(path); dialog.queue_free())
	dialog.canceled.connect(func(): playtest.cancel_selection(); dialog.queue_free())
	dialog.popup_centered_ratio(0.7)
