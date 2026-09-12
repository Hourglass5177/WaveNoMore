class_name LevelTimeline
extends Control
## 剪辑操作只在松手时提交一次文档命令；候选帧供预览，无隐式涟漪编辑。
signal seek_requested(time_us: int)
signal selection_changed(object_id: String, track_id: String, item_id: String)
signal candidate_changed(tracks: Array)
signal loop_changed(start_us: int, end_us: int)
signal binding_requested(object_id: String, binding_id: String)
signal selection_set_changed(objects: PackedStringArray, track_id: String, items: PackedStringArray)
signal seek_finished(time_us: int)
signal manual_browse
var document: LevelDocument
var section := "song"
var difficulty := ""
var tempo: TempoMap
var sections: Array[SectionMarker] = []
var waveform := PackedVector2Array()
var waveform_duration := 0.0
var clip_waveforms := {}
var time_us := 0
var pixels_per_second := 100.0
var left_seconds := 0.0
var row_scroll := 0.0
var selected := PackedStringArray()
var folded := {}
var rows: Array[Dictionary] = []
var generated_tracks: Array = []
var selected_object := ""
var selected_track := ""
var snap_ticks := 120
var snap_seconds := 0.1
var loop_start_us := 0
var loop_end_us := 4000000
var _hits: Array[Dictionary] = []
var _drag := {}
var _candidate := {}
var _clipboard: Array = []
var _browse := Vector2.ZERO
var _zoom_pending := 0.0
var _zoom_anchor := 0.0
var _scroll_sync := false
var _hscroll := HScrollBar.new()
var _vscroll := VScrollBar.new()
var _cursor := Control.new()
var _stack := PopupMenu.new()
var _stack_hits: Array = []
var reference_notes: Array = []

const HEADER := 206.0
const RULER := 82.0
const ROW := 24.0
const COLORS := {"property": Color("ddbb77"), "action": Color("988bd6"), "audio": Color("67b7aa"), "visibility": Color("749ac3"), "sequence": Color("b886b9")}

func _init() -> void:
	for control in [_hscroll,_vscroll,_cursor,_stack]:add_child(control)

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL; mouse_default_cursor_shape = Control.CURSOR_ARROW
	clip_contents = true; custom_minimum_size.y = 120
	for bar in [_hscroll, _vscroll]:
		bar.step = 0.01
	_hscroll.value_changed.connect(func(value):
		if _scroll_sync: return
		manual_browse.emit(); left_seconds = value; queue_redraw(); update_cursor())
	_vscroll.value_changed.connect(func(value):
		if _scroll_sync: return
		row_scroll = value; queue_redraw())
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cursor.draw.connect(func():
		var x := x_at(time_us)
		if x >= HEADER and x < size.x - 14: _cursor.draw_line(Vector2(x,0),Vector2(x,size.y-14),Color("ff8977"),2))
	_stack.id_pressed.connect(func(id):
		if id<1000: _choose_hit(_stack_hits[id],_stack_hits[id].rect.get_center(),false,false);_drag.clear();return
		match id:
			1000:copy_selected()
			1001:paste_selected()
			1002:delete_selected()
			1003:split_selected()
	)
	resized.connect(_sync_scrollbars)
	_sync_scrollbars()

func bind(doc: LevelDocument) -> void:
	document = doc
	document.changed.connect(func(kind):
		if kind=="saved": return
		if kind=="project" or document.last_changes.any(func(change): return change.kind in ["objects","tracks","bindings"]): rebuild_rows())
	rebuild_rows()

func rebuild_rows() -> void:
	rows.clear()
	if document == null: return
	for object_data: Dictionary in document.entries("objects"):
		rows.append({"object": object_data, "track": {}})
		if folded.get(object_data.id, false): continue
		for track: Dictionary in document.entries("tracks"):
			if track.object_id == object_data.id and track.section == section:
				rows.append({"object": object_data, "track": track})
		for track: Dictionary in generated_tracks:
			if track.object_id==object_data.id and section=="song":rows.append({"object":object_data,"track":track})
	row_scroll = clampf(row_scroll, 0, maxf(0, rows.size() * ROW - size.y + RULER + 14))
	_sync_scrollbars()
	queue_redraw()

func x_at(us: int) -> float: return HEADER + (float(us) / 1000000.0 - left_seconds) * pixels_per_second
func time_at(x: float) -> int: return roundi((left_seconds + (x - HEADER) / pixels_per_second) * 1000000.0)

func snap(us: int, unsnapped := false) -> int:
	if unsnapped or snap_ticks <= 0: return us
	if section == "song" and tempo != null:
		return tempo.tick_to_us(roundi(tempo.us_to_tick(us) / float(snap_ticks)) * snap_ticks)
	return roundi(snappedf(float(us) / 1000000.0, snap_seconds) * 1000000.0)

func focus_time(us: int) -> void:
	if x_at(us) < HEADER + 10 or x_at(us) > size.x - 20:
		left_seconds = float(us) / 1000000.0 - (size.x - HEADER) * 0.25 / pixels_per_second
		queue_redraw(); _sync_scrollbars()
	update_cursor()

func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color("151c29"))
	_hits.clear()
	var step := 1.0
	while step * pixels_per_second < 65: step *= 2.0
	while step * pixels_per_second > 180: step *= 0.5
	var second := floorf(left_seconds / step) * step
	while x_at(roundi(second * 1000000)) < size.x:
		var x := x_at(roundi(second * 1000000))
		if x >= HEADER:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color("344050"), 1)
			draw_string(font, Vector2(x + 4, 16), "%0.1fs" % second, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("aab9ca"))
		second += step
	if tempo != null and section == "song":
		var tick_step := maxi(tempo.ppq, snap_ticks)
		var tick := floori(tempo.us_to_tick(time_at(HEADER)) / tick_step) * tick_step
		var limit := tempo.us_to_tick(time_at(size.x))
		while tick < limit:
			var x := x_at(tempo.tick_to_us(tick))
			if x >= HEADER:
				draw_line(Vector2(x, 21), Vector2(x, 28), Color("758292"))
				draw_string(font, Vector2(x + 3, 31), "♩%d" % (tick / tempo.ppq + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("8d9baa"))
			tick += tick_step
	if not waveform.is_empty() and waveform_duration > 0.0 and section == "song":
		for x in range(int(HEADER), int(size.x), 2):
			var ratio := float(time_at(x)) / 1000000.0 / waveform_duration
			if ratio < 0.0 or ratio >= 1.0: continue
			var peak := waveform[clampi(int(ratio * waveform.size()), 0, waveform.size() - 1)]
			draw_line(Vector2(x, 64 + peak.x * 11), Vector2(x, 64 + peak.y * 11), Color("426d70"))
	if section == "song" and tempo != null:
		for marker in sections:
			var x := x_at(tempo.tick_to_us(marker.tick))
			if x < HEADER or x > size.x: continue
			draw_line(Vector2(x, 52), Vector2(x, 76), Color("d5ac62"), 2)
			draw_string(font, Vector2(x + 4, 66), marker.label, HORIZONTAL_ALIGNMENT_LEFT, 120, 11, Color("e2c48a"))
	var loop_rect := Rect2(x_at(loop_start_us), 76, x_at(loop_end_us) - x_at(loop_start_us), 6)
	draw_rect(loop_rect.intersection(Rect2(HEADER, 76, maxf(0, size.x - HEADER), 6)), Color(0.3, 0.7, 0.6, 0.35))
	for index in rows.size():
		var y := RULER + index * ROW - row_scroll
		if y < RULER - ROW or y > size.y: continue
		var row: Dictionary = rows[index]
		var track: Dictionary = _candidate.get(row.track.get("id", ""), row.track)
		var object_data: Dictionary = row.object
		draw_rect(Rect2(0, y, HEADER, ROW), Color("25344a") if object_data.id == selected_object else (Color("1e2737") if track.is_empty() else Color("18212f")))
		draw_line(Vector2(0, y + ROW), Vector2(size.x, y + ROW), Color("303a4a"))
		var title := ("▸ " if folded.get(object_data.id, false) else "▾ ") + str(object_data.name)
		if not track.is_empty(): title = "   " + str(LevelFormat.PROPERTIES.get(track.property, {"action": "动作", "audio": "音频", "visibility": "显示区间", "sequence": "演出片段"}.get(track.type, track.property))) + (" · 共用" if track.difficulties.is_empty() else " · " + ",".join(track.difficulties))
		if track.get("generated",false):title="   BOSS "+str({"action":"动作","effect":"特效","audio":"音效"}.get(track.type,track.type))+" · 自动编排"
		draw_string(font, Vector2(8, y + 17), title, HORIZONTAL_ALIGNMENT_LEFT, HEADER - 16, 12, Color("dbe1ea") if track.is_empty() or LevelFormat.visible_in(track, difficulty) else Color("687689"))
		var summary: bool = track.is_empty() and folded.get(object_data.id,false)
		if summary:
			track={"id":"","type":"property","property":"","keys":[],"clips":[],"difficulties":[]}
			for source: Dictionary in document.entries("tracks")+generated_tracks:
				if source.object_id!=object_data.id or source.section!=section: continue
				for item: Dictionary in source.keys:
					var copy:=item.duplicate(); copy._track=source.id; track.keys.append(copy)
				for item: Dictionary in source.clips:
					var copy:=item.duplicate(); copy._track=source.id; track.clips.append(copy)
		if track.is_empty(): continue
		var color: Color = COLORS.get(track.type, COLORS.property)
		for key: Dictionary in track.keys:
			var x := x_at(int(key.time_us))
			if x < HEADER or x > size.x: continue
			var points := PackedVector2Array([Vector2(x, y + 4), Vector2(x + 6, y + 12), Vector2(x, y + 20), Vector2(x - 6, y + 12)])
			draw_colored_polygon(points, Color.WHITE if key.id in selected else color)
			_hits.append({"rect": Rect2(x - 8, y + 5, 16, 20), "track": key.get("_track",track.id), "id": key.id, "kind": "key", "object": object_data.id})
		for clip: Dictionary in track.clips:
			var rect := Rect2(x_at(int(clip.start_us)), y + 4, float(clip.duration_us) / 1000000.0 * pixels_per_second, ROW - 8)
			var visible_rect := rect.intersection(Rect2(HEADER, RULER, maxf(0, size.x - HEADER), maxf(0, size.y - RULER)))
			if visible_rect.size.x <= 0: continue
			draw_rect(visible_rect, color.darkened(0.35)); draw_rect(visible_rect, Color.WHITE if clip.id in selected else color, false, 1)
			if track.type=="audio" and clip_waveforms.has(clip.asset):
				var wave:Dictionary=clip_waveforms[clip.asset]
				for pixel in range(ceili(visible_rect.position.x),floori(visible_rect.end.x),2):
					var seconds:=float(int(clip.offset_us)+(time_at(pixel)-int(clip.start_us))*float(clip.rate))/1000000.0
					if clip.loop:seconds=fposmod(seconds,float(wave.duration))
					if seconds<0 or seconds>=float(wave.duration):continue
					var peak:Vector2=wave.peaks[mini(wave.peaks.size()-1,floori(seconds/float(wave.duration)*wave.peaks.size()))]
					draw_line(Vector2(pixel,y+ROW*0.5+peak.x*10),Vector2(pixel,y+ROW*0.5+peak.y*10),Color(0.6,0.95,0.85,0.75))
			draw_string(font, visible_rect.position + Vector2(6, 16), str(clip.name), HORIZONTAL_ALIGNMENT_LEFT, maxf(0, visible_rect.size.x - 12), 11, Color.WHITE)
			var fade_in := float(clip.get("fade_in_us", 0)) / 1000000.0 * pixels_per_second
			var fade_out := float(clip.get("fade_out_us", 0)) / 1000000.0 * pixels_per_second
			if rect.position.x >= HEADER: draw_line(rect.position + Vector2(0, rect.size.y), rect.position + Vector2(fade_in, 0), color)
			draw_line(rect.end - Vector2(fade_out, rect.size.y), rect.end, color)
			_hits.append({"rect": visible_rect.grow_individual(4,0,4,0), "full_rect": rect, "track": clip.get("_track",track.id), "id": clip.id, "kind": "clip", "object": object_data.id})
	draw_rect(Rect2(0, 0, HEADER, RULER), Color("1c283b"))
	draw_string(font, Vector2(12, 24), "对象 / 动画轨", HORIZONTAL_ALIGNMENT_LEFT, HEADER - 20, 14, Color.WHITE)
	draw_string(font, Vector2(12, 46), "谱面参考 · 只读", HORIZONTAL_ALIGNMENT_LEFT, HEADER - 20, 11, Color("99adbf"))
	if _drag.get("mode", "") == "box": draw_rect(Rect2(_drag.origin, _drag.current - _drag.origin).abs(), Color(0.55, 0.7, 1.0, 0.25))
	draw_string(font,Vector2(12,70),"歌曲波形",HORIZONTAL_ALIGNMENT_LEFT,HEADER-20,11,Color("99adbf"))
	# 零点之前保留 BOSS 提前动作的可编辑时间。
	if x_at(0) >= HEADER and x_at(0) <= size.x:
		draw_line(Vector2(x_at(0),0),Vector2(x_at(0),size.y),Color("d4bf92"),2)
	for note: Dictionary in reference_notes:
		var x := x_at(int(note.time_us))
		if section == "song" and x >= HEADER and x < size.x-14:
			draw_line(Vector2(x,37),Vector2(x,48),Color("bc8ed6"),2)

func update_cursor() -> void:
	_cursor.queue_redraw()

func _sync_scrollbars() -> void:
	if not is_inside_tree(): return
	_scroll_sync = true
	_hscroll.position = Vector2(HEADER,size.y-14); _hscroll.size = Vector2(maxf(1,size.x-HEADER-14),14)
	_vscroll.position = Vector2(size.x-14,RULER); _vscroll.size = Vector2(14,maxf(1,size.y-RULER-14))
	var page := maxf(1,size.x-HEADER-14)/pixels_per_second
	var end := maxf(waveform_duration,float(time_us)/1000000.0)
	var start := minf(-5,left_seconds)
	if document != null:
		for track: Dictionary in document.entries("tracks") + generated_tracks:
			if track.section != section: continue
			for key: Dictionary in track.keys:
				start = minf(start,float(key.time_us)/1000000.0); end = maxf(end,float(key.time_us)/1000000.0)
			for clip: Dictionary in track.clips:
				start = minf(start,float(clip.start_us)/1000000.0); end = maxf(end,float(clip.start_us+clip.duration_us)/1000000.0)
	_hscroll.min_value = start; _hscroll.max_value = maxf(end+5,left_seconds+page); _hscroll.page = page; _hscroll.value = left_seconds
	_vscroll.max_value = maxf(rows.size()*ROW,size.y-RULER-14); _vscroll.page = maxf(1,size.y-RULER-14); _vscroll.value = row_scroll
	_scroll_sync = false

func _queue_browse(pixels: Vector2, zoom_delta := 0.0, anchor := 0.0) -> void:
	# 手势的起点不能被另外一次触摸板滚动改写。
	if not _drag.is_empty(): return
	if pixels.x != 0 or zoom_delta != 0: manual_browse.emit()
	_browse += pixels; _zoom_pending += zoom_delta; _zoom_anchor = anchor

func _flush_browse() -> void:
	if _browse == Vector2.ZERO and _zoom_pending == 0: return
	left_seconds += _browse.x / pixels_per_second
	row_scroll = clampf(row_scroll+_browse.y,0,maxf(0,rows.size()*ROW-size.y+RULER+14))
	if _zoom_pending != 0:
		var anchor := float(time_at(_zoom_anchor))/1000000.0
		pixels_per_second = clampf(pixels_per_second*pow(1.2,_zoom_pending),1,1600)
		left_seconds = anchor-(_zoom_anchor-HEADER)/pixels_per_second
	_browse = Vector2.ZERO; _zoom_pending = 0
	_sync_scrollbars(); queue_redraw(); update_cursor()

func _process(delta: float) -> void:
	_flush_browse()
	if _drag.get("mode","") in ["move","trim_start","trim_end","box"] and _drag.get("moved",false):
		var at: Vector2 = _drag.get("current",_drag.origin)
		var speed := clampf((at.x-(size.x-38))/24,0,1)-clampf((HEADER+24-at.x)/24,0,1)
		if speed != 0:
			left_seconds += speed*400*delta/pixels_per_second
			var motion := InputEventMouseMotion.new(); motion.position=at; motion.alt_pressed=Input.is_key_pressed(KEY_ALT)
			_gui_input(motion); _sync_scrollbars(); update_cursor()

func _notify_selection() -> void:
	var ids := PackedStringArray()
	for track: Dictionary in document.entries("tracks"):
		if (track.keys+track.clips).any(func(item): return item.id in selected) and not track.object_id in ids: ids.append(track.object_id)
	if ids.is_empty() and not selected_object.is_empty(): ids.append(selected_object)
	selection_set_changed.emit(ids,selected_track,selected.duplicate())
	queue_redraw()

func _choose_hit(hit: Dictionary, at: Vector2, additive: bool, double_click: bool) -> void:
	var generated := LevelFormat.find(generated_tracks,hit.track)
	if not generated.is_empty():
		binding_requested.emit(hit.object,str(LevelFormat.find(generated.clips,hit.id).get("binding_id",""))); return
	selected_object=hit.object; selected_track=hit.track
	if additive:
		if hit.id in selected: selected.remove_at(selected.find(hit.id))
		else: selected.append(hit.id)
	elif not hit.id in selected: selected=PackedStringArray([hit.id])
	_notify_selection()
	if additive: return
	var track := document.find("tracks",hit.track)
	if track.locked or not document.editable_object(hit.object) or not LevelFormat.visible_in(track,difficulty): return
	var mode := "move"
	if hit.kind == "clip":
		var start_distance := absf(at.x-hit.full_rect.position.x)
		var end_distance := absf(at.x-hit.full_rect.end.x)
		if minf(start_distance,end_distance)<8: mode="trim_start" if start_distance<end_distance else "trim_end"
	var item := LevelFormat.find(track.keys if hit.kind=="key" else track.clips,hit.id)
	var reference := int(item.time_us if hit.kind=="key" else item.start_us)
	if double_click: seek_requested.emit(reference); seek_finished.emit(reference); focus_time(reference); return
	_drag={"mode":mode,"origin":at,"anchor":time_at(at.x),"reference":reference,"before":_selected_tracks(),"hit":hit,"left":left_seconds,"scroll":row_scroll,"moved":false}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventPanGesture:
		_queue_browse(event.delta*32); accept_event(); return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]:
			if event.pressed:
				var vertical: bool = event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]
				var amount: float = (-1 if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_LEFT] else 1)*event.factor
				if vertical and event.ctrl_pressed: _queue_browse(Vector2.ZERO,-amount,event.position.x)
				else: _queue_browse(Vector2(0,amount*48) if vertical else Vector2(amount*100,0))
			accept_event(); return
		if event.pressed: _flush_browse(); grab_focus()
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and _drag.is_empty():
				manual_browse.emit(); _drag={"mode":"pan","origin":event.position,"left":left_seconds,"scroll":row_scroll}
			elif not event.pressed and _drag.get("mode","")=="pan": _finish_drag()
			accept_event(); return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_stack_hits=_hits.filter(func(hit): return hit.rect.has_point(event.position))
			_stack_hits.reverse(); _stack.clear()
			for hit: Dictionary in _stack_hits:
				var track:=document.find("tracks",hit.track)
				var item:=LevelFormat.find(track.get("keys",[])+track.get("clips",[]),hit.id)
				_stack.add_item("选择 · "+str(item.get("name",LevelFormat.PROPERTIES.get(track.get("property",""),"自动编排")))+" · %.3f s"%(float(item.get("time_us",item.get("start_us",0)))/1000000))
			_stack.add_separator()
			for pair in [["复制选中事件",1000],["粘贴到游标",1001],["删除选中事件",1002],["在游标处分割",1003]]:_stack.add_item(pair[0],pair[1])
			_stack.position=Vector2i(get_global_mouse_position()); _stack.popup()
			return
		if event.button_index != MOUSE_BUTTON_LEFT: return
		if not event.pressed: _finish_drag(); accept_event(); return
		if not _drag.is_empty(): return
		if event.position.x < HEADER:
			var index := floori((event.position.y-RULER+row_scroll)/ROW)
			if event.position.y>=RULER and index>=0 and index<rows.size():
				var row: Dictionary=rows[index]
				if row.track.is_empty() and event.position.x<28:
					folded[row.object.id]=not folded.get(row.object.id,false); rebuild_rows(); return
				selected_object=row.object.id; selected_track=str(row.track.get("id","")); selected.clear(); _notify_selection()
			return
		if event.position.y < RULER:
			manual_browse.emit()
			_drag={"mode":"loop" if event.shift_pressed else "seek","start":snap(time_at(event.position.x),event.alt_pressed),"loop_before":Vector2i(loop_start_us,loop_end_us)}
			if not event.shift_pressed: seek_requested.emit(time_at(event.position.x))
			return
		for index in range(_hits.size()-1,-1,-1):
			if _hits[index].rect.has_point(event.position):
				_choose_hit(_hits[index],event.position,event.shift_pressed or event.ctrl_pressed,event.double_click); return
		var before_selection := selected.duplicate()
		if not (event.shift_pressed or event.ctrl_pressed): selected.clear()
		_drag={"mode":"box","origin":event.position,"current":event.position,"previous":selected.duplicate(),"selection_before":before_selection,"left":left_seconds,"scroll":row_scroll,"moved":false}
		_notify_selection()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_drag.current=event.position
		if _drag.has("moved"):
			_drag.moved = _drag.moved or event.position.distance_to(_drag.origin)>=6
			if not _drag.moved: return
		match str(_drag.mode):
			"pan":
				left_seconds=_drag.left-(event.position.x-_drag.origin.x)/pixels_per_second
				row_scroll=clampf(_drag.scroll-(event.position.y-_drag.origin.y),0,maxf(0,rows.size()*ROW-size.y+RULER+14))
			"seek": seek_requested.emit(time_at(event.position.x))
			"loop":
				var end := snap(time_at(event.position.x),event.alt_pressed)
				loop_start_us=mini(end,_drag.start); loop_end_us=maxi(end,_drag.start); loop_changed.emit(loop_start_us,loop_end_us)
			"box":
				_drag.current=event.position; selected=_drag.previous.duplicate()
				var box := Rect2(_drag.origin,event.position-_drag.origin).abs()
				for hit: Dictionary in _hits:
					if box.intersects(hit.rect) and not hit.id in selected and LevelFormat.find(generated_tracks,hit.track).is_empty(): selected.append(hit.id)
				_notify_selection()
			_:
				var delta := time_at(event.position.x)-int(_drag.anchor)
				if _drag.mode=="move": delta=snap(int(_drag.reference)+delta,event.alt_pressed)-int(_drag.reference)
				_candidate.clear()
				for before: Dictionary in _drag.before:
					var track := before.duplicate(true)
					for key: Dictionary in track.keys:
						if _drag.mode=="move" and key.id in selected: key.time_us=int(key.time_us)+delta
					for clip: Dictionary in track.clips:
						if not clip.id in selected: continue
						if _drag.mode!="move" and clip.id!=_drag.hit.id: continue
						match str(_drag.mode):
							"trim_start":
								var start := mini(snap(int(clip.start_us)+delta,event.alt_pressed),int(clip.start_us)+int(clip.duration_us)-1000)
								start=maxi(start,int(clip.start_us)-roundi(float(clip.offset_us)/float(clip.rate)))
								var trim := start-int(clip.start_us)
								clip.start_us=start; clip.duration_us-=trim; clip.offset_us=int(clip.offset_us)+roundi(trim*float(clip.rate))
							"trim_end": clip.duration_us=maxi(1000,snap(int(clip.start_us)+int(clip.duration_us)+delta,event.alt_pressed)-int(clip.start_us))
							_: clip.start_us=int(clip.start_us)+delta
					_candidate[track.id]=track
				candidate_changed.emit(_candidate.values())
		_sync_scrollbars(); update_cursor(); queue_redraw(); accept_event()
	elif event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: cancel_drag(); accept_event()

func _selected_tracks() -> Array:
	return document.entries("tracks").filter(func(track): return not track.locked and document.editable_object(track.object_id) and LevelFormat.visible_in(track,difficulty) and (track.keys.any(func(key): return key.id in selected) or track.clips.any(func(clip): return clip.id in selected))).duplicate(true)

func _finish_drag() -> void:
	if _drag.get("mode","")=="seek": seek_finished.emit(time_us)
	if not _candidate.is_empty():
		var before: Array = _drag.before; var after: Array = _candidate.values().duplicate(true)
		_drag.clear(); _candidate.clear(); candidate_changed.emit([])
		if before != after: document.replace("移动或裁剪时间线内容", "tracks", before, after)
	_drag.clear(); queue_redraw()

func cancel_drag() -> void:
	if _drag.is_empty() and _candidate.is_empty(): return
	if _drag.has("left"): left_seconds=_drag.left; row_scroll=_drag.scroll
	if _drag.has("selection_before"): selected=_drag.selection_before; _notify_selection()
	if _drag.get("mode","")=="loop":
		loop_start_us=_drag.loop_before.x; loop_end_us=_drag.loop_before.y; loop_changed.emit(loop_start_us,loop_end_us)
	_browse=Vector2.ZERO; _zoom_pending=0; _sync_scrollbars(); update_cursor()
	_drag.clear(); _candidate.clear(); candidate_changed.emit([]); queue_redraw()

func delete_selected() -> void:
	var before := _selected_tracks(); var after := before.duplicate(true)
	for track: Dictionary in after:
		track.keys = track.keys.filter(func(key): return not key.id in selected)
		track.clips = track.clips.filter(func(clip): return not clip.id in selected)
	if not before.is_empty(): document.replace("删除时间线选区", "tracks", before, after)
	selected.clear(); _notify_selection()

func split_selected() -> void:
	var before := _selected_tracks(); var after := before.duplicate(true)
	for track: Dictionary in after:
		var additions := []
		for clip: Dictionary in track.clips:
			if not clip.id in selected or time_us <= int(clip.start_us) or time_us >= int(clip.start_us) + int(clip.duration_us): continue
			var other := clip.duplicate(true); other.id = LevelFormat.id("clip"); other.start_us = time_us
			other.duration_us = int(clip.start_us) + int(clip.duration_us) - time_us
			other.offset_us = int(clip.offset_us) + roundi((time_us - int(clip.start_us)) * float(clip.rate))
			other.fade_in_us = 0; clip.fade_out_us = 0; clip.duration_us = time_us - int(clip.start_us)
			additions.append(other)
		track.clips.append_array(additions)
	if before != after: document.replace("在游标处拆分片段", "tracks", before, after)

func copy_selected() -> void:
	_clipboard = _selected_tracks()
	for track: Dictionary in _clipboard:
		track.keys = track.keys.filter(func(key): return key.id in selected)
		track.clips = track.clips.filter(func(clip): return clip.id in selected)

func paste_selected() -> void:
	if _clipboard.is_empty(): return
	var earliest := 9223372036854775807
	for track: Dictionary in _clipboard:
		for key: Dictionary in track.keys: earliest = mini(earliest, int(key.time_us))
		for clip: Dictionary in track.clips: earliest = mini(earliest, int(clip.start_us))
	var before := []; var after := []; selected.clear()
	for source: Dictionary in _clipboard:
		var track := document.find("tracks", source.id)
		if track.is_empty(): continue
		before.append(track.duplicate(true)); track = track.duplicate(true)
		for source_key: Dictionary in source.keys:
			var key := source_key.duplicate(true); key.id = LevelFormat.id("key"); key.time_us += time_us - earliest
			track.keys.append(key); selected.append(key.id)
		for source_clip: Dictionary in source.clips:
			var clip := source_clip.duplicate(true); clip.id = LevelFormat.id("clip"); clip.start_us += time_us - earliest
			track.clips.append(clip); selected.append(clip.id)
		after.append(track)
	if not after.is_empty(): document.replace("粘贴时间线内容", "tracks", before, after)
	_notify_selection()
