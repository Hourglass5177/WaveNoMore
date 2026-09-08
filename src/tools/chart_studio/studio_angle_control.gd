class_name StudioAngleControl
extends Control
## 拖动期间只有候选角度，释放形成一次命令；参考轴不随窗口宽高比变化。
signal angle_preview(index: int, value: float)
signal angle_committed(index: int, value: float)
signal cancelled
var path: TuningPathEvent
var selected := 0
var dragging := false
var _before := 0.0
var _last_mouse_angle := 0.0
var rules: GameplayRuleSet = preload("res://content/rules/default_gameplay_rules.tres")

func _ready() -> void:
	custom_minimum_size = Vector2(160, 180)
	focus_mode = Control.FOCUS_ALL
	get_window().focus_exited.connect(cancel)

func point_position(index: int) -> Vector2:
	var angle := ChartPathAdapter.BASE_ANGLE + deg_to_rad(path.points[index].angle_deg)
	return size * 0.5 + Vector2.from_angle(angle) * (minf(size.x, size.y) * 0.38)

func _draw() -> void:
	var center := size * 0.5; var radius := minf(size.x, size.y) * 0.38
	draw_circle(center, radius, Color("333f51"), false, 1, true)
	var axis := Vector2.from_angle(ChartPathAdapter.BASE_ANGLE) * radius
	draw_line(center - axis, center + axis, Color("c8b47b"), 1, true)
	draw_string(ThemeDB.fallback_font, center + axis + Vector2(-16, -6), "0°", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ddc785"))
	if path == null: return
	var limits := ChartPathAdapter.angle_limits(path.affinity, rules)
	# 两个短槽就是拖动边界，不增加文字；位置与提交校验共用角色连线。
	for value in [limits.x, limits.y]:
		var radial := Vector2.from_angle(ChartPathAdapter.BASE_ANGLE + deg_to_rad(value))
		var tangent := radial.rotated(PI * 0.5)
		var p := center + radial * radius
		draw_line(p - radial * 7 - tangent * 3, p + radial * 7 - tangent * 3, Color("c8b47b"), 2, true)
		draw_line(p - radial * 7 + tangent * 3, p + radial * 7 + tangent * 3, Color("c8b47b"), 2, true)
	for i in range(1, path.points.size()):
		var angle := ChartPathAdapter.BASE_ANGLE + deg_to_rad(path.points[i - 1].angle_deg)
		var delta := deg_to_rad(wrapf(path.points[i].angle_deg - path.points[i - 1].angle_deg, -180, 180))
		var points := PackedVector2Array()
		for j in 33: points.append(center + Vector2.from_angle(angle + delta * j / 32.0) * radius)
		draw_polyline(points, Color("d59179") if path.affinity == 0 else Color("8eb6dd"), 2, true)
		var middle := angle + delta * 0.5; var at := center + Vector2.from_angle(middle) * radius
		var direction := Vector2.from_angle(middle + signf(delta) * PI / 2)
		draw_line(at, at - direction.rotated(0.6) * 7, Color.WHITE, 2)
		draw_line(at, at - direction.rotated(-0.6) * 7, Color.WHITE, 2)
	for i in path.points.size():
		var p := point_position(i)
		var earlier := false
		for j in i: earlier = earlier or p.distance_to(point_position(j)) < 3
		if earlier: continue
		var labels := PackedStringArray(); var active := false
		for j in range(i, path.points.size()):
			if p.distance_to(point_position(j)) < 3: labels.append(str(j + 1)); active = active or j == selected
		draw_circle(p, 7 if active else 5, Color("ffdf9c") if active else Color("90a1b7"))
		draw_string(ThemeDB.fallback_font, p + Vector2(7, 14), "/".join(labels), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func _gui_input(event: InputEvent) -> void:
	if path == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var nearest := selected
			for i in path.points.size():
				if point_position(i).distance_to(event.position) < point_position(nearest).distance_to(event.position) - 1: nearest = i
			if point_position(nearest).distance_to(event.position) > 18: return
			selected = nearest; _before = path.points[selected].angle_deg
			_last_mouse_angle = (event.position - size * 0.5).angle(); dragging = true; grab_focus()
		else:
			if dragging:
				dragging = false; angle_committed.emit(selected, path.points[selected].angle_deg)
		accept_event(); queue_redraw()
	elif event is InputEventMouseMotion and dragging:
		var angle: float = (event.position - size * 0.5).angle()
		var delta := rad_to_deg(wrapf(angle - _last_mouse_angle, -PI, PI)) * (0.1 if event.shift_pressed else 1.0)
		_last_mouse_angle = angle
		var limits := ChartPathAdapter.angle_limits(path.affinity, rules)
		var current := ChartPathAdapter.unwrap_angle(path.points[selected].angle_deg, path.affinity, rules)
		path.points[selected].angle_deg = clampf(current + delta, limits.x, limits.y)
		angle_preview.emit(selected, path.points[selected].angle_deg); queue_redraw(); accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel(); accept_event()

func cancel() -> void:
	if not dragging: return
	dragging = false; path.points[selected].angle_deg = _before
	cancelled.emit(); queue_redraw()
