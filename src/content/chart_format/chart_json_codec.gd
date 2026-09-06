class_name ChartJsonCodec
extends RefCounted
## 工具和游戏共用的 JSON v1 转换。原对象附在 Resource 元数据中，编辑已知字段时保留兼容扩展。

static func decode_chart(data: Dictionary) -> Dictionary:
	var errors: PackedStringArray = []
	if data.get("format") != "minghe-chart" or data.get("format_version") != 1:
		return {"chart": null, "errors": PackedStringArray(["不支持的谱面格式或版本"])}
	var structure_error := _check_chart_structure(data)
	if not structure_error.is_empty(): return {"chart": null, "errors": PackedStringArray([structure_error])}
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

## 这里只拒绝无法建立时间映射的数据；重叠、负长音等玩法冲突仍可作为草稿打开。
static func _check_chart_structure(data: Dictionary) -> String:
	if not data.get("timing") is Dictionary: return "timing 必须是时间对象"
	var timing: Dictionary = data.timing
	for key in ["ppq", "chart_offset_ticks", "end_tick"]:
		if not _integer(timing.get(key)): return "timing.%s 必须是整数" % key
	if timing.ppq <= 0: return "timing.ppq 必须大于零"
	if not _number(timing.get("first_beat_offset_ms", 0)): return "首拍偏移必须是有限数值"
	for key in ["tempo_events", "meter_events"]:
		if not timing.get(key) is Array or timing[key].is_empty(): return "timing.%s 不能为空" % key
		var previous := -1
		for item in timing[key]:
			if not item is Dictionary or not _integer(item.get("tick")): return "%s 的 tick 必须是整数" % key
			if item.tick <= previous: return "%s 必须按非负 tick 严格递增" % key
			previous = int(item.tick)
			if key == "tempo_events":
				if not _number(item.get("bpm")) or item.bpm <= 0: return "BPM 必须是大于零的有限数值"
			else:
				if not _integer(item.get("numerator")) or not _integer(item.get("denominator")): return "拍号必须为整数"
				var denominator := int(item.denominator)
				if item.numerator <= 0 or denominator <= 0: return "拍号必须大于零"
				if denominator & (denominator - 1) != 0 or int(timing.ppq) * 4 % denominator != 0: return "拍号分母必须是 PPQ 可表示的二次幂"
		if timing[key][0].tick != 0: return "%s 必须从 tick 0 开始" % key
	for key in ["notes", "sections"]:
		if not data.get(key, []) is Array: return "%s 必须是数组" % key
		for item in data.get(key, []):
			if not item is Dictionary or not _integer(item.get("tick")): return "%s 对象的 tick 必须是整数" % key
			if key == "notes" and not _integer(item.get("duration_ticks", 0)): return "音符 duration_ticks 必须是整数"
			if key == "notes" and not item.get("behaviors", {}) is Dictionary: return "音符 behaviors 必须是命名行为对象"
	if not data.get("presentation", {}) is Dictionary: return "presentation 必须是对象"
	if not data.get("presentation", {}).get("palette_overrides", {}) is Dictionary: return "palette_overrides 必须是对象"
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))

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
		if a.get("tick", 0) != b.get("tick", 0): return a.get("tick", 0) < b.get("tick", 0)
		if a.get("affinity", "") != b.get("affinity", ""): return a.get("affinity") == "zhu"
		return str(a.get("id", "")) < str(b.get("id", "")))
	return data

static func decode_song(data: Dictionary) -> Dictionary:
	if data.get("format") != "minghe-song" or data.get("format_version") != 1:
		return {"song": null, "errors": PackedStringArray(["不支持的歌曲格式或版本"])}
	if not data.get("charts", []) is Array: return {"song": null, "errors": ["charts 必须是数组"]}
	for entry in data.get("charts", []):
		if not entry is Dictionary or not entry.get("path") is String: return {"song": null, "errors": ["难度引用缺少 path"]}
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
	if not FileAccess.file_exists(path): return null
	match path.get_extension().to_lower():
		"wav": return AudioStreamWAV.load_from_file(path)
		"ogg": return AudioStreamOggVorbis.load_from_file(path)
		"mp3": return AudioStreamMP3.load_from_file(path)
	return null

static func audio_from_bytes(data: PackedByteArray, extension: String) -> AudioStream:
	if data.is_empty(): return null
	match extension.to_lower():
		"wav": return AudioStreamWAV.load_from_buffer(data)
		"ogg": return AudioStreamOggVorbis.load_from_buffer(data)
		"mp3":
			var stream := AudioStreamMP3.new(); stream.data = data; return stream
	return null
