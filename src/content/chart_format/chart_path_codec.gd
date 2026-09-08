class_name ChartPathCodec
extends RefCounted
## v2 新轨的无损 JSON 适配，节点的未知字段也随其稳定身份保留。
static func decode(data: Dictionary, chart: SongChart) -> String:
	for key in ["tuning_paths", "ghost_events"]:
		if not data.get(key, []) is Array: return key + " 必须是数组"
		for raw in data.get(key, []):
			if not raw is Dictionary or not ChartJsonCodec._integer(raw.get("tick")): return key + " 的 tick 必须是整数"
			if key == "tuning_paths":
				if not raw.get("points", []) is Array: return "Tuning 节点必须是数组"
				var path := TuningPathEvent.new()
				path.event_id = str(raw.get("id", "")); path.tick = int(raw.tick)
				path.affinity = {"zhu": 0, "xuan": 1}.get(str(raw.get("affinity")), -1)
				path.hold_id = str(raw.get("hold_id", "")); path.support_hold_id = str(raw.get("support_hold_id", ""))
				path.set_meta("json_source", raw.duplicate(true))
				for point_raw in raw.get("points", []):
					if not point_raw is Dictionary or not ChartJsonCodec._integer(point_raw.get("offset_ticks")) or not ChartJsonCodec._number(point_raw.get("angle_deg")): return "Tuning 节点需要整数 tick 和有限角度"
					var point := TuningPathPoint.new()
					point.event_id = str(point_raw.get("id", "")); point.offset_ticks = int(point_raw.offset_ticks); point.angle_deg = float(point_raw.angle_deg)
					point.set_meta("json_source", point_raw.duplicate(true)); path.points.append(point)
				chart.tuning_paths.append(path)
			else:
				if not raw.get("tuning_ids", []) is Array or not ChartJsonCodec._integer(raw.get("count", 1)): return "Ghost 需要整数数量和 Tuning 引用数组"
				var ghost := GhostEvent.new()
				ghost.event_id = str(raw.get("id", "")); ghost.tick = int(raw.tick)
				ghost.count = int(raw.get("count", 1)); ghost.boss = bool(raw.get("boss", false))
				ghost.tuning_ids = PackedStringArray(raw.get("tuning_ids", []))
				ghost.set_meta("json_source", raw.duplicate(true)); chart.ghost_events.append(ghost)
	return ""

static func encode(chart: SongChart, data: Dictionary) -> void:
	data.tuning_paths = []; data.ghost_events = []
	for path in chart.tuning_paths:
		var raw: Dictionary = path.get_meta("json_source", {}).duplicate(true)
		raw.merge({"id": path.event_id, "affinity": "zhu" if path.affinity == 0 else "xuan", "tick": path.tick, "hold_id": path.hold_id, "support_hold_id": path.support_hold_id, "points": []}, true)
		for point in path.points:
			var p: Dictionary = point.get_meta("json_source", {}).duplicate(true)
			p.merge({"id": point.event_id, "offset_ticks": point.offset_ticks, "angle_deg": point.angle_deg}, true)
			raw.points.append(p)
		data.tuning_paths.append(raw)
	for ghost in chart.ghost_events:
		var raw: Dictionary = ghost.get_meta("json_source", {}).duplicate(true)
		raw.merge({"id": ghost.event_id, "tick": ghost.tick, "count": ghost.count, "tuning_ids": Array(ghost.tuning_ids), "boss": ghost.boss}, true)
		data.ghost_events.append(raw)
