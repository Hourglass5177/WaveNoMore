extends ItemList
signal frame_moved(from: int, to: int)
func _get_drag_data(at: Vector2) -> Variant:
	var index:=get_item_at_position(at,true)
	if index<0:return null
	var label:=Label.new();label.text=get_item_text(index);set_drag_preview(label)
	return {"animation_frame":index,"owner":get_instance_id()}
func _can_drop_data(_at: Vector2,data: Variant) -> bool:
	return data is Dictionary and data.get("owner")==get_instance_id()
func _drop_data(at: Vector2,data: Variant) -> void:
	var index:=get_item_at_position(at,true)
	frame_moved.emit(int(data.animation_frame),item_count-1 if index<0 else index)
