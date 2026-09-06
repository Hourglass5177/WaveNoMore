class_name StudioTimeline
extends Control
## 秒坐标显示、音乐 tick 编辑；手势只更新候选集合，释放时提交增量命令。
signal selection_changed
signal seek_requested(seconds: float)
signal candidate_changed
signal context_requested(position: Vector2)
signal gesture_started
signal seek_finished(seconds: float)
signal loop_changed(start: float, end: float)
signal view_changed
signal manual_browse
var document: StudioDocument
var selected := PackedStringArray()
var candidates: Array[NoteEvent] = []
var view_start := -2.0:
	set(value):
		if is_equal_approx(view_start, value): return
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
var _indexed_notes: Array[NoteEvent] = []
var _prefix_end := PackedInt64Array()
const RULER := 108.0
var row_height: float:
	get: return maxf(28.0, (size.y - RULER) / 2.0)

func _ready() -> void:
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
	if document.change_kind in [&"metadata", &"presentation"]: return
	_map = document.tempo_map()
	_indexed_notes.assign(document.chart().note_events)
	_indexed_notes.sort_custom(func(a: NoteEvent, b: NoteEvent) -> bool: return a.tick < b.tick)
	_prefix_end.clear()
	var end := -9223372036854775807
	for note in _indexed_notes:
		end = maxi(end, note.tick + note.duration_ticks)
		_prefix_end.append(end)
	queue_redraw()

func x_at(tick: int) -> float:
	return (float(_map.tick_to_us(tick)) / 1000000.0 - view_start) * pixels_per_second

func tick_at(x: float, free := false) -> int:
	var tick := _map.us_to_tick(roundi((view_start + x / pixels_per_second) * 1000000.0))
	return roundi(tick) if free or snap_ticks == 0 else roundi(tick / snap_ticks) * snap_ticks

func note_rect(note: NoteEvent) -> Rect2:
	var x := x_at(note.tick)
	var width := maxf(12, x_at(note.tick + note.duration_ticks) - x + 12)
	return Rect2(x - 6, RULER + note.affinity * row_height + 6, width, row_height - 12)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("141a25"))
	if document == null: return
	var font := ThemeDB.fallback_font
	var zero_x := -view_start * pixels_per_second
	if zero_x > 0: draw_rect(Rect2(0, 0, minf(zero_x, size.x), size.y), Color(0.24, 0.22, 0.3, 0.2))
	var end_sec := view_start + size.x / pixels_per_second
	if loop_range.y > loop_range.x:
		draw_rect(Rect2((loop_range.x - view_start) * pixels_per_second, 0, (loop_range.y - loop_range.x) * pixels_per_second, 24), Color(0.75, 0.58, 0.25, 0.3 if loop_enabled else 0.1))
	for side in 2:
		draw_rect(Rect2(0, RULER + side * row_height, size.x, row_height), Color("211d25") if side == 0 else Color("1b2431"))
		draw_string(font, Vector2(8, RULER + side * row_height + 17), "生钟 / F" if side == 0 else "死钟 / J", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("969fb1"))
	var second_step := maxf(0.25, pow(2, ceil(log(70.0 / pixels_per_second) / log(2.0))))
	var seconds: float = floor(view_start / second_step) * second_step
	while seconds <= end_sec:
		var x := (seconds - view_start) * pixels_per_second
		draw_line(Vector2(x, 0), Vector2(x, 24), Color("526077"))
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
		draw_line(Vector2(x, 25), Vector2(x, size.y), Color(0.4, 0.5, 0.65, 0.28 if beat else 0.1))
		if beat: draw_string(font, Vector2(x + 2, 39), music_label(tick), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9da8bc"))
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
			draw_line(Vector2(x, 70 - high * 25), Vector2(x, 70 - low * 25), Color("659093"))
	for tempo in document.chart().tempo_events:
		draw_string(font, Vector2(x_at(tempo.tick - document.chart().chart_offset_ticks) + 3, 104), "♩ %.2f" % tempo.bpm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("d4ae70"))
	for section in document.chart().sections:
		draw_string(font, Vector2(x_at(section.tick) + 3, 54), section.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ddc9a0"))
	if zero_x >= 0 and zero_x <= size.x:
		draw_line(Vector2(zero_x, 0), Vector2(zero_x, size.y), Color("a8cfdd"), 2)
		draw_string(font, Vector2(zero_x + 4, 55), "音乐起点", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a8cfdd"))
	var beat_x := (document.offset_sec() - view_start) * pixels_per_second
	if beat_x >= 0 and beat_x <= size.x:
		draw_string(font, Vector2(beat_x + 4, 88), "首拍", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ddc9a0"))
	for endpoint in [loop_range.x, loop_range.y]:
		var x: float = (endpoint - view_start) * pixels_per_second
		draw_line(Vector2(x, 0), Vector2(x, 24), Color("d4ae70"), 3)
	var hidden := {}
	for note in candidates: hidden[note.event_id] = true
	for note in visible_notes(0, size.x):
		if not hidden.has(note.event_id): _draw_note(note, false)
	for note in candidates: _draw_note(note, true)
	if _mode == "box":
		var rect := Rect2(_down, _current - _down).abs()
		draw_rect(rect, Color(0.45, 0.65, 1, 0.15))
		draw_rect(rect, Color("8ca7d1"), false)

func _draw_note(note: NoteEvent, ghost: bool, target: CanvasItem = self) -> void:
	var rect := note_rect(note)
	if rect.end.x < 0 or rect.position.x > size.x: return
	var color := Color("be645a") if note.affinity == 0 else Color("7194bb")
	if ghost: color.a = 0.65
	target.draw_rect(rect, color)
	if selected.has(note.event_id) or ghost:
		target.draw_rect(rect.grow(2), Color("ffdd9d"), false, 2)
	if note.duration_ticks > 0:
		target.draw_line(rect.position + Vector2(6, 0), rect.position + Vector2(6, rect.size.y), Color.WHITE, 2)
		target.draw_line(rect.end - Vector2(6, rect.size.y), rect.end - Vector2(6, 0), Color.WHITE, 2)

func _hit(pos: Vector2) -> NoteEvent:
	var visible := visible_notes(pos.x - 14, pos.x + 14)
	for i in range(visible.size() - 1, -1, -1):
		var note := visible[i]
		if note_rect(note).grow(4).has_point(pos): return note
	return null

func _gui_input(event: InputEvent) -> void:
	if document == null: return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			manual_browse.emit()
			var direction := -1 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if mouse.ctrl_pressed:
				var anchor := view_start + mouse.position.x / pixels_per_second
				pixels_per_second = clampf(pixels_per_second * pow(1.2, -direction), 12, 3000)
				view_start = anchor - mouse.position.x / pixels_per_second
			else: view_start += direction * 100.0 / pixels_per_second
			queue_redraw()
			accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
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

func _begin(event: InputEventMouseButton) -> void:
	gesture_started.emit()
	_down = event.position
	_current = _down
	_anchor_tick = tick_at(_down.x, event.alt_pressed)
	candidates.clear()
	_before.clear()
	_last_alt = event.alt_pressed
	if _down.y < 24:
		_loop_before = loop_range
		for index in 2:
			if absf(_down.x - ((loop_range.x if index == 0 else loop_range.y) - view_start) * pixels_per_second) < 7:
				_mode = "loop_start" if index == 0 else "loop_end"; return
	if _down.y < RULER:
		_mode = "seek"
		seek_requested.emit(view_start + _down.x / pixels_per_second)
		return
	if _down.y >= RULER + row_height * 2: return
	var hit := _hit(_down)
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
		if hit.duration_ticks > 0:
			if absf(_down.x - x_at(hit.tick)) <= 8: _mode = "head"
			elif absf(_down.x - x_at(hit.tick + hit.duration_ticks)) <= 8: _mode = "tail"
		for id in selected:
			var note := document.find_note(id)
			if note != null and (_mode == "move" or note == hit): _before.append(note.duplicate(true))
		selection_changed.emit()
	else:
		_mode = "draw"
		_side = clampi(int((_down.y - RULER) / row_height), 0, 1)
	queue_redraw()

func _motion(event: InputEventMouseMotion) -> void:
	_current = event.position
	_last_alt = event.alt_pressed
	if _mode == "pan": view_start -= event.relative.x / pixels_per_second
	elif _mode == "seek": seek_requested.emit(view_start + _current.x / pixels_per_second)
	elif _mode in ["loop_start", "loop_end"]:
		var seconds := view_start + _current.x / pixels_per_second
		loop_changed.emit(minf(seconds, loop_range.y - 0.001) if _mode == "loop_start" else loop_range.x, maxf(seconds, loop_range.x + 0.001) if _mode == "loop_end" else loop_range.y)
	elif _mode == "draw":
		var note := NoteEvent.new()
		note.event_id = "candidate"
		note.affinity = _side
		note.tick = _anchor_tick
		if absf(_current.x - _down.x) >= 6:
			var end := tick_at(_current.x, event.alt_pressed)
			note.tick = mini(end, _anchor_tick)
			note.kind = GameplayTypes.NoteKind.HOLD
			note.duration_ticks = maxi(1 if event.alt_pressed else maxi(1, snap_ticks), absi(end - _anchor_tick))
		candidates.assign([note])
	elif _mode in ["move", "head", "tail"]:
		if _current.distance_to(_down) < 6: return
		candidates.clear()
		var delta := tick_at(_current.x, event.alt_pressed) - _anchor_tick
		var sides := {}
		for old: NoteEvent in _before: sides[old.affinity] = true
		for old: NoteEvent in _before:
			var note := old.duplicate(true) as NoteEvent
			var minimum := 1 if event.alt_pressed else maxi(1, snap_ticks)
			if _mode == "head":
				note.tick = mini(old.tick + delta, old.tick + old.duration_ticks - minimum)
				note.duration_ticks = old.tick + old.duration_ticks - note.tick
			elif _mode == "tail": note.duration_ticks = maxi(minimum, old.duration_ticks + delta)
			else:
				note.tick += delta
				if sides.size() == 1: note.affinity = clampi(int((_current.y - RULER) / row_height), 0, 1)
			candidates.append(note)
	if not _mode.is_empty():
		queue_redraw()
		if _mode in ["draw", "move", "head", "tail"]: candidate_changed.emit()

func _finish(event: InputEventMouseButton) -> void:
	if _mode == "seek": seek_finished.emit(view_start + event.position.x / pixels_per_second)
	if _mode == "box":
		var rect := Rect2(_down, event.position - _down).abs()
		for note in visible_notes(rect.position.x - 14, rect.end.x + 14):
			if rect.intersects(note_rect(note)) and not selected.has(note.event_id): selected.append(note.event_id)
	elif _mode == "draw":
		if candidates.is_empty():
			var note := NoteEvent.new()
			note.tick = _anchor_tick
			note.affinity = _side
			candidates.append(note)
		candidates[0].event_id = StudioDocument.new_id("note")
		selected = PackedStringArray([candidates[0].event_id])
		document.execute("绘制音符", [], candidates.duplicate())
	elif _mode in ["move", "head", "tail"] and not candidates.is_empty():
		document.execute("调整音符", _before.duplicate(), candidates.duplicate())
	cancel_gesture(false)
	selection_changed.emit()

func cancel_gesture(refresh_preview := true) -> void:
	var had_candidates := not candidates.is_empty()
	if refresh_preview and _mode in ["loop_start", "loop_end"]: loop_changed.emit(_loop_before.x, _loop_before.y)
	_mode = ""
	candidates.clear()
	_before.clear()
	queue_redraw()
	if refresh_preview and had_candidates: candidate_changed.emit()

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

func visible_notes(left: float, right: float) -> Array[NoteEvent]:
	var from_tick := tick_at(left - 12, true)
	var to_tick := tick_at(right + 12, true)
	# 前缀尾点也覆盖从画面左侧之外延伸进来的长 Hold。
	var low := 0
	var high := _prefix_end.size()
	while low < high:
		var middle := (low + high) / 2
		if _prefix_end[middle] < from_tick: low = middle + 1
		else: high = middle
	var result: Array[NoteEvent] = []
	for index in range(low, _indexed_notes.size()):
		var note := _indexed_notes[index]
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
	if _mode not in ["draw", "move", "head", "tail", "box"]: return
	var speed := -maxf(0, 28 - _current.x) if _current.x < 28 else maxf(0, _current.x - size.x + 28)
	if is_zero_approx(speed): return
	view_start += clampf(speed * 8, -600, 600) * delta / pixels_per_second
	manual_browse.emit()
	var motion := InputEventMouseMotion.new(); motion.position = _current; motion.alt_pressed = _last_alt
	_motion(motion)
