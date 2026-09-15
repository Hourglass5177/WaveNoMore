extends Control
## 正式 UI 不依赖本审看场景；所有控件只控制表现时间。
const FIRE=preload("res://src/presentation/ui/flame_frame_visual.gd")
var fires:Array=[]
var clock:=0.
var playing:=true
var design:Control
var bar:HSlider
var old:TextureRect
var show_background:=true
var mode:=0
var background:ColorRect
var toolbar:HBoxContainer
var planning:Dictionary

func _ready() -> void:
	planning=PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background=ColorRect.new();background.color=Color("191b29");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	design=Control.new();add_child(design)
	var layer:=CanvasLayer.new();layer.layer=10;add_child(layer)
	toolbar=HBoxContainer.new();toolbar.position=Vector2(24,16);layer.add_child(toolbar)
	for title in ["暂停","重置","背景","横框","旧版对照"]:
		var b:=Button.new();b.text=title;toolbar.add_child(b);b.pressed.connect(command.bind(title,b))
	bar=HSlider.new();bar.custom_minimum_size=Vector2(360,28);bar.max_value=30.;bar.step=.001;toolbar.add_child(bar);bar.value_changed.connect(sample)
	resized.connect(fit);rebuild();fit()

func fit() -> void:design.scale=Vector2.ONE*minf(size.x/1920.,size.y/1080.);design.position=(size-Vector2(1920,1080)*design.scale)*.5

func label_at(text:String,p:Vector2,font_size:int=24) -> void:
	var l:=Label.new();l.text=text;l.position=p;l.add_theme_font_size_override("font_size",font_size);design.add_child(l)

func fire_at(p:Vector2,extent:Vector2,color:int,seed:int) -> Control:
	var f=FIRE.new();f.position=p;f.size=extent;f.palette=color;f.random_seed=seed;f.automatic=false;f.apply_planning(planning);design.add_child(f);fires.append(f);return f

func rebuild() -> void:
	for child in design.get_children():child.free()
	fires.clear();old=null
	if mode==1:
		for i in 2:
			# 底图右侧带有透明留白，先配准实际外缘，再与火根共用同一个矩形。
			var source:Texture2D=load("res://assets/ui/art/设置页面/底图.png")
			var cropped:=AtlasTexture.new();cropped.atlas=source;cropped.region=source.get_image().get_used_rect()
			var panel:=TextureRect.new();panel.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;panel.texture=cropped;panel.position=Vector2(440,180+i*440);panel.size=Vector2(1040,330);design.add_child(panel)
			fire_at(panel.position,panel.size,i,i*19+4)
			label_at("声音设置\n\n音乐音量                         85%\n\n保存并返回",panel.position+Vector2(280,45),27)
	else:
		for i in 2:
			var p:=Vector2(420+i*720,235);var extent:=Vector2(360,650)
			var panel:=TextureRect.new();panel.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;panel.texture=load("res://assets/image/ui/选关/框/框选中.png");panel.position=p;panel.size=extent;panel.stretch_mode=TextureRect.STRETCH_SCALE;design.add_child(panel)
			fire_at(p,extent,i,i*19+4)
			label_at((["原八帧","新燃烧"] if mode==2 else ["红焰","蓝焰"])[i],p+Vector2(120,-120),30)
			label_at("冥河，冥河！\n\n\n\n\n\n      000000\n\n  〔沿河而行〕",p+Vector2(92,115),24)
		if mode==2:
			fires[0].hide();old=TextureRect.new();old.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			var rect: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/flame_frame/source_registration.json")).old_root_rect
			var factor:=Vector2(360./(rect[2]-rect[0]),650./(rect[3]-rect[1]))
			old.position=Vector2(420,235)-Vector2(rect[0],rect[1])*factor;old.size=Vector2(384,512)*factor;design.add_child(old)
	sample(clock)

func command(title:String,button:Button) -> void:
	match title:
		"暂停":playing=not playing;button.text="暂停" if playing else "播放"
		"重置":sample(0.)
		"背景":show_background=not show_background;background.color=Color("191b29") if show_background else Color("5b5260")
		"横框":mode=0 if mode==1 else 1;rebuild()
		"旧版对照":mode=0 if mode==2 else 2;rebuild()

func sample(seconds:float) -> void:
	clock=seconds
	for f in fires:f.sample(seconds)
	if old!=null:old.texture=load("res://assets/image/ui/选关/火框燃烧_8帧_透明PNG/火框燃烧_%02d.png"%(int(seconds*12.)%8+1))
	if bar!=null:bar.set_value_no_signal(fmod(seconds,30.))

func _process(delta:float) -> void:
	if playing:sample(clock+delta)
