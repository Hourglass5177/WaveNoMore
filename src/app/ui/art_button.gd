extends Button
## 漆面按钮轻压、细光舒展；箭头只挪动美术子节点，布局位置保持固定。
@export var underline_enabled := true
@export var focus_art_shift := Vector2.ZERO
var _motion: Tween
var _down := false
var _art: Control
var _art_origin := Vector2.ZERO
func _ready() -> void:
	get_node("/root/MenuAudioService").bind_control(self)
	if underline_enabled:
		MenuInteraction.attach(self)
	else:
		add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	_art = get_node_or_null("Art") as Control
	if _art: _art_origin = _art.position
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	button_down.connect(func():
		_down = true
		_refresh())
	button_up.connect(func():
		_down = false
		_refresh())
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			if _motion: _motion.kill()
			_down = false
			scale = Vector2.ONE
			if _art: _art.position = _art_origin)
	resized.connect(func(): pivot_offset = size*0.5)
	pivot_offset = size*0.5
func _refresh() -> void:
	if _motion: _motion.kill()
	_motion = create_tween().set_parallel(true)
	_motion.tween_property(self,"scale",Vector2.ONE*(0.98 if _down and not disabled else 1.0),0.09).set_trans(Tween.TRANS_SINE)
	if _art:
		var active := not disabled and (has_focus() or is_hovered())
		_motion.tween_property(_art,"position",_art_origin+(focus_art_shift if active else Vector2.ZERO),0.16).set_trans(Tween.TRANS_SINE)
