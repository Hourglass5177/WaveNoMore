## 写谱器总控制器：组装文档、历史、时间线、属性、校验、保存、波形和正式运行时预览。
@tool
class_name MingheChartEditorWorkspace
extends Control

## 工具栏显示名与内部创建类型的对应表；时间线只接收右侧的稳定类型字符串。
const PALETTE_ITEMS := [
	["朱 Tap", "tap_zhu"],
	["玄 Tap", "tap_xuan"],
	["普通双押", "chord"],
	["朱 Hold", "hold_zhu"],
	["玄 Hold", "hold_xuan"],
	["调频场", "tuning_field"],
	["朱调频滑条", "slider_zhu"],
	["玄调频滑条", "slider_xuan"],
	["生死双滑条", "slider_pair"],
	["素音凝现", "su_manifestation"],
	["双钟疾振", "rapid"],
	["StageShow cue", "show"],
]

## 当前内存文档。所有编辑入口最终都通过它修改 SongChart 或 StageShow。
var document := MingheChartEditorDocument.new()
## 最多保留 200 次操作的 Undo/Redo 历史，由 Workspace 在手势结束时写入。
var history := MingheChartEditorHistory.new()
## 在谱面 tick 与音频秒数之间换算，并负责吸附到网格。
var tempo_map := MingheEditorTempoMap.new()
## 把正式校验器输出整理成右侧问题列表可用的统一结构。
var validation_adapter := MingheChartValidationAdapter.new()
## 负责正式保存、恢复稿、备份和中断事务恢复；可在测试中替换存储路径。
var save_service := MingheChartEditorSaveService.new()
## 用当前未保存文档创建正式 StageRoot 预览的桥接器。
var preview_bridge := MingheChartPreviewBridge.new()

## 八轨时间线节点；由 `_build_ui()` 创建，之后负责绘制事件并发送手势信号。
var _timeline: MingheChartTimelineView
## 右侧精确字段编辑节点；只发送请求，不直接修改 Resource。
var _property_panel: MingheChartPropertyPanel
## 右侧校验问题列表；条目元数据保存可定位的 event_id。
var _validation_list: ItemList
## 顶部操作结果文本，错误时切换为警示颜色。
var _status_label: Label
## 当前音频秒数与对应 tick 的只读显示。
var _time_label: Label
## 「已保存/未保存」提示，由内容签名比较结果刷新。
var _dirty_label: Label
## Undo 按钮；可用状态和文字随 `history_changed` 更新。
var _undo_button: Button
## Redo 按钮；指向历史游标之后的下一项操作。
var _redo_button: Button
## 当前放置工具下拉框，选项数据来自 `PALETTE_ITEMS`。
var _palette: OptionButton
## 网格吸附精度下拉框，值的单位是谱面 tick。
var _snap: OptionButton
## BGM 预览倍速下拉框，最终写入 `AudioStreamPlayer.pitch_scale`。
var _speed: OptionButton
## 是否启用 A/B 循环的复选框。
var _loop_toggle: CheckButton
## BGM 播放器是预览的主时钟来源，播放头不会自行按帧累计时间。
var _audio_player: AudioStreamPlayer
## 选择 `stage_definition.tres` 的打开对话框。
var _open_dialog: FileDialog
## 选择制谱用 PCM16 WAV 的文件对话框。
var _wave_dialog: FileDialog
## 新文档首次保存时选择六文件关卡包目录的对话框。
var _save_directory_dialog: FileDialog
## 周期性触发恢复稿写入，不直接覆盖正式资源。
var _autosave_timer: Timer

## 当前选中事件的稳定 ID；事件删除或 Undo 后会过滤失效 ID。
var _selected_ids: PackedStringArray = PackedStringArray()
## 拖动开始前的 Chart/Show 深拷贝；空字典表示当前没有进行中的手势。
var _gesture_before: Dictionary = {}
## 内部剪贴板，每项保存轨道名和事件深拷贝，不使用系统剪贴板。
var _clipboard: Array[Dictionary] = []
## 剪贴板事件中最早的 tick；粘贴时把它作为整体时间原点。
var _clipboard_min_tick: int = 0
## A/B 循环起点，单位为从音频文件开头计算的秒数。
var _loop_start_sec: float = 0.0
## A/B 循环终点，单位为音频秒；始终至少比起点晚 0.05 秒。
var _loop_end_sec: float = 4.0
## 上次成功写恢复稿时的内容 SHA-256；相同则跳过重复写盘。
var _last_autosave_signature: String = ""
## 最近一次校验的标准化问题数组，同时供列表显示和正式保存门禁读取。
var _validation_issues: Array[Dictionary] = []
## `_build_ui()` 执行期间为 true，防止控件初始化信号被当作用户操作。
var _building_ui := false
## 手势每帧套用预览快照期间为 true，防止 `document.changed` 触发完整重绑。
var _suspend_document_refresh := false
## 当前 WAV 解析工作线程；只读文件和建缓存，绝不能在其中操作节点。
var _waveform_thread: Thread
## 当前线程对应的 WAV 路径；空字符串表示没有待完成的波形任务。
var _pending_waveform_path: String = ""


func _ready() -> void:
	# UI 在代码中构造，使 EditorPlugin 与独立运行场景共用完全相同的工作区。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_model()
	document.create_empty()
	_refresh_document("ready")
	var recovery_result := save_service.recover_interrupted_save()
	if not recovery_result.get("ok", true):
		_set_status(String(recovery_result.get("message", "恢复检查失败")), true)


func _exit_tree() -> void:
	if _waveform_thread != null and _waveform_thread.is_started():
		_waveform_thread.wait_to_finish()
		_waveform_thread = null


func set_shared_services(tempo: Object = null, validator: Object = null, compiler: Object = null) -> void:
	tempo_map.configure(document.chart, tempo)
	validation_adapter.set_shared_validator(validator)
	preview_bridge.set_shared_services(compiler, validator)
	_timeline.bind(document, tempo_map)


func set_runtime_preview_factory(factory: Callable) -> void:
	preview_bridge.set_runtime_factory(factory)


func has_unsaved_changes() -> bool:
	return document.is_dirty()


func save_document() -> bool:
	# 正式保存前先阻断结构错误；无路径的新文档改走六文件关卡包流程。
	_run_validation()
	for issue in _validation_issues:
		if String(issue.get("severity", "")).to_lower() == "error":
			_set_status("存在阻断错误，未保存正式谱面", true)
			return false
	if document.chart_path.is_empty() or document.show_path.is_empty():
		_save_directory_dialog.popup_centered_ratio(0.62)
		return false
	var result := save_service.save_document(document)
	_set_status(String(result.get("message", "保存结束")), not bool(result.get("ok", false)))
	_refresh_dirty_state()
	return bool(result.get("ok", false))


func write_recovery() -> void:
	if document.is_dirty():
		save_service.autosave(document)


func open_stage_path(path: String) -> bool:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null or not _looks_like_stage_definition(resource):
		_set_status("所选资源不是 StageDefinition：%s" % path, true)
		return false
	if not document.open_stage(resource, path):
		_set_status("关卡依赖加载失败：%s" % path, true)
		return false
	history.clear()
	_selected_ids.clear()
	_load_song_audio()
	_refresh_document("open_stage")
	_set_status("已打开：%s" % path)
	return true


func _build_ui() -> void:
	_building_ui = true
	var root := VBoxContainer.new()
	root.name = "WorkspaceLayout"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var toolbar_scroll := ScrollContainer.new()
	toolbar_scroll.custom_minimum_size.y = 48.0
	toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(toolbar_scroll)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 5)
	toolbar_scroll.add_child(toolbar)
	_add_toolbar_button(toolbar, "新建", _new_document)
	_add_toolbar_button(toolbar, "打开关卡", func() -> void: _open_dialog.popup_centered_ratio(0.72))
	_add_toolbar_button(toolbar, "保存", save_document)
	_add_toolbar_button(toolbar, "加载 WAV", func() -> void: _wave_dialog.popup_centered_ratio(0.72))
	toolbar.add_child(VSeparator.new())
	_undo_button = _add_toolbar_button(toolbar, "撤销", _undo)
	_redo_button = _add_toolbar_button(toolbar, "重做", _redo)
	toolbar.add_child(VSeparator.new())
	_add_toolbar_button(toolbar, "▶", _toggle_play)
	_add_toolbar_button(toolbar, "■", _stop_audio)
	_loop_toggle = CheckButton.new()
	_loop_toggle.text = "循环"
	toolbar.add_child(_loop_toggle)
	_add_toolbar_button(toolbar, "设 I", func() -> void: _loop_start_sec = _current_audio_time())
	_add_toolbar_button(toolbar, "设 O", func() -> void: _loop_end_sec = maxf(_loop_start_sec + 0.05, _current_audio_time()))
	_speed = OptionButton.new()
	for item in [["0.5×", 0.5], ["0.75×", 0.75], ["1.0×", 1.0]]:
		_speed.add_item(item[0])
		_speed.set_item_metadata(_speed.item_count - 1, item[1])
	_speed.select(2)
	_speed.item_selected.connect(_on_speed_selected)
	toolbar.add_child(_speed)
	toolbar.add_child(VSeparator.new())
	_palette = OptionButton.new()
	for item in PALETTE_ITEMS:
		_palette.add_item(item[0])
		_palette.set_item_metadata(_palette.item_count - 1, item[1])
	_palette.item_selected.connect(_on_palette_selected)
	toolbar.add_child(_palette)
	_snap = OptionButton.new()
	for item in [["1/4", 480], ["1/8", 240], ["1/16", 120], ["1/24", 80], ["1/32", 60], ["自由", 1]]:
		_snap.add_item(item[0])
		_snap.set_item_metadata(_snap.item_count - 1, item[1])
	_snap.select(2)
	_snap.item_selected.connect(_on_snap_selected)
	toolbar.add_child(_snap)
	_add_toolbar_button(toolbar, "校验", _run_validation)
	_add_toolbar_button(toolbar, "正式预览", _open_runtime_preview)
	_time_label = Label.new()
	_time_label.custom_minimum_size.x = 180.0
	toolbar.add_child(_time_label)
	_dirty_label = Label.new()
	_dirty_label.custom_minimum_size.x = 96.0
	toolbar.add_child(_dirty_label)

	var main_split := HSplitContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 152
	root.add_child(main_split)
	main_split.add_child(_build_track_tree())

	var center_split := VSplitContainer.new()
	center_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_split.split_offset = 520
	main_split.add_child(center_split)
	_timeline = MingheChartTimelineView.new()
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_split.add_child(_timeline)
	_validation_list = ItemList.new()
	_validation_list.custom_minimum_size.y = 140.0
	_validation_list.item_clicked.connect(_on_validation_item_clicked)
	center_split.add_child(_validation_list)
	_property_panel = MingheChartPropertyPanel.new()
	main_split.add_child(_property_panel)

	var status_panel := PanelContainer.new()
	status_panel.custom_minimum_size.y = 28.0
	root.add_child(status_panel)
	_status_label = Label.new()
	_status_label.text = "就绪"
	_status_label.add_theme_constant_override("outline_size", 2)
	status_panel.add_child(_status_label)

	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = &"Music"
	add_child(_audio_player)
	_open_dialog = _make_file_dialog("打开 StageDefinition", FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.tres ; Godot Resource"]))
	_open_dialog.file_selected.connect(open_stage_path)
	_wave_dialog = _make_file_dialog("选择 16-bit PCM WAV", FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.wav ; PCM WAV"]))
	_wave_dialog.file_selected.connect(_load_waveform)
	_save_directory_dialog = _make_file_dialog("选择谱面保存目录", FileDialog.FILE_MODE_OPEN_DIR, PackedStringArray())
	_save_directory_dialog.dir_selected.connect(_save_to_directory)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 30.0
	_autosave_timer.one_shot = false
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_autosave_if_needed)
	add_child(_autosave_timer)
	_building_ui = false


func _build_track_tree() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 150.0
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "轨道"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	for label_text in ["Timing / 波形", "朱音", "玄音", "调频场", "朱滑条", "玄滑条", "素音", "疾振", "StageShow"]:
		var row := HBoxContainer.new()
		var lock := CheckButton.new()
		lock.text = "◉"
		lock.tooltip_text = "显示/锁定占位；MVP 中不影响正式数据"
		lock.button_pressed = true
		row.add_child(lock)
		var label := Label.new()
		label.text = label_text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		box.add_child(row)
	box.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = "左键空白：放置\n拖动：移动\n拖尾：拉伸\nShift：多选/框选\nAlt：临时关闭 Snap\nCtrl+滚轮：缩放"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.69, 0.71, 0.75)
	box.add_child(hint)
	return panel


func _connect_model() -> void:
	# 时间线和属性面板只发送“想做什么”；Workspace 统一改文档、保存 Undo 快照并重新校验。
	# 因此子控件不直接写 Resource，也不会各自产生互不兼容的编辑历史。
	document.changed.connect(_refresh_document)
	history.history_changed.connect(_on_history_changed)
	_timeline.create_requested.connect(_create_event)
	_timeline.selection_changed.connect(_on_selection_changed)
	_timeline.gesture_started.connect(_on_gesture_started)
	_timeline.gesture_preview.connect(_on_gesture_preview)
	_timeline.gesture_committed.connect(_on_gesture_committed)
	_timeline.seek_requested.connect(_seek_audio)
	_timeline.view_changed.connect(func(_start: float, _zoom: float) -> void: pass)
	_property_panel.property_change_requested.connect(_change_property)
	preview_bridge.preview_unavailable.connect(func(reason: String) -> void: _set_status(reason, true))


func _refresh_document(_reason: String = "") -> void:
	if _suspend_document_refresh:
		return
	if document.chart == null:
		return
	tempo_map.configure(document.chart, tempo_map.shared_tempo_map)
	_timeline.bind(document, tempo_map)
	_timeline.first_beat_offset_sec = float(document.song_definition.get("first_beat_offset_sec")) if document.song_definition != null else 0.0
	_timeline.set_selected(_selected_ids)
	_refresh_property_panel()
	if _reason != "gesture_preview":
		_refresh_dirty_state()


func _refresh_dirty_state() -> void:
	if _dirty_label == null:
		return
	_dirty_label.text = "● 未保存" if document.is_dirty() else "已保存"
	_dirty_label.modulate = Color("e2a45f") if document.is_dirty() else Color(0.58, 0.72, 0.61)


func _process(_delta: float) -> void:
	_poll_waveform_thread()
	if _audio_player == null:
		return
	if not is_visible_in_tree():
		return
	# 音频播放位置是预览的主时钟；播放头只跟随它，不能用帧 delta 自己累加时间。
	var seconds := _current_audio_time()
	if _loop_toggle != null and _loop_toggle.button_pressed and _audio_player.playing and seconds >= _loop_end_sec:
		_audio_player.seek(_loop_start_sec)
		seconds = _loop_start_sec
	if _timeline != null:
		_timeline.set_playhead(seconds)
	if _time_label != null and tempo_map != null:
		var tick := tempo_map.seconds_to_tick(seconds - _timeline.first_beat_offset_sec)
		_time_label.text = "%7.3f s  ·  tick %d" % [seconds, tick]


func _shortcut_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.ctrl_pressed and key.keycode == KEY_S:
		save_document()
		accept_event()
	elif key.ctrl_pressed and key.shift_pressed and key.keycode == KEY_Z:
		_redo()
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_Z:
		_undo()
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_C:
		_copy_selected()
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_V:
		_paste_clipboard()
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_D:
		_duplicate_selected()
		accept_event()
	elif key.keycode == KEY_DELETE:
		_delete_selected()
		accept_event()
	elif key.keycode == KEY_SPACE and not _line_edit_has_focus():
		_toggle_play()
		accept_event()
	elif key.keycode == KEY_I:
		_loop_start_sec = _current_audio_time()
	elif key.keycode == KEY_O:
		_loop_end_sec = maxf(_loop_start_sec + 0.05, _current_audio_time())
	elif key.keycode == KEY_F and not _selected_ids.is_empty():
		_timeline.focus_event(_selected_ids[0])


func _new_document() -> void:
	write_recovery()
	_stop_audio()
	document.create_empty()
	history.clear()
	_selected_ids.clear()
	_timeline.set_waveform(null)
	_set_status("已新建空白谱面；保存时选择关卡目录")


func _create_event(kind: String, tick: int, row: int) -> void:
	# 一次用户操作只生成一条历史记录；双押虽含两个 NoteEvent，仍作为一个编辑动作处理。
	var before := document.snapshot()
	var created_ids := PackedStringArray()
	match kind:
		"tap_zhu", "tap_xuan", "hold_zhu", "hold_xuan":
			var note := NoteEvent.new()
			note.event_id = document.next_id("note")
			note.tick = tick
			note.affinity = GameplayTypes.Affinity.XUAN if kind.ends_with("xuan") or row == 1 else GameplayTypes.Affinity.ZHU
			note.kind = GameplayTypes.NoteKind.HOLD if kind.begins_with("hold") else GameplayTypes.NoteKind.TAP
			note.duration_ticks = tempo_map.ppq() if note.kind == GameplayTypes.NoteKind.HOLD else 0
			note.damage_group_id = note.event_id
			document.add_event(MingheChartEditorDocument.TRACK_NOTES, note)
			created_ids.append(note.event_id)
		"chord":
			var group_id := document.next_id("chord")
			for affinity in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
				var note := NoteEvent.new()
				note.event_id = document.next_id("note")
				note.group_id = group_id
				note.damage_group_id = group_id
				note.tick = tick
				note.affinity = affinity
				document.add_event(MingheChartEditorDocument.TRACK_NOTES, note)
				created_ids.append(note.event_id)
		"tuning_field":
			var field := TuningFieldRegion.new()
			field.event_id = document.next_id("field")
			field.tick = tick
			field.duration_ticks = tempo_map.ppq() * 4
			document.add_event(MingheChartEditorDocument.TRACK_TUNING_FIELDS, field)
			created_ids.append(field.event_id)
		"slider_zhu", "slider_xuan", "slider_pair":
			var field_id := _tuning_field_at(tick)
			var group_id := document.next_id("tuning_group") if kind == "slider_pair" else ""
			var affinities := [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN] if kind == "slider_pair" else [GameplayTypes.Affinity.XUAN if kind == "slider_xuan" else GameplayTypes.Affinity.ZHU]
			for affinity in affinities:
				var slider := TuningSliderEvent.new()
				slider.event_id = document.next_id("slider")
				slider.field_id = field_id
				slider.group_id = group_id
				slider.affinity = affinity
				slider.tick = tick
				slider.traversal_ticks = tempo_map.ppq() * 2
				slider.traversal_count = 1
				slider.start_value = _base_tuning_value()
				# 普通滑条默认跨度为 2 Hz：对应 320 px 弦长，手势角由等效圆统一推导。
				slider.end_value = clampf(slider.start_value + _normalized_frequency_span(2.0), 0.0, 1.0)
				document.add_event(MingheChartEditorDocument.TRACK_TUNING_SLIDERS, slider)
				created_ids.append(slider.event_id)
		"su_manifestation":
			var manifestation := SuManifestationEvent.new()
			manifestation.event_id = document.next_id("su")
			manifestation.group_id = _paired_slider_group_before(tick)
			manifestation.tick = tick
			document.add_event(MingheChartEditorDocument.TRACK_SU_MANIFESTATIONS, manifestation)
			created_ids.append(manifestation.event_id)
		"rapid":
			var rapid := RapidRegion.new()
			rapid.event_id = document.next_id("rapid")
			rapid.damage_group_id = rapid.event_id
			rapid.tick = tick
			rapid.duration_ticks = tempo_map.ppq()
			document.add_event(MingheChartEditorDocument.TRACK_RAPID, rapid)
			created_ids.append(rapid.event_id)
		"show":
			var cue := ShowCue.new()
			cue.event_id = document.next_id("cue")
			cue.tick = tick
			cue.cue_id = &"new_cue"
			document.add_event(MingheChartEditorDocument.TRACK_SHOW, cue)
			created_ids.append(cue.event_id)
		_:
			return
	var after := document.snapshot()
	history.push("新增 %s" % kind, before, after)
	_on_selection_changed(created_ids)
	_run_validation()


func _on_selection_changed(ids: PackedStringArray) -> void:
	_selected_ids = ids.duplicate()
	_timeline.set_selected(_selected_ids)
	_refresh_property_panel()


func _refresh_property_panel() -> void:
	if _property_panel == null:
		return
	if _selected_ids.size() != 1:
		_property_panel.show_empty("已选择 %d 个事件" % _selected_ids.size() if not _selected_ids.is_empty() else "选择一个事件以编辑属性")
		return
	var event := document.find_event(_selected_ids[0])
	_property_panel.edit_event(event, document.find_track(_selected_ids[0]))


func _on_gesture_started(_label: String) -> void:
	_gesture_before = document.snapshot()


func _on_gesture_preview(ids: PackedStringArray, delta_ticks: int, resize_delta_ticks: int, mode: String) -> void:
	# 每帧都从拖动前快照重算，避免鼠标增量累计误差；松手时才写入 Undo 历史。
	if _gesture_before.is_empty():
		return
	_suspend_document_refresh = true
	document.replace_working_copy(_gesture_before.chart, _gesture_before.stage_show, "gesture_preview_reset")
	for event_id in ids:
		var event := document.find_event(event_id)
		if event == null:
			continue
		if mode == "resize":
			var current_duration := _event_duration(event)
			var next_duration := maxi(1, current_duration + resize_delta_ticks)
			_set_event_duration(event, next_duration)
		else:
			event.set("tick", int(event.get("tick")) + delta_ticks)
	document.notify_mutated("gesture_preview")
	_suspend_document_refresh = false
	_refresh_document("gesture_preview")
	_selected_ids = ids.duplicate()
	_timeline.set_selected(_selected_ids)


func _on_gesture_committed() -> void:
	if _gesture_before.is_empty():
		return
	var after := document.snapshot()
	history.push("调整时间线事件", _gesture_before, after)
	_gesture_before = {}
	_refresh_dirty_state()
	_run_validation()


func _change_property(event_id: String, property_name: StringName, value: Variant) -> void:
	var event := document.find_event(event_id)
	if event == null or event.get(property_name) == value:
		return
	var before := document.snapshot()
	event.set(property_name, value)
	document.notify_mutated("property")
	var after := document.snapshot()
	history.push("修改 %s" % String(property_name), before, after)
	_on_selection_changed(PackedStringArray([event_id]))


func _delete_selected() -> void:
	if _selected_ids.is_empty():
		return
	var before := document.snapshot()
	document.remove_events(_selected_ids)
	history.push("删除事件", before, document.snapshot())
	_on_selection_changed(PackedStringArray())
	_run_validation()


func _copy_selected() -> void:
	# 复制时保留事件相对间距；粘贴阶段再统一改写稳定 ID、组 ID 和区域引用。
	_clipboard.clear()
	_clipboard_min_tick = 2147483647
	for event_id in _selected_ids:
		var event := document.find_event(event_id)
		if event == null:
			continue
		_clipboard.append({"track": document.find_track(event_id), "event": event.duplicate(true)})
		_clipboard_min_tick = mini(_clipboard_min_tick, int(event.get("tick")))
	if _clipboard.is_empty():
		_clipboard_min_tick = 0
	_set_status("已复制 %d 个事件" % _clipboard.size())


func _paste_clipboard(tick_override: int = -2147483648) -> void:
	if _clipboard.is_empty():
		return
	var paste_tick := tick_override
	if paste_tick == -2147483648:
		paste_tick = tempo_map.snap_tick(tempo_map.seconds_to_tick(_current_audio_time() - _timeline.first_beat_offset_sec), _timeline.snap_ticks)
	var before := document.snapshot()
	# 第一遍先建立旧 ID 与组 ID 映射，第二遍才能正确重接 field_id 和 group_id。
	var id_map: Dictionary = {}
	var group_map: Dictionary = {}
	for entry in _clipboard:
		var old_event: Resource = entry.event
		id_map[String(old_event.get("event_id"))] = document.next_id("copy")
		for property_name in [&"group_id", &"damage_group_id"]:
			if not _resource_has_property(old_event, property_name):
				continue
			var old_group := String(old_event.get(property_name))
			if not old_group.is_empty() and not group_map.has(old_group):
				group_map[old_group] = document.next_id("group")
	var created := PackedStringArray()
	for entry in _clipboard:
		var copied: Resource = entry.event.duplicate(true)
		var old_id := String(copied.get("event_id"))
		copied.set("event_id", id_map[old_id])
		copied.set("tick", paste_tick + int(copied.get("tick")) - _clipboard_min_tick)
		for property_name in [&"group_id", &"damage_group_id"]:
			if not _resource_has_property(copied, property_name):
				continue
			var old_group := String(copied.get(property_name))
			if group_map.has(old_group):
				copied.set(property_name, group_map[old_group])
		var field_value: Variant = copied.get("field_id") if _resource_has_property(copied, &"field_id") else null
		if field_value != null:
			var old_field := String(field_value)
			if id_map.has(old_field):
				copied.set("field_id", id_map[old_field])
		document.add_event(String(entry.track), copied)
		created.append(String(copied.get("event_id")))
	history.push("粘贴事件", before, document.snapshot())
	_on_selection_changed(created)
	_run_validation()


func _duplicate_selected() -> void:
	_copy_selected()
	_paste_clipboard(_clipboard_min_tick + _timeline.snap_ticks)


func _undo() -> void:
	if history.undo(document):
		_selected_ids = _filter_existing_selection(_selected_ids)
		_refresh_document("undo")


func _redo() -> void:
	if history.redo(document):
		_selected_ids = _filter_existing_selection(_selected_ids)
		_refresh_document("redo")


func _on_history_changed(can_undo: bool, can_redo: bool, undo_label: String, redo_label: String) -> void:
	if _undo_button != null:
		_undo_button.disabled = not can_undo
		_undo_button.tooltip_text = undo_label
	if _redo_button != null:
		_redo_button.disabled = not can_redo
		_redo_button.tooltip_text = redo_label


func _run_validation() -> void:
	_validation_issues = validation_adapter.validate(document)
	_validation_list.clear()
	for issue in _validation_issues:
		var severity := String(issue.get("severity", "info")).to_lower()
		var prefix: String = {"error": "⛔", "warning": "⚠", "info": "·"}.get(severity, "·")
		var index: int = _validation_list.add_item("%s [%s] tick %d · %s" % [prefix, issue.get("code", ""), int(issue.get("tick", 0)), issue.get("message", "")])
		_validation_list.set_item_metadata(index, issue)
	_set_status("校验完成：%d 项" % _validation_issues.size())


func _on_validation_item_clicked(index: int, _position: Vector2, _mouse_button_index: int) -> void:
	var issue: Dictionary = _validation_list.get_item_metadata(index)
	var event_id := String(issue.get("event_id", ""))
	if not event_id.is_empty() and document.find_event(event_id) != null:
		_on_selection_changed(PackedStringArray([event_id]))
		_timeline.focus_event(event_id)


func _open_runtime_preview() -> void:
	# 预览复用正式 StageRoot，目的就是尽早暴露「工具里能播、游戏里不能播」的差异。
	_run_validation()
	for issue in _validation_issues:
		if String(issue.get("severity", "")).to_lower() == "error":
			_set_status("存在校验错误，不能启动正式预览", true)
			return
	var preview_node := preview_bridge.create_preview(document, {"source": "chart_editor", "seek_tick": tempo_map.seconds_to_tick(_current_audio_time())})
	if preview_node == null:
		return
	var preview_window := Window.new()
	preview_window.title = "《冥河，冥河！》Gameplay Preview"
	preview_window.size = Vector2i(1280, 720)
	preview_window.close_requested.connect(preview_window.queue_free)
	add_child(preview_window)
	preview_window.add_child(preview_node)
	if preview_node is Control:
		preview_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_window.popup_centered()


func _toggle_play() -> void:
	if _audio_player.stream == null:
		_load_song_audio()
	if _audio_player.stream == null:
		_set_status("当前 SongDefinition 没有音频", true)
		return
	if _audio_player.playing:
		_audio_player.stream_paused = not _audio_player.stream_paused
	else:
		_audio_player.play(_current_audio_time())


func _seek_audio(seconds: float) -> void:
	var target := maxf(0.0, seconds)
	_timeline.set_playhead(target)
	if _audio_player.stream != null:
		if not _audio_player.playing:
			_audio_player.play(target)
			_audio_player.stream_paused = true
		else:
			_audio_player.seek(target)


func _stop_audio() -> void:
	if _audio_player != null:
		_audio_player.stop()
		_audio_player.stream_paused = false
	if _timeline != null:
		_timeline.set_playhead(0.0)


func _load_song_audio() -> void:
	if document.song_definition == null:
		return
	_audio_player.stream = document.song_definition.get("audio_stream")


func _load_waveform(path: String) -> void:
	# 音频扫描可能读取整首 WAV，放到后台线程以免拖住编辑器界面。
	if _waveform_thread != null and _waveform_thread.is_started():
		_set_status("已有波形任务正在运行，请稍候", true)
		return
	_set_status("正在读取 WAV 波形……")
	_pending_waveform_path = path
	_waveform_thread = Thread.new()
	var start_error := _waveform_thread.start(_build_waveform_background.bind(path))
	if start_error != OK:
		_waveform_thread = null
		_pending_waveform_path = ""
		_set_status("无法启动波形后台任务：%s" % error_string(start_error), true)


func _build_waveform_background(path: String) -> Dictionary:
	return MinghePcm16WaveformBuilder.load_or_build(path)


func _poll_waveform_thread() -> void:
	# 后台线程只读文件并建立缓存；线程结束后回到主线程，才允许更新 Godot UI 节点。
	if _waveform_thread == null or not _waveform_thread.is_started() or _waveform_thread.is_alive():
		return
	var result: Dictionary = _waveform_thread.wait_to_finish()
	_waveform_thread = null
	_pending_waveform_path = ""
	if result.get("cache") == null:
		_set_status(String(result.get("error", "波形读取失败")), true)
		return
	_timeline.set_waveform(result.cache)
	_set_status("已加载波形：%.2f 秒" % result.cache.duration_seconds())


func _save_to_directory(directory: String) -> void:
	var normalized := ProjectSettings.localize_path(directory).trim_suffix("/")
	var result: Dictionary
	if document.stage_path.is_empty():
		result = save_service.save_new_stage_package(document, normalized)
	else:
		result = save_service.save_document(document, normalized + "/song_chart.tres", normalized + "/stage_show.tres")
	_set_status(String(result.get("message", "保存结束")), not bool(result.get("ok", false)))
	_refresh_dirty_state()


func _autosave_if_needed() -> void:
	# 自动保存写入 recovery 恢复文件，不覆盖正式文件；同一内容签名只写一次。
	if not document.is_dirty() or not _gesture_before.is_empty():
		return
	var signature := document.content_signature()
	if signature == _last_autosave_signature:
		return
	var result := save_service.autosave(document)
	if bool(result.get("ok", false)):
		_last_autosave_signature = signature


func _on_palette_selected(index: int) -> void:
	_timeline.creation_kind = String(_palette.get_item_metadata(index))


func _on_snap_selected(index: int) -> void:
	_timeline.snap_ticks = int(_snap.get_item_metadata(index))
	_timeline.queue_redraw()


func _on_speed_selected(index: int) -> void:
	_audio_player.pitch_scale = float(_speed.get_item_metadata(index))


func _current_audio_time() -> float:
	if _audio_player == null or not _audio_player.playing:
		return _timeline.playhead_seconds if _timeline != null else 0.0
	return _audio_player.get_playback_position()


func _tuning_field_at(tick: int) -> String:
	for field in document.get_track_array(MingheChartEditorDocument.TRACK_TUNING_FIELDS):
		var start := int(field.get("tick"))
		var end := start + int(field.get("duration_ticks"))
		if tick >= start and tick < end:
			return String(field.get("event_id"))
	return ""


func _paired_slider_group_before(tick: int) -> String:
	# 素音默认关联同一调频场内、已经结束且离当前最近的双侧组；找不到时留空交给校验器提示。
	var sides_by_group: Dictionary = {}
	var latest_end_by_group: Dictionary = {}
	for slider in document.get_track_array(MingheChartEditorDocument.TRACK_TUNING_SLIDERS):
		var group_id := String(slider.get("group_id"))
		if group_id.is_empty():
			continue
		var end_tick := int(slider.get("tick")) + int(slider.get("traversal_ticks")) * int(slider.get("traversal_count"))
		if end_tick > tick:
			continue
		var sides: Dictionary = sides_by_group.get(group_id, {})
		sides[int(slider.get("affinity"))] = true
		sides_by_group[group_id] = sides
		latest_end_by_group[group_id] = maxi(int(latest_end_by_group.get(group_id, -1)), end_tick)
	var best_group := ""
	var best_end := -1
	for group_id in sides_by_group:
		var sides: Dictionary = sides_by_group[group_id]
		if sides.has(GameplayTypes.Affinity.ZHU) and sides.has(GameplayTypes.Affinity.XUAN) and int(latest_end_by_group[group_id]) > best_end:
			best_group = String(group_id)
			best_end = int(latest_end_by_group[group_id])
	return best_group


func _base_tuning_value() -> float:
	if document.rule_set == null:
		return 0.5
	var minimum := float(document.rule_set.get("tuning_min_frequency_hz"))
	var maximum := float(document.rule_set.get("tuning_max_frequency_hz"))
	return clampf((float(document.rule_set.get("tuning_base_frequency_hz")) - minimum) / maxf(0.001, maximum - minimum), 0.0, 1.0)


func _normalized_frequency_span(hz: float) -> float:
	if document.rule_set == null:
		return hz / 5.1
	return hz / maxf(0.001, float(document.rule_set.get("tuning_max_frequency_hz")) - float(document.rule_set.get("tuning_min_frequency_hz")))


func _event_duration(event: Resource) -> int:
	if event is TuningSliderEvent:
		return maxi(1, event.traversal_ticks) * maxi(1, event.traversal_count)
	var value: Variant = event.get("duration_ticks")
	return int(value) if value != null else 0


func _set_event_duration(event: Resource, total_ticks: int) -> void:
	if event is TuningSliderEvent:
		event.traversal_ticks = maxi(1, roundi(float(total_ticks) / float(maxi(1, event.traversal_count))))
	elif event.get("duration_ticks") != null:
		event.set("duration_ticks", maxi(1, total_ticks))


func _filter_existing_selection(source: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for event_id in source:
		if document.find_event(event_id) != null:
			result.append(event_id)
	return result


func _looks_like_stage_definition(resource: Resource) -> bool:
	return resource.get("chart") != null and resource.get("stage_show") != null


func _resource_has_property(resource: Resource, property_name: StringName) -> bool:
	for property in resource.get_property_list():
		if property.get("name", &"") == property_name:
			return true
	return false


func _line_edit_has_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is SpinBox


func _add_toolbar_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _make_file_dialog(title: String, mode: FileDialog.FileMode, filters: PackedStringArray) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = filters
	add_child(dialog)
	return dialog


func _set_status(message: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.modulate = Color("ef806e") if is_error else Color("d7d7cf")
