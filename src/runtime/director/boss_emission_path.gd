class_name BossEmissionPath
extends RefCounted
## 提前段只改变视觉，入轨之后完整交还现有路径与真实波接触。
static func build(origin: Vector2, entrance: Vector2, entrance_velocity: Vector2, duration_us: int, handle: Vector2) -> Dictionary:
	var seconds := float(duration_us) / 1000000.0
	var controls := PackedVector2Array([origin, origin + handle, entrance - entrance_velocity * seconds / 3.0, entrance])
	var cumulative := PackedFloat32Array([0.0])
	var previous := origin
	for index in range(1, 97):
		var point := controls[0].bezier_interpolate(controls[1], controls[2], controls[3], float(index) / 96.0)
		cumulative.append(cumulative[-1] + previous.distance_to(point)); previous = point
	return {"controls": controls, "duration_us": duration_us, "lengths": cumulative}

static func sample(path: Dictionary, elapsed_us: int) -> Dictionary:
	if path.has("arc_profile"): return _sample_scatter(path, elapsed_us)
	var ratio := clampf(float(elapsed_us) / float(path.duration_us), 0, 1)
	var points: PackedVector2Array = path.controls
	var position := points[0].bezier_interpolate(points[1], points[2], points[3], ratio)
	var derivative := 3.0 * (1.0 - ratio) * (1.0 - ratio) * (points[1] - points[0]) + 6.0 * (1.0 - ratio) * ratio * (points[2] - points[1]) + 3.0 * ratio * ratio * (points[3] - points[2])
	var index := ratio * float(path.lengths.size() - 1)
	var lower := floori(index)
	var distance := lerpf(path.lengths[lower], path.lengths[mini(lower + 1, path.lengths.size() - 1)], index - lower)
	return {"position": position, "velocity": derivative / (float(path.duration_us) / 1000000.0), "distance": distance}

## 末端在原路径内部衔接，不经过固定出生点。时间参数与空间弧长分开。
static func scatter(origin: Vector2, profile: Dictionary, approach_sec: float, early_sec: float, seed_text: String, speed: float, spread_deg: float) -> Dictionary:
	var lead := minf(approach_sec*0.8,maxf(0.35,early_sec+0.35))
	var join_ratio := 1.0-lead/approach_sec
	var target := NoteApproachPath.point_at_ratio(profile,join_ratio)
	var tangent := NoteApproachPath.tangent_at_ratio(profile,join_ratio)
	var terminal_speed := NoteApproachPath.length(profile)/approach_sec
	# 固定字符散列只用于表现，不读取进程随机种子。
	var seed := 17
	for character in seed_text.to_utf8_buffer(): seed = (seed*31+int(character))%2147483647
	var angle := deg_to_rad(spread_deg)*(float(seed%65536)/32767.5-1.0)
	var distance := origin.distance_to(target)
	var direction := (target-origin).normalized().rotated(angle)
	var controls := PackedVector2Array([origin,origin+direction*distance*0.42,target-tangent*minf(distance*0.35,240.0),target])
	var lengths := PackedFloat32Array([0.0]); var previous := origin
	for i in range(1,97):
		var point := controls[0].bezier_interpolate(controls[1],controls[2],controls[3],float(i)/96)
		lengths.append(lengths[-1]+previous.distance_to(point));previous=point
	var length := maxf(0.001,lengths[-1])
	var duration := maxf(approach_sec+1.0-lead,length/maxf(1.0,speed))
	var ramp := minf(0.3,minf(duration*0.2,length/maxf(terminal_speed,1.0)))
	var cruise := (length-terminal_speed*ramp*0.5)/(duration-ramp)
	var arc := {"controls":controls,"cumulative_lengths":lengths,"segment_count":96,"length_px":length}
	return {"controls":controls,"lengths":lengths,"arc_profile":arc,"duration_us":roundi(duration*1000000),"join_lead_us":roundi(lead*1000000),"terminal_speed":terminal_speed,"cruise":cruise,"ramp":ramp}

static func _sample_scatter(path: Dictionary, elapsed_us: int) -> Dictionary:
	var revision: int=path.origin_revision.call() if path.has("origin_revision") else -1
	if path.has("origin_sampler") and path.get("sampled_revision",-2)!=revision:
		path.sampled_revision=revision
		var origin: Vector2=path.origin_sampler.call()
		var controls: PackedVector2Array=path.controls
		if not origin.is_equal_approx(controls[0]):
			controls[1]+=origin-controls[0];controls[0]=origin
			var lengths:=PackedFloat32Array([0.0]);var previous:=origin
			for i in range(1,97):
				var point:=controls[0].bezier_interpolate(controls[1],controls[2],controls[3],float(i)/96)
				lengths.append(lengths[-1]+previous.distance_to(point));previous=point
			path.controls=controls;path.lengths=lengths;path.arc_profile.controls=controls;path.arc_profile.cumulative_lengths=lengths;path.arc_profile.length_px=lengths[-1]
			path.cruise=(float(lengths[-1])-float(path.terminal_speed)*float(path.ramp)*0.5)/(float(path.duration_us)/1000000-float(path.ramp))
	var duration := float(path.duration_us)/1000000
	var t := clampf(float(elapsed_us)/1000000,0,duration)
	var ramp := float(path.ramp);var cruise := float(path.cruise)
	var distance := 0.0;var speed := 0.0
	if t < ramp:
		var u := t/ramp
		distance=cruise*ramp*(u*u*u-0.5*u*u*u*u);speed=cruise*smoothstep(0,1,u)
	elif t <= duration-ramp:
		distance=cruise*(t-ramp*0.5);speed=cruise
	else:
		var u := (t-duration+ramp)/ramp
		distance=cruise*(duration-1.5*ramp)+cruise*ramp*u+(float(path.terminal_speed)-cruise)*ramp*(u*u*u-0.5*u*u*u*u)
		speed=lerpf(cruise,float(path.terminal_speed),smoothstep(0,1,u))
	var ratio := clampf(distance/float(path.arc_profile.length_px),0,1)
	return {"position":NoteApproachPath.point_at_ratio(path.arc_profile,ratio),"velocity":NoteApproachPath.tangent_at_ratio(path.arc_profile,ratio)*speed,"distance":distance}
