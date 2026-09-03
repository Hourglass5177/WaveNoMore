extends SceneTree

## 写谱器的命令行回归测试。
## 覆盖文档、撤销、保存事务、崩溃恢复、波形和正式关卡预览。

## 预览桥探针：模拟 StageRoot 需要的最小接口，只记录桥传入的关卡和 seek tick。
class PreviewProbe:
	extends Node
	## 桥接器写入的临时关卡快照；探针只保存引用，不启动关卡。
	var initial_stage: StageDefinition
	## 模拟正式 StageRoot 的同名开关；桥接器会将它改为 false，避免载入后自行播放。
	var auto_start_initial_stage: bool = true
	## 最近一次收到的预览跳转 tick；-1 表示 `seek_to_tick()` 尚未调用。
	var received_seek_tick: int = -1

	func seek_tick(tick: int) -> bool:
		received_seek_tick = tick
		return true


## 故障注入替身：只让 Journal 写入失败，用来验证正式资源不会被覆盖。
class JournalFailingSaveService:
	extends MingheChartEditorSaveService

	# 人为制造事务日志（Journal）写入失败，确认工具会报告错误而不是损坏正式文件。
	func _write_journal(_value: Dictionary) -> Error:
		return ERR_CANT_CREATE


## 故障注入替身：只让历史备份失败，用来验证事务会在替换前停止。
class BackupFailingSaveService:
	extends MingheChartEditorSaveService

	# 人为制造备份失败，确认事务不会继续覆盖原文件。
	func _create_backup(_document: MingheChartEditorDocument, _chart_target: String, _show_target: String) -> Dictionary:
		return {"ok": false, "message": "备份写入失败（测试注入）"}


## 本文件累计的失败断言数，最终直接作为进程退出码。
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# 先验证内存编辑，再验证磁盘事务和运行时预览。
	_test_document_and_history()
	_test_complete_empty_document()
	_test_complete_mechanism_document()
	_test_shared_validation()
	_test_atomic_save_and_reload()
	_test_new_stage_package_and_lazy_open()
	_test_interrupted_save_recovery()
	_test_persistence_failures_are_reported()
	_test_pcm16_waveform()
	await _test_preview_snapshot()
	await _test_workspace_scene()
	if _failures == 0:
		print("[chart_editor_tests] PASS")
	else:
		push_error("[chart_editor_tests] FAIL: %d assertion(s)" % _failures)
	quit(_failures)


func _test_document_and_history() -> void:
	var document := MingheChartEditorDocument.new()
	document.create_empty()
	var history := MingheChartEditorHistory.new()
	var before := document.snapshot()
	var note := NoteEvent.new()
	note.event_id = document.next_id("note")
	note.damage_group_id = note.event_id
	note.tick = 480
	document.add_event(MingheChartEditorDocument.TRACK_NOTES, note)
	var after := document.snapshot()
	history.push("add", before, after)
	_expect(document.get_track_array(MingheChartEditorDocument.TRACK_NOTES).size() == 1, "note add")
	_expect(history.undo(document), "undo returns true")
	_expect(document.get_track_array(MingheChartEditorDocument.TRACK_NOTES).is_empty(), "undo restores document")
	_expect(history.redo(document), "redo returns true")
	_expect(document.get_track_array(MingheChartEditorDocument.TRACK_NOTES).size() == 1, "redo restores document")


func _test_complete_empty_document() -> void:
	var document := MingheChartEditorDocument.new()
	document.create_empty()
	_expect(document.stage_definition != null, "new document has StageDefinition")
	_expect(document.song_definition != null, "new document has SongDefinition")
	_expect(document.chart != null and document.stage_show != null, "new document has chart and show")
	_expect(document.visual_theme != null, "new document has StageVisualTheme")
	_expect(document.reward_definition != null, "new document has RewardDefinition")
	_expect(document.rule_set != null, "new document has GameplayRuleSet")
	_expect((document.stage_definition as StageDefinition).dependencies_resolved(), "new document binds complete stage composition")


func _test_shared_validation() -> void:
	var document := MingheChartEditorDocument.new()
	document.create_empty()
	var adapter := MingheChartValidationAdapter.new()
	var issues: Array[Dictionary] = adapter.validate(document)
	for issue in issues:
		_expect(String(issue.get("severity", "")) != "error", "new template validates: %s" % issue.get("message", ""))


func _test_complete_mechanism_document() -> void:
	var document := MingheChartEditorDocument.new()
	document.create_empty()
	var chord_id := "chord_test"
	for affinity in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		var tap := NoteEvent.new()
		tap.event_id = "tap_%d" % affinity
		tap.group_id = chord_id
		tap.damage_group_id = chord_id
		tap.tick = 480
		tap.affinity = affinity
		document.add_event(MingheChartEditorDocument.TRACK_NOTES, tap)
	var hold := NoteEvent.new()
	hold.event_id = "hold_zhu"
	hold.damage_group_id = hold.event_id
	hold.tick = 960
	hold.duration_ticks = 480
	hold.kind = GameplayTypes.NoteKind.HOLD
	hold.affinity = GameplayTypes.Affinity.ZHU
	document.add_event(MingheChartEditorDocument.TRACK_NOTES, hold)
	var field := TuningFieldRegion.new()
	field.event_id = "field_test"
	field.tick = 1920
	field.duration_ticks = 1440
	document.add_event(MingheChartEditorDocument.TRACK_TUNING_FIELDS, field)
	var tuning_group_id := "tuning_pair_test"
	for affinity in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		var slider := TuningSliderEvent.new()
		slider.event_id = "slider_%d" % affinity
		slider.field_id = field.event_id
		slider.group_id = tuning_group_id
		slider.affinity = affinity
		slider.tick = 1920
		slider.traversal_ticks = 480
		slider.traversal_count = 1
		slider.start_value = 0.5
		slider.end_value = 0.9
		document.add_event(MingheChartEditorDocument.TRACK_TUNING_SLIDERS, slider)
	var su := SuManifestationEvent.new()
	su.event_id = "su_test"
	su.group_id = tuning_group_id
	su.tick = 2400
	su.count = 2
	su.spawn_region_normalized = Rect2(0.2, 0.2, 0.6, 0.6)
	document.add_event(MingheChartEditorDocument.TRACK_SU_MANIFESTATIONS, su)
	var rapid := RapidRegion.new()
	rapid.event_id = "rapid_test"
	rapid.damage_group_id = rapid.event_id
	rapid.tick = 3360
	rapid.duration_ticks = 480
	document.add_event(MingheChartEditorDocument.TRACK_RAPID, rapid)
	var cue := ShowCue.new()
	cue.event_id = "cue_test"
	cue.tick = 3840
	cue.cue_id = &"actor_reveal"
	document.add_event(MingheChartEditorDocument.TRACK_SHOW, cue)
	var adapter := MingheChartValidationAdapter.new()
	var issues: Array[Dictionary] = adapter.validate(document)
	for issue in issues:
		_expect(String(issue.get("severity", "")) != "error", "all-mechanism document: %s" % issue.get("message", ""))


func _test_atomic_save_and_reload() -> void:
	var document := MingheChartEditorDocument.new()
	document.create_empty()
	var service := MingheChartEditorSaveService.new()
	var token := str(Time.get_ticks_usec())
	var base := "user://minghe_chart_editor/tests/%s" % token
	_configure_test_service(service, base)
	var result := service.save_document(document, base + "/song_chart.tres", base + "/stage_show.tres")
	_expect(bool(result.get("ok", false)), "atomic save")
	var chart := ResourceLoader.load(base + "/song_chart.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var show := ResourceLoader.load(base + "/stage_show.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(chart != null and show != null, "saved resources reload")
	document.chart.set("chart_id", "second_save")
	document.notify_mutated("test_second_save")
	var second := service.save_document(document, base + "/song_chart.tres", base + "/stage_show.tres")
	_expect(bool(second.get("ok", false)), "atomic replace existing pair")
	var replaced := ResourceLoader.load(base + "/song_chart.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(replaced != null and String(replaced.get("chart_id")) == "second_save", "replacement content reloads")
	var autosave := service.autosave(document)
	_expect(bool(autosave.get("ok", false)), "autosave recovery pair")
	var recovery := service.load_recovery("second_save")
	_expect(bool(recovery.get("ok", false)), "recovery pair reloads")


func _test_new_stage_package_and_lazy_open() -> void:
	var token := str(Time.get_ticks_usec())
	var base := "user://minghe_chart_editor/tests/package_%s" % token
	var package_directory := base + "/s_test"
	var service := MingheChartEditorSaveService.new()
	_configure_test_service(service, base)
	var document := MingheChartEditorDocument.new()
	document.create_empty()
	var result := service.save_new_stage_package(document, package_directory)
	_expect(bool(result.get("ok", false)), "new document commits complete stage package: %s" % result.get("message", ""))
	for file_name: String in [
		"song_definition.tres",
		"song_chart.tres",
		"stage_show.tres",
		"reward_definition.tres",
		"stage_visual_theme.tres",
		"stage_definition.tres",
	]:
		_expect(FileAccess.file_exists(package_directory + "/" + file_name), "stage package contains %s" % file_name)
	var marker := ResourceLoader.load(package_directory + "/stage_definition.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as StageDefinition
	_expect(marker != null, "stage commit marker reloads")
	if marker == null:
		return
	_expect(marker.chart == null and not marker.chart_resource_path.is_empty(), "stage marker uses lazy chart path")
	_expect(marker.song == null and marker.stage_show == null, "stage marker stays lightweight")
	var reopened := MingheChartEditorDocument.new()
	_expect(reopened.open_stage(marker, package_directory + "/stage_definition.tres"), "editor resolves lightweight StageDefinition")
	_expect(reopened.chart != null and reopened.stage_show != null, "lazy chart/show become working copies")
	_expect(reopened.song_definition != null and reopened.visual_theme != null, "lazy song/theme resolve")
	_expect(reopened.reward_definition != null and reopened.rule_set != null, "lazy reward/rules resolve")
	_expect(reopened.chart_path == package_directory + "/song_chart.tres", "resolved document preserves chart target path")


func _test_interrupted_save_recovery() -> void:
	# 分别模拟首次保存、覆盖旧文件、提交后清理时崩溃，确保不会留下半套谱面。
	_test_first_save_chart_replaced_crash()
	_test_existing_pair_chart_replaced_crash()
	_test_committed_cleanup_crash()


func _test_first_save_chart_replaced_crash() -> void:
	var base := "user://minghe_chart_editor/tests/crash_first_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var service := MingheChartEditorSaveService.new()
	_configure_test_service(service, base)
	var chart_target := base + "/song_chart.tres"
	var show_target := base + "/stage_show.tres"
	var chart_temp := base + "/chart.tmp.tres"
	var show_temp := base + "/show.tmp.tres"
	var new_chart := SongChart.new()
	new_chart.chart_id = "new_partial"
	ResourceSaver.save(new_chart, chart_target)
	ResourceSaver.save(StageShow.new(), show_temp)
	var journal := _make_crash_journal(chart_target, show_target, chart_temp, show_temp, false, false, "chart_replaced")
	_expect(service._write_json(service.journal_path, journal) == OK, "write first-save crash journal")
	var recovered := service.recover_interrupted_save()
	_expect(bool(recovered.get("ok", false)), "recover first-save chart-replaced crash")
	_expect(not FileAccess.file_exists(chart_target), "first-save partial chart is removed")
	_expect(not FileAccess.file_exists(show_temp), "first-save temporary show is removed")
	_expect(not FileAccess.file_exists(service.journal_path), "first-save journal is cleared")


func _test_existing_pair_chart_replaced_crash() -> void:
	var base := "user://minghe_chart_editor/tests/crash_existing_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var service := MingheChartEditorSaveService.new()
	_configure_test_service(service, base)
	var chart_target := base + "/song_chart.tres"
	var show_target := base + "/stage_show.tres"
	var chart_old := base + "/chart.old.tres"
	var show_old := base + "/show.old.tres"
	var chart_temp := base + "/chart.tmp.tres"
	var show_temp := base + "/show.tmp.tres"
	var old_chart := SongChart.new()
	old_chart.chart_id = "old_chart"
	var old_show := StageShow.new()
	old_show.show_id = "old_show"
	var new_chart := SongChart.new()
	new_chart.chart_id = "new_chart"
	ResourceSaver.save(old_chart, chart_old)
	ResourceSaver.save(old_show, show_old)
	ResourceSaver.save(new_chart, chart_target)
	ResourceSaver.save(StageShow.new(), show_temp)
	var journal := _make_crash_journal(chart_target, show_target, chart_temp, show_temp, true, true, "chart_replaced")
	journal.chart_old = chart_old
	journal.show_old = show_old
	_expect(service._write_json(service.journal_path, journal) == OK, "write existing-pair crash journal")
	var recovered := service.recover_interrupted_save()
	_expect(bool(recovered.get("ok", false)), "recover existing chart-replaced crash")
	var restored_chart := ResourceLoader.load(chart_target, "", ResourceLoader.CACHE_MODE_IGNORE) as SongChart
	var restored_show := ResourceLoader.load(show_target, "", ResourceLoader.CACHE_MODE_IGNORE) as StageShow
	_expect(restored_chart != null and restored_chart.chart_id == "old_chart", "existing SongChart is rolled back")
	_expect(restored_show != null and restored_show.show_id == "old_show", "existing StageShow is rolled back")


func _test_committed_cleanup_crash() -> void:
	var base := "user://minghe_chart_editor/tests/crash_committed_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var service := MingheChartEditorSaveService.new()
	_configure_test_service(service, base)
	var chart_target := base + "/song_chart.tres"
	var show_target := base + "/stage_show.tres"
	var chart_old := base + "/chart.old.tres"
	var show_old := base + "/show.old.tres"
	var committed_chart := SongChart.new()
	committed_chart.chart_id = "committed_chart"
	ResourceSaver.save(committed_chart, chart_target)
	ResourceSaver.save(StageShow.new(), show_target)
	ResourceSaver.save(SongChart.new(), chart_old)
	ResourceSaver.save(StageShow.new(), show_old)
	var journal := _make_crash_journal(chart_target, show_target, "", "", true, true, "committed")
	journal.chart_old = chart_old
	journal.show_old = show_old
	_expect(service._write_json(service.journal_path, journal) == OK, "write committed crash journal")
	var recovered := service.recover_interrupted_save()
	_expect(bool(recovered.get("ok", false)), "recover committed cleanup crash")
	var kept_chart := ResourceLoader.load(chart_target, "", ResourceLoader.CACHE_MODE_IGNORE) as SongChart
	_expect(kept_chart != null and kept_chart.chart_id == "committed_chart", "committed target remains authoritative")
	_expect(not FileAccess.file_exists(chart_old) and not FileAccess.file_exists(show_old), "committed old pair is cleaned")


func _test_persistence_failures_are_reported() -> void:
	var base := "user://minghe_chart_editor/tests/failures_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var document := MingheChartEditorDocument.new()
	document.create_empty()
	var journal_service := JournalFailingSaveService.new()
	_configure_test_service(journal_service, base + "/journal_case")
	var journal_result := journal_service.save_document(document, base + "/journal_case/song_chart.tres", base + "/journal_case/stage_show.tres")
	_expect(not bool(journal_result.get("ok", true)), "journal write failure is reported")
	_expect(String(journal_result.get("message", "")).contains("Journal"), "journal failure message is explicit")

	var backup_service := BackupFailingSaveService.new()
	_configure_test_service(backup_service, base + "/backup_case")
	var backup_result := backup_service.save_document(document, base + "/backup_case/song_chart.tres", base + "/backup_case/stage_show.tres")
	_expect(not bool(backup_result.get("ok", true)), "backup write failure is reported")
	_expect(String(backup_result.get("message", "")).contains("备份"), "backup failure message is explicit")


func _test_pcm16_waveform() -> void:
	var token := str(Time.get_ticks_usec())
	var directory := "user://minghe_chart_editor/tests/%s" % token
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var wav_path := directory + "/fixture.wav"
	_write_test_wav(wav_path)
	var result := MinghePcm16WaveformBuilder.load_or_build(wav_path)
	var cache: MingheWaveformCache = result.get("cache") as MingheWaveformCache
	_expect(cache != null, "PCM16 waveform builds: %s" % result.get("error", ""))
	if cache != null:
		_expect(cache.sample_rate == 8000, "waveform sample rate")
		_expect(cache.channels == 1, "waveform channels")
		_expect(cache.frame_count == 800, "waveform frame count")
		_expect(not cache.levels.is_empty(), "waveform levels")


func _test_preview_snapshot() -> void:
	# 预览使用裁剪后的深拷贝；无论怎样跳转，都不能改坏编辑器中的原稿。
	var document := MingheChartEditorDocument.new()
	document.create_empty()
	var old_tap := NoteEvent.new()
	old_tap.event_id = "old_tap"
	old_tap.tick = 480
	document.add_event(MingheChartEditorDocument.TRACK_NOTES, old_tap)
	var spanning_hold := NoteEvent.new()
	spanning_hold.event_id = "spanning_hold"
	spanning_hold.tick = 720
	spanning_hold.duration_ticks = 600
	spanning_hold.kind = GameplayTypes.NoteKind.HOLD
	document.add_event(MingheChartEditorDocument.TRACK_NOTES, spanning_hold)
	var future_tap := NoteEvent.new()
	future_tap.event_id = "future_tap"
	future_tap.tick = 1440
	document.add_event(MingheChartEditorDocument.TRACK_NOTES, future_tap)
	var old_cue := ShowCue.new()
	old_cue.event_id = "old_cue"
	old_cue.tick = 600
	document.add_event(MingheChartEditorDocument.TRACK_SHOW, old_cue)
	var future_cue := ShowCue.new()
	future_cue.event_id = "future_cue"
	future_cue.tick = 1200
	document.add_event(MingheChartEditorDocument.TRACK_SHOW, future_cue)
	var future_field := TuningFieldRegion.new()
	future_field.event_id = "future_field"
	future_field.tick = 1200
	future_field.duration_ticks = 1200
	document.add_event(MingheChartEditorDocument.TRACK_TUNING_FIELDS, future_field)
	for affinity in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		var slider := TuningSliderEvent.new()
		slider.event_id = "future_slider_%d" % affinity
		slider.field_id = future_field.event_id
		slider.group_id = "future_pair"
		slider.affinity = affinity
		slider.tick = 1200
		slider.traversal_ticks = 480
		slider.start_value = 0.5
		slider.end_value = 0.9
		document.add_event(MingheChartEditorDocument.TRACK_TUNING_SLIDERS, slider)
	var future_su := SuManifestationEvent.new()
	future_su.event_id = "future_su"
	future_su.group_id = "future_pair"
	future_su.tick = 1680
	document.add_event(MingheChartEditorDocument.TRACK_SU_MANIFESTATIONS, future_su)
	var bridge := MingheChartPreviewBridge.new()
	var snapshot := bridge.build_stage_snapshot(document, 1000) as StageDefinition
	_expect(snapshot != null, "preview stage snapshot")
	_expect(snapshot.get("chart") != document.chart, "preview chart is immutable copy")
	_expect(snapshot.get("stage_show") != document.stage_show, "preview show is immutable copy")
	var preview_chart := snapshot.chart
	_expect(preview_chart.note_events.size() == 1, "mid-song preview prunes every mechanism that started before seek")
	_expect(preview_chart.note_events[0].event_id == "future_tap", "future mechanism survives preview seek")
	_expect(preview_chart.tuning_fields.size() == 1, "future tuning field survives preview seek")
	_expect(preview_chart.tuning_sliders.size() == 2, "paired tuning sliders keep their field references")
	_expect(preview_chart.su_manifestations.size() == 1, "Su manifestation keeps its paired group reference")
	_expect(snapshot.stage_show.cues.size() == 1 and snapshot.stage_show.cues[0].event_id == "future_cue", "past StageShow cue is pruned")
	_expect(document.chart.note_events.size() == 3 and document.stage_show.cues.size() == 2, "preview pruning does not mutate document")
	bridge.set_runtime_factory(func(_stage: Resource, _options: Dictionary) -> Node: return PreviewProbe.new())
	var preview_node := bridge.create_preview(document, {"auto_start": false, "seek_tick": 1000})
	_expect(preview_node != null, "PreviewBridge creates runtime preview")
	if preview_node != null:
		_expect(preview_node.get("initial_stage") != null, "PreviewBridge assigns snapshot before ready")
		root.add_child(preview_node)
		await process_frame
		_expect((preview_node as PreviewProbe).received_seek_tick == 1000, "PreviewBridge calls seek_tick after StageRoot ready")
		preview_node.queue_free()
		await process_frame


func _test_workspace_scene() -> void:
	var scene := load("res://scenes/tools/chart_editor/chart_editor_workspace.tscn") as PackedScene
	_expect(scene != null, "workspace scene loads")
	if scene == null:
		return
	var workspace := scene.instantiate()
	root.add_child(workspace)
	await process_frame
	_expect(workspace is MingheChartEditorWorkspace, "workspace script attached")
	_expect(workspace.get_node_or_null("WorkspaceLayout") != null, "workspace UI builds")
	var typed_workspace := workspace as MingheChartEditorWorkspace
	# 新调频调色板应能建立调频场、成组双滑条和动态素音，并在复制时重映射两种引用。
	typed_workspace._create_event("tuning_field", 960, 2)
	typed_workspace._create_event("slider_pair", 960, 3)
	var original_field: TuningFieldRegion = typed_workspace.document.chart.tuning_fields[0]
	var original_group := String(typed_workspace.document.chart.tuning_sliders[0].group_id)
	typed_workspace._create_event("su_manifestation", 1920, 5)
	_expect(typed_workspace.document.chart.tuning_sliders.size() == 2, "palette creates two independent slider resources")
	_expect(typed_workspace.document.chart.su_manifestations[0].group_id == original_group, "palette connects Su to latest paired slider group")
	typed_workspace._on_selection_changed(PackedStringArray([
		original_field.event_id,
		typed_workspace.document.chart.tuning_sliders[0].event_id,
		typed_workspace.document.chart.tuning_sliders[1].event_id,
		typed_workspace.document.chart.su_manifestations[0].event_id,
	]))
	typed_workspace._copy_selected()
	typed_workspace._paste_clipboard(3360)
	var pasted_fields: Array = typed_workspace.document.chart.tuning_fields.filter(func(field: TuningFieldRegion) -> bool: return field.event_id != original_field.event_id)
	var pasted_sliders: Array = typed_workspace.document.chart.tuning_sliders.filter(func(slider: TuningSliderEvent) -> bool: return slider.group_id != original_group)
	var pasted_su: Array = typed_workspace.document.chart.su_manifestations.filter(func(item: SuManifestationEvent) -> bool: return item.group_id != original_group)
	_expect(pasted_fields.size() == 1 and pasted_sliders.size() == 2 and pasted_su.size() == 1, "clipboard duplicates the complete tuning group")
	if pasted_fields.size() == 1 and pasted_sliders.size() == 2 and pasted_su.size() == 1:
		var pasted_field_id := String(pasted_fields[0].event_id)
		var pasted_group_id := String(pasted_sliders[0].group_id)
		_expect(pasted_sliders[0].field_id == pasted_field_id and pasted_sliders[1].field_id == pasted_field_id, "clipboard remaps field_id")
		_expect(pasted_sliders[1].group_id == pasted_group_id and pasted_su[0].group_id == pasted_group_id, "clipboard remaps group_id")
	var waveform_directory := "user://minghe_chart_editor/tests/workspace_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(waveform_directory))
	var waveform_path := waveform_directory + "/threaded.wav"
	_write_test_wav(waveform_path)
	typed_workspace._load_waveform(waveform_path)
	for _frame in 120:
		if typed_workspace._waveform_thread == null:
			break
		await process_frame
	_expect(typed_workspace._timeline.waveform != null, "workspace threaded waveform load")
	workspace.queue_free()
	await process_frame


func _write_test_wav(path: String) -> void:
	var sample_rate := 8000
	var frame_count := 800
	var data_size := frame_count * 2
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.big_endian = false
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_size)
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(sample_rate)
	file.store_32(sample_rate * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_size)
	for index in frame_count:
		var sample := roundi(sin(float(index) * TAU / 40.0) * 12000.0)
		file.store_16(sample & 0xffff)


func _configure_test_service(service: MingheChartEditorSaveService, base: String) -> void:
	service.journal_path = base + "/save_journal.json"
	service.backup_root = base + "/backups"
	service.recovery_root = base + "/recovery"


func _make_crash_journal(
	chart_target: String,
	show_target: String,
	chart_temp: String,
	show_temp: String,
	chart_had_original: bool,
	show_had_original: bool,
	phase: String
) -> Dictionary:
	# 直接构造某一事务 phase 的磁盘现场，比真的杀死测试进程更稳定，也能逐阶段覆盖恢复分支。
	return {
		"schema_version": 2,
		"chart_target": chart_target,
		"show_target": show_target,
		"chart_temp": chart_temp,
		"show_temp": show_temp,
		"chart_old": chart_target.trim_suffix(".tres") + ".old.tres",
		"show_old": show_target.trim_suffix(".tres") + ".old.tres",
		"had_original": {"chart": chart_had_original, "show": show_had_original},
		"phase": phase,
	}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS ", label)
	else:
		_failures += 1
		push_error("  FAIL %s" % label)
