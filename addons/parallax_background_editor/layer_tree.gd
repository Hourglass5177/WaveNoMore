@tool
extends Tree
## 树拖放只提交深度与同组前后位置，不把鼠标距离换算为深度。
signal reorder_requested(id: int, depth: int, target: int, in_front: bool)
var editing_enabled := true


func _get_drag_data(_position: Vector2) -> Variant:
	if not editing_enabled: return null
	var item := get_selected()
	if item == null: return null
	var metadata = item.get_metadata(0)
	if not metadata is Dictionary or not metadata.has("id"): return null
	var label := Label.new()
	label.text = "移动素材"
	set_drag_preview(label)
	return {"type": "background_entry", "id": metadata.id}


func _can_drop_data(position: Vector2, data: Variant) -> bool:
	if not editing_enabled or not data is Dictionary or data.get("type") != "background_entry": return false
	var item := get_item_at_position(position)
	if item == null: return false
	var metadata = item.get_metadata(0)
	drop_mode_flags = Tree.DROP_MODE_INBETWEEN if metadata is Dictionary and metadata.has("id") else Tree.DROP_MODE_ON_ITEM
	return metadata is Dictionary and metadata.has("depth")


func _drop_data(position: Vector2, data: Variant) -> void:
	var item := get_item_at_position(position)
	var metadata: Dictionary = item.get_metadata(0)
	reorder_requested.emit(data.id, metadata.depth, metadata.get("id", -1), get_drop_section_at_position(position) <= 0)
