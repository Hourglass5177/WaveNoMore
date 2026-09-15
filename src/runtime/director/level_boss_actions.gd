class_name LevelBossActions
extends RefCounted
## 自动识别与生成轨共用；旧绑定的常态动作不能冒充攻击动作。
static func resolve(assets: LevelAssetLibrary, object: Dictionary, binding: Dictionary) -> Dictionary:
	var asset := str(object.get("asset", ""))
	var names := assets.actions(asset)
	var visual := str(object.get("boss",{}).get("visual",""))
	var visual_config := {}
	if visual in ["bat","snake","goat","goat_eye"]:
		visual_config = LevelProjectIO.read_json("res://assets/bosses/animation_studies/"+visual+"/animation.json")
		names = ["attack_start","attack_loop","attack_end","hurt","death"]
		if visual == "goat": names.append("phase_break")
	var mapping: Dictionary = assets.boss_action_mapping(asset)
	mapping.merge(object.get("boss", {}).get("actions", {}),true)
	var result := {"idle": assets.default_animation(asset)}
	result.idle = str(mapping.get("idle",result.idle))
	for role in ["attack", "attack_start", "attack_loop", "attack_end", "hurt", "phase_break", "death"]:
		var name := str(mapping.get(role, role))
		result[role] = name if name in names else ""
	if binding.get("action_mode", "auto") == "custom":
		result.attack = str(binding.get("action", ""))
		result.attack_start = ""; result.attack_loop = ""; result.attack_end = ""
	result.segmented = not str(result.attack_start).is_empty() and not str(result.attack_loop).is_empty() and not str(result.attack_end).is_empty()
	result.action = result.attack_start if result.segmented else result.attack
	result.rate = maxf(0.01, float(binding.get("rate", 1.0)))
	var duration := assets.action_duration(asset, result.action) if not str(result.action).is_empty() else 0.0
	result.duration = duration
	if not visual_config.is_empty():
		result.idle = str(visual_config.idle)
		result.duration = float(visual_config.start)
		duration = result.duration
		result.loop_duration = float(visual_config.loop)
		result.end_duration = float(visual_config.end)
		result.death_duration = float(visual_config.death)
	result.release = duration if result.segmented else assets.release_time(asset, result.action)
	if not result.segmented and not assets.has_release_marker(asset, result.action): result.release = duration * 0.5
	if binding.get("action_mode", "auto") == "custom": result.release = float(binding.get("release_sec", result.release))
	return result

static func tracks(events: Array, assets: LevelAssetLibrary, offset_us: int) -> Array:
	var result: Array = []
	events.sort_custom(func(a, b): return a.release_us < b.release_us)
	var groups := {}
	for event: Dictionary in events:
		var spec: Dictionary = event.spec
		if str(spec.action).is_empty(): continue
		var key := str(event.object_id) + "|" + JSON.stringify(spec)
		if not groups.has(key): groups[key] = []
		groups[key].append(event)
	for group: Array in groups.values():
		var first: Dictionary = group[0]
		var spec: Dictionary = first.spec
		if not spec.segmented:
			for i in group.size():
				var event: Dictionary = group[i]
				var start := int(event.release_us) - roundi(float(spec.release) / float(spec.rate) * 1000000)
				var end := start + roundi(float(spec.duration) / float(spec.rate) * 1000000)
				if i + 1 < group.size(): end = mini(end, int(group[i+1].release_us) - roundi(float(spec.release) / float(spec.rate) * 1000000))
				if end > start: result.append(_track(event, spec.action, start + offset_us, end-start, false))
			continue
		var cycle := maxi(1, roundi(float(spec.get("loop_duration",assets.action_duration(first.asset, spec.attack_loop))) / float(spec.rate) * 1000000))
		var index := 0
		while index < group.size():
			var event: Dictionary = group[index]
			var last := index
			while last+1 < group.size() and int(group[last+1].release_us)-int(group[last].release_us) <= cycle: last += 1
			var release := int(event.release_us)
			var lead := roundi(float(spec.duration) / float(spec.rate) * 1000000)
			var end := release + (int((int(group[last].release_us)-release) / cycle)+1)*cycle
			result.append(_track(event, spec.attack_start, release-lead+offset_us, lead, false))
			result.append(_track(event, spec.attack_loop, release+offset_us, end-release, true))
			var tail := roundi(float(spec.get("end_duration",assets.action_duration(event.asset, spec.attack_end))) / float(spec.rate) * 1000000)
			if last+1 < group.size(): tail = mini(tail, int(group[last+1].release_us)-lead-end)
			if tail > 0: result.append(_track(event, spec.attack_end, end+offset_us, tail, false))
			index = last+1
	return result

static func _track(event: Dictionary, action: String, start: int, duration: int, loop: bool) -> Dictionary:
	var track := LevelFormat.track(event.object_id, "action", "song", "action")
	track.id = "boss_%s_%s_%d" % [event.binding_id, action, start]
	track.binding_id = event.binding_id
	var clip := LevelFormat.clip(start, "", maxi(1,duration))
	clip.id = track.id; clip.action = action; clip.rate = event.spec.rate; clip.loop = loop; clip.name = "自动攻击 · " + action
	clip.boss_control = true
	track.clips = [clip]
	return track
