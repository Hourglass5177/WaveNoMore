extends SceneTree
## 本地五分钟实曲循环样本：检查后台解码、独立 EXE、取消与缓存。
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var w = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	w.offer_recovery_on_start = false; w.recovery_path = "user://chart_studio/tests/rhythm_measure/recovery.json"
	root.add_child(w); w._open_path("res://tests/editor/fixtures/training/song.json")
	for i in 12: await process_frame
	while w.preview.rebuilding: await process_frame
	var path := ProjectSettings.globalize_path("res://builds/rhythm-probe/five_minutes.wav")
	w.audio.set_stream(ChartJsonCodec.load_audio(path)); w.audio.set_playing(true)
	var results: Array = []
	w.rhythm.job.completed.connect(func(result: Dictionary) -> void: results.append(result))
	var start := Time.get_ticks_usec()
	w.rhythm.job.start(path, Vector2(0, 300), true)
	while w.rhythm.job._pid < 0 and w.rhythm.job.busy: await process_frame
	var cancel_started := Time.get_ticks_usec()
	w.rhythm.job.cancel()
	var cancel_ms := (Time.get_ticks_usec() - cancel_started) / 1000.0
	w.rhythm.job.start(path, Vector2(0, 300), true)
	var frames: Array[float] = []
	var previous := Time.get_ticks_usec()
	var rebuilds: int = w.preview.rebuild_count
	while results.is_empty() and Time.get_ticks_usec() - start < 240000000:
		await process_frame
		var now := Time.get_ticks_usec(); frames.append((now - previous) / 1000.0); previous = now
		if not w.rhythm.job.busy: break
	var total := (Time.get_ticks_usec() - start) / 1000000.0
	frames.sort()
	var measurement := {"success": not results.is_empty(), "elapsed_including_cancel_seconds": total, "cancel_ms": cancel_ms, "frame_median_ms": frames[frames.size() / 2], "frame_p95_ms": frames[floori(frames.size() * 0.95)], "preview_rebuilds": w.preview.rebuild_count - rebuilds, "audio_position": w.audio.position}
	if not results.is_empty():
		measurement.fit = results[0].fit; measurement.inference_seconds = results[0].elapsed_seconds
		var count := results.size(); w.rhythm.job.start(path, Vector2(0, 300))
		measurement.cache_reused = results.size() == count + 1 and not w.rhythm.job.busy
	StudioProjectIO.write_json("res://builds/rhythm-probe/integration-measurement.json", measurement)
	print(JSON.stringify(measurement))
	w.queue_free(); await process_frame
	quit(0 if measurement.success else 1)
