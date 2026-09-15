@tool
extends ProgressBar
## 共享细长血条。真实血量立即更新；赭红层只表示刚失去的血量。

@export_range(0.0, 0.3) var damage_hold_sec: float = 0.08
@export_range(0.05, 1.0) var damage_fade_sec: float = 0.38

var _ink: ShaderMaterial
var _feedback: Tween
var _initialized := false
var _trail_ratio := 1.0

func _ready() -> void:
	_ink = $Ink.material.duplicate() as ShaderMaterial
	$Ink.material = _ink
	resized.connect(_sync_size)
	value_changed.connect(_sync_fill)
	_sync_size()
	settle_feedback()

func _sync_size() -> void:
	_ink.set_shader_parameter("draw_size", size)

func _sync_fill(_value: float = 0.0) -> void:
	_ink.set_shader_parameter("health_ratio", ratio)

func set_health(current: float, maximum: float, immediate: bool = false) -> void:
	var next_max := maxf(maximum, 1.0)
	var next_value := clampf(current, 0.0, next_max)
	var snap := immediate or not _initialized or not is_equal_approx(max_value, next_max)
	if not snap and is_equal_approx(value, next_value):
		return
	var previous := ratio
	max_value = next_max
	value = next_value
	_initialized = true
	if snap or ratio >= previous:
		settle_feedback()
		return
	if _feedback != null:
		_feedback.kill()
	_set_trail(maxf(_trail_ratio, previous))
	_ink.set_shader_parameter("impact", 1.0)
	# 同时只保留一个过渡，连续 Hold 扣血不会叠加多个 Tween。
	_feedback = create_tween().set_parallel(true)
	_feedback.tween_method(_set_trail, _trail_ratio, ratio, damage_fade_sec).set_delay(damage_hold_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_feedback.tween_method(_set_impact, 1.0, 0.0, 0.22)

func settle_feedback() -> void:
	if _feedback != null:
		_feedback.kill()
	_set_trail(ratio)
	_set_impact(0.0)
	_sync_fill()

func _set_trail(amount: float) -> void:
	_trail_ratio = amount
	_ink.set_shader_parameter("trail_ratio", amount)

func _set_impact(amount: float) -> void:
	_ink.set_shader_parameter("impact", amount)
