class_name ChartJsonCodec
extends RefCounted
## 工具和游戏共用的 JSON v1 转换。原对象附在 Resource 元数据中，编辑已知字段时保留兼容扩展。

static func decode_chart(data: Dictionary) -> Dictionary:
	var errors: PackedStringArray = []
	if data.get("format") != "minghe-chart" or data.get("format_version") != 1:
		return {"chart": null, "errors": PackedStringArray(["不支持的谱面格式或版本"])}
	var chart := SongChart.new()
	chart.set_meta("json_source", data.duplicate(true))
	chart.chart_id = str(data.get("chart_id", ""))
	chart.difficulty_id = str(data.get("difficulty_id", "normal"))
	var timing: Dictionary = data.get("timing", {})
	chart.ppq = int(timing.get("ppq", 480))
	chart.chart_offset_ticks = int(timing.get("chart_offset_ticks", 0))
	chart.end_tick = int(timing.get("end_tick", 0))
	for raw: Dictionary in timing.get("tempo_events", []):
		var item := TempoEvent.new()
		item.tick = int(raw.get("tick", 0))
		item.bpm = float(raw.get("bpm", 0))
		item.set_meta("json_source", raw.duplicate(true))
		chart.tempo_events.append(item)
	for raw: Dictionary in timing.get("meter_events", []):
		var item := MeterEvent.new()
		item.tick = int(raw.get("tick", 0))
		item.numerator = int(raw.get("numerator", 4))
		item.denominator = int(raw.get("denominator", 4))
		item.set_meta("json_source", raw.duplicate(true))
		chart.meter_events.append(item)
	var unknown: Array = []
	for raw: Dictionary in data.get("notes", []):
		if raw.get("kind") not in ["tap", "hold"] or raw.get("affinity") not in ["zhu", "xuan"] or not raw.get("behaviors", {}).is_empty():
			unknown.append(raw.duplicate(true))
			errors.append("音符 %s 含暂不支持的类型或行为，已保留原数据" % raw.get("id", ""))
			continue
		var item := NoteEvent.new()
		item.event_id = str(raw.get("id", ""))
		item.kind = GameplayTypes.NoteKind.HOLD if raw.get("kind") == "hold" else GameplayTypes.NoteKind.TAP
		item.affinity = GameplayTypes.Affinity.ZHU if raw.get("affinity") == "zhu" else GameplayTypes.Affinity.XUAN
		if raw.get("affinity") not in ["zhu", "xuan"]:
			errors.append("音符 %s 侧别无效" % item.event_id)
		item.tick = int(raw.get("tick", 0))
		item.duration_ticks = int(raw.get("duration_ticks", 0))
		item.group_id = str(raw.get("group_id", ""))
		item.damage_group_id = str(raw.get("damage_group_id", ""))
		item.visual_variant = StringName(raw.get("visual_variant", "default"))
		item.set_meta("json_source", raw.duplicate(true))
		chart.note_events.append(item)
	for raw: Dictionary in data.get("sections", []):
		var item := SectionMarker.new()
		item.event_id = str(raw.get("id", ""))
		item.label = str(raw.get("name", ""))
		item.tick = int(raw.get("tick", 0))
		item.set_meta("json_source", raw.duplicate(true))
		chart.sections.append(item)
	chart.set_meta("unknown_notes", unknown)
	return {"chart": chart, "errors": errors}

static func encode_chart(chart: SongChart) -> Dictionary:
	var data: Dictionary = chart.get_meta("json_source", {}).duplicate(true)
	data.merge({"format": "minghe-chart", "format_version": 1, "chart_id": chart.chart_id, "difficulty_id": chart.difficulty_id}, true)
	var timing: Dictionary = data.get("timing", {}).duplicate(true)
	timing.merge({"ppq": chart.ppq, "chart_offset_ticks": chart.chart_offset_ticks, "end_tick": chart.end_tick}, true)
	timing["tempo_events"] = []
	for item in chart.tempo_events:
		var raw: Dictionary = item.get_meta("json_source", {}).duplicate(true)
		raw.merge({"tick": item.tick, "bpm": item.bpm}, true)
		timing.tempo_events.append(raw)
	timing["meter_events"] = []
	for item in chart.meter_events:
		var raw: Dictionary = item.get_meta("json_source", {}).duplicate(true)
		raw.merge({"tick": item.tick, "numerator": item.numerator, "denominator": item.denominator}, true)
		timing.meter_events.append(raw)
	data["sections"] = []
	for item in chart.sections:
		var raw: Dictionary = item.get_meta("json_source", {}).duplicate(true)
		raw.merge({"id": item.event_id, "tick": item.tick, "name": item.label}, true)
		data.sections.append(raw)
	data["timing"] = timing
	data["notes"] = chart.get_meta("unknown_notes", []).duplicate(true)
	for item in chart.note_events:
		var raw: Dictionary = item.get_meta("json_source", {}).duplicate(true)
		raw.merge({"id": item.event_id, "kind": "hold" if item.kind == GameplayTypes.NoteKind.HOLD else "tap", "affinity": "zhu" if item.affinity == GameplayTypes.Affinity.ZHU else "xuan", "tick": item.tick, "duration_ticks": item.duration_ticks}, true)
		for key in ["group_id", "damage_group_id", "visual_variant"]:
			if str(item.get(key)).is_empty():
				raw.erase(key)
			else:
				raw[key] = str(item.get(key))
		data.notes.append(raw)
	data.notes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.tick != b.tick: return a.tick < b.tick
		if a.affinity != b.affinity: return a.affinity == "zhu"
		return str(a.id) < str(b.id))
	return data

static func decode_song(data: Dictionary) -> Dictionary:
	if data.get("format") != "minghe-song" or data.get("format_version") != 1:
		return {"song": null, "errors": PackedStringArray(["不支持的歌曲格式或版本"])}
	var song := SongDefinition.new()
	song.song_id = str(data.get("song_id", ""))
	song.title = str(data.get("title", ""))
	song.artist = str(data.get("artist", ""))
	song.set_meta("json_source", data.duplicate(true))
	return {"song": song, "errors": PackedStringArray()}

static func encode_song(song: SongDefinition) -> Dictionary:
	var data: Dictionary = song.get_meta("json_source", {}).duplicate(true)
	data.merge({"format": "minghe-song", "format_version": 1, "song_id": song.song_id, "title": song.title, "artist": song.artist}, true)
	return data

static func load_audio(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"wav": return AudioStreamWAV.load_from_file(path)
		"ogg": return AudioStreamOggVorbis.load_from_file(path)
		"mp3": return AudioStreamMP3.load_from_file(path)
	return null
