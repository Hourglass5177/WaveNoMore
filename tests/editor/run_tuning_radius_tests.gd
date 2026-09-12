extends SceneTree
## 半径贯穿编辑、持久化与正式表现，同时对照未修改半径的领域结果。
var failures := 0
var checks := 0
const RULES = preload("res://content/rules/default_gameplay_rules.tres")
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
func settle() -> void:
	for i: int in 5: await process_frame
func compile_chart(chart: SongChart) -> CompiledChart:
	return ChartCompiler.compile(ChartPathAdapter.project(chart, RULES), RULES).compiled
func geometry(data: Dictionary) -> Dictionary:
	var visual := GrayboxFieldVisual.new()
	root.add_child(visual); visual.configure_from_rules(RULES); visual.prepare(data)
	var state: Dictionary = visual.visual_state_snapshot()
	visual.free()
	return state

func run() -> void:
	var document := StudioDocument.new()
	check(StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", document).is_empty(), "旧谱正常打开")
	var original := document.chart().duplicate(true) as SongChart
	var baseline := compile_chart(original)
	check(original.tuning_paths.all(func(path): return path.visual_radius_px == 0.0), "旧谱默认自动半径")
	for index: int in document.chart().tuning_paths.size():
		var old: TuningPathEvent = document.chart().tuning_paths[index]
		var changed := old.duplicate(true) as TuningPathEvent
		changed.visual_radius_px = 300.0 if index == 0 else 430.0
		document.execute("半径", [old], [changed])
	var modified := compile_chart(document.chart())
	check(baseline.content_hash == modified.content_hash, "半径不进入 Replay 内容哈希")
	var last_end := {}
	for index: int in modified.tuning_sliders.size():
		var data: Dictionary = modified.tuning_sliders[index]
		var old_data: Dictionary = baseline.tuning_sliders[index]
		var copied := data.duplicate(true); copied.erase("visual_radius_px")
		var old_copy := old_data.duplicate(true); old_copy.erase("visual_radius_px")
		check(copied == old_copy, "仅新增表现半径，编译调频要求不变 %s" % data.id)
		var view := geometry(data); var auto_view := geometry(old_data)
		check(is_equal_approx(view.rail_radius, data.visual_radius_px), "采用指定半径 %s" % data.id)
		check(is_equal_approx(view.arc_span_rad, auto_view.arc_span_rad), "角行程保持一致 %s" % data.id)
		for point: Vector2 in view.curve_points:
			if absf(point.distance_to(Vector2(960, 540)) - data.visual_radius_px) > 0.02:
				check(false, "所有采样点位于指定同心圆"); break
		if last_end.has(data.affinity):
			check(Vector2(last_end[data.affinity]).distance_to(view.slider_start_point) < 0.01, "同侧分段接合处无半径跳动")
		last_end[data.affinity] = view.slider_end_point
	var input_a := StudioPreviewInputs.build(baseline, RULES)
	var input_b := StudioPreviewInputs.build(modified, RULES)
	var same_inputs := input_a.size() == input_b.size()
	for i: int in input_a.size():
		same_inputs = same_inputs and input_a[i].timestamp_us == input_b[i].timestamp_us and input_a[i].kind == input_b[i].kind and input_a[i].tune_vector == input_b[i].tune_vector
	check(same_inputs, "理想输入逐条不变")
	var replay := ReplayData.new(); replay.inputs = input_a
	var first := ReplayRunner.run(baseline, RULES, replay)
	var second := ReplayRunner.run(modified, RULES, replay)
	check(first.digest == second.digest, "Replay 结算摘要一致")
	check(first.simulation.snapshot().su_manifestations.size() == original.ghost_events.size(), "对照 Replay 确实包含全部 Ghost 批次")
	check(first.simulation.snapshot().su_manifestations == second.simulation.snapshot().su_manifestations, "Ghost 数量、坐标及结果一致")
	var raw := ChartJsonCodec.encode_chart(document.chart())
	check(ChartJsonCodec.decode_chart(raw).chart.tuning_paths[0].visual_radius_px == 300.0, "JSON 往返保留半径")
	var invalid := document.chart().duplicate(true) as SongChart
	for radius: float in [-1.0, INF, NAN]:
		invalid.tuning_paths[0].visual_radius_px = radius
		check(not ChartPathAdapter.validate(invalid, RULES).is_empty(), "非法半径进入问题检查 %s" % radius)
	check(StudioProjectIO.save_project(document, "user://chart_studio/tests/radius/project").is_empty(), "保存隔离项目")
	var reopened := StudioDocument.new()
	check(StudioProjectIO.open_project("user://chart_studio/tests/radius/project/song.json", reopened).is_empty() and reopened.chart().tuning_paths[0].visual_radius_px == 300.0, "保存重开保留半径")
	check(StudioProjectIO.export_zip(document, "user://chart_studio/tests/radius/chart.zip").is_empty(), "导出谱面 ZIP")
	var loaded := ChartProjectLoader.load_stage("user://chart_studio/tests/radius/chart.zip")
	check(loaded.stage != null and loaded.stage.chart.tuning_sliders[0].visual_radius_px == 300.0, "正式游戏读取导出半径")
	document.copy_notes(PackedStringArray(["life_tuning"]))
	var pasted := document.paste(7200)
	check(document.find_note(pasted[0]).visual_radius_px == 300.0, "复制粘贴保留半径")
	document.undo(); document.undo(true)
	check(document.find_note(pasted[0]).visual_radius_px == 300.0, "撤销重做保留半径")
	await ui_test()
	print("TUNING RADIUS TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func ui_test() -> void:
	var workspace = load("res://scenes/tools/chart_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start = false
	workspace.recovery_path = "user://chart_studio/tests/radius/recovery.json"
	root.add_child(workspace); await settle()
	workspace._open_path("user://chart_studio/tests/radius/project/song.json"); await settle()
	workspace.timeline.selected = PackedStringArray(["life_tuning"]); workspace._inspect()
	var spin: SpinBox = workspace.fields.get_node("TuningRadius")
	check(spin.value == 300.0, "属性面板显示单条半径")
	spin.get_line_edit().text = "360"
	spin.get_line_edit().text_submitted.emit("360"); await settle()
	check(workspace.document.find_note("life_tuning").visual_radius_px == 360.0, "真实文本提交修改半径")
	workspace.document.undo(); await settle()
	check(workspace.document.find_note("life_tuning").visual_radius_px == 300.0, "数值编辑一步撤销")
	spin = workspace.fields.get_node("TuningRadius")
	spin.value += spin.step; await settle()
	check(workspace.document.find_note("life_tuning").visual_radius_px == 301.0, "箭头微调立即提交 1 px")
	workspace.document.undo(); await settle()
	workspace._refresh_pending = false; await workspace._rebuild_preview()
	check(workspace.preview.stage_root.stage_session.compiled_chart.tuning_sliders[0].visual_radius_px == 300.0, "属性修改刷新正式内嵌预览")
	if DisplayServer.get_name() != "headless":
		workspace.set_process(false)
		workspace._seek(3.8)
		while workspace.preview.rebuilding: await process_frame
		var output := "res://builds/visual-review/tap-radius"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		for size: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
			root.size = size; await settle(); await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output + "/tuning-workspace-%d.png" % size.x)
		workspace.viewport.get_texture().get_image().save_png(output + "/tuning-stage.png")
		workspace.set_process(true)
	var automatic: CheckButton = workspace.fields.get_node("TuningRadiusAutomatic")
	automatic.button_pressed = true; await settle()
	check(workspace.document.find_note("life_tuning").visual_radius_px == 0.0, "恢复自动半径")
	automatic = workspace.fields.get_node("TuningRadiusAutomatic")
	automatic.button_pressed = false; await settle()
	var expected := ChartPathAdapter.automatic_visual_radius(workspace.document.find_note("life_tuning"), RULES)
	check(is_equal_approx(workspace.document.find_note("life_tuning").visual_radius_px, expected), "关闭自动取首段原半径")
	workspace._write_recovery()
	var recovery: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(workspace.recovery_path))
	workspace.document.new_project(); workspace._restore_recovery(recovery); await settle()
	check(is_equal_approx(workspace.document.find_note("life_tuning").visual_radius_px, expected), "自动恢复保存自定义半径")
	workspace.queue_free(); await settle()
