class_name ChartCompiler
extends RefCounted

## 谱面进入玩法内核前的统一编译入口。这里只做迁移、校验、时间换算和稳定排序，
## 不读取场景节点，也不负责播放或判定。

static func compile(
		chart: SongChart,
		rules: GameplayRuleSet,
		first_beat_offset_us: int = 0,
		song_duration_us: int = -1
) -> Dictionary:
	# 顺序固定为“迁移旧版本 → 校验 → 换算运行时数据”。任一步有 ERROR 就停止，
	# 不能把半有效谱面交给后面的判定器猜测。
	var migration: Dictionary = ChartMigrator.migrate(chart)
	var report: ValidationReport = migration["report"]
	if not bool(migration["ok"]):
		return {"ok": false, "compiled": null, "report": report}
	var migrated: SongChart = migration["chart"]
	var validation := ChartValidator.validate(migrated, rules, song_duration_us)
	for issue in validation.issues:
		report.add_issue(issue)
	if report.has_errors():
		return {"ok": false, "compiled": null, "report": report}
	var compiled := CompiledChart.new()
	compiled.schema_version = migrated.schema_version
	compiled.chart_id = migrated.chart_id
	compiled.difficulty_id = migrated.difficulty_id
	compiled.ppq = migrated.ppq
	compiled.end_tick = migrated.end_tick
	compiled.tempo_map = TempoMap.from_chart(migrated, first_beat_offset_us)
	compiled.end_time_us = compiled.tempo_map.tick_to_us(migrated.end_tick)
	compiled.notes = _compile_notes(migrated, compiled.tempo_map)
	compiled.tuning_fields = _compile_tuning_fields(migrated, compiled.tempo_map)
	compiled.tuning_sliders = _compile_tuning_sliders(migrated, compiled.tempo_map)
	compiled.su_manifestations = _compile_su_manifestations(migrated, compiled.tempo_map)
	compiled.rapid_regions = _compile_rapid(migrated, compiled.tempo_map)
	compiled.sections = _compile_sections(migrated, compiled.tempo_map)
	compiled.theoretical_unit_count = compiled.notes.size() + _tuning_unit_count(compiled.tuning_sliders) + compiled.rapid_regions.size()
	compiled.content_hash = _chart_hash(compiled)
	report.add_info(&"chart.theoretical_units", "Compiled %d judgment units." % compiled.theoretical_unit_count)
	return {"ok": true, "compiled": compiled, "report": report}


static func rules_hash(rules: GameplayRuleSet) -> String:
	# 只收集真正存盘的规则字段，并按字段名排序；这样属性枚举顺序不会改变哈希。
	if rules == null:
		return ""
	var names: PackedStringArray = []
	var values: Dictionary = {}
	for property in rules.get_property_list():
		var usage: int = int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name: String = String(property["name"])
		if property_name == "resource_path" or property_name == "resource_name" or property_name == "script":
			continue
		names.append(property_name)
		values[property_name] = rules.get(property_name)
	names.sort()
	var lines := PackedStringArray(["GameplayRuleSet:v2"])
	for property_name in names:
		lines.append("%s=%s" % [property_name, var_to_str(values[property_name])])
	return "\n".join(lines).sha256_text()


static func _compile_notes(chart: SongChart, tempo_map: TempoMap) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for note in chart.note_events:
		var end_tick: int = note.tick + note.duration_ticks
		var start_us: int = tempo_map.tick_to_us(note.tick)
		var end_us: int = tempo_map.tick_to_us(end_tick)
		result.append({
			"id": note.event_id,
			"event_id": note.event_id,
			"unit_id": note.event_id,
			"unit_kind": &"hold" if note.kind == GameplayTypes.NoteKind.HOLD else &"tap",
			"note_kind": note.kind,
			"kind": note.kind,
			"affinity": note.affinity,
			"tick": note.tick,
			"end_tick": end_tick,
			"start_us": start_us,
			"end_us": end_us,
			"start_time_us": start_us,
			"end_time_us": end_us,
			"time_us": start_us,
			"duration_us": end_us - start_us,
			"group_id": note.group_id,
			"damage_group_id": _damage_group(note.damage_group_id, note.group_id, note.event_id),
			"tail_requires_release": note.tail_requires_release,
			"visual_variant": note.visual_variant,
		})
	result.sort_custom(_sort_compiled_unit)
	return result


static func _compile_tuning_fields(chart: SongChart, tempo_map: TempoMap) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for field in chart.tuning_fields:
		var start_us: int = tempo_map.tick_to_us(field.tick)
		var end_tick: int = field.tick + field.duration_ticks
		var end_us: int = tempo_map.tick_to_us(end_tick)
		result.append({
			"id": field.event_id,
			"event_id": field.event_id,
			"tick": field.tick,
			"end_tick": end_tick,
			"duration_ticks": field.duration_ticks,
			"start_us": start_us,
			"end_us": end_us,
			"start_time_us": start_us,
			"end_time_us": end_us,
			"time_us": start_us,
			"duration_us": end_us - start_us,
		})
	result.sort_custom(_sort_time_then_id)
	return result


static func _compile_tuning_sliders(chart: SongChart, tempo_map: TempoMap) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slider in chart.tuning_sliders:
		var duration_ticks: int = slider.traversal_ticks * slider.traversal_count
		var end_tick: int = slider.tick + duration_ticks
		var start_us: int = tempo_map.tick_to_us(slider.tick)
		var end_us: int = tempo_map.tick_to_us(end_tick)
		var unit_id: String = slider.group_id if not slider.group_id.is_empty() else slider.event_id
		result.append({
			"id": slider.event_id,
			"event_id": slider.event_id,
			"unit_id": unit_id,
			"unit_kind": &"tuning",
			"affinity": slider.affinity,
			"field_id": slider.field_id,
			"group_id": slider.group_id,
			"tick": slider.tick,
			"end_tick": end_tick,
			"duration_ticks": duration_ticks,
			"traversal_ticks": slider.traversal_ticks,
			"traversal_count": slider.traversal_count,
			"start_us": start_us,
			"end_us": end_us,
			"start_time_us": start_us,
			"end_time_us": end_us,
			"time_us": start_us,
			"duration_us": end_us - start_us,
			"start_value": slider.start_value,
			"end_value": slider.end_value,
			"arc_rotation_deg": slider.arc_rotation_deg,
			"visual_offset_px": slider.visual_offset_px,
			"visual_radius_px": slider.visual_radius_px,
			"damage_group_id": unit_id,
		})
	result.sort_custom(_sort_compiled_unit)
	return result


static func _compile_su_manifestations(chart: SongChart, tempo_map: TempoMap) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for manifestation in chart.su_manifestations:
		var time_us: int = tempo_map.tick_to_us(manifestation.tick)
		result.append({
			"id": manifestation.event_id,
			"event_id": manifestation.event_id,
			"group_id": manifestation.group_id,
			"tick": manifestation.tick,
			"time_us": time_us,
			"start_us": time_us,
			"end_us": time_us,
			"count": manifestation.count,
			"spawn_region_normalized": manifestation.spawn_region_normalized,
			"visual_variant": manifestation.visual_variant,
			"target_visual_variant": manifestation.target_visual_variant,
			"target_hold_duration_sec": manifestation.target_hold_duration_sec,
		})
	result.sort_custom(_sort_time_then_id)
	return result


static func _compile_rapid(chart: SongChart, tempo_map: TempoMap) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for region in chart.rapid_regions:
		var start_us: int = tempo_map.tick_to_us(region.tick)
		var end_us: int = tempo_map.tick_to_us(region.tick + region.duration_ticks)
		result.append({
			"id": region.event_id,
			"event_id": region.event_id,
			"unit_id": region.event_id,
			"unit_kind": &"rapid",
			"affinity": GameplayTypes.Affinity.SU,
			"tick": region.tick,
			"end_tick": region.tick + region.duration_ticks,
			"start_us": start_us,
			"end_us": end_us,
			"start_time_us": start_us,
			"end_time_us": end_us,
			"time_us": start_us,
			"duration_us": end_us - start_us,
			"required_strikes": region.required_strikes,
			"debounce_us": region.debounce_ms * 1000,
			"must_alternate": region.must_alternate,
			"group_id": "",
			"damage_group_id": _damage_group(region.damage_group_id, "", region.event_id),
			"visual_variant": region.visual_variant,
		})
	result.sort_custom(_sort_compiled_unit)
	return result


static func _compile_sections(chart: SongChart, tempo_map: TempoMap) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for section in chart.sections:
		result.append({
			"id": section.event_id,
			"tick": section.tick,
			"time_us": tempo_map.tick_to_us(section.tick),
			"label": section.label,
			"tutorial_key": section.tutorial_key,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tick"]) != int(b["tick"]):
			return int(a["tick"]) < int(b["tick"])
		return String(a["id"]) < String(b["id"])
	)
	return result


static func _chart_hash(compiled: CompiledChart) -> String:
	# Replay 用此哈希确认谱面没有被改过，所以写入顺序和浮点格式都必须固定。
	var lines := PackedStringArray([
		"SongChart:v%d" % compiled.schema_version,
		"chart=%s" % compiled.chart_id,
		"difficulty=%s" % compiled.difficulty_id,
		"ppq=%d" % compiled.ppq,
		"end=%d" % compiled.end_tick,
		"offset_ticks=%d" % compiled.tempo_map.chart_offset_ticks,
		"first_beat_us=%d" % compiled.tempo_map.first_beat_offset_us,
	])
	for tempo in compiled.tempo_map.events_copy():
		lines.append("tempo|%d|%.9f" % [tempo["tick"], tempo["bpm"]])
	for note in compiled.notes:
		lines.append("note|%s|%s|%d|%d|%d|%s|%s|%d" % [note["id"], note["unit_kind"], note["affinity"], note["tick"], note["end_tick"], note["group_id"], note["damage_group_id"], int(note["tail_requires_release"])])
	for field in compiled.tuning_fields:
		lines.append("tuning_field|%s|%d|%d" % [field["id"], field["tick"], field["end_tick"]])
	for slider in compiled.tuning_sliders:
		# visual_offset_px 与 visual_radius_px 是纯表现构图，不进入 Replay 内容哈希。
		lines.append("tuning_slider|%s|%s|%s|%d|%d|%d|%d|%.9f|%.9f|%.3f" % [slider["id"], slider["field_id"], slider["group_id"], slider["affinity"], slider["tick"], slider["traversal_ticks"], slider["traversal_count"], slider["start_value"], slider["end_value"], slider.get("arc_rotation_deg", 0.0)])
	for manifestation in compiled.su_manifestations:
		var spawn_region: Rect2 = manifestation["spawn_region_normalized"]
		lines.append("su_manifestation|%s|%s|%d|%d|%.9f|%.9f|%.9f|%.9f" % [manifestation["id"], manifestation["group_id"], manifestation["tick"], manifestation["count"], spawn_region.position.x, spawn_region.position.y, spawn_region.size.x, spawn_region.size.y])
	for region in compiled.rapid_regions:
		lines.append("rapid|%s|%d|%d|%d|%d|%d|%s" % [region["id"], region["tick"], region["end_tick"], region["required_strikes"], region["debounce_us"], int(region["must_alternate"]), region["damage_group_id"]])
	return "\n".join(lines).sha256_text()


static func _damage_group(explicit_id: String, group_id: String, event_id: String) -> String:
	if not explicit_id.is_empty():
		return explicit_id
	if not group_id.is_empty():
		return group_id
	return event_id


static func _sort_compiled_unit(a: Dictionary, b: Dictionary) -> bool:
	# 同一时刻仍按机制、阵营、尾点和稳定 ID 排序，避免字典遍历顺序影响运行结果。
	if int(a["start_us"]) != int(b["start_us"]):
		return int(a["start_us"]) < int(b["start_us"])
	var a_rank: int = _type_rank(StringName(a["unit_kind"]))
	var b_rank: int = _type_rank(StringName(b["unit_kind"]))
	if a_rank != b_rank:
		return a_rank < b_rank
	if int(a["affinity"]) != int(b["affinity"]):
		return int(a["affinity"]) < int(b["affinity"])
	if int(a["end_tick"]) != int(b["end_tick"]):
		return int(a["end_tick"]) < int(b["end_tick"])
	return String(a["id"]) < String(b["id"])


static func _sort_time_then_id(a: Dictionary, b: Dictionary) -> bool:
	if int(a["start_us"]) != int(b["start_us"]):
		return int(a["start_us"]) < int(b["start_us"])
	return String(a["id"]) < String(b["id"])


static func _tuning_unit_count(sliders: Array[Dictionary]) -> int:
	var unit_ids: Dictionary = {}
	for slider: Dictionary in sliders:
		unit_ids[String(slider["unit_id"])] = true
	return unit_ids.size()


static func _type_rank(kind: StringName) -> int:
	match kind:
		&"tap": return 0
		&"hold": return 1
		&"tuning": return 2
		&"rapid": return 3
	return 99
