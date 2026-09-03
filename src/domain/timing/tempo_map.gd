class_name TempoMap
extends RefCounted

## 纯 tick/时间换算器。资源层允许 float BPM，但公开时间都明确舍入到整数微秒，
## 防止各玩法系统按帧累加并产生不同结果。

## 一分钟的微秒数；领域时间统一用整数微秒，避免浮点秒累计漂移。
const USEC_PER_MINUTE: float = 60_000_000.0

## 每四分音符包含的 tick 数；越大谱面时间分辨率越高。
var ppq: int = 480
## 编译时加到所有作者 tick 上的全局整数偏移；正值整体推迟，负值整体提前。
var chart_offset_ticks: int = 0
## 音频开头到谱面 tick 0 的有符号微秒；正值表示首拍晚于音频开头。
var first_beat_offset_us: int = 0
## 预计算后的变速段，按起始 tick 排序，供双向时间换算二分/顺序查询。
var _events: Array[Dictionary] = []


static func from_chart(chart: SongChart, p_first_beat_offset_us: int = 0) -> TempoMap:
	var result := TempoMap.new()
	result.configure(chart.ppq, chart.chart_offset_ticks, chart.tempo_events, p_first_beat_offset_us)
	return result


func configure(
		p_ppq: int,
		p_chart_offset_ticks: int,
		tempo_events: Array[TempoEvent],
		p_first_beat_offset_us: int = 0
) -> void:
	ppq = maxi(1, p_ppq)
	chart_offset_ticks = p_chart_offset_ticks
	first_beat_offset_us = p_first_beat_offset_us
	_events.clear()
	for event in tempo_events:
		if event == null:
			continue
		_events.append({"tick": event.tick, "bpm": event.bpm})
	_events.sort_custom(_sort_tempo_event)
	if _events.is_empty():
		_events.append({"tick": 0, "bpm": 120.0})


func tick_to_us(tick: int) -> int:
	var effective_tick: int = tick + chart_offset_ticks
	if effective_tick >= 0:
		return first_beat_offset_us + _duration_between_ticks(0, effective_tick)
	return first_beat_offset_us - _duration_between_ticks(effective_tick, 0)


func tick_span_to_us(from_tick: int, to_tick: int) -> int:
	return tick_to_us(to_tick) - tick_to_us(from_tick)


func us_to_tick(time_us: int) -> float:
	# 用二分搜索取得相邻整数 tick，再在区间内插值；整个反算不依赖帧 delta。
	var target_us: int = time_us
	var low: int = -1
	var high: int = 1
	while tick_to_us(low) > target_us:
		high = low
		low *= 2
	while tick_to_us(high) < target_us:
		low = high
		high *= 2
	for _iteration in range(64):
		if high - low <= 1:
			break
		var middle: int = low + (high - low) / 2
		if tick_to_us(middle) <= target_us:
			low = middle
		else:
			high = middle
	var low_us: int = tick_to_us(low)
	var high_us: int = tick_to_us(high)
	if high_us == low_us:
		return float(low)
	return float(low) + float(target_us - low_us) / float(high_us - low_us)


func us_to_tick_rounded(time_us: int) -> int:
	return roundi(us_to_tick(time_us))


func bpm_at_tick(tick: int) -> float:
	var chosen_bpm: float = float(_events[0]["bpm"])
	for event in _events:
		if int(event["tick"]) > tick:
			break
		chosen_bpm = float(event["bpm"])
	return chosen_bpm


func events_copy() -> Array[Dictionary]:
	return _events.duplicate(true)


func _duration_between_ticks(from_tick: int, to_tick: int) -> int:
	if to_tick <= from_tick:
		return 0
	var cursor: int = from_tick
	var bpm: float = bpm_at_tick(from_tick)
	var total_us: int = 0
	for event in _events:
		var event_tick: int = int(event["tick"])
		if event_tick <= from_tick:
			continue
		if event_tick >= to_tick:
			break
		total_us += _ticks_at_bpm_to_us(event_tick - cursor, bpm)
		cursor = event_tick
		bpm = float(event["bpm"])
	total_us += _ticks_at_bpm_to_us(to_tick - cursor, bpm)
	return total_us


func _ticks_at_bpm_to_us(ticks: int, bpm: float) -> int:
	if ticks == 0:
		return 0
	if bpm <= 0.0:
		return 0
	return roundi(USEC_PER_MINUTE * float(ticks) / (bpm * float(ppq)))


static func _sort_tempo_event(a: Dictionary, b: Dictionary) -> bool:
	if int(a["tick"]) != int(b["tick"]):
		return int(a["tick"]) < int(b["tick"])
	return float(a["bpm"]) < float(b["bpm"])
