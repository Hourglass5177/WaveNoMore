extends Tree
## 树只表达放置目标，变换保持和历史由工作区处理。
signal rearrange_requested(ids: PackedStringArray, target: String, placement: int)

func _get_drag_data(at: Vector2) -> Variant:
	var item:=get_item_at_position(at)
	if item==null or item.get_metadata(0)==null:return null
	var ids:=PackedStringArray();var selected_item:=get_next_selected(null)
	while selected_item!=null:
		ids.append(str(selected_item.get_metadata(0)));selected_item=get_next_selected(selected_item)
	if str(item.get_metadata(0)) not in ids:ids=PackedStringArray([str(item.get_metadata(0))])
	var label:=Label.new();label.text="移动 %d 个对象"%ids.size();set_drag_preview(label)
	return {"level_objects":ids}

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	drop_mode_flags=Tree.DROP_MODE_ON_ITEM|Tree.DROP_MODE_INBETWEEN
	return data is Dictionary and data.has("level_objects")

func _drop_data(at: Vector2, data: Variant) -> void:
	var item:=get_item_at_position(at)
	rearrange_requested.emit(data.level_objects,str(item.get_metadata(0)) if item!=null else "",get_drop_section_at_position(at) if item!=null else 1)
