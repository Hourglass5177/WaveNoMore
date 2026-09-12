class_name LevelShowSampler
extends RefCounted
## 属性按绝对时间求值。定位和正常播放使用同一函数，不依赖此前渲染过哪些帧。

static func sample_keys(keys: Array, time_us: int, base, as_color := false):
	if keys.is_empty() or time_us < int(keys[0].time_us): return base
	# 文档装入和编辑提交时排序；逐帧只二分查找当前区间。
	var low := 0; var high := keys.size()
	while low < high:
		var middle := (low + high) / 2
		if int(keys[middle].time_us) <= time_us: low = middle + 1
		else: high = middle
	var index := low - 1
	if index >= keys.size() - 1: return keys.back().value
	var a: Dictionary = keys[index]; var b: Dictionary = keys[index + 1]
	var ratio := float(time_us - int(a.time_us)) / float(int(b.time_us) - int(a.time_us))
	match str(a.get("interpolation", "linear")):
		"hold": ratio = 0.0
		"ease": ratio = ratio * ratio * (3.0 - 2.0 * ratio)
		"bezier": ratio = bezier_ratio(ratio, LevelFormat.vec(a.get("out_handle", [0.33, 0.33])), LevelFormat.vec(a.get("in_handle", [0.67, 0.67])))
	if as_color:return Color(str(a.value)).lerp(Color(str(b.value)),ratio).to_html()
	return blend(a.value, b.value, ratio)

static func blend(a, b, weight: float):
	if a is bool or b is bool: return b if weight >= 1.0 else a
	if (a is float or a is int) and (b is float or b is int): return lerpf(float(a), float(b), weight)
	if a is Array and b is Array:
		var result := []
		for i in mini(a.size(), b.size()): result.append(lerpf(float(a[i]), float(b[i]), weight))
		return result
	return b if weight >= 1.0 else a

static func bezier_ratio(x: float, first: Vector2, second: Vector2) -> float:
	var low := 0.0; var high := 1.0
	for i in 18:
		var t := (low + high) * 0.5
		var px := 3.0 * (1.0 - t) * (1.0 - t) * t * first.x + 3.0 * (1.0 - t) * t * t * second.x + t * t * t
		if px < x: low = t
		else: high = t
	var t := (low + high) * 0.5
	return 3.0 * (1.0 - t) * (1.0 - t) * t * first.y + 3.0 * (1.0 - t) * t * t * second.y + t * t * t

static func clip_weight(clip_data: Dictionary, time_us: int) -> float:
	var age := time_us - int(clip_data.start_us)
	var duration := int(clip_data.duration_us)
	if age < 0 or age >= duration: return 0.0
	var weight := 1.0
	if int(clip_data.get("fade_in_us", 0)) > 0: weight = minf(weight, float(age) / float(clip_data.fade_in_us))
	if int(clip_data.get("fade_out_us", 0)) > 0: weight = minf(weight, float(duration - age) / float(clip_data.fade_out_us))
	return weight

static func object_state(show: Dictionary, object_data: Dictionary, section: String, time_us: int, difficulty: String) -> Dictionary:
	var state: Dictionary = object_data.get("fields", {}).duplicate(true)
	for track_data: Dictionary in show.get("tracks", []):
		if track_data.get("object_id", "") != object_data.id or track_data.get("type", "property") != "property": continue
		if track_data.get("section", "song") != section or not LevelFormat.visible_in(track_data, difficulty): continue
		var property := str(track_data.property)
		state[property] = sample_keys(track_data.get("keys", []), time_us, state.get(property, 0.0), property == "color" or property in object_data.get("color_properties",[]))
	return state

static func object_transform(show: Dictionary, object_id: String, section: String, time_us: int, difficulty: String, depth := 0) -> Transform2D:
	var object_data := LevelFormat.find(show.get("objects", []), object_id)
	if object_data.is_empty() or depth > show.get("objects", []).size(): return Transform2D.IDENTITY
	var state := object_state(show, object_data, section, time_us, difficulty)
	var transform := Transform2D(deg_to_rad(float(state.get("rotation", 0.0))), LevelFormat.vec(state.get("scale", [1, 1]), Vector2.ONE), deg_to_rad(float(state.get("skew", 0.0))), LevelFormat.vec(state.get("position", [0, 0])))
	var parent := str(object_data.get("parent_id", ""))
	if not parent.is_empty(): transform = object_transform(show, parent, section, time_us, difficulty, depth + 1) * transform
	elif object_data.get("layer", "world") == "death": transform = Transform2D(PI, Vector2(1920, 1080)) * transform
	return transform

static func local_appearance(show: Dictionary, object_data: Dictionary, section: String, time_us: int, difficulty: String) -> Dictionary:
	var state := object_state(show, object_data, section, time_us, difficulty)
	var color := Color(str(state.get("color", "ffffffff")))
	color.a *= float(state.get("opacity", 1.0))
	var visible := bool(state.get("visible", true)) and not bool(object_data.get("hidden", false))
	for track: Dictionary in show.get("tracks", []):
		if track.object_id != object_data.id or track.type != "visibility" or track.section != section or not LevelFormat.visible_in(track, difficulty): continue
		var weight := 0.0
		for clip: Dictionary in track.clips: weight = maxf(weight, clip_weight(clip, time_us))
		visible = visible and weight > 0.0; color.a *= weight
	return {"visible":visible,"color":color}

static func active_clips(show: Dictionary, section: String, time_us: int, difficulty: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for track_data: Dictionary in show.get("tracks", []):
		if track_data.get("type", "property") == "property" or track_data.get("section", "song") != section or not LevelFormat.visible_in(track_data, difficulty): continue
		for source: Dictionary in track_data.get("clips", []):
			var age := time_us - int(source.start_us)
			if age < 0 or (age >= int(source.duration_us) and not source.get("hold_last", false)): continue
			var entry := source.duplicate(true)
			entry.object_id = track_data.object_id; entry.track_id = track_data.id; entry.type = track_data.type
			entry.local_us = int(source.get("offset_us", 0)) + roundi(mini(age, int(source.duration_us)) * float(source.get("rate", 1.0)))
			entry.weight = clip_weight(source, time_us) if age < int(source.duration_us) else 1.0
			result.append(entry)
	return result
