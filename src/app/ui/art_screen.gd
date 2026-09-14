@tool
extends Control
## 固定设计画布等比适配；编辑器也能直接看到最终布局。
var _fade: Tween
var closing := false

func _ready() -> void:
	resized.connect(_fit)
	_fit()
	if not Engine.is_editor_hint():
		modulate.a = 0.0
		fade_in()
func _fit() -> void:
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	$Design.scale = Vector2.ONE * factor
	$Design.position = (size - Vector2(1920,1080)*factor)*0.5

## 关闭期间继续遮挡底层输入，淡出完成后由宿主释放页面并恢复焦点。
func fade_in() -> void:
	closing = false
	if _fade: _fade.kill()
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)

func fade_out() -> void:
	closing = true
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	set_process_unhandled_input(false)
	if _fade: _fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	await _fade.finished

func _input(_event: InputEvent) -> void:
	if closing:
		get_viewport().set_input_as_handled()
