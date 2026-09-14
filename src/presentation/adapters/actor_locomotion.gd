class_name ActorLocomotion
extends RefCounted
## 地景启停表。只在背景安排改变后生成，采样不依赖上一次渲染的位置。
var changes: Array[Dictionary] = []
var sequence: StageEnvironmentSequence
var theme: StageVisualTheme
var lanes: Array[Dictionary] = []
var time_offset_sec := 0.0

func configure(value: StageEnvironmentSequence, style: StageVisualTheme, offset_sec := 0.0) -> void:
	sequence = value
	theme = style
	time_offset_sec = offset_sec
	lanes.clear()
	changes.clear()
	for key: String in [style.life_movement_layer_key, style.death_movement_layer_key]:
		var found := {}
		for lane: Dictionary in value.lanes:
			if lane.id == key: found = lane; break
		lanes.append(found)
	var points: Array[float] = [0.0]
	for lane: Dictionary in lanes:
		if lane.is_empty(): continue
		for motion: Dictionary in lane.motions: points.append(maxf(0.0, float(motion.at) / 1000000.0 - offset_sec))
		for source: Dictionary in lane.sources:
			points.append(maxf(0.0, float(source.born_us) / 1000000.0 - offset_sec))
			if not source.outgoing.is_empty(): points.append(maxf(0.0, float(source.outgoing.finish_us) / 1000000.0 - offset_sec))
	# 编排镜头可使用曲线：固定时间格定位阈值区间，再二分到微秒；不扫描骨骼或关卡。
	if value.camera.is_valid():
		for frame in range(1, ceili((float(value.end_us) / 1000000.0 - offset_sec) * 60.0) + 1): points.append(float(frame) / 60.0)
	points.sort()
	var previous: Array[bool] = [false, false]
	var prior_time := 0.0
	var events: Array[Dictionary] = []
	for time: float in points:
		var current := state_at(time)
		for side in 2:
			if current[side] == previous[side]: continue
			var at := time
			if value.camera.is_valid() and time > prior_time:
				var low := prior_time
				var high := time
				for i in 16:
					var middle := (low + high) * 0.5
					if state_at(middle)[side] == previous[side]: low = middle
					else: high = middle
				at = snappedf(high, 0.000001)
			events.append({"time": at, "side": side, "moving": current[side]})
		previous = current
		prior_time = time
	# 两侧的镜头阈值可能在同一采样格内先后跨过，分别定位，不能提前启动另一侧。
	events.sort_custom(func(a: Dictionary, b: Dictionary): return a.time < b.time)
	var moving: Array[bool] = [false, false]
	for event: Dictionary in events:
		moving[event.side] = event.moving
		if not changes.is_empty() and changes[-1].time == event.time: changes[-1].moving = moving.duplicate()
		else: changes.append({"time": event.time, "moving": moving.duplicate()})

func state_at(seconds: float) -> Array[bool]:
	var result: Array[bool] = [false, false]
	if seconds < 0.0: return result
	var at := roundi((seconds + time_offset_sec) * 1000000.0)
	var camera_speed := sequence.camera_velocity
	if sequence.camera.is_valid(): camera_speed = (sequence.camera_at(at + 1000) - sequence.camera_at(at)) * 1000.0
	for side in 2:
		var lane: Dictionary = lanes[side]
		if lane.is_empty(): continue
		var present := false
		for source: Dictionary in lane.sources:
			if not source.record.is_empty() and source.born_us <= at and (source.outgoing.is_empty() or at < source.outgoing.finish_us): present = true
		if not present: continue
		var motion := StageEnvironmentSequence.motion_at(lane, at)
		if motion.depth == 0: continue
		var velocity: Vector2 = motion.velocity - camera_speed / float(motion.depth)
		result[side] = absf(velocity.dot(lane.direction)) >= theme.walk_stop_speed_px_sec
	return result

func moving_at(seconds: float) -> Array[bool]:
	var result: Array[bool] = [false, false]
	for change: Dictionary in changes:
		if change.time > seconds: break
		result = change.moving
	return result
