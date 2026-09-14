class_name GhostWaveForecast
extends RefCounted
## 装载时编好正确跟随引导的改频与按钟时间线，生成 Ghost 时只重演未来区间。
var _events: Array[Dictionary] = []
var _holds: Array[Dictionary] = []
func configure(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	_events.clear(); _holds.clear()
	if compiled.su_manifestations.is_empty(): return
	for side: int in 2:
		var intervals: Array[Dictionary] = []
		for note: Dictionary in compiled.notes:
			if int(note.affinity) == side and note.unit_kind == &"hold": intervals.append({"start":int(note.start_us),"end":int(note.end_us)})
		intervals.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.start) < int(b.start))
		var merged: Array[Dictionary] = []
		for interval: Dictionary in intervals:
			if not merged.is_empty() and int(interval.start) <= int(merged[-1].end): merged[-1].end = maxi(int(merged[-1].end),int(interval.end))
			else: merged.append(interval)
		for interval: Dictionary in merged:
			_holds.append({"side":side,"start":int(interval.start),"end":int(interval.end)})
			_events.append({"time":int(interval.start),"side":side,"held":true,"priority":0})
			_events.append({"time":int(interval.end)+1,"side":side,"held":false,"priority":3})
	for field: Dictionary in compiled.tuning_fields:
		for side: int in 2:
			_events.append({"time":int(field.start_us),"side":side,"hz":rules.tuning_base_frequency_hz,"priority":1})
			_events.append({"time":int(field.end_us)+1,"side":side,"hz":rules.tuning_base_frequency_hz,"priority":1})
	for slider: Dictionary in compiled.tuning_sliders:
		var tick := int(slider.tick)
		while true:
			var elapsed := tick - int(slider.tick)
			var leg := mini(int(slider.traversal_count)-1, elapsed / int(slider.traversal_ticks))
			var ratio := float(elapsed - leg * int(slider.traversal_ticks)) / float(slider.traversal_ticks)
			if leg % 2 == 1: ratio = 1.0 - ratio
			var value := lerpf(float(slider.start_value), float(slider.end_value), ratio)
			_events.append({"time":compiled.tempo_map.tick_to_us(tick),"side":int(slider.affinity),"hz":lerpf(rules.tuning_min_frequency_hz,rules.tuning_max_frequency_hz,value),"priority":2})
			if tick == int(slider.end_tick): break
			tick = mini(int(slider.end_tick), tick + maxi(1,rules.tuning_sample_interval_ticks))
	_events.sort_custom(func(a: Dictionary,b: Dictionary):
		if a.time != b.time: return a.time < b.time
		if a.priority != b.priority: return a.priority < b.priority
		return a.side < b.side)

func predict(source: CarrierWaveEngine, at_us: int, target_us: int) -> CarrierWaveEngine:
	var forecast := source.fork_prediction()
	# 只假设从预测点起正确持有；预测点之前已经错过的波绝不补造。
	for interval: Dictionary in _holds:
		if int(interval.start) <= at_us and at_us <= int(interval.end): forecast.set_held(int(interval.side),true,at_us)
	var left := 0; var right := _events.size()
	while left < right:
		var mid := (left+right)/2
		if int(_events[mid].time) <= at_us: left = mid+1
		else: right = mid
	for index: int in range(left,_events.size()):
		var event: Dictionary = _events[index]
		if int(event.time) > target_us: break
		if event.has("held"): forecast.set_held(int(event.side),bool(event.held),int(event.time))
		else: forecast.set_frequency(int(event.side),float(event.hz),int(event.time))
	forecast.advance_to(target_us)
	return forecast
