extends StudioPreviewSession
## 优化前的逐输入完整发布路径，仅用于状态等价和耗时对照。
var publication_us := 0
func _publish_motion_frame(time_us: int) -> void:
	var start := Time.get_ticks_usec()
	stage_root.gameplay_coordinator.finish_preview_batch()
	stage_root.stage_session.publish_preview_state(time_us)
	stage_root.gameplay_coordinator.defer_preview_snapshot = true
	publication_us += Time.get_ticks_usec() - start
