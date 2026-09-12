class_name LevelCurveEditor
extends Control
## 编辑一段关键帧的归一化时间/值曲线；X 单调，Y 允许越界形成回弹。
signal candidate_changed(first: Vector2, second: Vector2)
signal canceled
signal committed(first: Vector2, second: Vector2)
var first := Vector2(0.333333,0.333333)
var second := Vector2(0.666667,0.666667)
var _drag := -1
var _before: Array[Vector2] = []
var _origin := Vector2.ZERO
var _moved := false

func _ready() -> void:
	custom_minimum_size = Vector2(220,160); focus_mode = Control.FOCUS_ALL

func point(value: Vector2) -> Vector2: return Vector2(20 + value.x * (size.x - 40), size.y - 25 - value.y * (size.y - 50))
func value(at: Vector2) -> Vector2: return Vector2(clampf((at.x - 20) / (size.x - 40), 0, 1), clampf((size.y - 25 - at.y) / (size.y - 50), -2, 3))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("152133"))
	for index in 5:
		var ratio := float(index)/4
		draw_line(point(Vector2(ratio,0)), point(Vector2(ratio,1)), Color("293b50"))
		draw_line(point(Vector2(0,ratio)), point(Vector2(1,ratio)), Color("293b50"))
	var points := PackedVector2Array()
	for index in 65: points.append(point(Vector2.ZERO.bezier_interpolate(first,second,Vector2.ONE,float(index)/64)))
	draw_polyline(points, Color("e7c387"), 2, true)
	draw_line(point(Vector2.ZERO), point(first), Color("82bfc4")); draw_line(point(Vector2.ONE), point(second), Color("82bfc4"))
	draw_circle(point(first), 6, Color("90d6d2")); draw_circle(point(second), 6, Color("90d6d2"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if minf(event.position.distance_to(point(first)),event.position.distance_to(point(second)))>10: return
			grab_focus(); _before.assign([first,second]); _origin=event.position; _moved=false
			_drag = 0 if event.position.distance_to(point(first)) < event.position.distance_to(point(second)) else 1
		elif _drag >= 0:
			_drag = -1
			if first!=_before[0] or second!=_before[1]: committed.emit(first,second)
	elif event is InputEventMouseMotion and _drag >= 0:
		_moved=_moved or event.position.distance_to(_origin)>=6
		if not _moved: return
		if _drag == 0: first = value(event.position); first.x = minf(first.x, second.x)
		else: second = value(event.position); second.x = maxf(first.x, second.x)
		candidate_changed.emit(first,second); queue_redraw()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _drag >= 0:
		cancel_drag(); accept_event()

func cancel_drag() -> void:
	if _drag<0: return
	first=_before[0]; second=_before[1]; _drag=-1
	canceled.emit(); queue_redraw()
