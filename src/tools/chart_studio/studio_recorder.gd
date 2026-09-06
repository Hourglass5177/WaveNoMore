class_name StudioRecorder
extends RefCounted
## 一段录制只在结束时进入文档历史；候选与已松开的音符即时显示在时间线上。
var active := false
var threshold_ms := 150.0
var notes: Array[NoteEvent] = []
var held := {}
var blocked := {}
var map: TempoMap
var snap := 120

func begin(time_map: TempoMap, step: int) -> void:
	active = true; notes.clear(); held.clear(); blocked.clear()
	map = time_map; snap = step

func press(side: int, seconds: float, wall_us: int) -> void:
	if held.has(side) or blocked.has(side): return
	held[side] = {"seconds": seconds, "wall": wall_us, "id": StudioDocument.new_id("record")}

func release(side: int, seconds: float, wall_us: int) -> void:
	if blocked.has(side): blocked.erase(side); return
	if not held.has(side): return
	notes.append(_make(side, seconds, wall_us)); held.erase(side)

func _tick(seconds: float) -> int:
	var value := map.us_to_tick(roundi(seconds * 1000000.0))
	return roundi(value / snap) * snap if snap > 0 else roundi(value)

func _make(side: int, seconds: float, wall_us: int) -> NoteEvent:
	var start: Dictionary = held[side]
	var note := NoteEvent.new(); note.event_id = start.id; note.affinity = side
	note.tick = _tick(start.seconds)
	if wall_us - int(start.wall) > threshold_ms * 1000:
		note.kind = GameplayTypes.NoteKind.HOLD
		note.duration_ticks = maxi(maxi(1, snap), _tick(seconds) - note.tick)
	return note

func display_notes(seconds: float, wall_us: int) -> Array[NoteEvent]:
	var result: Array[NoteEvent] = notes.duplicate()
	for side: int in held: result.append(_make(side, seconds, wall_us))
	return result

func cut_loop(seconds: float, wall_us: int) -> void:
	for side: int in held:
		var note := _make(side, seconds, wall_us)
		# 回绕是硬边界：末尾不足一个吸附格时截短，不能把尾点放到下一轮。
		var boundary := floori(map.us_to_tick(roundi(seconds * 1000000.0)))
		note.tick = mini(note.tick, boundary)
		if note.kind == GameplayTypes.NoteKind.HOLD:
			note.duration_ticks = mini(note.duration_ticks, boundary - note.tick)
			if note.duration_ticks <= 0: note.kind = GameplayTypes.NoteKind.TAP
		notes.append(note); blocked[side] = true
	held.clear()

func finish(seconds: float, wall_us: int, cancel_held := false) -> Array[NoteEvent]:
	if not cancel_held:
		for side: int in held: notes.append(_make(side, seconds, wall_us))
	held.clear(); blocked.clear(); active = false
	var result := notes.duplicate(); notes.clear()
	return result
