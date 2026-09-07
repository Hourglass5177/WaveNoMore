class_name StudioRhythmTools
extends RefCounted
## 分析候选使用音频秒；正式写入仍经过 TempoMap 和既有编辑命令。
static func apply_grid(doc: StudioDocument, bpm: float, anchor: float, numerator: int) -> void:
	var data := ChartJsonCodec.encode_chart(doc.chart())
	data.timing.tempo_events = [{"tick": 0, "bpm": bpm}]
	data.timing.meter_events = [{"tick": 0, "numerator": numerator, "denominator": 4}]
	# 锚点是谱面 tick 0，不是有效 tick 0；高级全谱偏移保持原值。
	data.timing.first_beat_offset_ms = anchor * 1000.0 - doc.chart().chart_offset_ticks * 60000.0 / bpm / doc.chart().ppq
	doc.change_metadata(data)

static func diagnose(raw: Dictionary, bpm: float, anchor: float, meter: int) -> Dictionary:
	var period := 60.0 / bpm
	var errors: Array[float] = []
	var signed_errors: Array[float] = []
	var regions: Array = []
	var segments: Array = []
	var previous := -1.0
	for time: float in raw.get("beats", []):
		# 正数始终表示候选网格晚于检测点；检测结果只是参照，不是人工真值。
		var error := anchor + roundf((time - anchor) / period) * period - time
		signed_errors.append(error); errors.append(absf(error))
		if previous >= 0 and time - previous > period * 4: regions.append({"start": previous, "end": time, "reason": "拍点缺失或静音"})
		previous = time
	# 长前奏和尾奏也提示，由谱师决定是否排除；不静默删去生成范围。
	var beats: Array = raw.get("beats", [])
	for first in range(0, maxi(1, beats.size() - 7), 8):
		var last := mini(first + 16, beats.size())
		if last - first < 2: continue
		var local: Array[float] = signed_errors.slice(first, last)
		var median := _median(local)
		var duration := float(beats[last - 1]) - float(beats[first])
		var coverage := minf(1, (last - first) / (duration / period + 1))
		# 连续展开相位再求局部趋势，避免半周期边界的换号伪造漂移。
		var unwrapped := local.duplicate()
		for i in range(1, unwrapped.size()):
			unwrapped[i] = unwrapped[i - 1] + wrapf(local[i] - local[i - 1], -period / 2, period / 2)
		var mean_time := 0.0
		var mean_error := 0.0
		for i in local.size(): mean_time += float(beats[first + i]); mean_error += unwrapped[i]
		mean_time /= local.size(); mean_error /= local.size()
		var variance := 0.0
		var covariance := 0.0
		for i in local.size():
			var delta := float(beats[first + i]) - mean_time
			variance += delta * delta; covariance += delta * (unwrapped[i] - mean_error)
		var slope := covariance / maxf(variance, 0.000001)
		var spread: Array[float] = []
		for error in local: spread.append(absf(error - median))
		spread.sort()
		var reason := ""
		if absf(slope * duration) > 0.02 and absf(slope) > 0.0005:
			reason = "网格逐渐%s（%+.2f ms/秒）" % ["偏晚" if slope > 0 else "偏早", slope * 1000]
		elif absf(median) > 0.02:
			reason = "网格整体%s（%+.1f ms）" % ["偏晚" if median > 0 else "偏早", median * 1000]
		if spread[mini(spread.size() - 1, floori(spread.size() * 0.95))] > 0.04:
			reason = "局部节拍不一致，可能变速或检测不稳定"
		if coverage < 0.7: reason += ("；" if not reason.is_empty() else "") + "检测覆盖较少，可能漏拍或半速识别"
		var segment := {"start": beats[first], "end": beats[last - 1], "signed_ms": median * 1000,
			"trend_ms_per_sec": slope * 1000, "coverage": coverage, "reason": reason}
		segments.append(segment)
		if not reason.is_empty(): regions.append(segment)
	var span: Array = raw.get("range", [])
	if not beats.is_empty() and span.size() == 2:
		if float(beats.front()) - float(span[0]) > period * 4: regions.append({"start": span[0], "end": beats.front(), "reason": "开头缺少拍点或静音"})
		if float(span[1]) - float(beats.back()) > period * 4: regions.append({"start": beats.back(), "end": span[1], "reason": "结尾缺少拍点或静音"})
	if meter > 0:
		for time: float in raw.get("downbeats", []):
			if posmod(roundi((time - anchor) / period), meter) != 0: regions.append({"start": time, "end": time + period, "reason": "小节重拍不一致"})
	errors.sort()
	return {"median_ms": _median(errors) * 1000.0, "signed_ms": _median(signed_errors) * 1000.0,
		"regions": regions, "segments": segments}

static func _median(values: Array[float]) -> float:
	if values.is_empty(): return 0
	var sorted := values.duplicate(); sorted.sort()
	var middle := sorted.size() / 2
	return sorted[middle] if sorted.size() % 2 else (sorted[middle - 1] + sorted[middle]) / 2

static func generate(doc: StudioDocument, span: Vector2, every_beat: bool, side: int, exclusions: Array) -> Dictionary:
	var chart := doc.chart()
	var map := doc.tempo_map()
	var rules: GameplayRuleSet = load("res://content/rules/default_gameplay_rules.tres")
	var occupied := ChartValidator.input_intervals(chart, rules)
	occupied.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.start) < int(b.start))
	var next_interval := 0
	var active: Array[Dictionary] = []
	var duplicates := {}
	for note in chart.note_events:
		if note.kind == GameplayTypes.NoteKind.TAP: duplicates["%s:%s" % [note.affinity, note.tick]] = true
	var notes: Array[NoteEvent] = []
	var issues: Array = []
	var repeated := 0
	var skipped := 0
	var meters: Array = []
	for m in chart.meter_events: meters.append({"tick": m.tick, "n": m.numerator, "d": m.denominator})
	meters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick)
	if meters.is_empty() or meters[0].tick > 0: meters.push_front({"tick": 0, "n": 4, "d": 4})
	var first := maxi(0, ceili(map.us_to_tick(roundi(maxf(0, span.x) * 1000000))))
	var last := mini(chart.end_tick, floori(map.us_to_tick(roundi(span.y * 1000000))))
	var ordinal := 0
	var single := SongChart.new(); single.ppq = chart.ppq; single.chart_offset_ticks = chart.chart_offset_ticks; single.tempo_events = chart.tempo_events
	for i in meters.size():
		var m: Dictionary = meters[i]
		var step := maxi(1, chart.ppq * 4 / int(m.d) * (1 if every_beat else int(m.n)))
		var start := maxi(first, int(m.tick))
		var end := mini(last, int(meters[i + 1].tick) - 1 if i + 1 < meters.size() else last)
		var tick := int(m.tick) + ceili(float(start - int(m.tick)) / step) * step
		while tick <= end:
			var affinity := ordinal % 2 if side == 2 else side
			ordinal += 1
			var seconds := map.tick_to_us(tick) / 1000000.0
			var excluded := false
			for region: Vector2 in exclusions:
				if seconds >= region.x and seconds <= region.y: excluded = true; break
			if excluded: skipped += 1; tick += step; continue
			if duplicates.has("%s:%s" % [affinity, tick]): repeated += 1; tick += step; continue
			var note := NoteEvent.new(); note.event_id = StudioDocument.new_id("draft"); note.tick = tick; note.affinity = affinity
			single.note_events.assign([note])
			var candidate: Dictionary = ChartValidator.input_intervals(single, rules)[0]
			# 候选按时间递增；只保留仍可能重叠的正式区间，避免密集谱反复全表扫描。
			while next_interval < occupied.size() and int(occupied[next_interval].start) <= int(candidate.end):
				active.append(occupied[next_interval]); next_interval += 1
			active = active.filter(func(interval: Dictionary) -> bool: return int(interval.end) >= int(candidate.start))
			var conflict := ""
			for interval in active:
				if ChartValidator.input_intervals_conflict(candidate, interval): conflict = str(interval.id); break
			if conflict.is_empty(): notes.append(note); active.append(candidate)
			else: issues.append({"start": seconds, "end": seconds, "reason": "与音符 %s 的输入区间冲突" % conflict})
			tick += step
	return {"notes": notes, "issues": issues, "duplicates": repeated, "excluded": skipped}
