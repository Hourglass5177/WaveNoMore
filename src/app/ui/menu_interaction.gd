class_name MenuInteraction
extends Control
## 事件驱动的骨白细光；只画局部反馈，不接管输入，不持续刷新。
## 主菜单把鼠标选择同步为焦点，避免同时画出两条选中线。
@export var focus_only := false
@export var underline_offset := -2.0
@export var underline_width := 1.4
@export var underline_strength := 0.70
var _control: Control
var _focus_motion: Tween
var _pulse_motion: Tween
var amount := 0.0:
	set(value):
		amount = value
		queue_redraw()
var pulse := 0.0:
	set(value):
		pulse = value
		queue_redraw()

static func attach(control: Control) -> MenuInteraction:
	var feedback := MenuInteraction.new()
	feedback.name = "Interaction"
	control.add_child(feedback)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return feedback

func _ready() -> void:
	_control = get_parent() as Control
	get_node("/root/MenuAudioService").bind_control(_control)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_control.mouse_entered.connect(refresh)
	_control.mouse_exited.connect(refresh)
	_control.focus_entered.connect(refresh)
	_control.focus_exited.connect(refresh)
	_control.visibility_changed.connect(_visibility_changed)
	if _control is BaseButton:
		_control.pressed.connect(acknowledge)
		_control.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	elif _control is HSlider:
		_control.value_changed.connect(func(_value: float):
			queue_redraw()
			if _control.has_focus() or _control.get_global_rect().has_point(_control.get_global_mouse_position()): acknowledge())
	elif _control is LineEdit:
		_control.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_control.text_submitted.connect(func(_text: String): acknowledge())

func refresh() -> void:
	var active := _control.has_focus() or (not focus_only and _control.get_global_rect().has_point(_control.get_global_mouse_position()))
	if _control is BaseButton and _control.disabled: active = false
	if _focus_motion: _focus_motion.kill()
	_focus_motion = create_tween()
	_focus_motion.tween_property(self,"amount",1.0 if active else 0.0,0.16).set_trans(Tween.TRANS_SINE)

func acknowledge() -> void:
	if _pulse_motion: _pulse_motion.kill()
	_pulse_motion = create_tween()
	_pulse_motion.tween_property(self,"pulse",1.0,0.045)
	_pulse_motion.tween_property(self,"pulse",0.0,0.24).set_trans(Tween.TRANS_SINE)

func _visibility_changed() -> void:
	if not is_visible_in_tree():
		if _focus_motion: _focus_motion.kill()
		if _pulse_motion: _pulse_motion.kill()
		amount = 0.0
		pulse = 0.0
	else:
		refresh()

func _draw() -> void:
	if amount + pulse < 0.001: return
	if _control is BaseButton and _control.disabled: return
	var bone := Color("e6ddc9")
	if _control is HSlider:
		# 光集中在当前滑块，既不改变滑轨长度，也不影响数值映射。
		var ratio: float = _control.ratio
		var knob := _control.get_theme_icon("grabber").get_width() * 0.5
		var center := Vector2(lerpf(knob,size.x-knob,ratio),size.y*0.5)
		for i in range(5,0,-1):
			draw_circle(center,5.0+i*2.2,Color(bone,0.025*amount+0.015*pulse),true,-1.0,true)
		return
	# 细光由中心舒展，暖色软边贴着按钮下沿；不扫过文字和美术字图。
	var half_width := size.x*0.42*(0.35+0.65*amount)
	var left := Vector2(size.x*0.5-half_width,size.y+underline_offset)
	var right := Vector2(size.x*0.5+half_width,size.y+underline_offset)
	for i in range(4,0,-1):
		draw_line(left,right,Color(0.78,0.46,0.47,(amount+0.5*pulse)*0.025),1.0+i*2.0,true)
	draw_line(left,right,Color(bone,underline_strength*amount+0.25*pulse),underline_width,true)
