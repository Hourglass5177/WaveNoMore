@tool
extends Tree
## 素材拖放提交目标子层和目标素材；顶层深度行不接收素材。
signal entry_reorder_requested(id: int, depth: int, target: int, in_front: bool, sublayer: int)
## 子层拖放只提交同深度内的子层前后排序。
signal sublayer_reorder_requested(id: int, target: int, in_front: bool)
var editing_enabled := true


func _get_drag_data(_position: Vector2) -> Variant:
	if not editing_enabled: return null
	var item := get_selected()
	if item == null: return null
	var metadata = item.get_metadata(0)
	if not metadata is Dictionary or (not metadata.has("id") and not metadata.has("sublayer")): return null
	var label := Label.new()
	var is_entry: bool = metadata.has("id")
	label.text = "移动素材" if is_entry else "移动子层"
	set_drag_preview(label)
	return {
		"type": "background_entry" if is_entry else "background_sublayer",
		"id": metadata.get("id", -1),
		"sublayer": metadata.get("sublayer", -1),
	}


func _can_drop_data(position: Vector2, data: Variant) -> bool:
	if not editing_enabled or not data is Dictionary: return false
	var item := get_item_at_position(position)
	if item == null: return false
	var metadata = item.get_metadata(0)
	if not metadata is Dictionary: return false
	if data.get("type") == "background_entry" and metadata.has("sublayer"):
		drop_mode_flags = Tree.DROP_MODE_INBETWEEN if metadata.has("id") else Tree.DROP_MODE_ON_ITEM
		return true
	if data.get("type") == "background_sublayer" and metadata.has("sublayer") and not metadata.has("id"):
		drop_mode_flags = Tree.DROP_MODE_INBETWEEN
		return data.sublayer != metadata.sublayer
	return false


func _drop_data(position: Vector2, data: Variant) -> void:
	var item := get_item_at_position(position)
	var metadata: Dictionary = item.get_metadata(0)
	_submit_drop(data, metadata, get_drop_section_at_position(position) <= 0)


## 将一次已通过校验的树拖放转换成明确的素材移动或子层排序事件。
func _submit_drop(data: Dictionary, target: Dictionary, in_front: bool) -> void:
	if data.get("type") == "background_entry":
		entry_reorder_requested.emit(data.id, target.depth, target.get("id", -1), in_front, target.sublayer)
	elif data.get("type") == "background_sublayer":
		sublayer_reorder_requested.emit(data.sublayer, target.sublayer, in_front)
