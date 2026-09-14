extends Control
## 独立白盒轮播：仅模拟 UI 深度，不负责关卡加载或解锁。
signal selection_changed(index: int, level_id: String)
signal stage_requested(stage_id: String)

const CARD := preload("res://scenes/ui/modals/level_card.tscn")
const DESIGN_SIZE := Vector2(1920, 1080)

@export var catalog: Resource

@export var card_size := Vector2(360, 480)
var horizontal_radius := 480.0
@export_range(0.1, 1.0, 0.01) var minimum_scale := 0.55
@export_range(0.1, 2.0, 0.01) var response_time := 0.35
@export_range(0.05, 0.95, 0.01) var joystick_engage_threshold := 0.55
@export_range(0.0, 0.9, 0.01) var joystick_release_threshold := 0.35
@export var joystick_repeat_interval := 0.55
@export var joystick_initial_delay := 0.55

var _levels: Array[Dictionary] = []
var _cards: Array[Control] = []
var _configured := false
var _progress := 0.0
var _target := 0
var _velocity := 0.0
var _moving := false
var _held_direction := 0
var _held_time := 0.0
var _repeat_time := 0.0
var _heading_transparency := 1.0
var _heading_pending := false


func _ready() -> void:
	$Design/Left.pressed.connect(step.bind(-1))
	$Design/Right.pressed.connect(step.bind(1))
	var heading_material := $Design/Heading/HeadingText.material as ShaderMaterial
	if heading_material != null:
		$Design/Heading/HeadingText.material = heading_material.duplicate()
	resized.connect(_fit_design)
	_fit_design()
	if catalog != null:
		set_catalog(catalog)
	elif not _configured:
		var examples: Array[Dictionary] = []
		for index in 7:
			examples.append({"id": "demo_%02d" % (index + 1), "title": "示例关卡 %02d" % (index + 1)})
		set_levels(examples)
	else:
		_rebuild_cards()
	set_process(false)

func _update_heading(index: int, _level_id: String) -> void:
	if not _levels.is_empty():
		$Design/Heading/HeadingText.texture = _levels[index].get("heading_texture") as Texture2D

## 从可编辑的 .tres 配置资源生成卡片数据。
func set_catalog(value: Resource) -> void:
	catalog = value
	var levels: Array[Dictionary] = []
	if catalog != null:
		horizontal_radius = catalog.horizontal_radius
		for index in catalog.cards.size():
			var entry: Resource = catalog.cards[index]
			levels.append({"id": "card_%02d" % (index + 1), "title": entry.title, "image": entry.image, "background": entry.background, "background_scale": entry.background_scale, "background_effect_frames": entry.background_effect_frames, "background_effect_animation": entry.background_effect_animation, "background_effect_scale": entry.background_effect_scale, "heading_texture": entry.heading_texture, "description": entry.description})
			levels.back()["stage_id"] = entry.stage_id
	set_levels(levels)


## 替换展示数据并立即定位；条目包含 id/title。允许在加入场景树前调用。
## 初始索引循环归一化；替换数据会取消尚未完成的移动，不发送到位信号。
func set_levels(levels: Array[Dictionary], initial_index: int = 0) -> void:
	_levels = levels.duplicate(true)
	_configured = true
	_target = posmod(initial_index, _levels.size()) if not _levels.is_empty() else 0
	_progress = float(_target)
	_velocity = 0.0
	_moving = false
	_heading_pending = false
	set_process(false)
	if is_node_ready():
		_rebuild_cards()
		$Design/Heading/HeadingText.texture = current_level().get("heading_texture") as Texture2D
		_set_heading_transparency(1.0)


## 左右各推进一个卡片；连续输入累加目标，不重置当前进度与速度。
func step(direction: int) -> void:
	if _levels.size() < 2 or direction == 0:
		return
	_target += 1 if direction > 0 else -1
	_begin_heading_change()
	_moving = true
	set_process(true)

func focus_index(index: int) -> void:
	if _levels.size() < 2: return
	var current := posmod(_target, _levels.size())
	var delta := posmod(index - current, _levels.size())
	if delta > _levels.size() / 2: delta -= _levels.size()
	_target += delta
	if delta != 0:
		_begin_heading_change()
		_moving = true
		set_process(true)

func current_index() -> int:
	return posmod(_target, _levels.size()) if not _levels.is_empty() else -1

func current_level() -> Dictionary:
	var index := current_index()
	return _levels[index] if index >= 0 else {}

func select_current() -> void:
	var data := current_level()
	if data.is_empty(): return
	var stage_id := str(data.get("stage_id", ""))
	if stage_id.is_empty():
		print("卡片未配置 stage_id：", data.get("id", "")); return
	var stage := ContentCatalog.get_stage(stage_id)
	if stage == null:
		print("关卡不存在：", stage_id); return
	var card := _cards[current_index()]
	if not SaveService.is_stage_unlocked(stage):
		card.set_locked(true)
		print("关卡未解锁：", stage_id); return
	card.set_locked(false)
	stage_requested.emit(stage_id)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"): step(-1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"): step(1)
	elif event.is_action_pressed("ui_accept"): select_current()
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		_set_held_direction(_axis_direction(event.axis_value))
	elif event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		var direction := -1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
		_set_held_direction(direction if event.pressed else 0)

func _axis_direction(value: float) -> int:
	var engage := maxf(joystick_engage_threshold, joystick_release_threshold)
	var release := minf(joystick_engage_threshold, joystick_release_threshold)
	if _held_direction < 0:
		if value <= -engage: return -1
		if value > -release: return 0
		return -1
	if _held_direction > 0:
		if value >= engage: return 1
		if value < release: return 0
		return 1
	if value <= -engage: return -1
	if value >= engage: return 1
	return 0


func _process(delta: float) -> void:
	_advance_held_input(delta)
	_advance_heading(delta)
	if not _moving:
		set_process(_held_direction != 0 or _heading_pending or _heading_transparency < 1.0)
		return
	# 临界阻尼解析解：帧率无关，重新定向时保留速度，没有 Tween 重启跳变。
	var omega := 12.0 / response_time
	var displacement := _progress - float(_target)
	var coefficient := _velocity + omega * displacement
	var decay := exp(-omega * delta)
	_progress = float(_target) + (displacement + coefficient * delta) * decay
	_velocity = (_velocity - omega * coefficient * delta) * decay
	if absf(_progress - float(_target)) < 0.001 and absf(_velocity) < 0.02:
		_progress = float(_target)
		_velocity = 0.0
		_moving = false
		set_process(_held_direction != 0)
	_layout_cards()
	if not _moving:
		var index := posmod(_target, _levels.size())
		selection_changed.emit(index, str(_levels[index].id))
		set_process(true)

## 从材质当前值继续淡出，连续换页不会重置透明度或提前换图。
func _begin_heading_change() -> void:
	var material := $Design/Heading/HeadingText.material as ShaderMaterial
	if material != null:
		_heading_transparency = float(material.get_shader_parameter("transparency"))
	_heading_pending = true

## 先完全淡出，再等待卡片停稳后换图；指数缓动可平滑响应反向输入。
func _advance_heading(delta: float) -> void:
	if _heading_pending:
		var value := _heading_transparency * exp(-delta * 18.0)
		_set_heading_transparency(0.0 if value < 0.001 else value)
		if not _moving and _heading_transparency == 0.0:
			_update_heading(current_index(), "")
			_heading_pending = false
	else:
		var value := lerpf(_heading_transparency, 1.0, 1.0 - exp(-delta * 14.0))
		_set_heading_transparency(1.0 if value > 0.999 else value)

func _set_heading_transparency(value: float) -> void:
	_heading_transparency = clampf(value, 0.0, 1.0)
	var material := $Design/Heading/HeadingText.material as ShaderMaterial
	if material != null: material.set_shader_parameter("transparency", _heading_transparency)

func _set_held_direction(direction: int) -> void:
	if direction == _held_direction:
		return
	_held_direction = direction
	_held_time = 0.0
	_repeat_time = 0.0
	if direction != 0:
		step(direction)
	set_process(_moving or direction != 0 or _heading_pending or _heading_transparency < 1.0)

func _advance_held_input(delta: float) -> void:
	if _held_direction == 0:
		return
	_held_time += delta
	if _held_time < joystick_initial_delay:
		return
	_repeat_time += delta
	while _repeat_time >= joystick_repeat_interval:
		_repeat_time -= joystick_repeat_interval
		step(_held_direction)


func _rebuild_cards() -> void:
	for card in _cards:
		$Design/Cards.remove_child(card)
		card.queue_free()
	_cards.clear()
	for index in _levels.size():
		var card := CARD.instantiate() as Control
		$Design/Cards.add_child(card)
		card.configure(_levels[index], index)
		card.clicked.connect(func(): focus_index(index) if index != current_index() else select_current())
		_cards.append(card)
	$Design/Empty.visible = _levels.is_empty()
	$Design/Left.disabled = _levels.size() < 2
	$Design/Right.disabled = _levels.size() < 2
	_layout_cards()


func _layout_cards() -> void:
	for index in _cards.size():
		var angle := TAU * fposmod(float(index) - _progress, float(_cards.size())) / float(_cards.size())
		var depth := (cos(angle) + 1.0) * 0.5
		var card := _cards[index]
		card.size = card_size
		card.pivot_offset = card_size * 0.5
		card.position = DESIGN_SIZE * 0.5 + Vector2(sin(angle) * horizontal_radius, 0) - card_size * 0.5
		card.scale = Vector2.ONE * lerpf(minimum_scale, 1.0, depth)
		card.rotation = 0.0
		# 使用环上的卡位距离，排除同样投影到屏幕中线的正后方卡片。
		var distance := absf(wrapf(float(index) - _progress, -float(_cards.size()) * 0.5, float(_cards.size()) * 0.5))
		card.set_selection_weight(1.0 - smoothstep(0.0, 1.0, distance))
	# 只重排 Cards 的子节点，箭头始终位于所有卡片之上。
	var sorted := _cards.duplicate()
	sorted.sort_custom(func(a: Control, b: Control):
		return a.scale.x < b.scale.x if not is_equal_approx(a.scale.x, b.scale.x) else _cards.find(a) < _cards.find(b))
	for index in sorted.size():
		$Design/Cards.move_child(sorted[index], index)


func _fit_design() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	$Design.scale = Vector2.ONE * factor
	$Design.position = (size - DESIGN_SIZE * factor) * 0.5
