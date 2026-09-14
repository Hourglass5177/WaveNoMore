extends Node
## 仅正式游戏启用；工具界面与内嵌预览沿用自己的字体。
const FONT = preload("res://assets/fonts/huiwen.otf")
func _ready() -> void:
	if StudioLaunch.is_active(): return
	get_tree().node_added.connect(_apply)
	_apply_tree(get_tree().root)
func _apply_tree(node: Node) -> void:
	_apply(node)
	for child in node.get_children(): _apply_tree(child)
func _apply(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit or node is PopupMenu:
		node.add_theme_font_override("font",FONT)
	elif node is RichTextLabel:
		node.add_theme_font_override("normal_font",FONT)
