class_name StudioCueEvents
extends RefCounted
## 秒事件只服务试听；所有正式拍点都从公共 TempoMap 和拍号计算。
static func build(doc: StudioDocument, notes_enabled: bool, metronome_enabled: bool, candidate: Dictionary, duration: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var map := doc.tempo_map(); var chart := doc.chart()
	if notes_enabled:
		for note in chart.note_events:
			result.append({"seconds": map.tick_to_us(note.tick) / 1000000.0, "sample": &"life" if note.affinity == 0 else &"death"})
	if not candidate.is_empty():
		var period := 60.0 / float(candidate.bpm)
		var anchor := float(candidate.anchor); var meter := int(candidate.meter)
		for i in range(ceili((0 - anchor) / period), floori((duration - anchor) / period) + 1):
			result.append({"seconds": anchor + i * period, "sample": &"strong" if meter > 0 and posmod(i, meter) == 0 else &"beat"})
	elif metronome_enabled:
		var meters: Array = chart.meter_events.duplicate()
		meters.sort_custom(func(a: MeterEvent, b: MeterEvent) -> bool: return a.tick < b.tick)
		if meters.is_empty(): meters.append(MeterEvent.new())
		for i in meters.size():
			var meter: MeterEvent = meters[i]
			var step := maxi(1, chart.ppq * 4 / meter.denominator)
			var end: int = meters[i + 1].tick - 1 if i + 1 < meters.size() else chart.end_tick
			var index := 0
			for tick in range(meter.tick, end + 1, step):
				result.append({"seconds": map.tick_to_us(tick) / 1000000.0, "sample": &"strong" if index % meter.numerator == 0 else &"beat"}); index += 1
	return result
