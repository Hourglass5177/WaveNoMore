extends Control
## 每次启动播放一次，完成后由标题页接续等待输入。
signal finished
@export var fade_in_sec := 0.6
@export var hold_sec := 1.2
@export var fade_out_sec := 0.6

func _ready() -> void:
	var animation := create_tween()
	animation.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property($Art, "modulate:a", 1.0, fade_in_sec)
	animation.tween_interval(hold_sec)
	animation.tween_property($Art, "modulate:a", 0.0, fade_out_sec)
	animation.tween_property(self, "modulate:a", 0.0, 0.3)
	animation.tween_callback(finished.emit)

func _input(_event: InputEvent) -> void:
	# 开屏期间的确认及松键不能穿透到标题页。
	get_viewport().set_input_as_handled()
