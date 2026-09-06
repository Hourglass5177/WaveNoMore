class_name StudioDocument
extends RefCounted
## 每条命令仅保存受影响音符的新旧资源；视图选择和候选手势由 Timeline 自己拥有。
signal changed
var song: SongDefinition
var charts: Array[SongChart] = []
var current := 0
var directory := ""
var dirty := false
var revision := 0
var load_errors: PackedStringArray = []
var _histories: Dictionary = {}
var _cursors: Dictionary = {}
var clipboard: Array[NoteEvent] = []
var _history_target := ""

func reset_history() -> void:
	_histories.clear()
	_cursors.clear()
	clipboard.clear()
	_history_target = ""

func chart() -> SongChart:
	return charts[current]

func new_project() -> void:
	song = SongDefinition.new()
	song.song_id = new_id("song")
	song.title = "未命名歌曲"
	song.set_meta("json_source", {"audio": "", "charts": []})
	charts.clear()
	current = 0
	add_difficulty("normal")
	directory = ""
	reset_history()
	load_errors.clear()
	dirty = false

func add_difficulty(id: String, copy_current := false) -> void:
	var data: Dictionary
	if copy_current and not charts.is_empty():
		data = ChartJsonCodec.encode_chart(chart())
		var groups := {}
		for note: Dictionary in data.notes:
			note.id = new_id("note")
			for field in ["group_id", "damage_group_id"]:
				if not note.has(field) or str(note[field]).is_empty(): continue
				var old := str(note[field])
				if not groups.has(old): groups[old] = new_id("group")
				note[field] = groups[old]
	else:
		data = {"format": "minghe-chart", "format_version": 1, "notes": [], "sections": [], "presentation": {"theme_id": "default"}, "timing": {"ppq": 480, "first_beat_offset_ms": 0, "chart_offset_ticks": 0, "end_tick": 7680, "tempo_events": [{"tick": 0, "bpm": 120}], "meter_events": [{"tick": 0, "numerator": 4, "denominator": 4}]}}
	data.merge({"chart_id": new_id("chart"), "song_id": song.song_id, "difficulty_id": id, "difficulty_name": id, "mapper": ""}, true)
	var decoded := ChartJsonCodec.decode_chart(data)
	charts.append(decoded.chart)
	current = charts.size() - 1
	mark_changed()

func offset_sec() -> float:
	var data: Dictionary = chart().get_meta("json_source", {})
	return float(data.get("timing", {}).get("first_beat_offset_ms", 0)) / 1000.0

func tempo_map() -> TempoMap:
	return TempoMap.from_chart(chart(), roundi(offset_sec() * 1000000.0))

func find_note(id: String) -> NoteEvent:
	for note in chart().note_events:
		if note.event_id == id: return note
	return null

func execute(label: String, before: Array, after: Array, metadata_before: Dictionary = {}, metadata_after: Dictionary = {}) -> void:
	var key := chart().chart_id
	_history_target = key
	var history: Array = _histories.get(key, [])
	history.resize(int(_cursors.get(key, 0)))
	history.append({"label": label, "before": before, "after": after, "meta_before": metadata_before, "meta_after": metadata_after})
	_histories[key] = history
	_cursors[key] = history.size()
	_apply(before, after, metadata_after)

func undo(redo := false) -> void:
	var key := "song" if _history_target == "song" else chart().chart_id
	var history: Array = _histories.get(key, [])
	var cursor: int = _cursors.get(key, 0)
	if (redo and cursor >= history.size()) or (not redo and cursor == 0): return
	var command: Dictionary = history[cursor if redo else cursor - 1]
	_cursors[key] = cursor + (1 if redo else -1)
	if key == "song":
		song.set(command.field, command.after if redo else command.before)
		mark_changed()
		return
	_apply(command.before if redo else command.after, command.after if redo else command.before, command.meta_after if redo else command.meta_before)

func _apply(remove: Array, add: Array, metadata: Dictionary) -> void:
	var ids := {}
	for note: NoteEvent in remove: ids[note.event_id] = true
	chart().note_events = chart().note_events.filter(func(n: NoteEvent) -> bool: return not ids.has(n.event_id))
	for note: NoteEvent in add: chart().note_events.append(note.duplicate(true))
	if not metadata.is_empty():
		var decoded := ChartJsonCodec.decode_chart(metadata)
		var replacement: SongChart = decoded.chart
		replacement.note_events = chart().note_events
		charts[current] = replacement
	chart().note_events.sort_custom(func(a: NoteEvent, b: NoteEvent) -> bool: return a.tick < b.tick if a.tick != b.tick else a.event_id < b.event_id)
	mark_changed()

func change_metadata(data: Dictionary) -> void:
	execute("修改谱面属性", [], [], ChartJsonCodec.encode_chart(chart()), data)

func mark_changed() -> void:
	dirty = true
	revision += 1
	changed.emit()

func copy_notes(ids: PackedStringArray) -> void:
	clipboard.clear()
	for id in ids:
		var note := find_note(id)
		if note != null: clipboard.append(note.duplicate(true))

func paste(at_tick: int) -> PackedStringArray:
	var result: PackedStringArray = []
	if clipboard.is_empty(): return result
	var minimum: int = clipboard[0].tick
	var counts := {}
	for note in clipboard:
		minimum = mini(minimum, note.tick)
		if not note.group_id.is_empty(): counts[note.group_id] = int(counts.get(note.group_id, 0)) + 1
	var groups := {}
	var after: Array = []
	for source in clipboard:
		var note := source.duplicate(true) as NoteEvent
		note.event_id = new_id("note")
		note.tick += at_tick - minimum
		for field in ["group_id", "damage_group_id"]:
			var old := str(source.get(field))
			if old.is_empty(): continue
			if field == "group_id" and counts.get(old, 0) != 2:
				note.set(field, "")
				continue
			if not groups.has(old): groups[old] = new_id("group")
			note.set(field, groups[old])
		after.append(note)
		result.append(note.event_id)
	execute("粘贴乐句", [], after)
	return result

static func new_id(prefix: String) -> String:
	return "%s_%s" % [prefix, Crypto.new().generate_random_bytes(8).hex_encode()]

func set_song_field(field: String, value: String) -> void:
	if song.get(field) == value: return
	var history: Array = _histories.get("song", [])
	history.resize(int(_cursors.get("song", 0)))
	history.append({"field": field, "before": song.get(field), "after": value})
	_histories["song"] = history
	_cursors["song"] = history.size()
	_history_target = "song"
	song.set(field, value)
	mark_changed()
