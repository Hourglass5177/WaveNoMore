class_name StudioTimeline
extends Control
## 秒坐标显示、音乐 tick 编辑；手势只更新候选集合，释放时提交增量命令。
signal rhythm_anchor_changed(seconds: float)
var rhythm_grid := {}
var rhythm_raw := {}
var rhythm_draft: Array[NoteEvent] = []
var _rhythm_anchor_before := 0.0
var _rhythm_context := PopupMenu.new()
var _rhythm_pick := 0.0
signal selection_changed
signal seek_requested(seconds: float)
signal candidate_changed
signal context_requested(position: Vector2)
signal gesture_started
signal seek_finished(seconds: float)
signal loop_changed(start: float, end: float)
signal view_changed
signal manual_browse
## 对齐候选只存在于视图；松手由工作区写入一次文档命令。
signal alignment_started
signal alignment_preview(seconds: float)
signal alignment_committed(seconds: float)
signal alignment_cancelled
signal waveform_context_requested(position: Vector2, seconds: float)
var move_waveform := false:
	set(value):
		move_waveform = value; queue_redraw()
var _alignment_before_offset := 0.0
var _alignment_before_view := 0.0
var _alignment_seconds := 0.0
var document: StudioDocument
var selected := PackedStringArray()
var candidates: Array = []
var view_start := -2.0:
	set(value):
		if view_start == value: return
		view_start = value; queue_redraw(); _redraw_overlay(); view_changed.emit()
var pixels_per_second := 160.0:
	set(value):
		pixels_per_second = clampf(value, 12, 3000); queue_redraw(); _redraw_overlay(); view_changed.emit()
var playhead := 0.0:
	set(value):
		playhead = value; _redraw_overlay()
var snap_ticks := 120
var peaks := PackedVector2Array()
var _peak_levels: Array[PackedVector2Array] = []
var audio_duration := 0.0
var loop_range := Vector2.ZERO:
	set(value):
		if loop_range == value: return
		loop_range = value; queue_redraw()
var loop_enabled := false:
	set(value):
		if loop_enabled == value: return
		loop_enabled = value; queue_redraw()
var _mode := ""
var _browse_pending := false
var _browse_pixels := Vector2.ZERO
var _browse_horizontal := false
var _browse_zoom := 0.0
var _browse_anchor_x := 0.0
var recording_notes: Array[NoteEvent] = []
var _overlay: Control
var _loop_before := Vector2.ZERO
var _last_alt := false
var _down := Vector2.ZERO
var _current := Vector2.ZERO
var _before: Array = []
var _anchor_tick := 0
var _grab_tick := 0
var _side := 0
var _map: TempoMap
var _indexed_notes: Array = []
var _prefix_end := PackedInt64Array()
const RULER := 72.0
const SECONDS_BOTTOM := 20.0
const WAVE_TOP := 36.0
const WAVE_BOTTOM := 60.0
const HEADER := 120.0
const TRACK_NAMES := ["生钟 · Tap / Hold", "死钟 · Tap / Hold", "生钟 · Tuning", "死钟 · Tuning", "Ghost"]
signal commit_requested(label: String, before: Array, after: Array)
signal path_edit_requested(id: String, tick: int)
signal notice(message: String)
var row_height := 48.0
var folded: Array[bool] = [true, true, true, true, true]
var track_scroll := 0.0
var _vscroll := VScrollBar.new()
var _stack_menu := PopupMenu.new()
var _node_index := -1
var _draw_track := 0
var selected_node := -1
var _hold_windows: Array[Vector2i] = []
var _related_selection := PackedStringArray()
var _ghost_stack_counts := {}

# 折叠仅压缩行高，绘制和交互统一使用实际高度。
func track_height(track: int) -> float:
	return 24.0 if folded[track] else row_height

func track_y(track: int) -> float:
	var y := RULER - track_scroll
	for i in track: y += track_height(i)
	return y

func track_at(y: float) -> int:
	for track in 5:
		if y >= maxf(RULER, track_y(track)) and y < track_y(track) + track_height(track): return track
	return -1

func _update_track_scroll() -> void:
	var height := 0.0
	for value in folded: height += 24.0 if value else row_height
	_vscroll.position = Vector2(size.x - 14, RULER)
	_vscroll.size = Vector2(14, maxf(1, size.y - RULER))
	_vscroll.max_value = height; _vscroll.page = maxf(1, size.y - RULER)
	_vscroll.visible = height > _vscroll.page
	track_scroll = clampf(track_scroll, 0, maxf(0, height - _vscroll.page))
	_vscroll.set_value_no_signal(track_scroll)

func submit(label: String, before: Array, after: Array) -> void:
	if commit_requested.has_connections(): commit_requested.emit(label, before, after)
	else: document.execute(label, before, after)


func _ready() -> void:
	add_child(_vscroll); add_child(_stack_menu)
	_vscroll.value_changed.connect(func(value: float): track_scroll = value; queue_redraw())
	_stack_menu.id_pressed.connect(func(index: int):
		selected = PackedStringArray([str(_stack_menu.get_item_metadata(index))]); selection_changed.emit(); queue_redraw())
	resized.connect(_update_track_scroll)
	_update_track_scroll()
	add_child(_rhythm_context); _rhythm_context.add_item("设为小节第一拍")
	_rhythm_context.id_pressed.connect(func(_i: int) -> void: rhythm_anchor_changed.emit(_rhythm_pick))
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	custom_minimum_size = Vector2(320, 164)
	_overlay = Control.new(); _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay); _overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	resized.connect(func() -> void: queue_redraw(); _redraw_overlay())

func bind(doc: StudioDocument) -> void:
	document = doc
	document.changed.connect(refresh)
	refresh()

func refresh() -> void:
	if document.change_kind == &"annotation":
		# 注解不改变时间索引，但命令已替换资源，绘制引用也必须跟随新对象。
		for i in _indexed_notes.size():
			if document.affected_ids.has(_indexed_notes[i].event_id): _indexed_notes[i] = document.find_note(_indexed_notes[i].event_id)
		queue_redraw(); return
	if document.change_kind in [&"metadata", &"presentation"]: return
	rebuild_index()

## 返回外部试玩后可独立恢复显示缓存，不伪造文档修改或重演玩法。
func rebuild_index() -> void:
	_map = document.tempo_map()
	_indexed_notes.assign(document.chart().note_events)
	for event in Array(document.chart().tuning_paths) + Array(document.chart().ghost_events): ChartEditEvents._insert(_indexed_notes, event)
	_prefix_end.clear()
	var end := -9223372036854775807
	for note in _indexed_notes:
		end = maxi(end, note.tick + note.duration_ticks)
		_prefix_end.append(end)
	_hold_windows.clear()
	_ghost_stack_counts.clear()
	for ghost in document.chart().ghost_events: _ghost_stack_counts[ghost.tick] = int(_ghost_stack_counts.get(ghost.tick, 0)) + 1
	var life := document.chart().note_events.filter(func(n): return n.kind == GameplayTypes.NoteKind.HOLD and n.affinity == 0)
	var death := document.chart().note_events.filter(func(n): return n.kind == GameplayTypes.NoteKind.HOLD and n.affinity == 1)
	life.sort_custom(func(a, b): return a.tick < b.tick); death.sort_custom(func(a, b): return a.tick < b.tick)
	var j := 0
	for a in life:
		while j < death.size() and death[j].tick + death[j].duration_ticks < a.tick: j += 1
		var k := j
		while k < death.size() and death[k].tick <= a.tick + a.duration_ticks:
			var window_start := maxi(a.tick, death[k].tick); var window_end := mini(a.tick + a.duration_ticks, death[k].tick + death[k].duration_ticks)
			if window_end > window_start: _hold_windows.append(Vector2i(window_start, window_end))
			k += 1
	queue_redraw()
	_redraw_overlay()

func x_at(tick: int) -> float:
	return (float(_map.tick_to_us(tick)) / 1000000.0 - view_start) * pixels_per_second

func tick_at(x: float, free := false) -> int:
	var tick := _map.us_to_tick(roundi((view_start + x / pixels_per_second) * 1000000.0))
	return roundi(tick) if free or snap_ticks == 0 else roundi(tick / snap_ticks) * snap_ticks

func note_rect(note) -> Rect2:
	var x := x_at(note.tick)
	var width := maxf(12, x_at(note.tick + note.duration_ticks) - x + 12)
	var track := ChartEditEvents.track(note)
	var inset := 3.0 if folded[track] else 6.0
	return Rect2(x - 6, track_y(track) + inset, maxf(width, 76 if note is GhostEvent else width), track_height(track) - inset * 2)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("141a25"))
	if document == null: return
	var font := ThemeDB.fallback_font
	var zero_x := -view_start * pixels_per_second
	if zero_x > 0: draw_rect(Rect2(0, 0, minf(zero_x, size.x), size.y), Color(0.24, 0.22, 0.3, 0.2))
	var end_sec := view_start + size.x / pixels_per_second
	if move_waveform:
		draw_rect(Rect2(0, WAVE_TOP, size.x, WAVE_BOTTOM - WAVE_TOP), Color(0.8, 0.58, 0.18, 0.18))
	if loop_range.y > loop_range.x:
		draw_rect(Rect2((loop_range.x - view_start) * pixels_per_second, 0, (loop_range.y - loop_range.x) * pixels_per_second, SECONDS_BOTTOM), Color(0.75, 0.58, 0.25, 0.3 if loop_enabled else 0.1))
	for track in 5:
		var top := maxf(RULER, track_y(track))
		var bottom := minf(size.y, track_y(track) + track_height(track))
		if bottom <= top: continue
		draw_rect(Rect2(0, top, size.x, bottom - top), Color("666a70") if track == 4 else (Color("211d25") if track in [0, 2] else Color("1b2431")))
	# 缓存双 Hold 窗口，不在每次绘制时做全谱两两相交。
	for window in _hold_windows:
		var left := maxf(HEADER, x_at(window.x)); var right := minf(size.x, x_at(window.y))
		if right <= left: continue
		for track in [2, 3]:
			var top := maxf(RULER, track_y(track)); var bottom := minf(size.y, track_y(track) + track_height(track))
			if bottom > top: draw_rect(Rect2(left, top, right - left, bottom - top), Color(0.32, 0.65, 0.49, 0.14))
	_related_selection = ChartEditEvents.linked_ids(document.chart(), selected)
	var second_step := maxf(0.25, pow(2, ceil(log(70.0 / pixels_per_second) / log(2.0))))
	var seconds: float = floor(view_start / second_step) * second_step
	while seconds <= end_sec:
		var x := (seconds - view_start) * pixels_per_second
		draw_line(Vector2(x, 0), Vector2(x, SECONDS_BOTTOM), Color("526077"))
		draw_string(font, Vector2(x + 3, 17), format_time(seconds), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		seconds += second_step
	# 缩小时只画能辨认的网格，实际吸附分辨率保持不变。
	var step := maxi(1, snap_ticks if snap_ticks else document.chart().ppq)
	while absf(x_at(step) - x_at(0)) < 12: step *= 2
	var first := floori(float(tick_at(0, true)) / step) * step
	var last := tick_at(size.x, true) + step
	for tick in range(first, last, step):
		var x := x_at(tick)
		var beat := posmod(tick, document.chart().ppq) == 0
		draw_line(Vector2(x, SECONDS_BOTTOM), Vector2(x, size.y), Color(0.4, 0.5, 0.65, 0.28 if beat else 0.1))
		if beat: draw_string(font, Vector2(x + 2, 33), music_label(tick), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9da8bc"))
	if not peaks.is_empty() and audio_duration > 0:
		var visible_peaks := peaks
		for level in _peak_levels:
			if float(visible_peaks.size()) / audio_duration / pixels_per_second <= 2: break
			visible_peaks = level
		for x in range(0, int(size.x), 2):
			var from_index := floori((view_start + x / pixels_per_second) / audio_duration * visible_peaks.size())
			var to_index := ceili((view_start + (x + 2) / pixels_per_second) / audio_duration * visible_peaks.size())
			var low := 0.0
			var high := 0.0
			for i in range(maxi(0, from_index), mini(visible_peaks.size(), maxi(from_index + 1, to_index))):
				low = minf(low, visible_peaks[i].x)
				high = maxf(high, visible_peaks[i].y)
			draw_line(Vector2(x, 48 - high * 11), Vector2(x, 48 - low * 11), Color("659093"))
	# BPM 与段落共用底部一行；同刻合并，邻近标签按下一个锚点裁宽。
	var annotations := {}
	for tempo in document.chart().tempo_events:
		annotations[tempo.tick - document.chart().chart_offset_ticks] = "♩ %.2f" % tempo.bpm
	for section in document.chart().sections:
		annotations[section.tick] = (str(annotations[section.tick]) + " · " if annotations.has(section.tick) else "") + section.label
	var annotation_ticks := annotations.keys(); annotation_ticks.sort()
	for i in annotation_ticks.size():
		var x := x_at(annotation_ticks[i]) + 3
		var right := x_at(annotation_ticks[i + 1]) - 3 if i + 1 < annotation_ticks.size() else size.x
		if right > x: draw_string(font, Vector2(x, 70), annotations[annotation_ticks[i]], HORIZONTAL_ALIGNMENT_LEFT, right - x, 11, Color("d4ae70"))
	if zero_x >= 0 and zero_x <= size.x:
		draw_line(Vector2(zero_x, 0), Vector2(zero_x, size.y), Color("a8cfdd"), 2)
	var beat_seconds := _alignment_seconds if is_aligning() else document.offset_sec()
	var beat_x := (beat_seconds - view_start) * pixels_per_second
	if beat_x >= 0 and beat_x <= size.x:
		draw_line(Vector2(beat_x, SECONDS_BOTTOM), Vector2(beat_x, size.y), Color("e5b663"), 2)
		draw_colored_polygon(PackedVector2Array([Vector2(beat_x - 6, WAVE_TOP), Vector2(beat_x + 6, WAVE_TOP), Vector2(beat_x, WAVE_TOP + 8)]), Color("e5b663"))
		draw_string(font, Vector2(beat_x + 8, 55), "首拍", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ddc9a0"))
	for endpoint in [loop_range.x, loop_range.y]:
		var x: float = (endpoint - view_start) * pixels_per_second
		draw_line(Vector2(x, 0), Vector2(x, SECONDS_BOTTOM), Color("d4ae70"), 3)
	var hidden := {}
	for note in candidates: hidden[note.event_id] = true
	for note in visible_notes(0, size.x):
		if not hidden.has(note.event_id): _draw_note(note, false)
	for note in candidates: _draw_note(note, true)
	_draw_rhythm()
	for note in rhythm_draft: _draw_note(note, true)
	if _mode == "box":
		var rect := Rect2(_down, _current - _down).abs()
		draw_rect(rect, Color(0.45, 0.65, 1, 0.15))
		draw_rect(rect, Color("8ca7d1"), false)

	for track in 5:
		var top := maxf(RULER, track_y(track)); var bottom := minf(size.y, track_y(track) + track_height(track))
		if bottom <= top: continue
		draw_rect(Rect2(0, top, HEADER, bottom - top), Color("757980") if track == 4 else Color("252e3d"))
		draw_string(font, Vector2(7, top + 17), ("+ " if folded[track] else "− ") + TRACK_NAMES[track], HORIZONTAL_ALIGNMENT_LEFT, HEADER - 8, 12, Color("f4f3ee") if track == 4 else Color("d2d9e3"))

func _draw_note(note, ghost: bool, target: CanvasItem = self) -> void:
	var track := ChartEditEvents.track(note)
	var rect := note_rect(note)
	if rect.end.x < HEADER or rect.position.x > size.x or rect.end.y <= RULER or rect.position.y >= size.y: return
	# 行边界裁切，避免垂直滚动后的半行覆盖标尺。
	rect = rect.intersection(Rect2(HEADER, RULER, maxf(1, size.x - HEADER - 14), maxf(1, size.y - RULER)))
	var color := Color("be645a") if note.affinity == 0 else Color("7194bb")
	if note is GhostEvent: color = Color("ddd9ce")
	if ghost: color.a = 0.65
	if note is GhostEvent and int(_ghost_stack_counts.get(note.tick, 0)) > 1:
		for offset in [2, 4]: target.draw_line(rect.position - Vector2(0, offset), Vector2(rect.end.x, rect.position.y - offset), color, 1)
	target.draw_rect(rect, color.darkened(0.25) if note is TuningPathEvent else color)
	if selected.has(note.event_id) or ghost or _related_selection.has(note.event_id): target.draw_rect(rect.grow(1), Color("ffdd9d"), false, 2 if selected.has(note.event_id) else 1)
	if note is TuningPathEvent:
		var points := PackedVector2Array()
		for i in note.points.size():
			var p := Vector2(x_at(note.tick + note.points[i].offset_ticks), rect.position.y + rect.size.y * (0.5 - sin(deg_to_rad(note.points[i].angle_deg)) * 0.32))
			points.append(p)
			if selected.has(note.event_id): target.draw_circle(p, 4, Color("ffdd9d"))
		if points.size() > 1: target.draw_polyline(points, color.lightened(0.4), 2, true)
		for i in range(1, points.size()):
			var middle := (points[i - 1] + points[i]) * 0.5
			if middle.x < HEADER + 8 or middle.x > size.x - 20: continue
			var direction := (points[i] - points[i - 1]).normalized()
			target.draw_line(middle, middle - direction.rotated(0.6) * 6, Color.WHITE, 1)
			target.draw_line(middle, middle - direction.rotated(-0.6) * 6, Color.WHITE, 1)
	elif note.duration_ticks > 0:
		target.draw_line(rect.position + Vector2(6, 0), rect.position + Vector2(6, rect.size.y), Color.WHITE, 2)
		target.draw_line(rect.end - Vector2(6, rect.size.y), rect.end - Vector2(6, 0), Color.WHITE, 2)
	if note is GhostEvent or (selected.has(note.event_id) and not folded[track]): target.draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 15), ChartEditEvents.title(note), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - (20 if folded[track] and ChartEditEvents.is_boss(note) else 8), 12, Color("17202a"))
	if ChartEditEvents.is_boss(note):
		if folded[track]:
			var badge := Rect2(rect.end.x - 11, rect.position.y + 3, 10, 12)
			target.draw_rect(badge, Color("ffe1a0"))
			target.draw_string(ThemeDB.fallback_font, badge.position + Vector2(1, 10), "B", HORIZONTAL_ALIGNMENT_LEFT, 9, 10, Color("17202a"))
		else: target.draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, rect.size.y - 3), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("ffe1a0"))

func _hit(pos: Vector2):
	var hit_track := track_at(pos.y)
	if hit_track < 0 or pos.x < HEADER: return null
	var visible := visible_notes(pos.x - 14, pos.x + 14)
	for note in visible:
		if note is GhostEvent and selected.has(note.event_id) and hit_track == 4 and note_rect(note).grow(4).has_point(pos): return note
	for i in range(visible.size() - 1, -1, -1):
		var note = visible[i]
		if ChartEditEvents.track(note) == hit_track and note_rect(note).grow(4).has_point(pos): return note
	return null

func _missing_holds(start: int, finish: int) -> String:
	var sides := [false, false]
	for note in document.chart().note_events:
		if note.kind == GameplayTypes.NoteKind.HOLD and note.tick <= start and note.tick + note.duration_ticks >= finish: sides[note.affinity] = true
	return "所选范围缺少生、死 Hold" if not sides[0] and not sides[1] else ("所选范围缺少生钟 Hold" if not sides[0] else ("所选范围缺少死钟 Hold" if not sides[1] else "请拖出两个不同时间的节点"))

func _get_tooltip(at: Vector2) -> String:
	if document == null: return ""
	if at.y < RULER:
		var seconds := view_start + at.x / pixels_per_second
		if absf(at.x - (document.offset_sec() - view_start) * pixels_per_second) <= 9 and at.y >= WAVE_TOP:
			return "首拍 " + format_time(document.offset_sec()) + "；拖动调整对齐"
		if absf(seconds * pixels_per_second) <= 6: return "音乐起点 00:00.000"
		if at.y >= WAVE_BOTTOM:
			var tick := tick_at(at.x, true)
			var label := ""
			for tempo in document.chart().tempo_events:
				if tempo.tick - document.chart().chart_offset_ticks <= tick: label = "BPM %.2f" % tempo.bpm
			var section_name := ""
			for section in document.chart().sections:
				if section.tick <= tick: section_name = section.label
			return label + (" · " + section_name if not section_name.is_empty() else "")
	var track := track_at(at.y)
	if at.x < HEADER and track >= 0: return "点击展开轨道；紧凑状态也可直接编辑" if folded[track] else "点击折叠为紧凑轨道"
	var hit = _hit(at)
	if hit != null:
		if hit is GhostEvent: return ("Ghost ×%d · tick %d\n命中时刻的一批目标；%d 个同刻批次，双击选择批次" % [hit.count, hit.tick, int(_ghost_stack_counts.get(hit.tick, 1))]) + ("\nBOSS 发出" if hit.boss else "")
		return "%s · tick %d～%d%s" % [ChartEditEvents.title(hit), hit.tick, hit.tick + hit.duration_ticks, " · BOSS 发出" if ChartEditEvents.is_boss(hit) else ""]
	if track_at(at.y) in [2, 3]: return "在双 Hold 重合窗口拖画 Tuning；绿色区域可创建"
	return ""

func _gui_input(event: InputEvent) -> void:
	if document == null: return
	if event is InputEventPanGesture:
		_queue_browse(event.delta * 32.0)
		accept_event()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			if mouse.pressed:
				var horizontal := mouse.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
				var direction := -1.0 if mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
				var amount := direction * mouse.factor
				if mouse.ctrl_pressed and not horizontal:
					_queue_browse(Vector2.ZERO, -amount, mouse.position.x)
				else:
					_queue_browse(Vector2(amount * 100.0, 0) if horizontal else Vector2(0, amount * 48.0))
			accept_event(); return
		# 同一帧先滚动再开始拖动时，先落实浏览，避免拖动基准采用旧视口。
		if mouse.pressed: _flush_browse()
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.position.y >= SECONDS_BOTTOM and mouse.position.y < WAVE_TOP and not rhythm_grid.is_empty():
			var period: float = 60.0 / float(rhythm_grid.bpm)
			var seconds := view_start + mouse.position.x / pixels_per_second
			_rhythm_pick = float(rhythm_grid.anchor) + round((seconds - float(rhythm_grid.anchor)) / period) * period
			_rhythm_context.position = Vector2i(get_global_mouse_position()); _rhythm_context.popup(); accept_event(); return
		if is_aligning() and mouse.button_index != MOUSE_BUTTON_LEFT:
			accept_event(); return
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			if mouse.position.y >= WAVE_TOP and mouse.position.y < WAVE_BOTTOM:
				waveform_context_requested.emit(get_global_mouse_position(), view_start + mouse.position.x / pixels_per_second)
			else:
				var hit = _hit(mouse.position)
				if hit != null and not selected.has(hit.event_id): selected = PackedStringArray([hit.event_id]); selection_changed.emit(); queue_redraw()
				context_requested.emit(get_global_mouse_position())
			return
		if mouse.button_index == MOUSE_BUTTON_MIDDLE:
			manual_browse.emit()
			_mode = "pan" if mouse.pressed else ""
			return
		if mouse.button_index != MOUSE_BUTTON_LEFT: return
		grab_focus()
		if mouse.pressed: _begin(mouse)
		else: _finish(mouse)
		accept_event()
	elif event is InputEventMouseMotion:
		_motion(event as InputEventMouseMotion)

func _queue_browse(pixels: Vector2, zoom := 0.0, anchor_x := 0.0) -> void:
	# 编辑手势已有自己的边缘滚动；双指和滚轮不能改变其起手坐标。
	if not _mode.is_empty() or (pixels == Vector2.ZERO and zoom == 0.0): return
	# 上下浏览只更换可见轨道，不解除水平方向的播放跟随。
	if (pixels.x != 0.0 or zoom != 0.0) and (not _browse_pending or (not _browse_horizontal and _browse_zoom == 0.0)): manual_browse.emit()
	_browse_pending = true
	_browse_pixels += pixels
	_browse_horizontal = _browse_horizontal or pixels.x != 0.0
	_browse_zoom += zoom
	if zoom != 0.0: _browse_anchor_x = anchor_x

func _flush_browse() -> void:
	if not _browse_pending: return
	# 两轴各自控制一个方向；不再把纵向滚动折算成横向时间。
	if _mode.is_empty():
		if _browse_pixels.x != 0.0:
			view_start += _browse_pixels.x / pixels_per_second
		if _browse_pixels.y != 0.0:
			track_scroll += _browse_pixels.y
			_update_track_scroll(); queue_redraw()
		if _browse_zoom != 0.0 and not _browse_horizontal:
			var anchor := view_start + _browse_anchor_x / pixels_per_second
			pixels_per_second *= pow(1.2, _browse_zoom)
			view_start = anchor - _browse_anchor_x / pixels_per_second
	_browse_pending = false
	_browse_pixels = Vector2.ZERO
	_browse_horizontal = false
	_browse_zoom = 0.0

func _begin(event: InputEventMouseButton) -> void:
	gesture_started.emit()
	_down = event.position
	if _down.y >= SECONDS_BOTTOM and _down.y < WAVE_TOP and not rhythm_grid.is_empty():
		_rhythm_anchor_before = float(rhythm_grid.anchor); _mode = "rhythm"; return
	_current = _down
	_anchor_tick = tick_at(_down.x, event.alt_pressed)
	candidates.clear()
	_before.clear()
	_last_alt = event.alt_pressed
	if _down.y < SECONDS_BOTTOM:
		_loop_before = loop_range
		for index in 2:
			if absf(_down.x - ((loop_range.x if index == 0 else loop_range.y) - view_start) * pixels_per_second) < 7:
				_mode = "loop_start" if index == 0 else "loop_end"; return
	if _down.y < RULER:
		var marker_x := (document.offset_sec() - view_start) * pixels_per_second
		if _down.y >= WAVE_TOP and _down.y < WAVE_BOTTOM and (absf(_down.x - marker_x) <= 9 or (move_waveform and not peaks.is_empty())):
			_mode = "align_marker" if absf(_down.x - marker_x) <= 9 else "align_wave"
			_alignment_before_offset = document.offset_sec()
			_alignment_before_view = view_start
			_alignment_seconds = _alignment_before_offset
			manual_browse.emit()
			alignment_started.emit()
			return
		_mode = "seek"
		seek_requested.emit(view_start + _down.x / pixels_per_second)
		return
	_draw_track = track_at(_down.y)
	if _draw_track < 0: return
	if _down.x < HEADER:
		folded[_draw_track] = not folded[_draw_track]; _update_track_scroll(); queue_redraw(); return
	var hit = _hit(_down)
	if hit is TuningPathEvent and event.double_click:
		selected = PackedStringArray([hit.event_id]); path_edit_requested.emit(hit.event_id, _anchor_tick); return
	if hit is GhostEvent and not event.shift_pressed:
		var stack := visible_notes(_down.x - 12, _down.x + 12).filter(func(e): return e is GhostEvent and e.tick == hit.tick)
		if stack.size() > 1 and (not selected.has(hit.event_id) or event.double_click):
			_stack_menu.clear()
			for item in stack:
				_stack_menu.add_item(ChartEditEvents.title(item) + (" · BOSS" if item.boss else "")); _stack_menu.set_item_metadata(_stack_menu.item_count - 1, item.event_id)
			_stack_menu.position = Vector2i(get_global_mouse_position()); _stack_menu.popup(); return
	if event.shift_pressed:
		if hit != null:
			if selected.has(hit.event_id): selected.remove_at(selected.find(hit.event_id))
			else: selected.append(hit.event_id)
			selection_changed.emit()
		else: _mode = "box"
	elif hit != null:
		if not selected.has(hit.event_id): selected = PackedStringArray([hit.event_id])
		_mode = "move"
		_grab_tick = hit.tick
		_side = hit.affinity
		_node_index = -1
		if hit.duration_ticks > 0:
			if absf(_down.x - x_at(hit.tick)) <= 8: _mode = "head"
			elif absf(_down.x - x_at(hit.tick + hit.duration_ticks)) <= 8: _mode = "tail"
		if hit is TuningPathEvent:
			for i in range(1, hit.points.size() - 1):
				if absf(_down.x - x_at(hit.tick + hit.points[i].offset_ticks)) <= 7: _mode = "node"; _node_index = i; selected_node = i; break
		var moving := ChartEditEvents.moving_ids(document.chart(), selected) if _mode == "move" else selected
		for id in moving:
			var note := document.find_note(id)
			if note != null and (_mode == "move" or note == hit): _before.append(note.duplicate(true))
		selection_changed.emit()
	else:
		_mode = "draw"
		_side = _draw_track % 2
	queue_redraw()

func _motion(event: InputEventMouseMotion) -> void:
	if is_aligning():
		# 增量缩放让 Shift 可在拖动中切换，不会突然跳到另一个偏移。
		var displacement := (event.position.x - _current.x) / pixels_per_second
		if event.shift_pressed: displacement *= 0.1
		_alignment_seconds += displacement * (-1.0 if _mode == "align_wave" else 1.0)
		_current = event.position
		_map.first_beat_offset_us = roundi(_alignment_seconds * 1000000.0)
		if _mode == "align_wave":
			# 平移视口抵消网格的偏移变化，屏幕上只有音频及秒尺移动。
			view_start = _alignment_before_view + _alignment_seconds - _alignment_before_offset
		queue_redraw(); _redraw_overlay()
		alignment_preview.emit(_alignment_seconds)
		return
	_current = event.position
	_last_alt = event.alt_pressed
	if _mode == "rhythm": rhythm_anchor_changed.emit(_rhythm_anchor_before + (_current.x - _down.x) / pixels_per_second)
	elif _mode == "pan": view_start -= event.relative.x / pixels_per_second
	elif _mode == "seek": seek_requested.emit(view_start + _current.x / pixels_per_second)
	elif _mode in ["loop_start", "loop_end"]:
		var seconds := view_start + _current.x / pixels_per_second
		loop_changed.emit(minf(seconds, loop_range.y - 0.001) if _mode == "loop_start" else loop_range.x, maxf(seconds, loop_range.x + 0.001) if _mode == "loop_end" else loop_range.y)
	elif _mode == "draw":
		var end := tick_at(_current.x, event.alt_pressed)
		var start := mini(end, _anchor_tick)
		var finish := maxi(end, _anchor_tick)
		candidates.clear()
		if _draw_track in [2, 3]:
			if finish <= start: return
			var path := ChartEditEvents.new_path(document.chart(), _side, start, finish)
			if path != null: path.event_id = "candidate"; candidates.append(path)
		elif _draw_track == 4:
			var batch := GhostEvent.new(); batch.event_id = "candidate"; batch.tick = _anchor_tick
			if ChartEditEvents.rebind(document.chart(), batch): candidates.append(batch)
		else:
			var note := NoteEvent.new(); note.event_id = "candidate"; note.affinity = _side; note.tick = _anchor_tick
			if absf(_current.x - _down.x) >= 6:
				note.tick = start; note.kind = GameplayTypes.NoteKind.HOLD
				note.duration_ticks = maxi(1 if event.alt_pressed else maxi(1, snap_ticks), finish - start)
			candidates.append(note)
	elif _mode in ["move", "head", "tail", "node"]:
		if _current.distance_to(_down) < 6: return
		candidates.clear()
		var delta := tick_at(_current.x, event.alt_pressed) - _anchor_tick
		var sides := {}
		for old in _before:
			if not old is GhostEvent: sides[old.affinity] = true
		for old in _before:
			var note = old.duplicate(true)
			var minimum := 1 if event.alt_pressed else maxi(1, snap_ticks)
			if _mode == "node":
				note.points[_node_index].offset_ticks = clampi(old.points[_node_index].offset_ticks + delta, old.points[_node_index - 1].offset_ticks + 1, old.points[_node_index + 1].offset_ticks - 1)
			elif _mode == "head":
				var latest: int = old.tick + (old.points[1].offset_ticks if old is TuningPathEvent else old.duration_ticks) - minimum
				note.tick = mini(old.tick + delta, latest)
				if note is TuningPathEvent:
					for i in range(1, note.points.size()): note.points[i].offset_ticks -= note.tick - old.tick
				else: note.duration_ticks = old.tick + old.duration_ticks - note.tick
			elif _mode == "tail":
				var floor_length: int = note.points[-2].offset_ticks + minimum if note is TuningPathEvent else minimum
				note.duration_ticks = maxi(floor_length, old.duration_ticks + delta)
			else:
				note.tick += delta
				var target_track := track_at(_current.y)
				if sides.size() == 1 and not note is GhostEvent and target_track >= 0 and target_track / 2 == _draw_track / 2:
					note.affinity = target_track % 2
					if note is TuningPathEvent and note.affinity != old.affinity: ChartEditEvents.rebind(document.chart(), note)
			candidates.append(note)
		if _mode == "move": ChartEditEvents.rebind_moved_ghosts(document.chart(), _before, candidates, selected)
	if not _mode.is_empty():
		queue_redraw()
		if _mode in ["draw", "move", "head", "tail", "node"]: candidate_changed.emit()

func _finish(event: InputEventMouseButton) -> void:
	if is_aligning():
		var motion := InputEventMouseMotion.new()
		motion.position = event.position; motion.shift_pressed = event.shift_pressed
		_motion(motion)
		var seconds := _alignment_seconds
		_mode = ""
		alignment_committed.emit(seconds)
		_map = document.tempo_map()
		queue_redraw(); _redraw_overlay()
		return
	if _mode == "seek": seek_finished.emit(view_start + event.position.x / pixels_per_second)
	if _mode == "box":
		var rect := Rect2(_down, event.position - _down).abs()
		for note in visible_notes(rect.position.x - 14, rect.end.x + 14):
			if rect.intersects(note_rect(note)) and not selected.has(note.event_id): selected.append(note.event_id)
	elif _mode == "draw":
		if candidates.is_empty():
			if _draw_track < 2:
				var note := NoteEvent.new(); note.tick = _anchor_tick; note.affinity = _side; candidates.append(note)
			elif _draw_track == 4:
				var batch := GhostEvent.new(); batch.tick = _anchor_tick
				if ChartEditEvents.rebind(document.chart(), batch): candidates.append(batch)
		if candidates.is_empty():
			if _draw_track in [2, 3]: notice.emit(_missing_holds(mini(_anchor_tick, tick_at(event.position.x, event.alt_pressed)), maxi(_anchor_tick, tick_at(event.position.x, event.alt_pressed))))
			else: notice.emit("此刻没有 Tuning，无法添加 Ghost")
		else:
			candidates[0].event_id = StudioDocument.new_id("event")
			selected = PackedStringArray([candidates[0].event_id])
			submit("绘制音符", [], candidates.duplicate())
	elif _mode in ["move", "head", "tail", "node"] and not candidates.is_empty():
		submit("调整音符", _before.duplicate(), candidates.duplicate())
	cancel_gesture(false)
	selection_changed.emit()

func cancel_gesture(refresh_preview := true) -> void:
	if refresh_preview and _mode == "rhythm": rhythm_anchor_changed.emit(_rhythm_anchor_before)
	if is_aligning():
		view_start = _alignment_before_view
		_map = document.tempo_map()
		alignment_cancelled.emit()
		_redraw_overlay()
	var had_candidates := not candidates.is_empty()
	if refresh_preview and _mode in ["loop_start", "loop_end"]: loop_changed.emit(_loop_before.x, _loop_before.y)
	_mode = ""
	candidates.clear()
	_before.clear()
	queue_redraw()
	if refresh_preview and had_candidates: candidate_changed.emit()

func is_aligning() -> bool:
	return _mode in ["align_marker", "align_wave"]

func music_label(tick: int) -> String:
	var start := 0
	var bar := 1
	var numerator := 4
	var denominator := 4
	for meter in document.chart().meter_events:
		if meter.tick > tick: break
		var length := document.chart().ppq * 4.0 * numerator / denominator
		bar += ceili(float(meter.tick - start) / length)
		start = meter.tick; numerator = meter.numerator; denominator = meter.denominator
	var beat_ticks := document.chart().ppq * 4.0 / denominator
	var elapsed := floori(float(tick - start) / beat_ticks)
	return "%d:%d" % [bar + floori(float(elapsed) / numerator), posmod(elapsed, numerator) + 1]

func set_waveform(value: PackedVector2Array, duration: float) -> void:
	peaks = value; audio_duration = duration; _peak_levels.clear()
	var previous := peaks
	while previous.size() > 1:
		var level := PackedVector2Array()
		for i in range(0, previous.size(), 2):
			var next := previous[mini(i + 1, previous.size() - 1)]
			level.append(Vector2(minf(previous[i].x, next.x), maxf(previous[i].y, next.y)))
		_peak_levels.append(level); previous = level
	queue_redraw()

func visible_notes(left: float, right: float) -> Array:
	var from_tick := tick_at(left - 12, true)
	var to_tick := tick_at(right + 12, true)
	# 前缀尾点也覆盖从画面左侧之外延伸进来的长 Hold。
	var low := 0
	var high := _prefix_end.size()
	while low < high:
		var middle := (low + high) / 2
		if _prefix_end[middle] < from_tick: low = middle + 1
		else: high = middle
	var result: Array = []
	for index in range(low, _indexed_notes.size()):
		var note = _indexed_notes[index]
		if note.tick > to_tick: break
		if note.tick + note.duration_ticks >= from_tick: result.append(note)
	return result

func format_time(seconds: float) -> String:
	var value := absf(seconds)
	return ("−" if seconds < 0 else "") + "%02d:%06.3f" % [int(value) / 60, fmod(value, 60)]

func _redraw_overlay() -> void:
	if is_instance_valid(_overlay): _overlay.queue_redraw()

func _draw_overlay() -> void:
	for note in recording_notes: _draw_note(note, true, _overlay)
	var x := (playhead - view_start) * pixels_per_second
	_overlay.draw_line(Vector2(x, 0), Vector2(x, size.y), Color("f6d493"), 2)

func _process(delta: float) -> void:
	_flush_browse()
	if _mode not in ["draw", "move", "head", "tail", "node", "box"]: return
	var speed := -maxf(0, 28 - _current.x) if _current.x < 28 else maxf(0, _current.x - size.x + 28)
	if is_zero_approx(speed): return
	view_start += clampf(speed * 8, -600, 600) * delta / pixels_per_second
	manual_browse.emit()
	var motion := InputEventMouseMotion.new(); motion.position = _current; motion.alt_pressed = _last_alt
	_motion(motion)


func _draw_rhythm() -> void:
	for seconds: float in rhythm_raw.get("beats", []):
		var x := (seconds - view_start) * pixels_per_second
		if x >= 0 and x <= size.x: draw_line(Vector2(x, 54), Vector2(x, 59), Color("79b9ff"), 1)
	for seconds: float in rhythm_raw.get("downbeats", []):
		var x := (seconds - view_start) * pixels_per_second
		if x >= 0 and x <= size.x: draw_line(Vector2(x, 48), Vector2(x, 59), Color("d89deb"), 2)
	if rhythm_grid.is_empty(): return
	for region: Dictionary in rhythm_grid.get("regions", []):
		var left := maxf(0, (float(region.start) - view_start) * pixels_per_second)
		var right := minf(size.x, (float(region.end) - view_start) * pixels_per_second)
		if right > left: draw_rect(Rect2(left, WAVE_TOP, right - left, size.y - WAVE_TOP), Color(1, 0.6, 0.2, 0.12))
	var period: float = 60.0 / float(rhythm_grid.bpm)
	var anchor: float = rhythm_grid.anchor
	var first := floori((view_start - anchor) / period)
	var last := ceili((view_start + size.x / pixels_per_second - anchor) / period)
	var stride := maxi(1, ceili(8.0 / (period * pixels_per_second)))
	for index in range(first, last + 1, stride):
		var x := (anchor + index * period - view_start) * pixels_per_second
		var strong: bool = int(rhythm_grid.meter) > 0 and posmod(index, int(rhythm_grid.meter)) == 0
		draw_line(Vector2(x, SECONDS_BOTTOM), Vector2(x, size.y), Color(0.3, 0.95, 0.65, 0.6 if strong else 0.18), 2 if strong else 1)
		draw_rect(Rect2(x - 3, SECONDS_BOTTOM + 1, 6, 6), Color("70e5a6"))
