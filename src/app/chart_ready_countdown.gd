class_name ChartReadyCountdown
extends CanvasLayer
## 准备阶段不运行游戏时钟；随关卡卸载即取消，不留下等待中的协程。
signal finished
var remaining := 3.0
var _label: Label
var _started_us := 0

func _ready() -> void:
	_started_us = Time.get_ticks_usec()
	layer = 60
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MingheUiStyle.style_title(_label, 64)
	shade.add_child(_label)
	_label.text = "准备\n3"

func _process(_delta: float) -> void:
	remaining = 3.0 - float(Time.get_ticks_usec() - _started_us) / 1000000.0
	_label.text = "准备\n%d" % maxi(1, ceili(remaining))
	if remaining <= 0:
		set_process(false)
		finished.emit()
		queue_free()
