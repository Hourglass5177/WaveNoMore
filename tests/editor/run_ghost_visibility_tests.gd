extends SceneTree
## 表现层遮挡回归：用五个测试目标验证层级，不把人工坐标用于生成算法验收。
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1
func run() -> void:
	var view := SubViewport.new(); view.size = Vector2i(640,360)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var field := TuningInterferenceVisual.new(); field.z_index = 4
	field.canvas_size = Vector2(640,360); view.add_child(field)
	# 与正式 Tuning 最高显示层相同，覆盖全部测试目标。
	var blocker := ColorRect.new(); blocker.size = Vector2(640,360); blocker.color = Color.BLACK; blocker.z_index = 35
	view.add_child(blocker)
	var overlay: Node2D = field._su_overlay
	overlay.set("canvas_size", Vector2(view.size))
	var points: Array[Vector2] = [Vector2(.15,.3),Vector2(.5,.3),Vector2(.85,.3),Vector2(.3,.75),Vector2(.7,.75)]
	overlay.prepare_targets({"event_id":"visibility", "time_us":1000000, "requested_count":5, "points":points})
	field.visible = true
	check(not overlay.z_as_relative and overlay.z_index > blocker.z_index, "Ghost 不继承波纹层，并高于 Tuning")
	check(overlay._entries.visibility.points.size() == 5, "表现层保留五个独立目标")
	if DisplayServer.get_name() != "headless":
		var draws := [0]
		overlay.draw.connect(func(): draws[0] += 1)
		await RenderingServer.frame_post_draw
		var frame := view.get_texture().get_image()
		for i in points.size():
			var p := Vector2i(points[i] * Vector2(640,360))
			var color := frame.get_pixelv(p)
			check(color.r > 0.9 and color.g > 0.9 and color.b > 0.9, "目标 %d 未被遮挡" % (i + 1))
		var static_draws: int = draws[0]
		for tick: int in 4:
			overlay.set_visual_time(float(tick) * 0.1)
			await process_frame
			await RenderingServer.frame_post_draw
		check(draws[0] == static_draws, "静止 Ghost 推进时钟不重新生成绘制命令")
		overlay.resolve_targets({"event_id": "visibility", "success": true})
		overlay.set_visual_time(1.2)
		await process_frame
		await RenderingServer.frame_post_draw
		check(draws[0] > static_draws and overlay.has_active_entries(), "结算后仍绘制命中动画")
		overlay.set_visual_time(2.0)
		await process_frame
		await RenderingServer.frame_post_draw
		check(not overlay.has_active_entries(), "结果过期后清除目标")
	view.queue_free(); await process_frame
	print("GHOST VISIBILITY TESTS: ", failures); quit(1 if failures else 0)
