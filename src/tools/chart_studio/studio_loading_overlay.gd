extends ColorRect
## 快速定位不闪蒙版；连续替换定位请求沿用等待起点，避免一直滑动时提示消失。
const SHOW_DELAY_US := 200000
var loading := false
var _started_us := 0

func _ready() -> void:
	hide()
	set_process(false)

func set_loading(active: bool) -> void:
	if loading == active: return
	loading = active
	if active:
		_started_us = Time.get_ticks_usec()
		set_process(true)
	else:
		hide()
		set_process(false)

func _process(_delta: float) -> void:
	visible = Time.get_ticks_usec() - _started_us >= SHOW_DELAY_US
	if visible: queue_redraw()

func _draw() -> void:
	# 转动提示只表达仍在工作，不把重演时长伪装成可预测的百分比。
	var phase := float(Time.get_ticks_usec() - _started_us) / 1000000.0 * TAU
	draw_arc(size * 0.5 - Vector2(0,28), 13, phase, phase + TAU * 0.72, 32, Color.WHITE, 3, true)
