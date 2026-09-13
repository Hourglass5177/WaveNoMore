extends TuningEngine
## 回归参照：使用优化前的全谱候选集，其他判定逻辑共用。
func _visible_slider_indices(_time: int) -> Array[int]:
	_preview_active.clear()
	for index in _slider_states.size(): _preview_active.append(index)
	return _preview_active
