extends SceneTree
## 从原始 Spine 导出生成先下击、后上挑的两段攻击与裙摆；烘焙衣料需图形渲染。
## godot --path . --script tools/generate_lingjun_gameplay.gd --rendering-method gl_compatibility

const FOLDER := "res://assets/character/lingjun/"
const STRIKE_END := 2.0 / 3.0
const ATTACK_END := 14.0 / 15.0
const SECTION_END := 1.1
const DOWN_SOURCE_START := 14.0 / 15.0
const DOWN_ENTRY := 4.0 / 15.0
const CLOTH_SLOTS := ["5", "2", "-7", "-9"]
const CONTROLS := ["skirt_waist", "skirt_body", "skirt_back", "skirt_middle", "skirt_front"]
const COLUMNS := 9
const ROWS := 13

var source: Dictionary
var actor: SpineSprite
var viewport: SubViewport
var cloth_rect: Rect2i
var control_origins: Array[Vector2] = []
var rest_hip: Vector2
var rest_front: Vector2
var rest_back: Vector2
var rest_knee: Vector2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("裙摆烘焙需要实际渲染，请去掉 --headless。")
		quit(1)
		return
	source = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "juese.spine-json"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1100, 900)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	actor = SpineSprite.new()
	actor.skeleton_data_res = load(FOLDER + "lingjun.tres")
	actor.position = Vector2(400, 820)
	viewport.add_child(actor)
	actor.set_update_mode(SpineConstant.UpdateMode_Manual)
	_sample(0.0)
	rest_hip = _bone_position("bone3")
	rest_front = _bone_position("y")
	rest_back = _bone_position("target")
	rest_knee = _bone_position("8")
	await _bake_cloth()
	var result := source.duplicate(true)
	result.skeleton.erase("hash")
	_build_attacks(result)
	_retime_downstroke(result)
	_build_attack_loop(result)
	preload("res://tools/lingjun_rest_animations.gd").new().build(result)
	_prepare_attack_sampling(result)
	_build_skirt(result)
	_write(FOLDER + "lingjun_gameplay.spine-json", JSON.stringify(result))
	var atlas := FileAccess.get_file_as_string(FOLDER + "juese.atlas").strip_edges()
	atlas += "\n\nlingjun_skirt.png\nsize:%d,%d\nfilter:Linear,Linear\npma:true\nscale:1\nlingjun_skirt\nbounds:0,0,%d,%d\n" % [cloth_rect.size.x, cloth_rect.size.y, cloth_rect.size.x, cloth_rect.size.y]
	_write(FOLDER + "lingjun_gameplay.atlas", atlas)
	await _bake_death_frame()
	print("Lingjun generated: down/up %.3f s each; skirt %s, %d vertices" % [SECTION_END, cloth_rect, COLUMNS * ROWS])
	viewport.queue_free()
	await process_frame
	quit()


func _sample(seconds: float, animation: String = "attack") -> void:
	actor.get_animation_state().clear_tracks()
	actor.get_skeleton().set_to_setup_pose()
	var entry := actor.get_animation_state().set_animation(animation, false, 0)
	entry.set_track_time(seconds)
	actor.update_skeleton(0.0)


func _bone_position(name: String) -> Vector2:
	# IK 求解结果在 applied_pose 中；get_pose() 中的膝骨世界坐标尚未应用约束。
	var pose := actor.get_skeleton().find_bone(name).get_applied_pose()
	# spine-godot 的实例将 skeleton.scale_y 设为 -1；导出 JSON 仍采用 Y 朝上的坐标。
	return Vector2(pose.get_world_x(), -pose.get_world_y())


func _bake_cloth() -> void:
	var slots := actor.get_skeleton().get_slots()
	for index in slots.size():
		if not source.slots[index].name in CLOTH_SLOTS:
			slots[index].get_pose().set_attachment(null)
	actor.update_skeleton(0.0)
	# update_skeleton 会再次应用动画，但源动画没有附件切换，隐藏槽位仍然有效。
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	var used := rendered.get_used_rect().grow(2)
	var cloth := rendered.get_region(used)
	_weld_texture_seam(cloth)
	cloth.save_png(FOLDER + "lingjun_skirt.png")
	cloth_rect = Rect2i(used.position - Vector2i(actor.position), used.size)
	assert(cloth_rect.size.x > 0 and cloth_rect.size.y > 0, "衣料烘焙结果不能为空")


func _weld_texture_seam(cloth: Image) -> void:
	# 原四片衣料在站姿仍有 1～11 px 的透明内缝。烘焙时用相邻布料颜色接合，
	# 仅处理两端都被布料包围的窄缝；保留下摆外轮廓及其较宽的凹口。
	for y in range(2, cloth.get_height() - 2):
		var left := -1
		for x in cloth.get_width():
			if cloth.get_pixel(x, y).a < 0.99: continue
			if left >= 0 and x - left > 1 and x - left <= 13:
				var a := cloth.get_pixel(left, y)
				var b := cloth.get_pixel(x, y)
				for inside in range(left + 1, x):
					cloth.set_pixel(inside, y, a.lerp(b, float(inside - left) / float(x - left)))
			left = x


func _timeline_value(keys: Array, seconds: float, property: String) -> float:
	var left: Dictionary = keys[0]
	if seconds < float(left.get("time", 0.0)):
		return 0.0
	for right: Dictionary in keys.slice(1):
		if seconds < float(right.get("time", 0.0)):
			if left.get("curve", "") == "stepped":
				return float(left.get(property, 0.0))
			var weight := inverse_lerp(float(left.get("time", 0.0)), float(right.time), seconds)
			return lerpf(float(left.get(property, 0.0)), float(right.get(property, 0.0)), weight)
		left = right
	return float(left.get(property, 0.0))


func _build_attacks(result: Dictionary) -> void:
	var animation: Dictionary = source.animations.attack
	var bones := {}
	for name: String in animation.bones:
		var timelines := {}
		for kind: String in animation.bones[name]:
			var original: Array = animation.bones[name][kind]
			var keys: Array = []
			var properties := ["value"] if kind == "rotate" else ["x", "y"]
			# 原第二招从收势中起手；先从站姿进入其蓄力姿势，再保留原下击和收招。
			for step in range(9):
				var fraction := float(step) / 8.0
				var key := {"time": DOWN_ENTRY * fraction}
				for property: String in properties:
					key[property] = lerpf(_timeline_value(original, 0.0, property),
						_timeline_value(original, DOWN_SOURCE_START, property), smoothstep(0.0, 1.0, fraction))
				keys.append(key)
			for key: Dictionary in original:
				var seconds := float(key.get("time", 0.0))
				if seconds > DOWN_SOURCE_START and seconds < 1.6:
					var copied := key.duplicate(true)
					copied.time = seconds - DOWN_SOURCE_START + DOWN_ENTRY
					keys.append(copied)
			# 两招均在 0.933 秒回到站姿，停 1/6 秒；段与段之间没有交叉混合。
			for seconds: float in [ATTACK_END, SECTION_END]:
				var key := {"time": seconds}
				for property: String in properties:
					key[property] = _timeline_value(original, 0.0, property)
				keys.append(key)
			# 上挑保留原第一招，整体移到第二段。
			# 保留首帧的 stepped 语义，不能把上挑起手变成缓慢滑动。
			if original[0].get("time", 0.0) == 0.0 and original[0].has("curve"):
				keys.back().curve = original[0].curve
			for key: Dictionary in original:
				var seconds := float(key.get("time", 0.0))
				if seconds > 0.0 and seconds < STRIKE_END - 0.000001:
					var copied := key.duplicate(true)
					copied.time = seconds + SECTION_END
					keys.append(copied)
			var cut := {"time": SECTION_END + STRIKE_END}
			var finish := {"time": SECTION_END + ATTACK_END}
			for property: String in properties:
				cut[property] = _timeline_value(original, STRIKE_END, property)
				finish[property] = _timeline_value(original, 1.6, property)
			keys.append(cut)
			# 收招用若干平滑关键帧，避免源片段末尾的 stepped 延伸成突然跳回。
			for step in range(1, 9):
				var fraction := float(step) / 8.0
				var ease := smoothstep(0.0, 1.0, fraction)
				var key := {"time": SECTION_END + lerpf(STRIKE_END, ATTACK_END, fraction)}
				for property: String in properties:
					key[property] = lerpf(cut[property], finish[property], ease)
				keys.append(key)
			var rest := finish.duplicate(true)
			rest.time = SECTION_END * 2.0
			keys.append(rest)
			timelines[kind] = keys
		bones[name] = timelines
	var order: Array = [{"time": 0.0}]
	# 下击起手时手臂位于身后；仅换槽位次序，不改服装、武器层级结构。
	var down_order := {}
	for key: Dictionary in animation.get("drawOrder", []):
		var seconds := float(key.get("time", 0.0))
		if seconds <= DOWN_SOURCE_START:
			down_order = key.duplicate(true)
		else:
			var copied := key.duplicate(true)
			copied.time = seconds - DOWN_SOURCE_START + DOWN_ENTRY
			order.append(copied)
	down_order.time = DOWN_ENTRY * 0.5
	order.insert(1, down_order)
	order.append({"time": ATTACK_END})
	order.append({"time": SECTION_END})
	for key: Dictionary in animation.get("drawOrder", []):
		if float(key.get("time", 0.0)) <= STRIKE_END:
			var copied := key.duplicate(true)
			copied.time = float(key.get("time", 0.0)) + SECTION_END
			order.append(copied)
	order.append({"time": SECTION_END + 0.8})
	result.animations = {"attack": {"bones": bones, "drawOrder": order}}


func _downstroke_time(time: float) -> float:
	# 保留右侧向下砸的轨迹：压缩举槌准备，给真正下劈多留几帧；整招长度不变。
	if time <= DOWN_ENTRY or time >= STRIKE_END: return time
	if time < 13.0 / 30.0: return remap(time, DOWN_ENTRY, 13.0 / 30.0, DOWN_ENTRY, 0.35)
	if time < 0.5: return remap(time, 13.0 / 30.0, 0.5, 0.35, 0.55)
	return remap(time, 0.5, STRIKE_END, 0.55, STRIKE_END)


func _retime_downstroke(result: Dictionary) -> void:
	for name: String in result.animations.attack.bones:
		for kind: String in result.animations.attack.bones[name]:
			var original: Array = result.animations.attack.bones[name][kind]
			var keys: Array = original.duplicate(true)
			# 在时间映射转折处补原姿势，避免稀疏轨道跨越转折而改变动作形状。
			for boundary: float in [DOWN_ENTRY, 13.0 / 30.0, 0.5, STRIKE_END]:
				if keys.any(func(key): return absf(float(key.get("time", 0.0)) - boundary) < 0.000001): continue
				var key := {"time": boundary}
				for property: String in (["value"] if kind == "rotate" else ["x", "y"]):
					key[property] = _timeline_value(original, boundary, property)
				for prior: Dictionary in original:
					if float(prior.get("time", 0.0)) > boundary: break
					if prior.get("curve", "") == "stepped": key.curve = "stepped"
					else: key.erase("curve")
				keys.append(key)
			for key: Dictionary in keys: key.time = _downstroke_time(float(key.get("time", 0.0)))
			keys.sort_custom(func(a, b): return a.time < b.time)
			result.animations.attack.bones[name][kind] = keys
	for key: Dictionary in result.animations.attack.drawOrder:
		key.time = _downstroke_time(float(key.get("time", 0.0)))


func _build_attack_loop(result: Dictionary) -> void:
	# 单次收招保留站姿；长按循环绕过站姿，把本招余势接到下一招蓄力。
	# 三次 Hermite 同时匹配两端姿势和速度，循环接缝也按同样方式处理。
	var cycle := SECTION_END * 2.0
	var loop: Dictionary = result.animations.attack.duplicate(true)
	for name: String in loop.bones:
		for kind: String in loop.bones[name]:
			var original: Array = result.animations.attack.bones[name][kind]
			var properties := ["value"] if kind == "rotate" else ["x", "y"]
			var keys: Array = []
			for key: Dictionary in original:
				var time := float(key.get("time", 0.0))
				if (time > DOWN_ENTRY and time < STRIKE_END) or (time > SECTION_END + DOWN_ENTRY and time < SECTION_END + STRIKE_END):
					keys.append(key.duplicate(true))
			for boundary: float in [SECTION_END, cycle]:
				var start := boundary - SECTION_END + STRIKE_END
				var end := boundary + DOWN_ENTRY
				var span := end - start
				var steps := roundi(span * 60.0)
				for step in range(steps + 1):
					var u := float(step) / steps
					var time := start + span * u
					var key := {"time": fposmod(time, cycle)}
					for property: String in properties:
						var a := _timeline_value(original, start, property)
						var b := _timeline_value(original, fposmod(end, cycle), property)
						var va := (a - _timeline_value(original, start - 0.001, property)) / 0.001
						var vb := (_timeline_value(original, fposmod(end, cycle) + 0.001, property) - b) / 0.001
						key[property] = (2*u*u*u - 3*u*u + 1)*a + (u*u*u - 2*u*u + u)*span*va + (-2*u*u*u + 3*u*u)*b + (u*u*u - u*u)*span*vb
					keys.append(key)
			keys.sort_custom(func(a, b): return a.time < b.time)
			# 2.2 秒恰好落在采样点上；首尾显式同姿，避免 Spine 循环时跳回。
			var finish: Dictionary = keys[0].duplicate(true)
			finish.time = cycle
			keys.append(finish)
			loop.bones[name][kind] = keys
	result.animations.attack_loop = loop


func _build_skirt(result: Dictionary) -> void:
	var rect := Rect2(cloth_rect)
	var top := -rect.position.y
	var bottom := -rect.end.y
	var middle_x := rect.position.x + rect.size.x * 0.58
	control_origins = [rest_hip, Vector2(middle_x, lerpf(top, bottom, 0.48)),
		Vector2(rect.position.x + rect.size.x * 0.12, bottom),
		Vector2(middle_x, bottom), Vector2(rect.end.x, bottom)]
	var first_bone: int = result.bones.size()
	for index in CONTROLS.size():
		var origin := (control_origins[index] - rest_hip) / 0.2 if index == 0 else control_origins[index] / 0.2
		result.bones.append({"name": CONTROLS[index], "parent": "bone3" if index == 0 else "bone2", "x": origin.x, "y": origin.y})
	var vertices := []
	var uvs := []
	var triangles := []
	for row in ROWS:
		var v := float(row) / float(ROWS - 1)
		for column in COLUMNS:
			var u := float(column) / float(COLUMNS - 1)
			var point := Vector2(lerpf(rect.position.x, rect.end.x, u), lerpf(top, bottom, v))
			uvs.append_array([u, v])
			var waist := 1.0 - smoothstep(0.10, 0.52, v)
			# 前缘从大腿处就开始撑开，不能等到裙底才跟随前脚，否则膝部会向内凹。
			var front_side := smoothstep(0.50, 0.92, u)
			var hem := lerpf(smoothstep(0.42, 0.94, v), smoothstep(0.08, 0.44, v), front_side)
			var back := 1.0 - smoothstep(0.05, 0.55, u)
			var front := smoothstep(0.55, 1.0, u)
			var weights := [waist, (1.0 - waist) * (1.0 - hem), (1.0 - waist) * hem * back,
				(1.0 - waist) * hem * (1.0 - back - front), (1.0 - waist) * hem * front]
			var count := 0
			for weight: float in weights:
				if weight > 0.000001: count += 1
			vertices.append(count)
			for index in weights.size():
				if weights[index] <= 0.000001: continue
				var local := (point - control_origins[index]) / 0.2
				vertices.append_array([first_bone + index, local.x, local.y, weights[index]])
			if row < ROWS - 1 and column < COLUMNS - 1:
				var a := row * COLUMNS + column
				triangles.append_array([a, a + COLUMNS, a + 1, a + 1, a + COLUMNS, a + COLUMNS + 1])
	var attachment := {"type": "mesh", "path": "lingjun_skirt", "uvs": uvs, "vertices": vertices,
		"triangles": triangles, "width": rect.size.x, "height": rect.size.y}
	# 复用原 2 槽，避免改变源动画 drawOrder 中的槽位索引；其余旧裙片只移除附件。
	for slot: Dictionary in result.slots:
		if slot.name in CLOTH_SLOTS:
			slot.erase("attachment")
			if slot.name == "2": slot.attachment = "lingjun_skirt"
	for skin: Dictionary in result.skins:
		for slot_name: String in CLOTH_SLOTS: skin.attachments.erase(slot_name)
		skin.attachments["2"] = {"lingjun_skirt": attachment}
	_animate_skirt(result)


func _prepare_attack_sampling(result: Dictionary) -> void:
	# 收招时脚与腰的插值经过 IK 后，膝盖并非沿直线返回。先加载完整两招作为
	# 生成时的参考骨架，再采样整段真实姿势；原衣料仅用于保持完整参考结构。
	DirAccess.make_dir_recursive_absolute("res://build/lingjun")
	var path := "res://build/lingjun/attack_reference.spine-json"
	_write(path, JSON.stringify(result))
	var file := SpineSkeletonFileResource.new()
	file.load_from_file(path)
	var data := SpineSkeletonDataResource.new()
	data.atlas_res = load(FOLDER + "juese.atlas")
	data.skeleton_file_res = file
	actor.skeleton_data_res = data


func _animate_skirt(result: Dictionary) -> void:
	for animation: String in result.animations:
		if animation == "hurt": continue
		_animate_skirt_clip(result, animation)


func _animate_skirt_clip(result: Dictionary, animation: String) -> void:
	var tracks: Array = [[], [], [], []]
	var deforms := []
	# 只在资源生成时采样脚部 IK；正式播放仅插值这四条裙骨轨道。
	var duration := 4.0 if animation == "idle" else (1.2 if animation == "death" else SECTION_END * 2.0)
	for frame in range(roundi(duration * 30.0) + 1):
		var seconds := float(frame) / 30.0
		_sample(seconds, animation)
		var hip := _bone_position("bone3") - rest_hip
		var front := _bone_position("y") - rest_front
		var back := _bone_position("target") - rest_back
		var knee := _bone_position("8") - rest_knee
		var offsets := [hip * 0.62 + front * 0.10, hip * 0.08 + back * 0.18,
			hip * 0.10 + front * 0.36, hip * 0.08 + front * 0.82]
		# 弓步后半程膝盖会继续前移而脚不再移动，裙子的前缘需同时包住膝与脚。
		offsets[3].x = hip.x * 0.08 + maxf(front.x * 0.82, knee.x * 0.94)
		# 前缘预留少量布料松量，避免短混合时非线性的膝部 IK 顶出线性混合的裙面。
		offsets[3].x += 32.0 * smoothstep(0.0, 80.0, front.x)
		if animation == "death":
			# 屈膝时裙身随腰下沉、下摆留在地面，前缘沿真实膝盖展开。
			var sink := smoothstep(0.16, 0.95, seconds)
			offsets = [hip * 0.52, Vector2(-35.0, 0.0) * sink,
				Vector2(30.0, 0.0) * sink, Vector2(maxf(knee.x + 28.0 * sink, 0.0), 0.0)]
			deforms.append({"time": seconds, "vertices": _kneeling_deform(result, hip, offsets, sink, knee.x)})
		for index in offsets.size():
			var offset: Vector2 = offsets[index]
			# 下摆主要横向撑开；腰部下压时不把裙底拉进地面。
			if index > 0: offset.y = maxf(offset.y * 0.2, -2.0)
			offset /= 0.2
			tracks[index].append({"time": seconds, "x": offset.x, "y": offset.y})
	for index in tracks.size():
		result.animations[animation].bones[CONTROLS[index + 1]] = {"translate": tracks[index]}
	if animation == "death":
		result.animations.death.attachments = {str(result.skins[0].name): {"2": {"lingjun_skirt": {"deform": deforms}}}}


func _kneeling_deform(result: Dictionary, hip: Vector2, offsets: Array, sink: float, knee_shift: float) -> Array:
	# 连续网格的前缘绕膝形成圆弧，裙底铺开。各影响骨使用同一个目标网格，
	# 因而修形不会产生不同权重之间的接缝，也不改变原贴图的 UV。
	var mesh: Dictionary = result.skins[0].attachments["2"].lingjun_skirt
	var values := []
	var cursor := 0
	for vertex in COLUMNS * ROWS:
		var u: float = mesh.uvs[vertex * 2]
		var v: float = mesh.uvs[vertex * 2 + 1]
		var front := smoothstep(0.4, 0.95, u)
		var bulge := maxf(120.0 * sink, knee_shift * 1.3)
		var shape := Vector2(hip.x * (1.0 - v) + front * (bulge * pow(sin(PI * v), 2.0) + 50.0 * sink * v) - 35.0 * sink * (1.0 - u) * v, hip.y * (1.0 - v))
		var count := int(mesh.vertices[cursor])
		cursor += 1
		for influence in count:
			var control: int = int(mesh.vertices[cursor]) - result.bones.size() + CONTROLS.size()
			var offset: Vector2 = hip if control == 0 else offsets[control - 1]
			values.append_array([(shape.x - offset.x) / 0.2, (shape.y - offset.y) / 0.2])
			cursor += 4
	return values


func _write(path: String, text: String) -> void:
	FileAccess.open(path, FileAccess.WRITE).store_string(text)


func _bake_death_frame() -> void:
	# 末姿整幅烘焙一次，死亡碎片直接使用此贴图，游戏中不读取 GPU 像素。
	var file := SpineSkeletonFileResource.new()
	file.load_from_file(FOLDER + "lingjun_gameplay.spine-json")
	var data := SpineSkeletonDataResource.new()
	data.atlas_res = load(FOLDER + "lingjun_gameplay.atlas")
	data.skeleton_file_res = file
	actor.skeleton_data_res = data
	_sample(1.2, "death")
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	var used := rendered.get_used_rect().grow(2)
	rendered.get_region(used).save_png(FOLDER + "lingjun_death.png")
	var rect := Rect2(used.position - Vector2i(actor.position), used.size)
	var scene := '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://src/presentation/vfx/lingjun_ashes.gd" id="1"]\n[ext_resource type="Texture2D" path="res://assets/character/lingjun/lingjun_death.png" id="2"]\n\n[node name="Ashes" type="MeshInstance2D"]\nvisible = false\ntexture = ExtResource("2")\nscript = ExtResource("1")\nframe_rect = Rect2(%f, %f, %f, %f)\n' % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	_write(FOLDER + "lingjun_ashes.tscn", scene)
