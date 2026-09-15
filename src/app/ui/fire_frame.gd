extends "res://src/presentation/ui/flame_frame_visual.gd"
## 正式弹窗复用燃烧组件，火根与底图可见边缘配准，原面板布局保持不变。
@export var panel_path: NodePath = ^"../Panel"
var _panel: TextureRect
var _visible_region: Rect2

func _ready() -> void:
	super._ready()
	apply_planning(PlanningParameters.read())
	_panel = get_node(panel_path)
	_visible_region = _panel.texture.get_image().get_used_rect()
	_panel.item_rect_changed.connect(_fit_panel)
	_fit_panel()

func _fit_panel() -> void:
	# 现有弹窗底图使用 SCALE；留白随底图一起缩放，不能计入燃烧根部宽度。
	var ratio := _panel.size / _panel.texture.get_size()
	position = _panel.position + _visible_region.position * ratio
	size = _visible_region.size * ratio
