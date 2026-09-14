extends RefCounted
## 派生静息、局部受击与支槌屈膝。所有求解在生成时完成，运行时只播放 Spine 关键帧。

const CHEST := "1cbbf49e2b0d797147a5b1861335f763"
const HURT_BONES := {"bone4": 3.0, "bozi": 1.2, "tou": 0.8, "tou3": -0.7, "tou8": -0.6, "piaodai1": -1.0}
var definitions := {}

func build(result: Dictionary) -> void:
	for bone: Dictionary in result.bones: definitions[bone.name] = bone
	# 叠加轨道涉及的属性必须由基础轨道每次明确赋值，不能累加上一帧的结果。
	for animation: Dictionary in result.animations.values():
		for name: String in HURT_BONES:
			if not animation.bones.has(name): animation.bones[name] = {}
			if not animation.bones[name].has("rotate"): animation.bones[name].rotate = [{"value": 0.0}]
	result.animations.idle = _idle(result.animations.attack)
	result.animations.walk = _walk(result.animations.attack)
	result.animations.hurt = _hurt()
	result.animations.death = _death(result.animations.attack)

func _rest(attack: Dictionary) -> Dictionary:
	var bones := {}
	for name: String in attack.bones:
		bones[name] = {}
		for kind: String in attack.bones[name]:
			var key: Dictionary = attack.bones[name][kind][0].duplicate(true)
			key.erase("curve")
			key.time = 0.0
			bones[name][kind] = [key]
	return {"bones": bones, "drawOrder": [{"time": 0.0}]}

func _breath(time: float) -> float:
	var phase := fposmod(time, 4.0)
	return smoothstep(0.0, 1.6, phase) if phase < 1.6 else 1.0 - smoothstep(1.6, 4.0, phase)

func _idle(attack: Dictionary) -> Dictionary:
	var clip := _rest(attack)
	# 最终显示约 300px 高，原先不足 2px 的呼吸在游戏尺寸下难以辨认。
	# 增强胸肩舒展与末梢跟随，骨盆和双脚仍固定，避免整个角色上下浮动。
	var amounts := {"bone4": -1.6, CHEST: 0.65, "bozi": 0.5, "tou": -0.35,
		"1": 0.9, "4": -0.7, "3": 0.35, "tou3": 1.6, "tou8": 1.4,
		"piaodai1": 2.4, "bone6": 1.3, "bone11": 1.0}
	for name: String in amounts:
		var keys := []
		for frame in 121:
			var time := float(frame) / 30.0
			var delay := 0.20 if name.begins_with("tou") or name == "piaodai1" else (0.10 if name.begins_with("bone") and name != "bone4" else 0.0)
			keys.append({"time": time, "value": amounts[name] * (_breath(time - delay) - _breath(-delay))})
		clip.bones[name].rotate = keys
	var breathing := []
	for frame in 121:
		var time := float(frame) / 30.0
		# bone4 的局部 X 沿躯干向上；骨架缩放 0.2、角色缩放 0.405。
		breathing.append({"time": time, "x": 65.0 * _breath(time), "y": 0.0})
	clip.bones[CHEST].translate = breathing
	return clip

func _walk(attack: Dictionary) -> Dictionary:
	var clip := _rest(attack)
	# 0.2 骨架缩放 × 0.405 角色缩放；24 px 脚程、3.5 px 抬脚。
	var tracks := {}
	for frame in 97:
		var time := float(frame) / 60.0
		var phase := time / 1.6
		var pose := {"bone3": {"translate": Vector2(0, 30.0 * (0.5 - 0.5 * cos(TAU * phase * 2.0)))},
			"bone4": {"rotate": -0.8 + 0.55 * sin(TAU * phase)},
			CHEST: {"rotate": 0.4 * sin(TAU * (phase - 0.06))},
			"bozi": {"rotate": -0.35 * sin(TAU * (phase - 0.08))},
			"tou": {"rotate": 0.25 * sin(TAU * (phase - 0.1))},
			"1": {"rotate": 1.2 * sin(TAU * phase)},
			"4": {"rotate": -0.7 * sin(TAU * phase)}, "3": {"rotate": 0.4 * sin(TAU * phase)}}
		for side in 2:
			var p := fposmod(phase + side * 0.5, 1.0)
			# 前半轮匀速承重后移，后半轮用 Hermite 接回，落脚前后速度连续。
			var x := 148.0 - 592.0 * p
			var lift := 0.0
			if p >= 0.5:
				var u := (p - 0.5) * 2.0
				x = -148.0 + 296.0 * (-4.0 * u * u * u + 6.0 * u * u - u)
				lift = 43.0 * pow(sin(PI * u), 2.0)
			pose["y" if side == 0 else "target"] = {"translate": Vector2(x, lift)}
		for name: String in ["tou3", "tou8", "piaodai1", "bone6", "bone11"]:
			pose[name] = {"rotate": 1.5 * sin(TAU * (phase - 0.11))}
		for name: String in pose:
			if not tracks.has(name): tracks[name] = {}
			for kind: String in pose[name]:
				if not tracks[name].has(kind): tracks[name][kind] = []
				var value = pose[name][kind]
				tracks[name][kind].append({"time": time, "x": value.x, "y": value.y} if kind == "translate" else {"time": time, "value": value})
	for name: String in tracks:
		if not clip.bones.has(name): clip.bones[name] = {}
		for kind: String in tracks[name]: clip.bones[name][kind] = tracks[name][kind]
	return clip

func _hurt() -> Dictionary:
	var bones := {}
	for name: String in HURT_BONES:
		var delay := 0.03 if name in ["tou3", "tou8", "piaodai1"] else 0.0
		var keys := [{"time": 0.0, "value": 0.0}]
		for frame in range(1, 33):
			var time := float(frame) / 100.0
			var t := maxf(time - delay, 0.0)
			var envelope := smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.06, 0.32 - delay, t))
			keys.append({"time": time, "value": HURT_BONES[name] * envelope})
		bones[name] = {"rotate": keys}
	return {"bones": bones}

func _death(attack: Dictionary) -> Dictionary:
	var clip := _rest(attack)
	var tracks := {}
	for frame in 73:
		var time := float(frame) / 60.0
		var sink := smoothstep(0.16, 0.95, time)
		var bow := smoothstep(0.04, 0.95, time)
		var pose := {"bone3": {"translate": Vector2(-100.0, -780.0) * sink},
			"bone4": {"rotate": -10.0 * bow}, CHEST: {"rotate": -5.0 * bow},
			"bozi": {"rotate": -8.0 * smoothstep(0.18, 1.0, time)},
			"tou": {"rotate": -10.0 * smoothstep(0.28, 1.08, time)},
			"target": {"translate": Vector2(-430.0, 30.0) * sink},
			"y": {"translate": Vector2.ZERO},
			"1": {"rotate": 22.0 * bow}, "-16": {"rotate": -48.0 * bow}}
		# 肩部到手掌的两段解析 IK，仅烘焙角度。槌头接地后固定，手掌始终握住同一点。
		var plant := smoothstep(0.10, 0.40, time)
		var rest_world := _world("cl_wuqi", {})
		var rest_head := rest_world * Vector2(932.0, 0.0)
		var head := rest_head.lerp(Vector2(235.0, 12.0), plant)
		var angle := lerp_angle(rest_world.get_rotation(), -PI * 0.5, plant)
		var weapon := definitions.cl_wuqi as Dictionary
		var grip := (Vector2(558.8518, 0.0) - Vector2(weapon.x, weapon.y)).rotated(-deg_to_rad(weapon.rotation)) / float(weapon.scaleX)
		var wrist := head + (grip - Vector2(932.0, 0.0)).rotated(angle) * (0.2 * float(weapon.scaleX))
		_solve_arm(pose, wrist)
		var forearm := _world("3", pose)
		var local_angle := angle - forearm.get_rotation()
		pose.cl_wuqi = {"rotate": rad_to_deg(wrapf(local_angle - deg_to_rad(weapon.rotation), -PI, PI)),
			"translate": Vector2(558.8518, 0.0) - grip.rotated(local_angle) * float(weapon.scaleX) - Vector2(weapon.x, weapon.y)}
		# 头发先保留惯性，再落回低头后的垂向；不让整束头发随头部硬折到身前。
		for name: String in ["tou2", "tou7", "tou5"]:
			pose[name] = {"rotate": 27.0 * smoothstep(0.12, 1.2, time)}
		for name: String in ["tou3", "tou8", "piaodai1", "bone6", "bone11"]:
			pose[name] = {"rotate": 4.0 * sin(PI * smoothstep(0.15, 1.2, time))}
		# 腰间长绦在屈膝后向后铺落，末段逐节弯曲，避免穿过地面。
		for name: String in ["bone7", "bone8", "bone9", "bone12", "bone13", "bone14"]:
			pose[name] = {"rotate": -22.0 * smoothstep(0.25, 1.05, time)}
		for name: String in ["tou10", "tou12", "tou13", "tou14", "toufa", "toufa2"]:
			pose[name] = {"rotate": -16.0 * smoothstep(0.25, 1.12, time)}
		for name: String in pose:
			if not tracks.has(name): tracks[name] = {}
			for kind: String in pose[name]:
				if not tracks[name].has(kind): tracks[name][kind] = []
				var key := {"time": time}
				if kind == "rotate": key.value = pose[name][kind]
				else:
					key.x = pose[name][kind].x
					key.y = pose[name][kind].y
				tracks[name][kind].append(key)
	for name: String in tracks:
		if not clip.bones.has(name): clip.bones[name] = {}
		clip.bones[name].merge(tracks[name], true)
	return clip

func _world(name: String, pose: Dictionary) -> Transform2D:
	var bone: Dictionary = definitions[name]
	var delta: Dictionary = pose.get(name, {})
	var angle := deg_to_rad(float(bone.get("rotation", 0.0)) + float(delta.get("rotate", 0.0)))
	var local := Transform2D(angle, Vector2(float(bone.get("x", 0.0)), float(bone.get("y", 0.0))) + Vector2(delta.get("translate", Vector2.ZERO)))
	local.x *= float(bone.get("scaleX", 1.0))
	local.y *= float(bone.get("scaleY", 1.0))
	return _world(bone.parent, pose) * local if bone.has("parent") else local

func _solve_arm(pose: Dictionary, wrist: Vector2) -> void:
	var parent := _world(CHEST, pose)
	var shoulder := parent * Vector2(definitions["4"].x, definitions["4"].y)
	var target := (wrist - shoulder) / 0.2
	var upper := Vector2(definitions["3"].x, definitions["3"].y)
	var length_a := upper.length()
	var length_b := 558.8518
	var elbow := -acos(clampf((target.length_squared() - length_a * length_a - length_b * length_b) / (2.0 * length_a * length_b), -1.0, 1.0))
	var arm := target.angle() - atan2(length_b * sin(elbow), length_a + length_b * cos(elbow)) - upper.angle()
	pose["4"] = {"rotate": rad_to_deg(wrapf(arm - parent.get_rotation() - deg_to_rad(definitions["4"].rotation), -PI, PI))}
	pose["3"] = {"rotate": rad_to_deg(wrapf(elbow + upper.angle() - deg_to_rad(definitions["3"].rotation), -PI, PI))}
