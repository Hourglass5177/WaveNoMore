# 优化前的完整恢复，仅作为结果对照，不进入工具运行路径。
extends Node
## 预览直接驱动正式 StageRoot。回拖从初态无声重演，每批让出一帧，最新请求可取消旧重建。
signal status_changed(message: String)
signal rebuilt
signal state_changed(state: Dictionary)
signal ghost_results_changed(results: Dictionary)
signal loading_changed(active: bool)
var ghost_results := {}
var stage_root: StageRoot
var rebuilding := false
var _inputs: Array[SemanticInputSample] = []
var _cursor := 0
var _time_us: int = -1000000000
var _motion_tick: int = -120
var _motion_ranges: Array[Dictionary] = []
var _motion_range_cursor: int = 0
var _request := 0
var offset_sec := 0.0
var sound_enabled := true
var rebuild_count := 0
var load_count := 0
var _frozen_viewport: SubViewport
var _render_mode_before := SubViewport.UPDATE_ALWAYS
var suspended := false

func set_suspended(value: bool) -> void:
	if suspended == value: return
	suspended = value
	if not is_instance_valid(stage_root): return
	# 后台试玩保留整场状态与最后画面，切回时无需重新装谱或重演。
	stage_root.process_mode = Node.PROCESS_MODE_DISABLED if suspended else Node.PROCESS_MODE_INHERIT
	if suspended: _freeze_frame()
	elif not rebuilding: _release_frame()

func _freeze_frame() -> void:
	# 历史重演仍更新正式表现状态，但不能把中途的调频/Hold 画面提交到屏幕。
	if is_instance_valid(_frozen_viewport): return
	_frozen_viewport = stage_root.get_viewport() as SubViewport
	_render_mode_before = _frozen_viewport.render_target_update_mode
	_frozen_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _release_frame(force := false) -> void:
	# 重演与后台休眠共用纹理冻结，任一尚未结束都不能重新开启持续渲染。
	if suspended and not force: return
	if is_instance_valid(_frozen_viewport): _frozen_viewport.render_target_update_mode = _render_mode_before
	_frozen_viewport = null

func clear_preview() -> void:
	_request += 1
	rebuilding = false
	loading_changed.emit(false)
	_release_frame(true)
	if is_instance_valid(stage_root):
		stage_root.get_parent().remove_child(stage_root)
		stage_root.queue_free()
	stage_root = null
	ghost_results.clear(); ghost_results_changed.emit(ghost_results)

func load_preview(stage: StageDefinition, viewport: SubViewport) -> bool:
	load_count += 1
	clear_preview()
	loading_changed.emit(true)
	stage_root = load("res://scenes/stage/stage_root.tscn").instantiate() as StageRoot
	stage_root.auto_start_initial_stage = false
	stage_root.initial_stage = null
	viewport.add_child(stage_root)
	stage_root.stage_session.external_preview = true
	stage_root.stage_session.pause_on_focus_loss = false
	stage_root.stage_session.set_process(false)
	stage_root.song_clock.set_process(false)
	stage_root.presentation.set_preview_time_driven()
	stage_root.audio_feedback.preview_strikes_muted = true
	stage_root.pause_overlay.hide()
	stage_root.debug_hud.hide()
	stage_root.gameplay_coordinator.snapshot_changed.connect(_collect_ghost_results)
	if not stage_root.load_stage(stage, false):
		loading_changed.emit(false)
		status_changed.emit("内容不可预览：请检查谱面")
		return false
	var physical_input := get_tree().root.get_node("InputEventBuffer")
	physical_input.set_mode(physical_input.InputMode.DISABLED)
	physical_input.set_process_input(false)
	offset_sec = stage.song.first_beat_offset_sec
	# 只从真实 Tap/Hold 生成敲钟输入，Tuning 追加频率姿态采样。
	_inputs = StudioPreviewInputs.build(stage_root.stage_session.compiled_chart, stage_root.stage_session.rule_set)
	_build_motion_ranges(stage_root.stage_session.compiled_chart)
	_cursor = 0
	_time_us = -1000000000
	_motion_tick = -120
	_motion_range_cursor = 0
	if suspended:
		stage_root.process_mode = Node.PROCESS_MODE_DISABLED
		_freeze_frame()
	status_changed.emit("自动演示")
	return true

func _collect_ghost_results(snapshot: Dictionary) -> void:
	var results: Array = snapshot.get("su_manifestations", [])
	# 复用正式发布的快照，不为属性标签额外拷贝整场历史。
	if results.size() == ghost_results.size(): return
	ghost_results.clear()
	for result in results:
		ghost_results[result.event_id] = {"actual": result.get("points", []).size(), "requested": result.get("requested_count", 0), "generation_issue": str(result.get("generation_issue", ""))}
	ghost_results_changed.emit(ghost_results)

func seek_preview(audio_us: int) -> void:
	if not is_instance_valid(stage_root): return
	rebuild_count += 1
	var tree := get_tree()
	_request += 1
	var request := _request
	var target := audio_us - roundi(offset_sec * 1000000.0)
	rebuilding = true
	loading_changed.emit(true)
	_freeze_frame()
	status_changed.emit("定位中")
	while suspended:
		await tree.process_frame
		if request != _request or not is_inside_tree(): return
	stage_root.audio_feedback.preview_muted = true
	stage_root.gameplay_coordinator.defer_preview_snapshot = false
	stage_root.stage_session.reset_preview()
	stage_root.gameplay_coordinator.defer_preview_snapshot = true
	stage_root.stage_show_director.call("reset")
	_cursor = 0
	_time_us = mini(-1000000, target)
	if not _inputs.is_empty(): _time_us = mini(_time_us, _inputs[0].timestamp_us - 1)
	_motion_tick = floori(float(_time_us) * 120.0 / 1000000.0) + 1
	_motion_range_cursor = 0
	stage_root.song_clock.publish_external_time(float(_time_us) / 1000000.0)
	# 8ms 批次限制的是场景树恢复工作，不改变模拟的精确事件时间。
	var batch_start := Time.get_ticks_usec()
	while true:
		# 已在进行的跨帧定位也让出 CPU；恢复后从原输入游标继续，仍可被新请求取消。
		while suspended:
			await tree.process_frame
			if request != _request or not is_inside_tree(): return
			batch_start = Time.get_ticks_usec()
		if _time_us >= target: break
		var next := mini(target, _inputs[_cursor].timestamp_us) if _cursor < _inputs.size() else target
		if _motion_range_cursor < _motion_ranges.size():
			var span: Dictionary = _motion_ranges[_motion_range_cursor]
			if int(span.begin) < next and int(span.end) > _time_us:
				# 长 Hold 没有输入事件时也定期让帧，定位可取消；空段仍直接跳过。
				next = mini(next, maxi(_time_us + 100000, int(span.begin)))
		_step_to(next)
		if Time.get_ticks_usec() - batch_start > 8000:
			await tree.process_frame
			if request != _request or not is_inside_tree(): return
			batch_start = Time.get_ticks_usec()
	_step_to(target)
	stage_root.gameplay_coordinator.finish_preview_batch()
	stage_root.stage_session.publish_preview_state(target)
	stage_root.stage_show_director.call("seek", float(target) / 1000000.0)
	rebuilding = false
	_release_frame()
	loading_changed.emit(false)
	status_changed.emit("自动演示 · 已定位")
	rebuilt.emit()
	state_changed.emit(get_preview_state())

func update_preview(stage: StageDefinition, viewport: SubViewport, audio_us: int) -> void:
	if load_preview(stage, viewport): await seek_preview(audio_us)

func set_transport(audio_us: int, playing: bool) -> void:
	advance(float(audio_us) / 1000000.0, playing)

func get_preview_state() -> Dictionary:
	return {"rebuilding": rebuilding, "time_us": _time_us, "input_cursor": _cursor, "snapshot": stage_root.gameplay_coordinator.snapshot() if is_instance_valid(stage_root) else {}}

func advance(audio_sec: float, playing: bool) -> void:
	if not is_instance_valid(stage_root) or rebuilding or suspended: return
	stage_root.audio_feedback.preview_muted = not playing or not sound_enabled
	var target := roundi((audio_sec - offset_sec) * 1000000.0)
	# 真正的定位和循环由 Transport 明确通知；普通采样的抖动不能触发重演。
	if target > _time_us:
		_step_to(target)

func apply_palette(theme: StageVisualTheme) -> void:
	if is_instance_valid(stage_root): stage_root.presentation.update_preview_palette(theme)

func _exit_tree() -> void:
	_request += 1
	_release_frame(true)

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
		# 输入后的同刻没有身体积分；下一采样直接读取新控制状态。
		# 角色的播放速度仍在这个精确边界切换，不能推迟到下一画面帧。
		var sim := coordinator.simulation
		stage_root.presentation._note_visual_host.sync_preview_controls(sim.motion_snapshot(), float(at) / 1000000.0)
		stage_root.presentation._update_actor_snapshot({"time_us":at, "life_held":sim.life_held,
			"death_held":sim.death_held, "life_frequency_hz":sim.tuning_engine.life_frequency_hz(),
			"death_frequency_hz":sim.tuning_engine.death_frequency_hz()})
	_advance_motion_to(target)
	session.advance_preview(target, true)
	if already_batched: _publish_motion_frame(target)
	if not already_batched:
		coordinator.finish_preview_batch()
		session.publish_preview_state(target)
	coordinator.defer_preview_snapshot = already_batched
	_time_us = target

func _publish_motion_frame(time_us: int) -> void:
	# 连续播放和历史恢复使用同一运动采样；HUD、背景和相纹仅在帧尾发布。
	var sample := ClockSample.new()
	sample.song_time_sec = float(time_us) / 1000000.0
	sample.judge_time_sec = sample.song_time_sec
	sample.visual_time_sec = sample.song_time_sec
	stage_root.presentation.restore_preview_motion(stage_root.gameplay_coordinator.simulation.motion_snapshot(), sample)

func _advance_motion_to(target: int) -> void:
	var at := roundi(float(_motion_tick) * 1000000.0 / 120.0)
	while at < target:
		# 没有 Hold 的整段时间直接跳过，保留原有长谱定位速度。
		while _motion_range_cursor < _motion_ranges.size() and at > _motion_ranges[_motion_range_cursor].end:
			_motion_range_cursor += 1
		if _motion_range_cursor == _motion_ranges.size(): return
		if at < _motion_ranges[_motion_range_cursor].begin:
			_motion_tick = ceili(float(_motion_ranges[_motion_range_cursor].begin) * 120.0 / 1000000.0)
			at = roundi(float(_motion_tick) * 1000000.0 / 120.0)
			if at >= target: return
		stage_root.stage_session.advance_preview(at, true)
		_publish_motion_frame(at)
		_motion_tick += 1
		at = roundi(float(_motion_tick) * 1000000.0 / 120.0)

func _build_motion_ranges(chart: CompiledChart) -> void:
	_motion_ranges.clear()
	for note: Dictionary in chart.notes:
		if StringName(note.get("unit_kind", &"tap")) != &"hold": continue
		var begin: int = stage_root.stage_session.chart_scheduler._spawn_time_usec(ChartScheduler.KIND_NOTE, note)
		_motion_ranges.append({"begin": begin, "end": int(note.end_us) + 1000000})
	_motion_ranges.sort_custom(func(a: Dictionary, b: Dictionary): return a.begin < b.begin)
	var merged: Array[Dictionary] = []
	for span: Dictionary in _motion_ranges:
		if not merged.is_empty() and span.begin <= merged[-1].end:
			merged[-1].end = maxi(merged[-1].end, span.end)
		else: merged.append(span)
	_motion_ranges = merged

