extends Control
## 每次启动播放一次，完成后由标题页接续等待输入。
signal finished
enum Stage { MEMO, HEADPHONES, CONTROLLER, LEAVING }
var stage := Stage.MEMO
var guide: Control
@export var fade_in_sec := 0.6
@export var hold_sec := 1.2
@export var fade_out_sec := 0.6
@export var headphones_hold_sec := 2.4

func _ready() -> void:
	var report := PlanningParameters.read()
	for key: String in ["fade_in_sec","hold_sec","fade_out_sec","headphones_hold_sec"]:
		var id := "ui_guides/"+key
		if report.values.has(id): set(key,report.values[id])
	var animation := create_tween()
	animation.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property($Art, "modulate:a", 1.0, fade_in_sec)
	animation.tween_interval(hold_sec)
	animation.tween_property($Art, "modulate:a", 0.0, fade_out_sec)
	animation.tween_callback(_headphones)

func _headphones() -> void:
	stage = Stage.HEADPHONES
	guide = preload("res://src/app/ui/instruction_guide.gd").new()
	guide.modulate.a = 0.0
	add_child(guide)
	var animation := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property(guide,"modulate:a",1.0,fade_in_sec)
	animation.tween_interval(headphones_hold_sec)
	animation.tween_property(guide,"modulate:a",0.0,fade_out_sec)
	animation.tween_callback(_controller)

func _controller() -> void:
	guide.queue_free()
	stage = Stage.CONTROLLER
	guide = preload("res://src/app/ui/instruction_guide.gd").new()
	guide.page = guide.Page.CONTROLLER
	guide.navigation_text = "继续"
	guide.modulate.a = 0.0
	guide.dismissed.connect(_leave)
	add_child(guide)
	var animation := create_tween()
	animation.tween_property(guide,"modulate:a",1.0,fade_in_sec).set_trans(Tween.TRANS_SINE)
	# 按键图由玩家读完后确认，避免固定时长来不及阅读。
	animation.tween_callback(guide.activate)

func _leave() -> void:
	stage = Stage.LEAVING
	var animation := create_tween().set_trans(Tween.TRANS_SINE)
	animation.tween_property(guide,"modulate:a",0.0,fade_out_sec)
	# 停在纯黑画面交给标题页溶解，避免先透出主界面又重新盖黑。
	animation.tween_callback(finished.emit)

func _input(_event: InputEvent) -> void:
	# 开屏期间的确认及松键不能穿透到标题页。
	get_viewport().set_input_as_handled()
