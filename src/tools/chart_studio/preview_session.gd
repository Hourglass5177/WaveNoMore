class_name StudioPreviewSession
extends Node
## 预览直接驱动正式 StageRoot。回拖从初态无声重演，每批让出一帧，最新请求可取消旧重建。
signal status_changed(message: String)
signal rebuilt
signal state_changed(state: Dictionary)
var stage_root: StageRoot
var rebuilding := false
var _inputs: Array[SemanticInputSample] = []
var _cursor := 0
var _time_us: int = -1000000000
var _request := 0
var offset_sec := 0.0
var sound_enabled := true
var rebuild_count := 0
var load_count := 0

func clear_preview() -> void:
	_request += 1
	rebuilding = false
	if is_instance_valid(stage_root):
		stage_root.get_parent().remove_child(stage_root)
		stage_root.queue_free()
	stage_root = null

func load_preview(stage: StageDefinition, viewport: SubViewport) -> bool:
	load_count += 1
	clear_preview()
	stage_root = load("res://scenes/stage/stage_root.tscn").instantiate() as StageRoot
	stage_root.auto_start_initial_stage = false
	stage_root.initial_stage = null
	viewport.add_child(stage_root)
	stage_root.stage_session.external_preview = true
	stage_root.stage_session.pause_on_focus_loss = false
	stage_root.stage_session.set_process(false)
	stage_root.song_clock.set_process(false)
	stage_root.presentation.set_preview_time_driven()
	stage_root.pause_overlay.hide()
	stage_root.debug_hud.hide()
	if not stage_root.load_stage(stage, false):
		status_changed.emit("内容不可预览：请检查谱面")
		return false
	var physical_input := get_tree().root.get_node("InputEventBuffer")
	physical_input.set_mode(physical_input.InputMode.DISABLED)
	physical_input.set_process_input(false)
	offset_sec = stage.song.first_beat_offset_sec
	# 复用正式理想输入发生器；JSON 首版编译结果只有 Tap/Hold。
	_inputs = ReplayRunner.build_perfect_replay(stage_root.stage_session.compiled_chart, stage.rule_set).sorted_inputs()
	_cursor = 0
	_time_us = -1000000000
	status_changed.emit("自动演示")
	return true

func seek_preview(audio_us: int) -> void:
	if not is_instance_valid(stage_root): return
	rebuild_count += 1
	var tree := get_tree()
	_request += 1
	var request := _request
	var target := audio_us - roundi(offset_sec * 1000000.0)
	rebuilding = true
	status_changed.emit("定位中")
	stage_root.audio_feedback.preview_muted = true
	stage_root.gameplay_coordinator.defer_preview_snapshot = false
	stage_root.stage_session.reset_preview()
	stage_root.gameplay_coordinator.defer_preview_snapshot = true
	stage_root.stage_show_director.call("reset")
	_cursor = 0
	_time_us = mini(-1000000, target)
	if not _inputs.is_empty(): _time_us = mini(_time_us, _inputs[0].timestamp_us - 1)
	stage_root.song_clock.publish_external_time(float(_time_us) / 1000000.0)
	# 8ms 批次限制的是场景树恢复工作，不改变模拟的精确事件时间。
	var batch_start := Time.get_ticks_usec()
	while _cursor < _inputs.size() and _inputs[_cursor].timestamp_us <= target:
		_step_to(_inputs[_cursor].timestamp_us)
		if Time.get_ticks_usec() - batch_start > 8000:
			await tree.process_frame
			if request != _request or not is_inside_tree(): return
			batch_start = Time.get_ticks_usec()
	_step_to(target)
	stage_root.gameplay_coordinator.finish_preview_batch()
	stage_root.stage_session.publish_preview_state(target)
	stage_root.stage_show_director.call("seek", float(target) / 1000000.0)
	rebuilding = false
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
	if not is_instance_valid(stage_root) or rebuilding: return
	stage_root.audio_feedback.preview_muted = not playing or not sound_enabled
	var target := roundi((audio_sec - offset_sec) * 1000000.0)
	# 真正的定位和循环由 Transport 明确通知；普通采样的抖动不能触发重演。
	if target > _time_us:
		_step_to(target)

func apply_palette(theme: StageVisualTheme) -> void:
	if is_instance_valid(stage_root): stage_root.presentation.update_preview_palette(theme)

func _exit_tree() -> void:
	_request += 1

func _step_to(target: int) -> void:
	var session := stage_root.stage_session
	var coordinator := stage_root.gameplay_coordinator
	var already_batched := coordinator.defer_preview_snapshot
	coordinator.defer_preview_snapshot = true
	while _cursor < _inputs.size() and _inputs[_cursor].timestamp_us <= target:
		var at := _inputs[_cursor].timestamp_us
		session.advance_preview(at, false)
		var batch: Array[SemanticInputSample] = []
		while _cursor < _inputs.size() and _inputs[_cursor].timestamp_us == at:
			batch.append(_inputs[_cursor])
			_cursor += 1
		session.inject_preview_inputs(batch)
		session.advance_preview(at, true)
	session.advance_preview(target, true)
	if not already_batched:
		coordinator.finish_preview_batch()
		session.publish_preview_state(target)
	_time_us = target
