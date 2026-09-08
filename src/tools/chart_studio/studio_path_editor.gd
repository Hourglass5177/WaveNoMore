extends VBoxContainer
## 属性面板里的独立编辑控件。新增节点先作为草稿，合法后一次提交。
signal submitted(path: TuningPathEvent)
signal candidate(path: TuningPathEvent)
signal edit_queued(commit: Callable)
var path: TuningPathEvent
var pending_node := false
@onready var circle: StudioAngleControl = $Circle
@onready var points: OptionButton = $Point
@onready var time_edit: SpinBox = $Time
@onready var angle_edit: SpinBox = $Angle
@onready var hint: Label = $Hint
var _updating := false

func _ready() -> void:
	_refresh()
	points.item_selected.connect(func(i: int): circle.selected = i; _show_point())
	circle.angle_preview.connect(func(_i: int, _value: float): _show_point(); candidate.emit(path))
	circle.angle_committed.connect(func(_i: int, _value: float): _commit())
	circle.cancelled.connect(func(): _show_point(); candidate.emit(null))
	for edit in [time_edit, angle_edit]:
		var apply := func():
			if _updating or not is_inside_tree(): return
			edit.apply()
			var point := path.points[circle.selected]
			if edit == time_edit:
				if circle.selected == 0: return
				point.offset_ticks = int(time_edit.value) - path.tick
			else:
				point.angle_deg = ChartPathAdapter.clamp_angle(angle_edit.value, path.affinity, circle.rules)
				_show_point()
			_commit()
		edit.get_line_edit().text_submitted.connect(func(_s: String): edit_queued.emit(apply))
		edit.get_line_edit().focus_exited.connect(func(): edit_queued.emit(apply))
	$Delete.pressed.connect(func():
		if circle.selected <= 0 or circle.selected >= path.points.size() - 1: return
		path.points.remove_at(circle.selected); circle.selected -= 1; _refresh(); _commit())
	$Apply.pressed.connect(_commit)

func _refresh() -> void:
	circle.path = path; points.clear()
	for i in path.points.size(): points.add_item("节点 %d%s" % [i + 1, " · 起点" if i == 0 else (" · 终点" if i == path.points.size() - 1 else "")])
	circle.selected = clampi(circle.selected, 0, path.points.size() - 1)
	_show_point()

func _show_point() -> void:
	_updating = true
	points.select(circle.selected)
	time_edit.set_value_no_signal(path.tick + path.points[circle.selected].offset_ticks)
	angle_edit.set_value_no_signal(ChartPathAdapter.unwrap_angle(path.points[circle.selected].angle_deg, path.affinity, circle.rules))
	time_edit.editable = circle.selected > 0
	$Delete.disabled = circle.selected == 0 or circle.selected == path.points.size() - 1
	circle.queue_redraw(); _updating = false

func _commit() -> void:
	if not is_inside_tree(): return
	var result := ChartPathAdapter.frequency_values(path, load("res://content/rules/default_gameplay_rules.tres"))
	if result.has("error"):
		hint.text = result.error; candidate.emit(path); return
	if pending_node:
		hint.text = "节点已就绪，点击“应用节点”提交"; candidate.emit(path)
		if not $Apply.has_focus(): return
	submitted.emit(path.duplicate(true))
