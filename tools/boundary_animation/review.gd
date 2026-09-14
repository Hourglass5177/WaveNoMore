extends Node2D
## 独立素材审看与离线采样共用。时间可直接定位，不依赖 shader TIME。
var controller: ParallaxController
var seconds := 0.0
var bpm := 120.0
var playing := true
var seek_bar: HSlider
var time_label: Label

func _ready() -> void:
	controller = ParallaxController.new(); add_child(controller)
	controller.configure(load("res://content/backgrounds/s00_grave_background.tres"))
	# 背景冻结，只观察分界线；圆圈标出正式判定区域。
	queue_redraw()
	var ui := CanvasLayer.new(); add_child(ui)
	var row := HBoxContainer.new(); row.position=Vector2(32,28); row.add_theme_constant_override("separation",16); ui.add_child(row)
	var pause := Button.new(); pause.text="暂停"; row.add_child(pause)
	pause.pressed.connect(func(): playing=not playing; pause.text="暂停" if playing else "播放")
	seek_bar=HSlider.new(); seek_bar.min_value=0; seek_bar.max_value=8; seek_bar.step=.001; seek_bar.custom_minimum_size=Vector2(500,32); row.add_child(seek_bar)
	seek_bar.value_changed.connect(func(value): sample(value))
	var speed := SpinBox.new(); speed.min_value=30; speed.max_value=300; speed.value=120; speed.suffix="BPM"; row.add_child(speed)
	speed.value_changed.connect(func(value): bpm=value; configure_tempo(); sample(seconds))
	var toggle := CheckButton.new(); toggle.text="波浪动画"; toggle.button_pressed=true; row.add_child(toggle)
	toggle.toggled.connect(func(on): controller.boundary_motion.style.enabled=on; sample(seconds))
	var flow := OptionButton.new(); row.add_child(flow)
	for title in ["原纹与细水纹","仅原纹流动","基底静止"]: flow.add_item(title)
	flow.item_selected.connect(func(index):
		controller.boundary_motion.style.flow_enabled=index!=2
		controller.boundary_motion.style.streak_strength=BoundaryMotion.DEFAULT_STYLE.streak_strength if index==0 else 0.0
		sample(seconds))
	time_label=Label.new(); row.add_child(time_label)
	configure_tempo()
	sample(0)

func configure_tempo() -> void:
	var chart:=SongChart.new();var event:=TempoEvent.new();event.bpm=bpm
	chart.tempo_events=[event]
	controller.boundary_motion.tempo_map=TempoMap.from_chart(chart)

func sample(value: float) -> void:
	seconds=value
	for wave in controller._background_scenes: wave.sample_background(seconds)
	if seek_bar!=null: seek_bar.set_value_no_signal(seconds)
	if time_label!=null: time_label.text="%.2f s"%seconds

func _process(delta: float) -> void:
	if playing: sample(fposmod(seconds+delta,8.0))

func _draw() -> void:
	draw_arc(Vector2(960,540),56,0,TAU,128,Color("e5dfbd"),2,true)
