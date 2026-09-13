extends Control
## 独立审看入口，展示资源与时间切换，不写装备、存档或正式随从配置。
const ACTOR := preload("res://src/tools/pet_animation/pet_study_actor.gd")
var actors: Array[Node2D] = []
var clock := 0.0
var playing := true
var play_button: Button
var timeline: HSlider
var time_label: Label
var stage: Control
var background: ColorRect
var size_choice: OptionButton

func _ready() -> void:
	background = ColorRect.new()
	background.color = Color("aca69f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "随从动画"
	title.add_theme_font_size_override("font_size",28)
	column.add_child(title)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation",12)
	column.add_child(bar)
	play_button = _button(bar,"暂停",func(): playing = not playing; _update_play_button())
	_button(bar,"技能",func(): for actor in actors: actor.trigger(clock))
	_button(bar,"死亡",func(): for actor in actors: actor.die(clock))
	_button(bar,"重置",reset)
	size_choice = OptionButton.new()
	for label: String in ["80 px", "120 px", "放大查看"]: size_choice.add_item(label)
	size_choice.select(2)
	size_choice.item_selected.connect(func(_index): _layout_actors())
	bar.add_child(size_choice)
	var colors := OptionButton.new()
	colors.add_item("浅色背景"); colors.add_item("深色背景")
	colors.item_selected.connect(func(index): background.color = Color("aca69f") if index==0 else Color("282633"))
	bar.add_child(colors)
	stage = Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stage)
	for row in 2:
		for id: String in ["bat", "snake", "sheep"]:
			var actor = ACTOR.new()
			stage.add_child(actor)
			actor.setup(id)
			actor.rotation = PI if row==1 else 0.0
			actors.append(actor)
			if row==0:
				var name_label := Label.new()
				name_label.name = id+"_label"
				name_label.text = str(actor.config.name)
				name_label.add_theme_font_size_override("font_size",22)
				stage.add_child(name_label)
	stage.resized.connect(_layout_actors)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	timeline = HSlider.new()
	timeline.min_value=0; timeline.max_value=12; timeline.step=.001
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.value_changed.connect(func(value): clock=value; playing=false; _update_play_button(); _sample())
	footer.add_child(timeline)
	time_label=Label.new()
	time_label.custom_minimum_size.x=90
	footer.add_child(time_label)
	_layout_actors.call_deferred()
	_sample()

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button:=Button.new()
	button.text=caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _layout_actors() -> void:
	if stage==null: return
	var factor: float = [1.0,1.5,2.5][size_choice.selected]
	for i in actors.size():
		var column := i%3 if i<3 else 2-i%3
		actors[i].position = Vector2(stage.size.x*(float(column)+.5)/3,stage.size.y*(.28 if i<3 else .72))
		actors[i].scale = Vector2.ONE*factor
		if i<3:
			var label:=stage.get_node(str(actors[i].config.id)+"_label") as Label
			label.position=Vector2(stage.size.x*(float(i)+.5)/3-label.size.x*.5,0)

func _process(delta: float) -> void:
	if playing:
		clock += delta
		if clock>=timeline.max_value: timeline.max_value += 12.0
	_sample()

func _sample() -> void:
	for actor in actors: actor.sample(clock)
	if timeline!=null: timeline.set_value_no_signal(clock)
	if time_label!=null: time_label.text="%.2f s" % clock

func reset() -> void:
	clock=0.0
	for actor in actors: actor.clear_events()
	_sample()

func _update_play_button() -> void:
	play_button.text="暂停" if playing else "播放"

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_SPACE:
		playing=not playing
		_update_play_button()
