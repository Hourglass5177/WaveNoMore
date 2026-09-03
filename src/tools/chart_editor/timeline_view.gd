## 八轨自绘时间线。它把波形、节拍网格、事件和鼠标手势放在同一时间坐标中。
@tool
class_name MingheChartTimelineView
extends Control

## 用户在空白处放置事件；kind 来自工具栏调色板，row 是八条可视轨之一。
signal create_requested(kind: String, tick: int, row: int)
## 选择集变化后通知 Workspace 刷新属性面板。
signal selection_changed(event_ids: PackedStringArray)
## 拖动分三段发送：开始保存快照，preview 实时预演，committed 在松手时写入一次 Undo。
signal gesture_started(label: String)
## 拖动中的临时位移或拉伸量，单位为 tick；mode 为 move 或 resize。
signal gesture_preview(event_ids: PackedStringArray, delta_ticks: int, resize_delta_ticks: int, mode: String)
## 鼠标松开时发送，通知 Workspace 把整段拖动提交为一次历史记录。
signal gesture_committed()
## 标尺点击请求音频跳转，seconds 从音频文件开头计算。
signal seek_requested(seconds: float)
## 可见横轴变化，参数分别是左边界音频秒数和每秒像素数。
signal view_changed(start_seconds: float, pixels_per_second: float)

## 每条轨道的固定高度，单位为 UI 像素。
const ROW_HEIGHT := 54.0
## 顶部时间标尺高度，单位为 UI 像素。
const TOP_RULER_HEIGHT := 34.0
## 八条可视轨从上到下的标签；滑条按生、死分行，避免两路数据叠在一起。
const ROW_LABELS := ["朱音", "玄音", "调频场", "朱滑条", "玄滑条", "素音", "疾振", "演出"]

## 当前绘制的内存文档，由 Workspace 绑定；为空时不应处理事件。
var document: MingheChartEditorDocument
## 当前谱面的 tick/秒换算器，与 document 同时绑定。
var tempo_map: MingheEditorTempoMap
## 可选 WAV 峰值缓存；为空时仍可显示网格和事件。
var waveform: MingheWaveformCache
## 视口左边界对应的音频秒数，允许为负以显示首拍前区域。
var view_start_seconds: float = -1.0
## 横向缩放，单位为「像素/秒」，数值越大显示越细。
var pixels_per_second: float = 120.0
## 谱面 tick 0 相对音频开头的偏移；tick 与音频秒数互转时必须一加一减。
var first_beat_offset_sec: float = 0.0
## 网格吸附间隔，单位为 tick；按 Alt 时临时绕过吸附。
var snap_ticks: int = 120
## 当前空白点击要创建的事件类型，值来自 Workspace 的调色板。
var creation_kind: String = "tap_zhu"
## 播放头所在的音频秒数，由 AudioStreamPlayer 驱动。
var playhead_seconds: float = 0.0
## 当前选中事件的稳定 ID 副本。
var selected_ids: PackedStringArray = PackedStringArray()

## 每次重绘得到的事件矩形，同时用于从鼠标位置反查命中的事件。
var _event_rects: Array[Dictionary] = []
## 当前拖动模式；空字符串表示未拖动，其他值为 move 或 resize。
var _drag_mode: String = ""
## 鼠标按下时的控件局部坐标，供框选矩形和拖动距离使用。
var _drag_start_position := Vector2.ZERO
## 鼠标按下位置换算出的谱面 tick。
var _drag_start_tick: int = 0
## 命中事件在拖动开始时的持续 tick；拉伸时作为基准。
var _drag_start_duration: int = 0
## 本次拖动涉及的事件 ID；多选时一次移动整组。
var _drag_ids: PackedStringArray = PackedStringArray()
## 空白处按下后先等待移动距离，松手时再区分单击创建与框选。
var _blank_press := false
## 从空白按下点到当前鼠标点的框选矩形，单位为控件像素。
var _marquee_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(720.0, TOP_RULER_HEIGHT + ROW_HEIGHT * ROW_LABELS.size())


func bind(source_document: MingheChartEditorDocument, source_tempo_map: MingheEditorTempoMap) -> void:
	document = source_document
	tempo_map = source_tempo_map
	queue_redraw()


func set_waveform(value: MingheWaveformCache) -> void:
	waveform = value
	queue_redraw()


func set_selected(ids: PackedStringArray) -> void:
	selected_ids = ids.duplicate()
	queue_redraw()


func set_playhead(seconds: float) -> void:
	playhead_seconds = seconds
	queue_redraw()


func focus_event(event_id: String) -> void:
	if document == null or tempo_map == null:
		return
	var event := document.find_event(event_id)
	if event == null:
		return
	var seconds := _tick_to_audio_seconds(int(event.get("tick")))
	view_start_seconds = seconds - size.x / pixels_per_second * 0.35
	selected_ids = PackedStringArray([event_id])
	selection_changed.emit(selected_ids)
	view_changed.emit(view_start_seconds, pixels_per_second)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("11151d"), true)
	_draw_waveform()
	_draw_grid()
	_event_rects.clear()
	if document != null:
		_draw_events()
	for row in ROW_LABELS.size():
		var y := TOP_RULER_HEIGHT + float(row) * ROW_HEIGHT
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.32, 0.35, 0.42, 0.36), 1.0)
	var playhead_x := _seconds_to_x(playhead_seconds)
	draw_line(Vector2(playhead_x, 0.0), Vector2(playhead_x, size.y), Color("f2d27a"), 2.0)
	if not _marquee_rect.size.is_zero_approx():
		draw_rect(_marquee_rect, Color(0.65, 0.78, 0.95, 0.14), true)
		draw_rect(_marquee_rect, Color(0.65, 0.78, 0.95, 0.8), false, 1.0)


func _draw_waveform() -> void:
	if waveform == null or waveform.sample_rate <= 0 or waveform.levels.is_empty():
		return
	var source_frames_per_pixel := float(waveform.sample_rate) / pixels_per_second
	var level_index := waveform.choose_level(source_frames_per_pixel)
	if level_index < 0:
		return
	var peaks: PackedVector2Array = waveform.levels[level_index]
	var block_frames := int(waveform.block_sizes[level_index])
	var center_y := TOP_RULER_HEIGHT + ROW_HEIGHT * 3.5
	var amplitude := ROW_HEIGHT * 3.1
	var first_peak := maxi(0, floori(view_start_seconds * float(waveform.sample_rate) / float(block_frames)))
	var last_second := view_start_seconds + size.x / pixels_per_second
	var last_peak := mini(peaks.size() - 1, ceili(last_second * float(waveform.sample_rate) / float(block_frames)))
	for peak_index in range(first_peak, last_peak + 1):
		var seconds := float(peak_index * block_frames) / float(waveform.sample_rate)
		var x := _seconds_to_x(seconds)
		var peak := peaks[peak_index]
		draw_line(
			Vector2(x, center_y - peak.y * amplitude),
			Vector2(x, center_y - peak.x * amplitude),
			Color(0.50, 0.55, 0.65, 0.12),
			1.0
		)


func _draw_grid() -> void:
	if tempo_map == null:
		return
	var first_tick := tempo_map.seconds_to_tick(view_start_seconds - first_beat_offset_sec)
	var last_tick := tempo_map.seconds_to_tick(view_start_seconds + size.x / pixels_per_second - first_beat_offset_sec)
	var grid_ticks := maxi(1, snap_ticks)
	var tick := floori(float(first_tick) / float(grid_ticks)) * grid_ticks
	var ppq := tempo_map.ppq()
	while tick <= last_tick + grid_ticks:
		var x := _seconds_to_x(_tick_to_audio_seconds(tick))
		var is_beat := posmod(tick, ppq) == 0
		var is_bar := posmod(tick, ppq * 4) == 0
		var color := Color(0.64, 0.67, 0.72, 0.14)
		var width := 1.0
		if is_beat:
			color = Color(0.72, 0.74, 0.80, 0.28)
		if is_bar:
			color = Color(0.88, 0.75, 0.48, 0.45)
			width = 2.0
			draw_string(get_theme_default_font(), Vector2(x + 4.0, 20.0), str(tick / (ppq * 4) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, color)
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), color, width)
		tick += grid_ticks


func _draw_events() -> void:
	# 横坐标先经 TempoMap 变为真实秒数，因此变速谱面的事件间距会随 BPM 改变。
	for entry in document.all_events():
		var event: Resource = entry.event
		var track: String = entry.track
		var row := _row_for_event(track, event)
		if row < 0:
			continue
		var tick := int(event.get("tick"))
		var duration := _event_duration(event)
		var x := _seconds_to_x(_tick_to_audio_seconds(tick))
		var end_x := _seconds_to_x(_tick_to_audio_seconds(tick + duration)) if duration > 0 else x + 14.0
		var width := maxf(14.0, end_x - x)
		var rect := Rect2(Vector2(x, TOP_RULER_HEIGHT + float(row) * ROW_HEIGHT + 8.0), Vector2(width, ROW_HEIGHT - 16.0))
		if rect.end.x < 0.0 or rect.position.x > size.x:
			continue
		var event_id := String(event.get("event_id"))
		var color := _event_color(track, event)
		var selected := selected_ids.has(event_id)
		draw_rect(rect, color.lightened(0.18) if selected else color, true)
		draw_rect(rect, Color("f7e6af") if selected else color.lightened(0.32), false, 2.0 if selected else 1.0)
		draw_string(get_theme_default_font(), rect.position + Vector2(5.0, 22.0), _event_label(track, event), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 12, Color("f0ede4"))
		if duration > 0:
			draw_line(Vector2(rect.end.x - 4.0, rect.position.y + 4.0), Vector2(rect.end.x - 4.0, rect.end.y - 4.0), Color("f7e6af"), 2.0)
		_event_rects.append({"id": event_id, "track": track, "event": event, "rect": rect})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# 标尺区点击负责 seek；事件区点击负责选择/拖动；空白点击才按当前调色板创建事件。
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at(event.position.x, 1.16 if event.ctrl_pressed else 1.0)
		if not event.ctrl_pressed:
			view_start_seconds -= 1.0
		_emit_view_changed()
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at(event.position.x, 1.0 / 1.16 if event.ctrl_pressed else 1.0)
		if not event.ctrl_pressed:
			view_start_seconds += 1.0
		_emit_view_changed()
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		if event.position.y < TOP_RULER_HEIGHT:
			seek_requested.emit(view_start_seconds + event.position.x / pixels_per_second)
			accept_event()
			return
		var hit := _hit_event(event.position)
		if not hit.is_empty():
			var id := String(hit.id)
			if event.shift_pressed:
				var ids := selected_ids.duplicate()
				if ids.has(id):
					ids.remove_at(ids.find(id))
				else:
					ids.append(id)
				set_selected(ids)
			else:
				set_selected(PackedStringArray([id]))
			selection_changed.emit(selected_ids)
			var rect: Rect2 = hit.rect
			_drag_mode = "resize" if rect.end.x - event.position.x <= 9.0 and _event_duration(hit.event) > 0 else "move"
			_drag_start_position = event.position
			_drag_start_tick = _x_to_tick(event.position.x)
			_drag_start_duration = _event_duration(hit.event)
			_drag_ids = selected_ids.duplicate()
			gesture_started.emit("调整事件长度" if _drag_mode == "resize" else "移动事件")
			accept_event()
			return
		_blank_press = true
		_drag_start_position = event.position
		_marquee_rect = Rect2()
		if not event.shift_pressed:
			set_selected(PackedStringArray())
			selection_changed.emit(selected_ids)
	else:
		if not _drag_mode.is_empty():
			_drag_mode = ""
			gesture_committed.emit()
			accept_event()
		elif _blank_press:
			if _marquee_rect.size.length() > 4.0:
				_select_marquee(_marquee_rect, event.shift_pressed)
			else:
				var row := floori((event.position.y - TOP_RULER_HEIGHT) / ROW_HEIGHT)
				if row >= 0 and row < ROW_LABELS.size():
					create_requested.emit(creation_kind, _snap_tick(_x_to_tick(event.position.x), event.alt_pressed), row)
			_blank_press = false
			_marquee_rect = Rect2()
			queue_redraw()
			accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _drag_mode.is_empty():
		var current_tick := _snap_tick(_x_to_tick(event.position.x), event.alt_pressed)
		var start_tick := _snap_tick(_drag_start_tick, event.alt_pressed)
		var delta_tick := current_tick - start_tick
		if _drag_mode == "resize":
			gesture_preview.emit(_drag_ids, 0, delta_tick, _drag_mode)
		else:
			gesture_preview.emit(_drag_ids, delta_tick, 0, _drag_mode)
		accept_event()
	elif _blank_press:
		_marquee_rect = Rect2(_drag_start_position, event.position - _drag_start_position).abs()
		queue_redraw()
		accept_event()


func _zoom_at(mouse_x: float, factor: float) -> void:
	# 缩放时固定鼠标下方的时间点，避免视图在滚轮操作中左右跳动。
	if is_equal_approx(factor, 1.0):
		return
	var anchor_second := view_start_seconds + mouse_x / pixels_per_second
	pixels_per_second = clampf(pixels_per_second * factor, 24.0, 900.0)
	view_start_seconds = anchor_second - mouse_x / pixels_per_second


func _emit_view_changed() -> void:
	view_changed.emit(view_start_seconds, pixels_per_second)
	queue_redraw()


func _hit_event(position: Vector2) -> Dictionary:
	for index in range(_event_rects.size() - 1, -1, -1):
		var candidate: Rect2 = _event_rects[index].rect
		if candidate.has_point(position):
			return _event_rects[index]
	return {}


func _select_marquee(rect: Rect2, append: bool) -> void:
	var ids := selected_ids.duplicate() if append else PackedStringArray()
	for entry in _event_rects:
		if rect.intersects(entry.rect) and not ids.has(String(entry.id)):
			ids.append(String(entry.id))
	set_selected(ids)
	selection_changed.emit(selected_ids)


func _row_for_event(track: String, event: Resource) -> int:
	match track:
		MingheChartEditorDocument.TRACK_NOTES:
			return 0 if int(event.get("affinity")) == GameplayTypes.Affinity.ZHU else 1
		MingheChartEditorDocument.TRACK_TUNING_FIELDS:
			return 2
		MingheChartEditorDocument.TRACK_TUNING_SLIDERS:
			return 3 if int(event.get("affinity")) == GameplayTypes.Affinity.ZHU else 4
		MingheChartEditorDocument.TRACK_SU_MANIFESTATIONS:
			return 5
		MingheChartEditorDocument.TRACK_RAPID:
			return 6
		MingheChartEditorDocument.TRACK_SHOW:
			return 7
	return -1


func _event_duration(event: Resource) -> int:
	# 调频滑条的显示总长包含所有往返程；它没有 duration_ticks 字段。
	if event is TuningSliderEvent:
		return maxi(1, event.traversal_ticks) * maxi(1, event.traversal_count)
	var value: Variant = event.get("duration_ticks")
	return int(value) if value != null else 0


func _event_color(track: String, event: Resource) -> Color:
	match track:
		MingheChartEditorDocument.TRACK_NOTES:
			return Color("a53632") if int(event.get("affinity")) == GameplayTypes.Affinity.ZHU else Color("30364d")
		MingheChartEditorDocument.TRACK_TUNING_FIELDS:
			return Color("675877")
		MingheChartEditorDocument.TRACK_TUNING_SLIDERS:
			return Color("b83d39") if int(event.get("affinity")) == GameplayTypes.Affinity.ZHU else Color("252b3e")
		MingheChartEditorDocument.TRACK_SU_MANIFESTATIONS:
			return Color("c4bfa9")
		MingheChartEditorDocument.TRACK_RAPID:
			return Color("77522d")
		MingheChartEditorDocument.TRACK_SHOW:
			return Color("315a60")
	return Color("555b66")


func _event_label(track: String, event: Resource) -> String:
	match track:
		MingheChartEditorDocument.TRACK_NOTES:
			return "Hold" if int(event.get("kind")) == GameplayTypes.NoteKind.HOLD else "Tap"
		MingheChartEditorDocument.TRACK_TUNING_FIELDS:
			return "调频场"
		MingheChartEditorDocument.TRACK_TUNING_SLIDERS:
			var direction := "↗" if float(event.get("end_value")) > float(event.get("start_value")) else "↘"
			return "%s %.2f%s%.2f ×%d" % ["朱" if int(event.get("affinity")) == GameplayTypes.Affinity.ZHU else "玄", float(event.get("start_value")), direction, float(event.get("end_value")), int(event.get("traversal_count"))]
		MingheChartEditorDocument.TRACK_SU_MANIFESTATIONS:
			return "素音 ×%d" % int(event.get("count"))
		MingheChartEditorDocument.TRACK_RAPID:
			return "疾振 ×%d" % int(event.get("required_strikes"))
		MingheChartEditorDocument.TRACK_SHOW:
			return String(event.get("cue_id")) if not String(event.get("cue_id")).is_empty() else "演出 cue"
	return "事件"


# 时间线显示音频文件中的秒数，谱面保存的 tick 却以首拍为零点：正向换算要加首拍偏移，
# 鼠标位置反算回 tick 时则必须减掉同一偏移。
func _tick_to_audio_seconds(tick: int) -> float:
	# 谱面时间以首拍为零点，画面和波形以音频文件开头为零点，因此正向换算要加首拍偏移。
	return first_beat_offset_sec + tempo_map.tick_to_seconds(tick)


func _seconds_to_x(seconds: float) -> float:
	return (seconds - view_start_seconds) * pixels_per_second


func _x_to_tick(x: float) -> int:
	# 鼠标横坐标先还原为音频秒数，再减去首拍偏移，才是可以写回谱面的 tick。
	return tempo_map.seconds_to_tick(view_start_seconds + x / pixels_per_second - first_beat_offset_sec)


func _snap_tick(tick: int, free_placement: bool) -> int:
	return tick if free_placement else tempo_map.snap_tick(tick, snap_ticks)
