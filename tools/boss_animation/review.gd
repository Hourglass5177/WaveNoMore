extends Node2D
## BOSS 素材独立审看，不连接关卡判定或 BOSS 事件。
const VISUAL=preload("res://tools/boss_animation/boss_visual.gd")
const IDS=["bat","snake","goat","goat_eye"]
var actors: Array[Node2D]=[]
var time:=0.
var playing:=true
var selected:=0
var paired:=false
var display_mode:=0
var background: ParallaxController
var timeline: HSlider
var status: Label
var toolbar: CanvasLayer
var references:=false
var planning: Dictionary={}
var flash_rect: ColorRect
var choices: OptionButton
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("292530"))
	get_window().content_scale_size=Vector2i(1920,1080)
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	planning=PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	var flash_layer:=CanvasLayer.new();flash_layer.layer=8;add_child(flash_layer)
	flash_rect=ColorRect.new();flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);flash_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE;flash_rect.color=Color(1,1,1,0);flash_layer.add_child(flash_rect)
	toolbar=CanvasLayer.new();toolbar.layer=10;add_child(toolbar)
	var panel:=PanelContainer.new();panel.position=Vector2(24,24);toolbar.add_child(panel)
	var box:=VBoxContainer.new();panel.add_child(box)
	var row:=HBoxContainer.new();box.add_child(row)
	choices=OptionButton.new()
	for label in ["蝙蝠","蛇","羊头","羊头 · 眼球形态"]:choices.add_item(label)
	row.add_child(choices);choices.item_selected.connect(func(i):selected=i;rebuild())
	button(row,"播放 / 暂停",func():playing=not playing)
	button(row,"开始攻击",func():request("start"))
	button(row,"结束攻击",func():request("end"))
	button(row,"受击",func():request("hurt"))
	button(row,"转阶段",func():request("phase_break"))
	button(row,"死亡",func():request("death"))
	button(row,"完整演示",demonstrate_phases)
	button(row,"重置",rebuild)
	var row2:=HBoxContainer.new();box.add_child(row2)
	var modes:=OptionButton.new()
	for label in ["完整效果","骨骼","光效"]:modes.add_item(label)
	row2.add_child(modes);modes.item_selected.connect(func(i):display_mode=i;sample_at(time))
	button(row2,"正式背景",toggle_background)
	button(row2,"中心对称",func():paired=not paired;rebuild())
	button(row2,"判定参照",func():references=not references;queue_redraw())
	status=Label.new();row2.add_child(status)
	timeline=HSlider.new();timeline.min_value=0.;timeline.max_value=15.;timeline.step=.001;timeline.custom_minimum_size=Vector2(1050,34);box.add_child(timeline)
	timeline.value_changed.connect(func(value):playing=false;sample_at(value))
	rebuild()
func button(row: HBoxContainer,label: String,action: Callable) -> void:
	var node:=Button.new();node.text=label;row.add_child(node);node.pressed.connect(action)
func rebuild() -> void:
	for actor in actors:actor.free()
	actors.clear();time=0.
	for i in (2 if paired else 1):
		var actor=VISUAL.new();add_child(actor)
		for key in ["glow_strength","effect_scale","fragment_multiplier"]:actor.set(key,planning.get("values",{}).get("boss/"+key,1.))
		actor.position=Vector2(960,600) if not paired else (Vector2(600,360) if i==0 else Vector2(1320,720))
		actor.rotation=PI if i==1 else 0.
		actor.scale=Vector2.ONE*(.62 if paired else 1.)
		actor.setup(IDS[selected]);actors.append(actor)
	sample_at(0.)
func request(kind: String) -> void:
	for actor in actors:actor.request(kind,time)
	sample_at(time)
func demonstrate_phases() -> void:
	selected=2;choices.select(2);rebuild()
	for actor in actors:
		actor.events.assign([{"kind":"phase_break","time":.4},{"kind":"start","time":3.7},{"kind":"end","time":4.6},{"kind":"death","time":6.7}]);actor.dirty=true
	playing=true;sample_at(0.)
func _process(delta: float) -> void:
	if playing:sample_at(time+delta)
func sample_at(value: float) -> void:
	time=value
	var flash:=0.
	for actor in actors:
		actor.sample(time)
		flash=maxf(flash,actor.white_flash)
		var state=actor.skeleton.get_animation_state()
		# 眼部亮层和原画共用加权骨架，隐藏原画槽才能独立审看完整眼光。
		var visibility=state.get_track(3) if state.get_num_tracks()>3 else null
		if display_mode==2 or visibility!=null:
			if visibility==null:
				visibility=state.set_animation("body_visibility",false,3);visibility.set_mix_duration(0.);visibility.set_time_scale(0.)
			visibility.set_track_time(1. if display_mode==2 else 0.)
			actor.skeleton.update_skeleton(0.)
		if display_mode==1:
			actor.skeleton.show()
			actor.effects.hide();actor.body_material.set_shader_parameter("light",0.)
			if not actor.eyes.is_empty():actor.skeleton.get_animation_state().get_track(2).set_track_time(0.);actor.skeleton.update_skeleton(0.)
			if state.get_num_tracks()>5 and state.get_track(5)!=null:state.get_track(5).set_track_time(0.);actor.skeleton.update_skeleton(0.)
		else:actor.effects.show()
		if display_mode==2 and state.get_num_tracks()>4 and state.get_track(4)!=null:state.get_track(4).set_track_time(3.);actor.skeleton.update_skeleton(0.)
		if actor.goat_fracture!=null and actor.goat_fracture.pieces!=null:
			actor.goat_fracture.pieces.material.set_shader_parameter("body_visible",0. if display_mode==2 else 1.)
	if flash_rect!=null:flash_rect.color=Color(1,1,1,flash if display_mode!=1 else 0.)
	if background!=null:background.set_song_time(time)
	timeline.max_value=maxf(15.,time+1.);timeline.set_value_no_signal(time)
	status.text="  %.2f s" % time
func toggle_background() -> void:
	if background!=null:background.free();background=null
	else:
		background=ParallaxController.new();add_child(background)
		background.configure(load("res://content/backgrounds/s03_grave3_background.tres"))
		background.configure_boundary(null,0.,planning);background.set_song_time(time)
func _draw() -> void:
	if not references:return
    # 静态尺寸参照，只显示判断区和音符轮廓，不模拟玩法。
	draw_arc(Vector2(960,540),112,0,TAU,128,Color("e6dfc6"),3.,true)
	for i in 6:
		var p:=Vector2(740+i*90,510 if i%2==0 else 570)
		draw_circle(p,19,Color("b96371") if i%2==0 else Color("888cab"))
		draw_arc(p,22,0,TAU,32,Color("e6dfc6"),2.,true)
	draw_polyline(PackedVector2Array([Vector2(820,390),Vector2(900,420),Vector2(1080,405)]),Color("b96371"),20.,true)
	draw_polyline(PackedVector2Array([Vector2(1100,690),Vector2(1020,660),Vector2(840,675)]),Color("888cab"),20.,true)
