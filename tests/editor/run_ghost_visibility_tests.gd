extends SceneTree
## Ghost 贴图、预告过渡、遮挡与网格复用的实际渲染回归。
var failures := 0
var checks := 0
var view: SubViewport
var overlay: SuManifestationOverlay
const OUT := "res://builds/ghost-review/"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func frame_at(time: float, name: String) -> Image:
	overlay.set_visual_time(time)
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := view.get_texture().get_image()
	if not name.is_empty(): frame.save_png(OUT + name + ".png")
	return frame
func brightness(frame: Image, at: Vector2i) -> float:
	var total := 0.0
	for y in range(at.y - 55, at.y + 75):
		for x in range(at.x - 65, at.x + 65):
			var color := frame.get_pixel(x, y)
			total += (color.r + color.g + color.b) / 3.0
	return total
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	view = SubViewport.new(); view.size = Vector2i(1920,1080)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var field := TuningInterferenceVisual.new(); field.z_index = 4
	field.canvas_size = Vector2(view.size); view.add_child(field)
	var blocker := ColorRect.new(); blocker.size = Vector2(view.size); blocker.color = Color.BLACK; blocker.z_index = 35
	view.add_child(blocker)
	overlay = field._su_overlay
	overlay.canvas_size = Vector2(view.size)
	var points: Array[Vector2] = [Vector2(.15,.3),Vector2(.5,.3),Vector2(.85,.3),Vector2(.3,.75),Vector2(.7,.75)]
	var target := {"event_id":"visibility", "time_us":3000000, "visible_from_us":300000, "points":points}
	overlay.prepare_targets(target)
	field.visible = true
	check(not overlay.z_as_relative and overlay.z_index > blocker.z_index, "Ghost 高于滑条，不被覆盖")
	check(overlay._entries.visibility.points.size() == 5, "五个 UV 点保持独立目标")
	var mesh: ArrayMesh = overlay._entries.visibility.view.mesh
	var surface := mesh.surface_get_arrays(0)
	var nodes := overlay.get_child_count()
	overlay.set_visual_time(.3)
	check(overlay.visual_phase(overlay._entries.visibility).y == 0.0, "出现起点从透明进入")
	overlay.set_visual_time(.5)
	check(overlay.visual_phase(overlay._entries.visibility) == Vector4(0,1,.13,0), "预告先闭眼并发弱光")
	overlay.set_visual_time(2.40)
	check(is_equal_approx(overlay.visual_phase(overlay._entries.visibility).x,.5), "睁眼中点平滑混合")
	overlay.set_visual_time(2.65)
	check(overlay.visual_phase(overlay._entries.visibility) == Vector4(1,1,.95,0), "睁眼后保持强白光")
	if DisplayServer.get_name() != "headless":
		var closed := await frame_at(.5,"01-closed")
		await frame_at(2.40,"02-opening")
		var opened := await frame_at(2.65,"03-open")
		for point in points:
			var p := Vector2i(point * Vector2(view.size))
			check(brightness(closed,p) > 10.0, "闭眼素材可辨认")
			check(brightness(opened,p) > brightness(closed,p) * 1.4, "睁眼后像素明显提亮")
		check(opened.get_pixel(20,20) == Color.BLACK, "远离音符无背景色矩形")
		var paused := await frame_at(2.65,"")
		check(paused.get_data() == opened.get_data(), "暂停画面不变")
		overlay.clear(); overlay.set_visual_time(2.65); overlay.prepare_targets(target)
		var seeked := await frame_at(2.65,"")
		check(seeked.get_data() == opened.get_data(), "直接定位重建同一睁眼状态")
	mesh = overlay._entries.visibility.view.mesh
	var before := mesh.surface_get_arrays(0)
	for i in 100: overlay.set_visual_time(2.65 + i * .001)
	check(mesh.surface_get_arrays(0) == before, "时钟推进不重建网格")
	overlay.resolve_targets({"event_id":"visibility", "success":true})
	overlay.set_visual_time(3.2)
	var phase := overlay.visual_phase(overlay._entries.visibility)
	overlay.resolve_targets({"event_id":"visibility", "success":false})
	check(overlay.visual_phase(overlay._entries.visibility) == phase, "重复结果不重启动画或改成失败")
	if DisplayServer.get_name() != "headless": await frame_at(3.2,"04-hit")
	overlay.set_visual_time(4.0)
	check(not overlay.has_active_entries(), "过期结果回收")
	overlay.set_visual_time(.5); overlay.prepare_targets(target)
	check(overlay.get_child_count() == nodes, "重复使用复用节点池")
	check(not overlay._entries.visibility.resolved, "复用清除结算和白光状态")
	overlay.resolve_targets({"event_id":"visibility", "success":false})
	overlay.set_visual_time(3.1)
	check(overlay.visual_phase(overlay._entries.visibility).z == 0.0, "Miss 关闭白光")
	overlay.clear()
	check(not overlay.has_active_entries(), "重试清除所有目标")
	view.queue_free(); await process_frame
	print("GHOST VISIBILITY: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
