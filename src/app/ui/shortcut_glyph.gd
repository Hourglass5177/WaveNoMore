@tool
extends Control
## 矢量键帽只作提示，不遮挡按钮、不取得焦点。设备切换时刷新一次。
@export var action: StringName = &"ui_accept"
var _texture: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if Engine.is_editor_hint(): return
	var hints := get_node("/root/UiInputHints")
	hints.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	_texture = get_node("/root/UiInputHints").texture_for(action)
	queue_redraw()

func _draw() -> void:
	if _texture == null: return
	var extent := _texture.get_size()
	var factor := minf(size.x / extent.x, size.y / extent.y)
	var target := extent * factor
	draw_texture_rect(_texture, Rect2((size - target) * 0.5, target), false)
