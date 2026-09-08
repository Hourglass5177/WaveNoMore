extends SceneTree
## 边界由实际角色连线求出，校验、圆盘拖动与数值提交遵循同一半圆。
var failures := 0
var rules: GameplayRuleSet = preload("res://content/rules/default_gameplay_rules.tres")
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func path_for(side: int) -> TuningPathEvent:
	var path := TuningPathEvent.new(); path.affinity = side
	var limits := ChartPathAdapter.angle_limits(side, rules)
	for i in 2:
		var point := TuningPathPoint.new(); point.event_id = "p%d" % i
		point.offset_ticks = i * 480; point.angle_deg = limits.y - 70 + i * 60
		path.points.append(point)
	return path
func run() -> void:
	for side in 2:
		var limits := ChartPathAdapter.angle_limits(side, rules)
		check(ChartPathAdapter.angle_allowed(limits.x, side, rules) and ChartPathAdapter.angle_allowed(limits.y, side, rules), "两端允许到达卡槽 %d" % side)
		check(not ChartPathAdapter.angle_allowed(limits.x - 0.01, side, rules) and not ChartPathAdapter.angle_allowed(limits.y + 0.01, side, rules), "两端禁止越线 %d" % side)
		var divider := (rules.death_wave_origin - rules.life_wave_origin).normalized()
		check(absf(Vector2.from_angle(ChartPathAdapter.BASE_ANGLE + deg_to_rad(limits.x)).cross(divider)) < 0.00001, "卡槽与角色连线共线 %d" % side)
		var circle := StudioAngleControl.new(); circle.path = path_for(side); circle.size = Vector2(320,320)
		root.add_child(circle); await process_frame
		var original := circle.path.points[1].angle_deg
		var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = circle.point_position(1)
		circle._gui_input(press)
		var motion := InputEventMouseMotion.new()
		motion.position = circle.size * 0.5 + Vector2.from_angle(ChartPathAdapter.BASE_ANGLE + deg_to_rad(limits.y + 20)) * 120
		circle._gui_input(motion)
		check(is_equal_approx(circle.path.points[1].angle_deg, limits.y), "鼠标越过卡槽时停在边界 %d" % side)
		circle.cancel()
		check(circle.path.points[1].angle_deg == original, "取消恢复手势前角度 %d" % side)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://builds/tuning-review")
			root.get_texture().get_image().get_region(Rect2i(0,0,320,320)).save_png("res://builds/tuning-review/angle-%d.png" % side)
		circle.queue_free(); await process_frame
		var editor = load("res://scenes/tools/chart_studio/path_editor.tscn").instantiate()
		editor.path = path_for(side)
		editor.edit_queued.connect(func(commit: Callable): commit.call())
		var result := {"path": null}
		editor.submitted.connect(func(path): result.path = path)
		root.add_child(editor); await process_frame
		editor.circle.selected = 1; editor._show_point()
		editor.angle_edit.get_line_edit().text = str(limits.y + 20)
		editor.angle_edit.get_line_edit().text_submitted.emit(editor.angle_edit.get_line_edit().text)
		check(result.path != null and is_equal_approx(result.path.points[1].angle_deg, limits.y), "数字输入不能绕过半圆限制 %d" % side)
		var invalid := path_for(side); invalid.points[1].angle_deg = limits.y + 1
		var validation := ChartPathAdapter.frequency_values(invalid, rules)
		check(validation.has("error") and validation.node == "p1", "已有越界草稿定位到节点 %d" % side)
		editor.queue_free(); await process_frame
	var death := path_for(1); death.points[0].angle_deg = 175; death.points[1].angle_deg = -145
	check(not ChartPathAdapter.frequency_values(death, rules).has("error"), "死侧跨 ±180°仍可编排合法短弧")
	print("TUNING BOUNDARY TESTS: ", failures); quit(1 if failures else 0)
