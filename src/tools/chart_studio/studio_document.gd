class_name StudioDocument
extends RefCounted
## 每条命令仅保存受影响音符的新旧资源；视图选择和候选手势由 Timeline 自己拥有。
signal changed
## 最近一次通知的用途；保留无参数信号，视图按用途决定局部更新。
var change_kind: StringName = &"project"
var affected_ids := PackedStringArray()
var song: SongDefinition
var charts: Array[SongChart] = []
var current := 0
var directory := ""
var dirty := false
var revision := 0
var load_errors: PackedStringArray = []
var _histories: Dictionary = {}
var _cursors: Dictionary = {}
var clipboard: Array = []
var _history_target := ""
var _event_index := {}
var _index_chart: SongChart
var _index_revision := -1

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
		var copied := chart().duplicate(true) as SongChart
		ChartEditEvents.replace(copied, ChartEditEvents.all(copied), duplicate_events(ChartEditEvents.all(chart()), 0))
		data = ChartJsonCodec.encode_chart(copied)
	else:
		# 与场景下拉列表共用排序，新增空白谱默认选择目录中的最后一项。
		var default_scene: StageDefinition = ChartSceneLibrary.shared().all_stages().back()
		data = {"format": "minghe-chart", "format_version": 1, "notes": [], "sections": [], "presentation": {"scene_id": default_scene.stage_id, "use_scene_show": false}, "timing": {"ppq": 480, "first_beat_offset_ms": 0, "chart_offset_ticks": 0, "end_tick": 7680, "tempo_events": [{"tick": 0, "bpm": 120}], "meter_events": [{"tick": 0, "numerator": 4, "denominator": 4}]}}
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

func find_note(id: String) -> Resource:
	if _index_chart != chart() or _index_revision != revision:
		_event_index.clear()
		for event in ChartEditEvents.all(chart()): _event_index[event.event_id] = event
		_index_chart = chart(); _index_revision = revision
	return _event_index.get(id)

func execute(label: String, before: Array, after: Array, metadata_before: Dictionary = {}, metadata_after: Dictionary = {}, purpose: StringName = &"notes") -> void:
	before = before.duplicate(); after = after.duplicate()
	# 新覆盖的另一侧 Tuning 自动加入共同关系；已经失效的旧关联不被暗中移除。
	if (before + after).any(func(e): return e is TuningPathEvent):
		var shadow := chart().duplicate(false) as SongChart
		ChartEditEvents.replace(shadow, before, after)
		for ghost in shadow.ghost_events:
			var coverage := ChartEditEvents.tuning_at(shadow, ghost.tick)
			if ghost.tuning_ids.is_empty() or not Array(ghost.tuning_ids).all(func(id): return coverage.has(id)): continue
			if coverage == ghost.tuning_ids: continue
			var copy := ghost.duplicate(true) as GhostEvent; copy.tuning_ids = coverage
			# shadow 使用副本，按 ID 找到同一次手势内已有的修改。
			var at := -1
			for i in after.size():
				if after[i].event_id == ghost.event_id: at = i; break
			if at >= 0: after[at] = copy
			else: before.append(find_note(ghost.event_id).duplicate(true)); after.append(copy)
	var key := chart().chart_id
	_history_target = key
	var history: Array = _histories.get(key, [])
	history.resize(int(_cursors.get(key, 0)))
	history.append({"label": label, "before": before, "after": after, "meta_before": metadata_before, "meta_after": metadata_after, "purpose": purpose})
	_histories[key] = history
	_cursors[key] = history.size()
	_apply(before, after, metadata_after, purpose)

func undo(redo := false) -> void:
	var key := "song" if _history_target == "song" else chart().chart_id
	var history: Array = _histories.get(key, [])
	var cursor: int = _cursors.get(key, 0)
	if (redo and cursor >= history.size()) or (not redo and cursor == 0): return
	var command: Dictionary = history[cursor if redo else cursor - 1]
	_cursors[key] = cursor + (1 if redo else -1)
	if command.has("offsets"):
		_apply_offsets(command.after if redo else command.before)
		return
	if key == "song":
		song.set(command.field, command.after if redo else command.before)
		mark_changed(&"metadata")
		return
	if command.has("presentation"):
		_apply_presentation(command.after if redo else command.before)
		return
	_apply(command.before if redo else command.after, command.after if redo else command.before, command.meta_after if redo else command.meta_before, command.get("purpose", &"notes"))

func _apply(remove: Array, add: Array, metadata: Dictionary, purpose: StringName = &"notes") -> void:
	var kind: StringName = purpose
	if not metadata.is_empty():
		var old: Dictionary = chart().get_meta("json_source", {})
		kind = &"timing" if old.get("timing") != metadata.get("timing") else &"metadata"
		if old.get("presentation") != metadata.get("presentation"): kind = &"presentation"
		if old.get("sections") != metadata.get("sections"): kind = &"sections"
	ChartEditEvents.replace(chart(), remove, add)
	if not metadata.is_empty():
		var decoded := ChartJsonCodec.decode_chart(metadata)
		var replacement: SongChart = decoded.chart
		replacement.note_events = chart().note_events
		replacement.tuning_paths = chart().tuning_paths
		replacement.ghost_events = chart().ghost_events
		charts[current] = replacement
	var affected := {}
	for note in remove + add:
		affected[note.event_id] = true
	mark_changed(kind, PackedStringArray(affected.keys()))

func change_presentation(value: Dictionary) -> void:
	var old: Dictionary = chart().get_meta("json_source", {}).get("presentation", {}).duplicate(true)
	if old == value: return
	var key := chart().chart_id
	var history: Array = _histories.get(key, [])
	history.resize(int(_cursors.get(key, 0)))
	history.append({"presentation": true, "before": old, "after": value.duplicate(true)})
	_histories[key] = history; _cursors[key] = history.size(); _history_target = key
	_apply_presentation(value)

func _apply_presentation(value: Dictionary) -> void:
	# 只复制外观数据，不复制整张谱面的音符。
	var raw: Dictionary = chart().get_meta("json_source", {}).duplicate()
	raw.presentation = value.duplicate(true)
	chart().set_meta("json_source", raw)
	mark_changed(&"presentation")

func change_metadata(data: Dictionary) -> void:
	execute("修改谱面属性", [], [], ChartJsonCodec.encode_chart(chart()), data)

func set_first_beat_offset_ms(value: float, all_difficulties := false) -> void:
	# 对齐只改时间基准，不复制或重排音符；跨难度同步放入歌曲级历史。
	if not is_finite(value): return
	var before := {}
	var after := {}
	for item in charts:
		if not all_difficulties and item != chart(): continue
		var old := float(item.get_meta("json_source", {}).get("timing", {}).get("first_beat_offset_ms", 0))
		if old == value: continue
		before[item.chart_id] = old
		after[item.chart_id] = value
	if before.is_empty(): return
	var key := "song" if all_difficulties else chart().chart_id
	var history: Array = _histories.get(key, [])
	history.resize(int(_cursors.get(key, 0)))
	history.append({"offsets": true, "label": "同步全部难度首拍" if all_difficulties else "调整首拍", "before": before, "after": after})
	_histories[key] = history; _cursors[key] = history.size(); _history_target = key
	_apply_offsets(after)

func _apply_offsets(values: Dictionary) -> void:
	for item in charts:
		if not values.has(item.chart_id): continue
		var raw: Dictionary = item.get_meta("json_source", {}).duplicate()
		var timing: Dictionary = raw.get("timing", {}).duplicate()
		timing.first_beat_offset_ms = values[item.chart_id]
		raw.timing = timing
		item.set_meta("json_source", raw)
	mark_changed(&"timing")

func mark_changed(kind: StringName = &"project", ids: PackedStringArray = PackedStringArray()) -> void:
	dirty = true
	revision += 1
	change_kind = kind; affected_ids = ids
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
	for event in clipboard: minimum = mini(minimum, event.tick)
	var after := duplicate_events(clipboard, at_tick - minimum)
	var shadow := chart().duplicate(false) as SongChart
	ChartEditEvents.replace(shadow, [], after)
	# 完整复制保留重映射关系；局部复制按落点重新寻找父对象。
	var copied_ids := {}
	for event in after: copied_ids[event.event_id] = true
	for event in after:
		if event is TuningPathEvent and (not copied_ids.has(event.hold_id) or not copied_ids.has(event.support_hold_id)): ChartEditEvents.rebind(shadow, event)
		if event is GhostEvent and not Array(event.tuning_ids).all(func(id): return copied_ids.has(id)): ChartEditEvents.rebind(shadow, event)
		result.append(event.event_id)
	execute("粘贴乐句", [], after)
	return result

static func duplicate_events(source_events: Array, delta: int) -> Array:
	var mapping := {}
	var counts := {}
	for event in source_events:
		mapping[event.event_id] = new_id("event")
		if event is NoteEvent and not event.group_id.is_empty(): counts[event.group_id] = int(counts.get(event.group_id, 0)) + 1
	var groups := {}
	var after: Array = []
	for source in source_events:
		var note = source.duplicate(true)
		note.event_id = mapping[source.event_id]; note.tick += delta
		if note is NoteEvent:
			for field in ["group_id", "damage_group_id"]:
				var old := str(source.get(field))
				if old.is_empty(): continue
				if field == "group_id" and counts.get(old, 0) != 2: note.set(field, ""); continue
				if not groups.has(old): groups[old] = new_id("group")
				note.set(field, groups[old])
		elif note is TuningPathEvent:
			note.hold_id = mapping.get(note.hold_id, note.hold_id)
			note.support_hold_id = mapping.get(note.support_hold_id, note.support_hold_id)
			for point in note.points: point.event_id = new_id("point")
		elif note is GhostEvent:
			for i in note.tuning_ids.size(): note.tuning_ids[i] = mapping.get(note.tuning_ids[i], note.tuning_ids[i])
		after.append(note)
	return after

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
	mark_changed(&"metadata")
