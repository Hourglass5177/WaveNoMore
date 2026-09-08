class_name ChartEditEvents
extends RefCounted
## 五轨共用的少量对象操作；正式判定仍使用原领域类型。
static func all(chart: SongChart) -> Array:
	return Array(chart.note_events) + Array(chart.tuning_paths) + Array(chart.ghost_events)

static func find(chart: SongChart, id: String):
	for event in all(chart):
		if event.event_id == id: return event
	return null

static func track(event) -> int:
	if event is GhostEvent: return 4
	return event.affinity + (2 if event is TuningPathEvent else 0)

static func title(event) -> String:
	if event is GhostEvent: return "Ghost ×%d" % event.count
	if event is TuningPathEvent: return "Tuning"
	return "Hold" if event.kind == GameplayTypes.NoteKind.HOLD else "Tap"

static func same(a, b) -> bool:
	if a.get_script() != b.get_script() or a.event_id != b.event_id or a.tick != b.tick or a.affinity != b.affinity or a.duration_ticks != b.duration_ticks: return false
	if a is GhostEvent: return a.count == b.count and a.boss == b.boss and a.tuning_ids == b.tuning_ids
	if a is TuningPathEvent:
		if a.hold_id != b.hold_id or a.support_hold_id != b.support_hold_id or a.points.size() != b.points.size(): return false
		for i in a.points.size():
			if a.points[i].event_id != b.points[i].event_id or a.points[i].offset_ticks != b.points[i].offset_ticks or a.points[i].angle_deg != b.points[i].angle_deg: return false
		return true
	return a.kind == b.kind and a.group_id == b.group_id and a.damage_group_id == b.damage_group_id and a.visual_variant == b.visual_variant and a.tail_requires_release == b.tail_requires_release and is_boss(a) == is_boss(b)

static func is_boss(event) -> bool:
	return event.boss if event is GhostEvent or event is NoteEvent else false

static func set_boss(event, value: bool) -> void:
	if event is GhostEvent or event is NoteEvent: event.boss = value

static func replace(chart: SongChart, before: Array, after: Array) -> void:
	var ids := {}
	for event in before: ids[event.event_id] = true
	chart.note_events = chart.note_events.filter(func(e): return not ids.has(e.event_id))
	chart.tuning_paths = chart.tuning_paths.filter(func(e): return not ids.has(e.event_id))
	chart.ghost_events = chart.ghost_events.filter(func(e): return not ids.has(e.event_id))
	for event in after:
		var copy = event.duplicate(true)
		if copy is NoteEvent: _insert(chart.note_events, copy)
		elif copy is TuningPathEvent: _insert(chart.tuning_paths, copy)
		elif copy is GhostEvent: _insert(chart.ghost_events, copy)

static func _insert(list: Array, event) -> void:
	var low := 0; var high := list.size()
	while low < high:
		var middle := (low + high) / 2
		var before: bool = list[middle].tick < event.tick or (list[middle].tick == event.tick and list[middle].event_id < event.event_id)
		if before: low = middle + 1
		else: high = middle
	list.insert(low, event)

static func linked_ids(chart: SongChart, selection: PackedStringArray) -> PackedStringArray:
	# 显式“选择关联内容”与高亮可向上查找；移动和影响删除仅向下传播。
	var ids := selection.duplicate()
	for ghost in chart.ghost_events:
		if selection.has(ghost.event_id):
			for id in ghost.tuning_ids:
				if not ids.has(id): ids.append(id)
	for path in chart.tuning_paths:
		if ids.has(path.event_id):
			for id in [path.hold_id, path.support_hold_id]:
				if not ids.has(id): ids.append(id)
	return related_ids(chart, ids)

static func hold_pair(chart: SongChart, side: int, start: int, end: int) -> Array:
	var own: NoteEvent
	var other: NoteEvent
	for note in chart.note_events:
		if note.kind != GameplayTypes.NoteKind.HOLD or note.tick > start or note.tick + note.duration_ticks < end: continue
		if note.affinity == side: own = note
		else: other = note
	return [own, other] if own != null and other != null else []

static func tuning_at(chart: SongChart, tick: int) -> PackedStringArray:
	var ids := PackedStringArray()
	for side in 2:
		var chosen: TuningPathEvent
		for path in chart.tuning_paths:
			if path.affinity != side or path.tick > tick or path.tick + path.duration_ticks < tick: continue
			# 尾点先于同刻新条，和当前领域事件顺序一致。
			if chosen == null or path.tick < chosen.tick: chosen = path
		if chosen != null: ids.append(chosen.event_id)
	return ids

static func moving_ids(chart: SongChart, selection: PackedStringArray) -> PackedStringArray:
	var result := selection.duplicate()
	for path in chart.tuning_paths:
		if result.has(path.hold_id) and not result.has(path.event_id): result.append(path.event_id)
	for ghost in chart.ghost_events:
		if ghost.tuning_ids.is_empty(): continue
		var follows := true
		for id in ghost.tuning_ids: follows = follows and result.has(id)
		if follows and not result.has(ghost.event_id): result.append(ghost.event_id)
	return result

static func related_ids(chart: SongChart, selection: PackedStringArray) -> PackedStringArray:
	var result := moving_ids(chart, selection)
	for ghost in chart.ghost_events:
		for id in ghost.tuning_ids:
			if result.has(id) and not result.has(ghost.event_id): result.append(ghost.event_id)
	return result

static func rebind(chart: SongChart, event) -> bool:
	if event is TuningPathEvent:
		var pair := hold_pair(chart, event.affinity, event.tick, event.tick + event.duration_ticks)
		if pair.is_empty(): return false
		event.hold_id = pair[0].event_id; event.support_hold_id = pair[1].event_id
	elif event is GhostEvent:
		var ids := tuning_at(chart, event.tick)
		if ids.is_empty(): return false
		event.tuning_ids = ids
	return true

static func rebind_moved_ghosts(chart: SongChart, before: Array, after: Array, selection: PackedStringArray) -> void:
	if not after.any(func(e): return e is GhostEvent and selection.has(e.event_id)): return
	# 同时移动路径与批次时，按整个候选位置查关联，不能误绑到移动前的旧窗口。
	var shadow := chart.duplicate(false) as SongChart
	replace(shadow, before, after)
	for event in after:
		if event is GhostEvent and selection.has(event.event_id): rebind(shadow, event)

static func new_path(chart: SongChart, side: int, start: int, end: int) -> TuningPathEvent:
	var path := TuningPathEvent.new()
	path.event_id = "tuning_" + Crypto.new().generate_random_bytes(8).hex_encode()
	path.affinity = side; path.tick = start
	var center := (-90.0 if side == 0 else 90.0) - rad_to_deg(atan2(-540.0, 960.0))
	for i in 2:
		var point := TuningPathPoint.new()
		point.event_id = "point_" + Crypto.new().generate_random_bytes(8).hex_encode()
		point.offset_ticks = 0 if i == 0 else end - start
		point.angle_deg = center + (-30.0 if i == 0 else 30.0)
		path.points.append(point)
	return path if rebind(chart, path) else null
