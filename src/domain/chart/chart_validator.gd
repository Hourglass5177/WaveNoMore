class_name ChartValidator
extends RefCounted

## 对 SongChart 和 GameplayRuleSet 做静态校验。它在运行前阻止不可能完成、
## 时间范围冲突或缺少稳定 ID 的谱面进入判定层。

static func validate(chart: SongChart, rules: GameplayRuleSet = null, song_duration_us: int = -1) -> ValidationReport:
	var report := ValidationReport.new()
	if chart == null:
		report.add_error(&"chart.null", "SongChart is null.")
		return report
	_validate_header(chart, report)
	_validate_timing(chart, report)
	# 所有轨道共用这一份 ID 表，因为写谱器、演出和 Replay 都可能跨类型定位事件。
	var ids: Dictionary = {}
	_validate_notes(chart, report, ids)
	var fields_by_id: Dictionary = _validate_tuning_fields(chart, report, ids)
	var slider_groups: Dictionary = _validate_tuning_sliders(chart, fields_by_id, rules, report, ids)
	_validate_su_manifestations(chart, fields_by_id, slider_groups, report, ids)
	_validate_rapid(chart, report, ids)
	_validate_sections(chart, report, ids)
	if rules != null:
		_validate_rules(rules, report)
		if not report.has_errors():
			_validate_input_conflicts(chart, rules, report)
	if song_duration_us >= 0 and not chart.tempo_events.is_empty():
		var tempo_map := TempoMap.from_chart(chart)
		if tempo_map.tick_to_us(chart.end_tick) > song_duration_us:
			report.add_error(&"chart.after_song_end", "Chart end lies after the authored song duration.", "", &"timing", chart.end_tick)
	return report


static func _validate_header(chart: SongChart, report: ValidationReport) -> void:
	if chart.schema_version != SongChart.CURRENT_SCHEMA_VERSION:
		report.add_error(&"schema.unsupported", "Expected schema %d, got %d." % [SongChart.CURRENT_SCHEMA_VERSION, chart.schema_version])
	if chart.chart_id.strip_edges().is_empty():
		report.add_error(&"chart.id_empty", "chart_id must not be empty.")
	if chart.difficulty_id.strip_edges().is_empty():
		report.add_error(&"chart.difficulty_empty", "difficulty_id must not be empty.")
	if chart.ppq != SongChart.DEFAULT_PPQ:
		report.add_error(&"chart.ppq_not_frozen", "MVP charts must use PPQ %d." % SongChart.DEFAULT_PPQ)
	if chart.end_tick <= 0:
		report.add_error(&"chart.end_invalid", "end_tick must be positive.", "", &"timing", chart.end_tick)


static func _validate_timing(chart: SongChart, report: ValidationReport) -> void:
	if chart.tempo_events.is_empty():
		report.add_error(&"tempo.empty", "At least one tempo event is required.", "", &"tempo", 0)
	var tempo_ticks: Dictionary = {}
	var has_zero_tempo: bool = false
	for event in chart.tempo_events:
		if event == null:
			report.add_error(&"tempo.null", "Tempo track contains a null event.", "", &"tempo", 0)
			continue
		if event.bpm <= 0.0 or not is_finite(event.bpm):
			report.add_error(&"tempo.bpm_invalid", "BPM must be finite and positive.", "", &"tempo", event.tick)
		if tempo_ticks.has(event.tick):
			report.add_error(&"tempo.duplicate_tick", "Only one tempo event is allowed at a tick.", "", &"tempo", event.tick)
		tempo_ticks[event.tick] = true
		has_zero_tempo = has_zero_tempo or event.tick == 0
	if not chart.tempo_events.is_empty() and not has_zero_tempo:
		report.add_error(&"tempo.missing_zero", "A tempo event at tick 0 is required.", "", &"tempo", 0)
	var meter_ticks: Dictionary = {}
	for event in chart.meter_events:
		if event == null:
			report.add_error(&"meter.null", "Meter track contains a null event.", "", &"meter", 0)
			continue
		if event.numerator <= 0 or not _is_power_of_two(event.denominator):
			report.add_error(&"meter.invalid", "Meter numerator must be positive and denominator must be a power of two.", "", &"meter", event.tick)
		if meter_ticks.has(event.tick):
			report.add_error(&"meter.duplicate_tick", "Only one meter event is allowed at a tick.", "", &"meter", event.tick)
		meter_ticks[event.tick] = true


static func _validate_notes(chart: SongChart, report: ValidationReport, ids: Dictionary) -> void:
	var groups: Dictionary = {}
	for note in chart.note_events:
		if note == null:
			report.add_error(&"note.null", "Note track contains a null event.", "", &"notes", 0)
			continue
		_register_id(note.event_id, &"notes", note.tick, ids, report)
		if note.tick < 0:
			report.add_warning(&"note.preroll", "Note occurs before tick 0.", note.event_id, &"notes", note.tick)
		if note.kind != GameplayTypes.NoteKind.TAP and note.kind != GameplayTypes.NoteKind.HOLD:
			report.add_error(&"note.kind_invalid", "Unsupported note kind.", note.event_id, &"notes", note.tick)
		if note.affinity != GameplayTypes.Affinity.ZHU and note.affinity != GameplayTypes.Affinity.XUAN:
			report.add_error(&"note.affinity_invalid", "Tap/Hold notes must be Zhu or Xuan.", note.event_id, &"notes", note.tick)
		if note.kind == GameplayTypes.NoteKind.TAP and note.duration_ticks != 0:
			report.add_error(&"note.tap_duration", "Tap duration must be zero.", note.event_id, &"notes", note.tick)
		if note.kind == GameplayTypes.NoteKind.HOLD and note.duration_ticks <= 0:
			report.add_error(&"note.hold_duration", "Hold duration must be positive.", note.event_id, &"notes", note.tick)
		if note.tick + maxi(0, note.duration_ticks) > chart.end_tick:
			report.add_error(&"note.after_chart_end", "Note extends beyond chart end.", note.event_id, &"notes", note.tick)
		if not note.group_id.is_empty():
			if not groups.has(note.group_id):
				groups[note.group_id] = []
			groups[note.group_id].append(note)
	for group_id in groups.keys():
		var members: Array = groups[group_id]
		if members.size() != 2:
			report.add_error(&"note.group_size", "Chord group '%s' must contain exactly two notes." % group_id, String(group_id), &"notes", 0)
			continue
		var first: NoteEvent = members[0]
		var second: NoteEvent = members[1]
		if first.tick != second.tick or first.affinity == second.affinity:
			report.add_error(&"note.group_mismatch", "Chord members must share a tick and use opposite affinities.", String(group_id), &"notes", mini(first.tick, second.tick))


static func _validate_tuning_fields(chart: SongChart, report: ValidationReport, ids: Dictionary) -> Dictionary:
	var by_id: Dictionary = {}
	var ordered_fields: Array[TuningFieldRegion] = []
	for field in chart.tuning_fields:
		if field == null:
			report.add_error(&"tuning_field.null", "Tuning field track contains a null region.", "", &"tuning_fields", 0)
			continue
		_register_id(field.event_id, &"tuning_fields", field.tick, ids, report)
		if not field.event_id.is_empty():
			by_id[field.event_id] = field
		if field.tick < 0:
			report.add_error(&"tuning_field.before_zero", "Tuning fields cannot begin before tick 0.", field.event_id, &"tuning_fields", field.tick)
		if field.duration_ticks <= 0:
			report.add_error(&"tuning_field.duration", "Tuning field duration must be positive.", field.event_id, &"tuning_fields", field.tick)
		if field.tick + maxi(0, field.duration_ticks) > chart.end_tick:
			report.add_error(&"tuning_field.after_chart_end", "Tuning field extends beyond chart end.", field.event_id, &"tuning_fields", field.tick)
		ordered_fields.append(field)
	ordered_fields.sort_custom(func(a: TuningFieldRegion, b: TuningFieldRegion) -> bool:
		if a.tick != b.tick:
			return a.tick < b.tick
		return a.event_id < b.event_id
	)
	for index in range(1, ordered_fields.size()):
		var previous: TuningFieldRegion = ordered_fields[index - 1]
		var current: TuningFieldRegion = ordered_fields[index]
		if previous.tick + previous.duration_ticks > current.tick:
			report.add_error(&"tuning_field.overlap", "Tuning fields '%s' and '%s' overlap." % [previous.event_id, current.event_id], current.event_id, &"tuning_fields", current.tick)
	return by_id


static func _validate_tuning_sliders(chart: SongChart, fields_by_id: Dictionary, rules: GameplayRuleSet, report: ValidationReport, ids: Dictionary) -> Dictionary:
	var groups: Dictionary = {}
	var sliders_by_side: Dictionary = {
		GameplayTypes.Affinity.ZHU: [],
		GameplayTypes.Affinity.XUAN: [],
	}
	for slider in chart.tuning_sliders:
		if slider == null:
			report.add_error(&"tuning_slider.null", "Tuning slider track contains a null event.", "", &"tuning_sliders", 0)
			continue
		_register_id(slider.event_id, &"tuning_sliders", slider.tick, ids, report)
		if not is_finite(slider.visual_radius_px) or slider.visual_radius_px < 0.0:
			report.add_error(&"tuning_slider.visual_radius", "Tuning 半径必须是有限的非负数，0 表示自动。", slider.event_id, &"tuning_sliders", slider.tick)
		if slider.tick < 0:
			report.add_error(&"tuning_slider.before_zero", "Tuning sliders cannot begin before tick 0.", slider.event_id, &"tuning_sliders", slider.tick)
		if slider.affinity != GameplayTypes.Affinity.ZHU and slider.affinity != GameplayTypes.Affinity.XUAN:
			report.add_error(&"tuning_slider.affinity", "Tuning sliders must belong to Zhu or Xuan.", slider.event_id, &"tuning_sliders", slider.tick)
		elif sliders_by_side.has(slider.affinity):
			sliders_by_side[slider.affinity].append(slider)
		if slider.traversal_ticks <= 0:
			report.add_error(&"tuning_slider.traversal_ticks", "traversal_ticks must be positive.", slider.event_id, &"tuning_sliders", slider.tick)
		if slider.traversal_count < 1 or slider.traversal_count > 32:
			report.add_error(&"tuning_slider.traversal_count", "traversal_count must be between 1 and 32.", slider.event_id, &"tuning_sliders", slider.tick)
		if not _is_normalized_finite(slider.start_value) or not _is_normalized_finite(slider.end_value):
			report.add_error(&"tuning_slider.value", "Slider endpoints must be finite values in [0, 1].", slider.event_id, &"tuning_sliders", slider.tick)
		elif is_equal_approx(slider.start_value, slider.end_value):
			report.add_error(&"tuning_slider.zero_span", "Slider endpoints must differ so the operation has a visible frequency span.", slider.event_id, &"tuning_sliders", slider.tick)
		var duration_ticks: int = maxi(0, slider.traversal_ticks) * maxi(0, slider.traversal_count)
		var slider_end_tick: int = slider.tick + duration_ticks
		if slider_end_tick > chart.end_tick:
			report.add_error(&"tuning_slider.after_chart_end", "Tuning slider extends beyond chart end.", slider.event_id, &"tuning_sliders", slider.tick)
		if not fields_by_id.has(slider.field_id):
			report.add_error(&"tuning_slider.field_missing", "Tuning slider references a missing tuning field.", slider.event_id, &"tuning_sliders", slider.tick)
		else:
			var field: TuningFieldRegion = fields_by_id[slider.field_id]
			if slider.tick < field.tick or slider_end_tick > field.tick + field.duration_ticks:
				report.add_error(&"tuning_slider.outside_field", "Tuning slider must lie completely inside its tuning field.", slider.event_id, &"tuning_sliders", slider.tick)
		if not slider.group_id.is_empty():
			if not groups.has(slider.group_id):
				groups[slider.group_id] = []
			groups[slider.group_id].append(slider)

	for side: int in sliders_by_side.keys():
		var ordered: Array = sliders_by_side[side]
		ordered.sort_custom(func(a: TuningSliderEvent, b: TuningSliderEvent) -> bool:
			if a.tick != b.tick:
				return a.tick < b.tick
			return a.event_id < b.event_id
		)
		for index in range(1, ordered.size()):
			var previous: TuningSliderEvent = ordered[index - 1]
			var current: TuningSliderEvent = ordered[index]
			var previous_end: int = previous.tick + previous.traversal_ticks * previous.traversal_count
			if previous_end > current.tick:
				report.add_error(&"tuning_slider.same_side_overlap", "Same-side tuning sliders '%s' and '%s' overlap." % [previous.event_id, current.event_id], current.event_id, &"tuning_sliders", current.tick)
	for group_id: String in groups.keys():
		var members: Array = groups[group_id]
		if members.size() != 2:
			report.add_error(&"tuning_slider.group_size", "Tuning group '%s' must contain exactly one Zhu slider and one Xuan slider." % group_id, group_id, &"tuning_sliders", 0)
			continue
		var first: TuningSliderEvent = members[0]
		var second: TuningSliderEvent = members[1]
		if first.affinity == second.affinity:
			report.add_error(&"tuning_slider.group_affinity", "Grouped tuning sliders must use opposite affinities.", group_id, &"tuning_sliders", mini(first.tick, second.tick))
		if first.field_id != second.field_id:
			report.add_error(&"tuning_slider.group_field", "Grouped tuning sliders must belong to the same tuning field.", group_id, &"tuning_sliders", mini(first.tick, second.tick))
		if first.tick != second.tick or first.traversal_ticks != second.traversal_ticks or first.traversal_count != second.traversal_count:
			report.add_error(&"tuning_slider.group_timing", "Grouped tuning sliders must share their start tick and traversal timing.", group_id, &"tuning_sliders", mini(first.tick, second.tick))
	return groups


static func _validate_su_manifestations(chart: SongChart, fields_by_id: Dictionary, slider_groups: Dictionary, report: ValidationReport, ids: Dictionary) -> void:
	for manifestation in chart.su_manifestations:
		if manifestation == null:
			report.add_error(&"su_manifestation.null", "Su manifestation track contains a null event.", "", &"su_manifestations", 0)
			continue
		_register_id(manifestation.event_id, &"su_manifestations", manifestation.tick, ids, report)
		if manifestation.tick < 0 or manifestation.tick > chart.end_tick:
			report.add_error(&"su_manifestation.outside_chart", "Su manifestation must lie inside chart bounds.", manifestation.event_id, &"su_manifestations", manifestation.tick)
		if manifestation.count < 1 or manifestation.count > 16:
			report.add_error(&"su_manifestation.count", "Su manifestation count must be between 1 and 16.", manifestation.event_id, &"su_manifestations", manifestation.tick)
		if manifestation.target_hold_duration_sec <= 0.0:
			report.add_error(&"su_manifestation.target_hold_duration", "Target hold duration must be positive.", manifestation.event_id, &"su_manifestations", manifestation.tick)
		if not _normalized_rect_is_valid(manifestation.spawn_region_normalized):
			report.add_error(&"su_manifestation.spawn_region", "spawn_region_normalized must have positive size and stay inside the normalized canvas.", manifestation.event_id, &"su_manifestations", manifestation.tick)
		if manifestation.group_id.is_empty():
			continue
		if not slider_groups.has(manifestation.group_id):
			report.add_error(&"su_manifestation.group_missing", "Su manifestation references a missing tuning group.", manifestation.event_id, &"su_manifestations", manifestation.tick)
			continue
		var members: Array = slider_groups[manifestation.group_id]
		if members.size() != 2:
			# 组本身的具体错误已由滑条校验报告；此处只阻止继续解引用不完整组。
			continue
		var first: TuningSliderEvent = members[0]
		var second: TuningSliderEvent = members[1]
		if first.affinity == second.affinity or first.field_id != second.field_id:
			continue
		var group_end_tick: int = first.tick + first.traversal_ticks * first.traversal_count
		if manifestation.tick < group_end_tick:
			report.add_error(&"su_manifestation.before_group_end", "Su manifestation cannot resolve before its paired tuning judgment ends.", manifestation.event_id, &"su_manifestations", manifestation.tick)
		if fields_by_id.has(first.field_id):
			var field: TuningFieldRegion = fields_by_id[first.field_id]
			if manifestation.tick > field.tick + field.duration_ticks:
				report.add_error(&"su_manifestation.after_field", "Su manifestation must occur before its tuning field closes.", manifestation.event_id, &"su_manifestations", manifestation.tick)


static func _validate_rapid(chart: SongChart, report: ValidationReport, ids: Dictionary) -> void:
	for region in chart.rapid_regions:
		if region == null:
			report.add_error(&"rapid.null", "Rapid track contains a null region.", "", &"rapid", 0)
			continue
		_register_id(region.event_id, &"rapid", region.tick, ids, report)
		if region.duration_ticks <= 0:
			report.add_error(&"rapid.duration", "Rapid duration must be positive.", region.event_id, &"rapid", region.tick)
		if region.tick + region.duration_ticks > chart.end_tick:
			report.add_error(&"rapid.after_chart_end", "Rapid region extends beyond chart end.", region.event_id, &"rapid", region.tick)
		if region.required_strikes < 2:
			report.add_error(&"rapid.strikes", "Rapid region requires at least two strikes.", region.event_id, &"rapid", region.tick)
		if region.debounce_ms < 0:
			report.add_error(&"rapid.debounce", "Rapid debounce cannot be negative.", region.event_id, &"rapid", region.tick)
		if not chart.tempo_events.is_empty() and region.duration_ticks > 0 and region.required_strikes >= 2:
			var tempo_map := TempoMap.from_chart(chart)
			var duration_us: int = tempo_map.tick_span_to_us(region.tick, region.tick + region.duration_ticks)
			# 起点可以先敲一次，此后每次至少相隔 debounce；提前拒绝理论上塞不下的目标次数。
			var maximum_strikes: int = 1 + duration_us / maxi(1, region.debounce_ms * 1000)
			if region.required_strikes > maximum_strikes:
				report.add_error(&"rapid.impossible_density", "required_strikes cannot fit inside the region after debounce.", region.event_id, &"rapid", region.tick)


static func _validate_sections(chart: SongChart, report: ValidationReport, ids: Dictionary) -> void:
	for section in chart.sections:
		if section == null:
			report.add_error(&"section.null", "Section track contains a null marker.", "", &"sections", 0)
			continue
		_register_id(section.event_id, &"sections", section.tick, ids, report)
		if section.tick < 0 or section.tick > chart.end_tick:
			report.add_error(&"section.outside_chart", "Section marker lies outside chart bounds.", section.event_id, &"sections", section.tick)


static func _validate_rules(rules: GameplayRuleSet, report: ValidationReport) -> void:
	if rules.perfect_window_ms > rules.good_window_ms or rules.good_window_ms > rules.pass_window_ms or rules.pass_window_ms > rules.miss_window_ms:
		report.add_error(&"rules.tap_windows", "Tap windows must satisfy Perfect <= Good <= Pass <= Miss.")
	# hold_release_* 只为旧资源反序列化保留，不再影响玩法，故不再校验其大小关系。
	if rules.tuning_sample_interval_ticks <= 0:
		report.add_error(&"rules.tuning_sample_step", "Tuning sample interval must be positive.")
	if rules.tuning_guide_time_window_ms < 0:
		report.add_error(&"rules.tuning_time_window", "Tuning guide time window cannot be negative.")
	if not is_finite(rules.tuning_spatial_margin) or rules.tuning_spatial_margin < 0.0 or rules.tuning_spatial_margin > 0.5:
		report.add_error(&"rules.tuning_spatial_margin", "Tuning spatial margin must be finite and in [0, 0.5].")
	if not is_finite(rules.tuning_min_frequency_hz) or not is_finite(rules.tuning_base_frequency_hz) or not is_finite(rules.tuning_max_frequency_hz) or rules.tuning_min_frequency_hz <= 0.0 or rules.tuning_min_frequency_hz >= rules.tuning_max_frequency_hz or rules.tuning_base_frequency_hz < rules.tuning_min_frequency_hz or rules.tuning_base_frequency_hz > rules.tuning_max_frequency_hz:
		report.add_error(&"rules.tuning_frequency_range", "Tuning frequencies must satisfy 0 < minimum <= base <= maximum, with minimum < maximum.")
	if not is_finite(rules.tuning_pixels_per_hz) or rules.tuning_pixels_per_hz <= 0.0:
		report.add_error(&"rules.tuning_scale", "Tuning pixels per Hz must be finite and positive.")
	if not is_finite(rules.tuning_hz_per_revolution) or rules.tuning_hz_per_revolution <= 0.0:
		report.add_error(&"rules.tuning_rotation_scale", "Tuning Hz per revolution must be finite and positive.")
	if rules.rapid_perfect_ratio > 1.0 or rules.rapid_good_ratio > rules.rapid_perfect_ratio or rules.rapid_pass_ratio > rules.rapid_good_ratio or rules.rapid_pass_ratio <= 0.0:
		report.add_error(&"rules.rapid_ratios", "Rapid ratios must satisfy 1 >= Perfect >= Good >= Pass > 0.")
	if rules.pass_score <= 0:
		report.add_error(&"rules.pass_score", "PASS score must be non-zero.")
	if rules.stray_input_breaks_combo or rules.stray_input_damages:
		report.add_warning(&"rules.stray_penalty", "Current design specifies that stray input neither breaks Combo nor damages soul fire.")
	if rules.wave_speed_px_sec <= 0.0 or rules.wave_front_half_width_px <= 0.0:
		report.add_error(&"rules.wave_motion", "Physical wave speed and front width must be positive.")
	if rules.wave_canvas_size.x <= 0.0 or rules.wave_canvas_size.y <= 0.0:
		report.add_error(&"rules.wave_canvas", "Physical wave canvas must have a positive size.")
	if rules.life_note_spawn.is_equal_approx(rules.life_note_cue) or rules.death_note_spawn.is_equal_approx(rules.death_note_cue):
		report.add_error(&"rules.note_motion", "Each note spawn must be separated from its central cue.")
	if rules.life_wave_origin.is_equal_approx(rules.life_note_cue) or rules.death_wave_origin.is_equal_approx(rules.death_note_cue):
		report.add_error(&"rules.wave_contact", "Each bell origin must be separated from its note cue so a wave can meet the incoming note.")


static func input_intervals(chart: SongChart, rules: GameplayRuleSet) -> Array[Dictionary]:
	var tempo_map := TempoMap.from_chart(chart)
	var intervals: Array[Dictionary] = []
	var pass_us: int = rules.pass_window_ms * 1000
	for note in chart.note_events:
		if note == null:
			continue
		var start_us: int = tempo_map.tick_to_us(note.tick)
		var end_us: int = start_us
		if note.kind == GameplayTypes.NoteKind.HOLD:
			end_us = tempo_map.tick_to_us(note.tick + note.duration_ticks)
		intervals.append({
			"id": note.event_id,
			"type": "hold" if note.kind == GameplayTypes.NoteKind.HOLD else "tap",
			"side": note.affinity,
			"start": start_us - pass_us,
			# Hold 的占用在尾点结束；旧版松键判定窗已经废弃。
			"end": end_us if note.kind == GameplayTypes.NoteKind.HOLD else end_us + pass_us,
			"tick": note.tick,
		})
	for slider in chart.tuning_sliders:
		if slider == null:
			continue
		var slider_end_tick: int = slider.tick + slider.traversal_ticks * slider.traversal_count
		intervals.append({
			"id": slider.event_id,
			"type": "tuning",
			"side": slider.affinity,
			"start": tempo_map.tick_to_us(slider.tick),
			"end": tempo_map.tick_to_us(slider_end_tick),
			"tick": slider.tick,
		})
	for region in chart.rapid_regions:
		if region == null:
			continue
		intervals.append({
			"id": region.event_id,
			"type": "rapid",
			"side": -1,
			"start": tempo_map.tick_to_us(region.tick),
			"end": tempo_map.tick_to_us(region.tick + region.duration_ticks),
			"tick": region.tick,
		})
	return intervals


static func _validate_input_conflicts(chart: SongChart, rules: GameplayRuleSet, report: ValidationReport) -> void:
	var intervals := input_intervals(chart, rules)
	# 按起点扫描，超过当前区间尾点后不再比较；重叠判定和闭区间边界保持原样。
	for index in intervals.size(): intervals[index]["source_order"] = index
	intervals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["start"]) < int(b["start"]))
	for first_index in range(intervals.size()):
		for second_index in range(first_index + 1, intervals.size()):
			var first: Dictionary = intervals[first_index]
			var second: Dictionary = intervals[second_index]
			if int(second["start"]) > int(first["end"]): break
			if not input_intervals_conflict(first, second): continue
			if first["source_order"] > second["source_order"]:
				var swap := first; first = second; second = swap
			report.add_error(
				&"input.window_conflict",
				"Gameplay input windows overlap between '%s' and '%s'." % [first["id"], second["id"]],
				String(first["id"]),
				&"gameplay",
				mini(int(first["tick"]), int(second["tick"]))
			)


static func _register_id(event_id: String, track: StringName, tick: int, ids: Dictionary, report: ValidationReport) -> void:
	if event_id.strip_edges().is_empty():
		report.add_error(&"event.id_empty", "Every chart event requires a stable ID.", event_id, track, tick)
		return
	if ids.has(event_id):
		report.add_error(&"event.id_duplicate", "Duplicate event ID '%s'." % event_id, event_id, track, tick)
		return
	ids[event_id] = true


static func _is_power_of_two(value: int) -> bool:
	return value > 0 and (value & (value - 1)) == 0


static func _is_normalized_finite(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0


static func _normalized_rect_is_valid(region: Rect2) -> bool:
	var end: Vector2 = region.position + region.size
	return (
		is_finite(region.position.x)
		and is_finite(region.position.y)
		and is_finite(region.size.x)
		and is_finite(region.size.y)
		and region.position.x >= 0.0
		and region.position.y >= 0.0
		and region.size.x > 0.0
		and region.size.y > 0.0
		and end.x <= 1.0
		and end.y <= 1.0
	)


static func input_intervals_conflict(first: Dictionary, second: Dictionary) -> bool:
	# 编辑器草稿查询和正式校验共用闭区间、异侧及 Tap 例外。
	if int(first.side) != -1 and int(second.side) != -1 and int(first.side) != int(second.side): return false
	var start := maxi(int(first.start), int(second.start))
	var end := mini(int(first.end), int(second.end))
	if start > end: return false
	if start == end and first.type == "tuning" and second.type == "tuning": return false
	# 调频位移与 Hold 持续可同时存在；共享查询也遵循正式双 Hold 联动规则。
	if (first.type == "hold" and second.type == "tuning") or (first.type == "tuning" and second.type == "hold"): return false
	return not (first.type == "tap" and second.type == "tap")
