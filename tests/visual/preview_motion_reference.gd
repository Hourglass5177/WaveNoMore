extends "res://src/tools/chart_studio/preview_session.gd"
## 合并零时间表现通知前的恢复路径。
func _step_to(target: int) -> void:
	var session := stage_root.stage_session
	var coordinator := stage_root.gameplay_coordinator
	var already_batched := coordinator.defer_preview_snapshot
	coordinator.defer_preview_snapshot = true
	while _cursor < _inputs.size() and _inputs[_cursor].timestamp_us <= target:
		var at := _inputs[_cursor].timestamp_us
		_advance_motion_to(at)
		session.advance_preview(at, false)
		# 新 Hold 在头判时记录实际姿态；先抵达输入时刻，再改变按住状态。
		_publish_motion_frame(at)
		var batch: Array[SemanticInputSample] = []
		while _cursor < _inputs.size() and _inputs[_cursor].timestamp_us == at:
			batch.append(_inputs[_cursor])
			_cursor += 1
		session.inject_preview_inputs(batch)
		session.advance_preview(at, true)
		_publish_motion_frame(at)
	_advance_motion_to(target)
	session.advance_preview(target, true)
	if already_batched: _publish_motion_frame(target)
	if not already_batched:
		coordinator.finish_preview_batch()
		session.publish_preview_state(target)
	coordinator.defer_preview_snapshot = already_batched
	_time_us = target
