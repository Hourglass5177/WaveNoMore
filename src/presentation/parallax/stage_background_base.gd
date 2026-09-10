## 将原灰盒底色与划痕绘制到背景画布，角色/分界/钟击反馈仍在玩法画布。
extends Node2D

@export var backdrop_path: NodePath
var _backdrop: GrayboxBackdrop


func _ready() -> void:
	_backdrop = get_node(backdrop_path) as GrayboxBackdrop
	_backdrop.draw.connect(queue_redraw)


func _draw() -> void:
	if is_instance_valid(_backdrop):
		_backdrop.draw_background(self)
