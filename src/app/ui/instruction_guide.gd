extends Control
## 开屏与设置共用同一份排版；原画只包含图样，文字使用正式汇文字体。
signal dismissed

enum Page { HEADPHONES, CONTROLLER }
var page := Page.HEADPHONES
var navigation_text := ""
var allow_cancel := false
var interactive := false
var _design := Control.new()
var _button: Button
const FONT = preload("res://assets/fonts/huiwen.otf")
const HEADPHONES = preload("res://assets/ui/art/boot/guides/headphones.png")
const CONTROLLER = preload("res://assets/ui/art/boot/guides/controller.png")
const INK := Color("e4ddcf")
const SECONDARY := Color("aaa396")
const LINE := Color("8e877c")
const ART := Rect2(555, 255, 810, 540)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.size = Vector2(1920,1080)
	add_child(_design)
	if not navigation_text.is_empty():
		_button = Button.new()
		_button.name = "Continue"
		_button.text = navigation_text
		_button.position = Vector2(1650,951)
		_button.size = Vector2(150,58)
		_button.add_theme_font_override("font",FONT)
		_button.add_theme_font_size_override("font_size",30)
		_button.add_theme_color_override("font_color",INK)
		_button.flat = true
		_button.disabled = true
		_design.add_child(_button)
		_button.pressed.connect(_dismiss)
		MenuInteraction.attach(_button)
		# 导航键帽沿用当前控制器家族，示意图明确以 Xbox 布局为准。
		var glyph := preload("res://src/app/ui/shortcut_glyph.gd").new()
		glyph.action = &"ui_cancel" if allow_cancel else &"ui_accept"
		glyph.position = Vector2(-42,13)
		glyph.size = Vector2(32,32)
		_button.add_child(glyph)
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	var factor := minf(size.x/1920.0,size.y/1080.0)
	_design.scale = Vector2.ONE*factor
	_design.position = (size-Vector2(1920,1080)*factor)*0.5
	queue_redraw()

func activate() -> void:
	interactive = true
	if _button:
		_button.disabled = false
		_button.grab_focus()

func _dismiss() -> void:
	if not interactive: return
	interactive = false
	dismissed.emit()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	get_node("/root/UiInputHints").observe(event)
	if interactive and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_point: Vector2 = _button.get_global_transform_with_canvas().affine_inverse()*event.position
		if Rect2(Vector2.ZERO,_button.size).has_point(local_point):
			get_viewport().set_input_as_handled()
			_dismiss()
			return
	if interactive and (event.is_action_pressed("ui_accept") or (allow_cancel and event.is_action_pressed("ui_cancel"))):
		get_viewport().set_input_as_handled()
		_dismiss()
		return
	# 屏蔽方向与肩键，设置草稿和底层焦点在审看期间保持原状。鼠标交给唯一按钮。
	if not event is InputEventMouse:
		get_viewport().set_input_as_handled()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color.BLACK)
	draw_set_transform(_design.position,0.0,_design.scale)
	if page == Page.HEADPHONES:
		draw_texture_rect(HEADPHONES,Rect2(660,170,600,600),false)
		_center("请您佩戴耳机以获得最佳游戏体验",825,40)
	else:
		_draw_controller()

func _center(text: String, baseline: float, font_size: int, color := INK) -> void:
	var width := FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(FONT,Vector2((1920-width)*0.5,baseline),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _source(point: Vector2) -> Vector2:
	return ART.position + point*(ART.size.x/1536.0)

func _caption(text: String, point: Vector2, font_size := 28, color := INK) -> void:
	draw_string(FONT,point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _callout(source: Vector2, bends: Array[Vector2], text: String, caption: Vector2, detail := "") -> void:
	var points := PackedVector2Array([_source(source)])
	points.append_array(PackedVector2Array(bends))
	draw_polyline(points,LINE,1.2,true)
	draw_circle(points[0],2.5,INK,true,-1,true)
	_caption(text,caption)
	if not detail.is_empty(): _caption(detail,caption+Vector2(0,50),21,SECONDARY)

func _draw_controller() -> void:
	_center("操作说明",112,44)
	_center("Xbox 布局",154,22,SECONDARY)
	draw_texture_rect(CONTROLLER,ART,false)
	# 引线从实际图样的按键中心出发；上下错层绕开彼此及摇杆轮廓。
	_callout(Vector2(380,124),[Vector2(650,330),Vector2(180,330)],"LB　敲击死钟",Vector2(180,310),"按住持续发波 · 菜单切换")
	_callout(Vector2(395,333),[Vector2(650,455),Vector2(180,455)],"左摇杆　死侧调频",Vector2(180,435),"按下敲击死钟 · 菜单导航")
	_callout(Vector2(570,559),[Vector2(715,610),Vector2(180,610)],"方向键　菜单导航",Vector2(180,590))
	_callout(Vector2(1160,124),[Vector2(1280,330),Vector2(1740,330)],"RB　敲击生钟",Vector2(1430,310),"按住持续发波 · 菜单切换")
	_callout(Vector2(1150,253),[Vector2(1320,405),Vector2(1740,405)],"Y　随从（选关）",Vector2(1430,387))
	_callout(Vector2(1238,347),[Vector2(1320,476),Vector2(1740,476)],"B　返回",Vector2(1430,458))
	_callout(Vector2(1061,347),[Vector2(1230,492),Vector2(1320,547),Vector2(1740,547)],"X　设置（选关）",Vector2(1430,529))
	_callout(Vector2(1150,435),[Vector2(1230,566),Vector2(1320,618),Vector2(1740,618)],"A　确认",Vector2(1430,600))
	_callout(Vector2(965,550),[Vector2(1090,670),Vector2(1370,735),Vector2(1740,735)],"右摇杆　生侧调频",Vector2(1430,715),"按下敲击生钟")
	_callout(Vector2(907,334),[Vector2(1033,817),Vector2(1300,817)],"菜单键　暂停",Vector2(1110,854))
	# 面键字母由字体绘制，避免生成图中文字失真；连接点移到字母之外。
	for entry in [["Y",Vector2(1150,253)],["X",Vector2(1061,347)],["B",Vector2(1238,347)],["A",Vector2(1150,435)]]:
		var point := _source(entry[1])
		draw_circle(point,10,Color.BLACK)
		_caption(entry[0],point+Vector2(-7,9),25)
	_center("本游戏仅支持使用控制器游玩",985,34)
