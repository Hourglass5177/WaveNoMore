extends SceneTree
## 检查导出网格在完整动作和重按混合中保持合理范围、连续且不翻折。

var failures := 0
var samples := 0
var actor: SpineSprite
var mesh: Dictionary
var cloth_image: Image


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/character/lingjun/lingjun_gameplay.spine-json"))
	mesh = data.skins[0].attachments["2"].lingjun_skirt
	cloth_image = (load("res://assets/character/lingjun/lingjun_skirt.png") as Texture2D).get_image()
	actor = SpineSprite.new()
	actor.skeleton_data_res = load("res://assets/character/lingjun/lingjun_gameplay.tres")
	root.add_child(actor)
	actor.set_update_mode(SpineConstant.UpdateMode_Manual)
	for animation: String in ["attack", "attack_loop", "idle", "death"]:
		var duration := 4.0 if animation == "idle" else (1.2 if animation == "death" else 2.2)
		for frame in range(roundi(duration * 120.0) + 1):
			actor.get_animation_state().clear_tracks()
			actor.get_skeleton().set_to_setup_pose()
			var track := actor.get_animation_state().set_animation(animation, false, 0)
			track.set_track_time(float(frame) / 120.0)
			actor.update_skeleton(0.0)
			_validate()
	# 覆盖整个循环上的松开与重新下击，特别检查连续衔接区的膝部覆盖。
	for phase: float in [0.46, 0.6, 0.8, 1.05, 1.3, 1.6, 1.9, 2.15]:
		for releasing: bool in [false, true]:
			actor.get_animation_state().clear_tracks()
			actor.get_skeleton().set_to_setup_pose()
			var old := actor.get_animation_state().set_animation("attack_loop", true, 0)
			old.set_track_time(phase)
			actor.update_skeleton(0.0)
			var track := actor.get_animation_state().set_animation("attack" if releasing else "attack_loop", not releasing, 0)
			track.set_track_time(phase if releasing else 0.46)
			if releasing: track.set_animation_end(1.1 if phase < 1.1 else 2.2)
			track.set_mix_duration(0.1 if releasing else 0.025)
			for step in 16:
				actor.update_skeleton(1.0 / 120.0)
				_validate()
	# 致命伤害可发生在任意挥击相位；混合中也要检查修形与腿部 IK 的组合。
	for phase: float in [0.46, 0.55, 0.8, 1.3, 1.5, 1.9]:
		actor.get_animation_state().clear_tracks()
		actor.get_skeleton().set_to_setup_pose()
		actor.get_animation_state().set_animation("attack_loop", true, 0).set_track_time(phase)
		actor.update_skeleton(0.0)
		var track := actor.get_animation_state().set_animation("death", false, 0)
		track.set_mix_duration(0.12)
		for frame in 145:
			actor.update_skeleton(1.0 / 120.0)
			_validate()
	actor.free()
	print("Lingjun skirt: %d sampled poses, %d failures" % [samples, failures])
	quit(1 if failures else 0)


func _validate() -> void:
	samples += 1
	var vertices: Array = mesh.vertices
	var bones := actor.get_skeleton().get_bones()
	var points := PackedVector2Array()
	var deform = actor.get_skeleton().get_slots()[9].get_pose().get_deform()
	var deform_cursor := 0
	var cursor := 0
	while cursor < vertices.size():
		var count := int(vertices[cursor])
		cursor += 1
		var point := Vector2.ZERO
		for influence in count:
			var pose = bones[int(vertices[cursor])].get_applied_pose()
			var x: float = vertices[cursor + 1]
			var y: float = vertices[cursor + 2]
			if not deform.is_empty():
				x += deform[deform_cursor]
				y += deform[deform_cursor + 1]
			deform_cursor += 2
			var weight: float = vertices[cursor + 3]
			point += Vector2(pose.get_a() * x + pose.get_b() * y + pose.get_world_x(),
				pose.get_c() * x + pose.get_d() * y + pose.get_world_y()) * weight
			cursor += 4
		points.append(point)
	var hip_y: float = actor.get_skeleton().find_bone("bone3").get_pose().get_world_y()
	for point in points:
		if not point.is_finite() or point.y < hip_y - 120.0 or point.y > 40.0:
			_fail("裙摆顶点超出腰部或地面范围：%s" % point)
			break
	var indices: Array = mesh.triangles
	for offset in range(0, indices.size(), 3):
		var a := points[int(indices[offset])]
		var b := points[int(indices[offset + 1])]
		var c := points[int(indices[offset + 2])]
		if (b - a).cross(c - a) >= -0.01:
			_fail("裙摆三角形翻折或退化：%d" % (offset / 3))
			break
	# 裙面必须包住真实前膝及前脚；仅检查没有开裂，仍可能留下向内凹的空洞。
	for bone_name: String in ["8", "y"]:
		var pose := actor.get_skeleton().find_bone(bone_name).get_applied_pose()
		var covered := Vector2(pose.get_world_x() + 8.0, pose.get_world_y())
		if not _cloth_contains(points, covered):
			_fail("第 %d 个姿势的裙面未覆盖 %s：%s" % [samples, bone_name, covered])
	# 再检查真正交给 Spine 渲染的附件范围，防止测试的坐标换算掩盖导出错误。
	for index in actor.get_skeleton().get_slots().size():
		if index != 9:
			actor.get_skeleton().get_slots()[index].get_pose().set_attachment(null)
	var bounds := actor.get_skeleton().get_bounds()
	if bounds.position.y < hip_y - 120.0 or bounds.end.y > 40.0 or bounds.size.x < 100.0:
		_fail("Spine 裙摆附件范围异常：%s" % bounds)


func _cloth_contains(points: PackedVector2Array, point: Vector2) -> bool:
	for offset in range(0, mesh.triangles.size(), 3):
		var a := int(mesh.triangles[offset])
		var b := int(mesh.triangles[offset + 1])
		var c := int(mesh.triangles[offset + 2])
		var ab := points[b] - points[a]
		var ac := points[c] - points[a]
		var relative := point - points[a]
		var wb := relative.cross(ac) / ab.cross(ac)
		var wc := ab.cross(relative) / ab.cross(ac)
		var wa := 1.0 - wb - wc
		if minf(wa, minf(wb, wc)) < -0.00001: continue
		var uv := Vector2(mesh.uvs[a * 2], mesh.uvs[a * 2 + 1]) * wa + Vector2(mesh.uvs[b * 2], mesh.uvs[b * 2 + 1]) * wb + Vector2(mesh.uvs[c * 2], mesh.uvs[c * 2 + 1]) * wc
		var x := clampi(roundi(uv.x * (cloth_image.get_width() - 1)), 0, cloth_image.get_width() - 1)
		var y := clampi(roundi(uv.y * (cloth_image.get_height() - 1)), 0, cloth_image.get_height() - 1)
		return cloth_image.get_pixel(x, y).a > 0.9
	return false


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
