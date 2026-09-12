@tool
class_name StageEnvironmentSequence
extends RefCounted
## 只保存空间片段与分段速度；渲染过哪些帧不会改变排队、接缝或局部动画时间。
var lanes: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var intro_us := 0
var song_us := 0
var end_us := 0
var camera: Callable
var camera_velocity := Vector2.ZERO

func absolute_time(section: String, time_us: int) -> int:
	return time_us - intro_us if section == "intro" else (song_us + time_us if section == "outro" else time_us)

static func layers(background: StageBackgroundDefinition) -> Dictionary:
	var result := {}
	if background == null: return result
	for layer in background.layers:
		for sublayer in layer.sublayers:
			result[sublayer.continuity_key(layer.depth)] = {"resource": sublayer, "depth": layer.depth}
	return result

func build(initial: StageBackgroundDefinition, cues: Array, resolve: Callable, difficulty: String, durations: Vector3i, camera_at := Callable(), base_velocity := Vector2.ZERO, previous:StageEnvironmentSequence=null) -> void:
	lanes.clear(); transitions.clear()
	intro_us = durations.x; song_us = durations.y; end_us = song_us + durations.z
	camera = camera_at; camera_velocity = base_velocity
	var current := layers(initial)
	var ordered: Array = []
	for index in cues.size():
		var cue: Dictionary = cues[index]
		if LevelFormat.visible_in(cue, difficulty):
			ordered.append({"cue": cue, "at": absolute_time(str(cue.get("section", "song")), int(cue.time_us)), "order": index})
	ordered.sort_custom(func(a, b): return a.at < b.at if a.at != b.at else a.order < b.order)
	var targets: Array = []
	var all := current.duplicate()
	for record in ordered:
		var target := layers(resolve.call(str(record.cue.asset)))
		targets.append(target)
		for key in target:
			if not all.has(key): all[key] = target[key]
	for key: String in all:
		# 各层只依赖自己的素材与覆盖项；修改其他层、显示名称或选区不重复安排。
		var inputs:Array=[_layer_values(current.get(key,{}))]
		for index in ordered.size():
			var cue:Dictionary=ordered[index].cue
			inputs.append([cue.id,ordered[index].at,_layer_values(targets[index].get(key,{})),cue.get("effect","none"),cue.get("blend_px",128.0),cue.get("static_fade_us",500000),cue.get("layers",{}).get(key,{})])
		var cached:Dictionary={}
		if previous!=null:
			for prior in previous.lanes:
				if prior.id==key and prior.get("inputs",[])==inputs:cached=prior;break
		if not cached.is_empty():
			lanes.append(cached);transitions.append_array(cached.transitions);continue
		var base: Dictionary = current.get(key, all[key])
		var resource: StageBackgroundSubLayer = base.resource
		var cycle := resource.cycle(base.depth, base_velocity)
		var lane := {"id": key, "name": resource.display_name, "depth": base.depth, "direction": cycle.direction, "sources": [], "motions": [], "transitions": [],"inputs":inputs}
		lane.motions.append({"at": -intro_us, "position": Vector2.ZERO, "velocity": _velocity(base),"depth":base.depth,"camera_offset":Vector2.ZERO})
		var active: Dictionary = current.get(key, {})
		var source := _source(active, Vector2.ZERO, -intro_us)
		lane.sources.append(source)
		var available: int = -intro_us
		for index in ordered.size():
			var record: Dictionary = ordered[index]
			var next: Dictionary = targets[index].get(key, {})
			if _same(active, next): continue
			var cue: Dictionary = record.cue
			var settings: Dictionary = cue.duplicate()
			settings.merge(cue.get("layers", {}).get(key, {}), true)
			var requested: int = maxi(-intro_us, record.at)
			var ready := maxi(requested, available)
			var width := maxf(0.0, float(settings.get("blend_px", 128.0))) if settings.get("effect", "none") == "fade" else 0.0
			var reference: Dictionary = active if not active.is_empty() else next
			var layer: StageBackgroundSubLayer = reference.resource
			var axis: Vector2 = lane.direction
			var speed := axis.dot(_velocity(reference) - base_velocity / float(reference.depth)) if reference.depth != 0 else 0.0
			var stationary := absf(speed) < 0.00001
			var enter := ready
			var finish := ready
			var seam := 0.0
			var offset := Vector2.ZERO
			if stationary:
				finish += maxi(0, int(settings.get("static_fade_us", 500000))) if settings.get("effect", "none") == "fade" else 0
			else:
				var bounds := projected_frame(axis)
				var position := axis.dot(displacement(lane, ready))
				var outgoing := layer.cycle(reference.depth, base_velocity)
				var origin: float = outgoing.start + axis.dot(source.offset)
				# 选择连渐变前沿也尚未入画的最近接缝，屏内已有的循环格不换图。
				seam = bounds.x - width * 0.5 - position if active.is_empty() else origin + floorf((bounds.x - width * 0.5 - position - origin) / outgoing.length) * outgoing.length
				enter = _arrival(lane, bounds.x - width * 0.5 - seam, ready)
				finish = _arrival(lane, bounds.y + width * 0.5 - seam, enter)
				if not next.is_empty():
					var incoming: Dictionary = next.resource.cycle(next.depth, base_velocity)
					offset = axis * (seam - float(incoming.end))
			var transition := {"cue_id": str(cue.id), "layer_id": key, "name": lane.name, "section": str(cue.get("section", "song")), "request_us": requested, "ready_us": ready, "enter_us": enter, "finish_us": finish, "seam": seam, "width": width, "static": stationary, "direction": axis}
			transitions.append(transition); lane.transitions.append(transition)
			source["outgoing"] = transition
			var following := _source(next, offset, enter)
			following["incoming"] = transition
			lane.sources.append(following)
			# 切速度前先保存当前位置，避免 velocity * 总时间造成位移突变。
			var old_motion:=motion_at(lane,finish)
			var next_depth:int=next.depth if not next.is_empty() else reference.depth
			# 层深度也在完全退出后接续，保存镜头累计量以免视差倍率变化造成跳位。
			var next_offset:Vector2=old_motion.camera_offset+camera_at(finish)*(_depth_factor(next_depth)-_depth_factor(old_motion.depth))
			lane.motions.append({"at": finish, "position": travel(lane, finish), "velocity": _velocity(next) if not next.is_empty() else _velocity(reference),"depth":next_depth,"camera_offset":next_offset})
			active = next; source = following; available = finish
		lanes.append(lane)

static func _source(record: Dictionary, offset: Vector2, born: int) -> Dictionary:
	return {"record": record, "offset": offset, "born_us": born, "incoming": {}, "outgoing": {}}

static func _velocity(record: Dictionary) -> Vector2:
	return record.resource.velocity / float(record.depth) if not record.is_empty() and record.depth != 0 else Vector2.ZERO

static func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return a.is_empty() and b.is_empty()
	if a.depth != b.depth: return false
	var left: StageBackgroundSubLayer = a.resource
	var right: StageBackgroundSubLayer = b.resource
	if left == right: return true
	if left.cycle_start!=right.cycle_start or left.cycle_end!=right.cycle_end or left.cycle_direction!=right.cycle_direction:return false
	if left.velocity != right.velocity or left.entries.size() != right.entries.size(): return false
	for index in left.entries.size():
		var x: StageBackgroundEntry = left.entries[index]
		var y: StageBackgroundEntry = right.entries[index]
		for property in ["texture", "sprite_frames", "animation", "material", "infinite", "random_flip", "position", "uniform_scale"]:
			if x.get(property) != y.get(property): return false
	return true

static func _layer_values(record:Dictionary) -> Array:
	if record.is_empty():return []
	var layer:StageBackgroundSubLayer=record.resource
	var values:Array=[record.depth,layer.display_name,layer.velocity,layer.cycle_start,layer.cycle_end,layer.cycle_direction]
	for entry in layer.entries:
		values.append([entry.texture,entry.sprite_frames,entry.animation,entry.material,entry.infinite,entry.random_flip,entry.position,entry.uniform_scale])
	return values

static func _depth_factor(depth:int) -> float:
	return 1.0/float(depth) if depth!=0 else 0.0

static func projected_frame(axis: Vector2) -> Vector2:
	var result := Vector2(INF, -INF)
	for corner in [Vector2.ZERO, Vector2(1920, 0), Vector2(0, 1080), Vector2(1920, 1080)]:
		var value := axis.dot(corner)
		result.x = minf(result.x, value); result.y = maxf(result.y, value)
	return result

static func motion_at(lane:Dictionary,time_us:int) -> Dictionary:
	var part: Dictionary = lane.motions[0]
	for item: Dictionary in lane.motions:
		if item.at > time_us: break
		part = item
	return part

static func travel(lane: Dictionary, time_us: int) -> Vector2:
	var part:=motion_at(lane,time_us)
	return part.position + part.velocity * (float(time_us - int(part.at)) / 1000000.0)

func camera_at(time_us: int) -> Vector2:
	return camera.call(time_us) if camera.is_valid() else camera_velocity * float(time_us + intro_us) / 1000000.0

func displacement(lane: Dictionary, time_us: int, render_camera:=Vector2(INF,INF)) -> Vector2:
	var part:=motion_at(lane,time_us)
	var position:=render_camera if render_camera.is_finite() else camera_at(time_us)
	return travel(lane,time_us)+part.camera_offset-position*_depth_factor(part.depth)

func _arrival(lane: Dictionary, target: float, after: int) -> int:
	if after >= 900000000000000: return after
	var axis: Vector2 = lane.direction
	var initial := axis.dot(displacement(lane, after))
	if initial >= target - 0.00001: return after
	if not camera.is_valid():
		var velocity: Vector2 = lane.motions.back().velocity - camera_velocity * _depth_factor(lane.motions.back().depth)
		var speed := axis.dot(velocity)
		return after + ceili((target - initial) / speed * 1000000.0) if speed > 0.00001 else 900000000000000
	# 有演出镜头时只在编辑变更后扫描求根；播放帧直接使用结果。
	var lower := after
	var limit := maxi(end_us + 60000000, after + 3600000000)
	while lower < limit:
		var upper := mini(lower + 100000, limit)
		if axis.dot(displacement(lane, upper)) >= target:
			while upper - lower > 1:
				var middle := lower + (upper - lower) / 2
				if axis.dot(displacement(lane, middle)) >= target: upper = middle
				else: lower = middle
			return upper
		lower = upper
	return 900000000000000

func visible_sources(lane: Dictionary, time_us: int, render_camera:=Vector2(INF,INF)) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var shift := displacement(lane, time_us,render_camera)
	var bounds := projected_frame(lane.direction)
	for index in lane.sources.size():
		var source: Dictionary = lane.sources[index]
		if source.record.is_empty(): continue
		var low := -1.0e12; var high := 1.0e12
		var low_width := 0.0; var high_width := 0.0; var opacity := 1.0
		var incoming: Dictionary = source.incoming
		var outgoing: Dictionary = source.outgoing
		if not incoming.is_empty():
			# 回拖到请求发生前时，这个空间来源尚不存在；不能提前看到未来场景。
			if time_us<int(incoming.ready_us):continue
			if incoming.static: opacity *= _fade(incoming, time_us)
			else: high = incoming.seam + lane.direction.dot(shift); high_width = incoming.width
		if not outgoing.is_empty() and time_us>=int(outgoing.ready_us):
			if outgoing.static: opacity *= 1.0 - _fade(outgoing, time_us)
			else: low = outgoing.seam + lane.direction.dot(shift); low_width = outgoing.width
		if opacity <= 0.0 or low - low_width * 0.5 >= bounds.y or high + high_width * 0.5 <= bounds.x: continue
		result.append({"index": index, "source": source, "shift": shift + source.offset, "low": low, "high": high, "low_width": low_width, "high_width": high_width, "opacity": opacity, "local_sec": maxf(0.0, float(time_us - int(source.born_us)) / 1000000.0)})
	return result

static func _fade(transition: Dictionary, time_us: int) -> float:
	if transition.finish_us <= transition.enter_us: return 1.0 if time_us >= transition.enter_us else 0.0
	return clampf(float(time_us - int(transition.enter_us)) / float(int(transition.finish_us) - int(transition.enter_us)), 0.0, 1.0)
