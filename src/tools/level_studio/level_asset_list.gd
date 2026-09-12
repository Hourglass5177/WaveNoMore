class_name LevelAssetList
extends ItemList
## 拖拽只传稳定素材引用，实际对象由工作区创建。
func _get_drag_data(at: Vector2) -> Variant:
	var index := get_item_at_position(at, true)
	if index < 0: return null
	var label := Label.new(); label.text = get_item_text(index); set_drag_preview(label)
	return {"level_asset": get_item_metadata(index)}
