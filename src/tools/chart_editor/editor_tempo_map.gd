## 写谱器的时间换算适配层。优先调用正式 TempoMap，备用分段表只保证工具在隔离环境也能工作。
@tool
class_name MingheEditorTempoMap
extends RefCounted

## 当前换算所依据的 SongChart，主要读取 ppq 和 tempo_events。
var chart: Resource
## 正式运行时 TempoMap；为空或不可用时才使用 `_segments` 后备表。
var shared_tempo_map: Object
## 工具备用的变速分段；每项记录起点 tick、BPM 和该点累计秒数。
var _segments: Array[Dictionary] = []


func configure(source_chart: Resource, shared: Object = null) -> void:
	chart = source_chart
	shared_tempo_map = shared
	_segments.clear()
	if (shared_tempo_map == null or shared_tempo_map is TempoMap) and chart is SongChart:
		shared_tempo_map = TempoMap.from_chart(chart)
	elif shared_tempo_map != null and shared_tempo_map.has_method("from_chart"):
		shared_tempo_map = shared_tempo_map.call("from_chart", chart)
	_build_editor_segments()


func tick_to_seconds(tick: int) -> float:
	if shared_tempo_map != null and shared_tempo_map.has_method("tick_to_seconds"):
		return float(shared_tempo_map.call("tick_to_seconds", tick))
	if shared_tempo_map != null and shared_tempo_map.has_method("tick_to_us"):
		return float(shared_tempo_map.call("tick_to_us", tick)) / 1_000_000.0
	if _segments.is_empty():
		return float(tick) / float(_ppq()) * 0.5
	var segment: Dictionary = _segments[0]
	for candidate in _segments:
		if int(candidate.tick) > tick:
			break
		segment = candidate
	return float(segment.start_sec) + float(tick - int(segment.tick)) * 60.0 / (float(segment.bpm) * float(_ppq()))


func seconds_to_tick(seconds: float) -> int:
	if shared_tempo_map != null and shared_tempo_map.has_method("seconds_to_tick"):
		return int(shared_tempo_map.call("seconds_to_tick", seconds))
	if shared_tempo_map != null and shared_tempo_map.has_method("us_to_tick_rounded"):
		return int(shared_tempo_map.call("us_to_tick_rounded", roundi(seconds * 1_000_000.0)))
	if _segments.is_empty():
		return roundi(seconds * float(_ppq()) / 0.5)
	var segment: Dictionary = _segments[0]
	for candidate in _segments:
		if float(candidate.start_sec) > seconds:
			break
		segment = candidate
	return int(segment.tick) + roundi((seconds - float(segment.start_sec)) * float(segment.bpm) * float(_ppq()) / 60.0)


func snap_tick(tick: int, snap_ticks: int) -> int:
	if snap_ticks <= 1:
		return tick
	return roundi(float(tick) / float(snap_ticks)) * snap_ticks


func ppq() -> int:
	return _ppq()


func bpm_at_tick(tick: int) -> float:
	if _segments.is_empty():
		return 120.0
	var bpm := float(_segments[0].bpm)
	for segment in _segments:
		if int(segment.tick) > tick:
			break
		bpm = float(segment.bpm)
	return bpm


func _build_editor_segments() -> void:
	# 每个分段保存起始 tick、BPM 和累计秒数，跨变速点换算时不重新遍历整首歌。
	var tempos: Array = chart.get("tempo_events") if chart != null else []
	var sorted_tempos := tempos.duplicate()
	sorted_tempos.sort_custom(func(a: Resource, b: Resource) -> bool: return int(a.get("tick")) < int(b.get("tick")))
	if sorted_tempos.is_empty() or int(sorted_tempos[0].get("tick")) > 0:
		_segments.append({"tick": 0, "bpm": 120.0, "start_sec": 0.0})
	for tempo in sorted_tempos:
		var tick := int(tempo.get("tick"))
		var bpm := maxf(1.0, float(tempo.get("bpm")))
		var start_sec := 0.0
		if not _segments.is_empty():
			var previous: Dictionary = _segments[-1]
			start_sec = float(previous.start_sec) + float(tick - int(previous.tick)) * 60.0 / (float(previous.bpm) * float(_ppq()))
		_segments.append({"tick": tick, "bpm": bpm, "start_sec": start_sec})
	if _segments.is_empty():
		_segments.append({"tick": 0, "bpm": 120.0, "start_sec": 0.0})


func _ppq() -> int:
	return maxi(1, int(chart.get("ppq"))) if chart != null else 480
